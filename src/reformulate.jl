################################################################################
#                              LOGICAL VARIABLES
################################################################################
# create binary (indicator) variables for logic variables.
function _reformulate_logical_variables(model::JuMP.Model)
    for (lv_idx, lv_data) in _logical_variables(model)
        lv = lv_data.variable
        lvref = LogicalVariableRef(model, lv_idx)
        bvref = JuMP.@variable(model, base_name = lv_data.name, binary=true, start = lv.start_value)
        if JuMP.is_fixed(lvref)
            JuMP.fix(bvref, JuMP.fix_value(lvref))
        end
        bv_idx = JuMP.index(bvref)
        push!(_reformulation_variables(model), bv_idx)
        _indicator_to_binary(model)[lv_idx] = bv_idx
    end
end

################################################################################
#                              DISJUNCTIONS
################################################################################
# disjunctions
function _reformulate_disjunctions(model::JuMP.Model, method::AbstractReformulationMethod)
    for (didx, disj) in _disjunctions(model)
        if !(didx in _nested_disjunctions(model))
            reformulate_disjunction(model, disj, method, false)
        end
    end
end

# disjuncts
"""
    reformulate_disjunction(
        model::JuMP.Model, 
        disj::ConstraintData{T},
        method::AbstractReformulationMethod,
        nested::Bool
    ) where {T<:Disjunction}

Reformulate a disjunction using the specified `method`. Current reformulation methods include
`BigM`, `Hull`, and `Indicator`. This method can be extended for other reformualtion techniques.

The `disj` field is the `ConstraintData` object for the disjunction, stored in the 
`disjunctions` field of the `GDPData` object.
"""
function reformulate_disjunction(model::JuMP.Model, disj::ConstraintData{T}, method::BigM, nested::Bool) where {T<:Disjunction}
    ref_cons = Vector{JuMP.AbstractConstraint}()
    for d in disj.constraint.indicators
        push!(ref_cons, _reformulate_disjunct(model, d, method, nested)...)
    end

    return ref_cons
end
function reformulate_disjunction(model::JuMP.Model, disj::ConstraintData{T}, method::Indicator, nested::Bool) where {T<:Disjunction}
    ref_cons = Vector{JuMP.AbstractConstraint}()
    for d in disj.constraint.indicators
        push!(ref_cons, _reformulate_disjunct(model, d, method, nested)...)
    end

    return ref_cons
end
function reformulate_disjunction(model::JuMP.Model, disj::ConstraintData{T}, method::Hull, nested::Bool) where {T<:Disjunction}
    ref_cons = Vector{JuMP.AbstractConstraint}()
    disj_vrefs = _get_disjunction_variables(model, disj)
    _update_variable_bounds.(disj_vrefs)
    hull = _Hull(method.value, disj_vrefs)
    for d in disj.constraint.indicators #reformulate each disjunct
        _disaggregate_variables(model, d, disj_vrefs, hull) #disaggregate variables for that disjunct
        push!(ref_cons, _reformulate_disjunct(model, d, hull, nested)...)
    end
    for vref in disj_vrefs #create sum constraint for disaggregated variables
        push!(ref_cons, _aggregate_variable(model, vref, hull, nested))
    end

    return ref_cons
end
function reformulate_disjunction(model::JuMP.Model, disj::ConstraintData{T}, method::_Hull, nested::Bool) where {T<:Disjunction}
    reformulate_disjunction(model, disj, Hull(method.value), nested)
end

# individual disjuncts
function _reformulate_disjunct(model::JuMP.Model, ind_ref::LogicalVariableRef, method::AbstractReformulationMethod, nested::Bool)
    #reformulate each constraint and add to the model
    lv_idx = JuMP.index(ind_ref)
    bv_idx = _indicator_to_binary(model)[lv_idx]
    bvref = JuMP.VariableRef(model, bv_idx)
    ref_cons = Vector{JuMP.AbstractConstraint}()
    for cidx in _indicator_to_constraints(model)[lv_idx]
        cdata = _disjunct_constraints(model)[cidx]
        push!(ref_cons, _reformulate_disjunct_constraint(model, cdata.constraint, bvref, method, cdata.name, nested)...)
    end

    return ref_cons
end

# reformulation for nested disjunction
function _reformulate_disjunct_constraint(
    model::JuMP.Model,  
    con::Disjunction, 
    bvref::JuMP.VariableRef,
    method::AbstractReformulationMethod,
    name::String,
    nested::Bool
)
    disj = ConstraintData{Disjunction}(con, name)
    ref_cons = reformulate_disjunction(model, disj, method, true)
    new_ref_cons = Vector{JuMP.AbstractConstraint}()
    for ref_con in ref_cons
        push!(new_ref_cons, _reformulate_disjunct_constraint(model, ref_con, bvref, method, name, false)...)
    end

    return new_ref_cons
end

# reformulation fallback for individual disjunct constraints
function _reformulate_disjunct_constraint(
    model::JuMP.Model,  
    con::JuMP.AbstractConstraint, 
    bvref::JuMP.VariableRef,
    method::AbstractReformulationMethod,
    name::String
)
    error("$method reformulation for constraint $con is not supported yet.")
end

function _add_reformulated_constraint(
    model::JuMP.Model,
    con::JuMP.AbstractConstraint,
    name::String
)
    reform_con = JuMP.add_constraint(model, con, name)
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), _map_con_shape(con)))
end

################################################################################
#                       LOGICAL CONSTRAINT REFORMULATION
################################################################################
# all logical constraints
function _reformulate_logical_constraints(model::JuMP.Model)
    for (_, lcon) in _logical_constraints(model)
        _reformulate_logical_constraint(model, lcon.constraint.func, lcon.constraint.set)
    end
end
# individual logical constraints
function _reformulate_logical_constraint(model::JuMP.Model, lvec::Vector{LogicalVariableRef}, set::Union{_MOIAtMost, _MOIAtLeast, _MOIExactly})
    return _reformulate_selector(model, set, set.value, lvec)
end
function _reformulate_logical_constraint(model::JuMP.Model, lexpr::_LogicalExpr, ::_MOI.EqualTo{Bool})
    return _reformulate_proposition(model, lexpr)
end