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
    for (_, disj) in _disjunctions(model)
        reformulate_disjunction(model, disj, method)
    end
end

# disjuncts
"""
    reformulate_disjunction(
        model::JuMP.Model, 
        disj::ConstraintData{T},
        method::AbstractReformulationMethod
    ) where {T<:Disjunction}

Reformulate a disjunction using the specified `method`. Current reformulation methods include
`BigM`, `Hull`, and `Indicator`. This method can be extended for other reformualtion techniques.

The `disj` field is the `ConstraintData` object for the disjunction, stored in the 
`disjunctions` field of the `GDPData` object.
"""
function reformulate_disjunction(model::JuMP.Model, disj::ConstraintData{T}, method::BigM) where {T<:Disjunction}
    for d in disj.constraint.indicators
        _reformulate_disjunct(model, d, method)
    end
end
function reformulate_disjunction(model::JuMP.Model, disj::ConstraintData{T}, method::Indicator) where {T<:Disjunction}
    for d in disj.constraint.indicators
        _reformulate_disjunct(model, d, method)
    end
end
function reformulate_disjunction(model::JuMP.Model, disj::ConstraintData{T}, method::Hull) where {T<:Disjunction}
    disj_vrefs = _get_disjunction_variables(model, disj)
    _update_variable_bounds.(disj_vrefs)
    hull = _Hull(method.value, disj_vrefs)
    for d in disj.constraint.indicators #reformulate each disjunct
        _disaggregate_variables(model, d, disj_vrefs, hull) #disaggregate variables for that disjunct
        _reformulate_disjunct(model, d, hull)
    end
    for vref in disj_vrefs #create sum constraint for disaggregated variables
        _aggregate_variable(model, vref, hull)
    end
end

# individual disjuncts
function _reformulate_disjunct(model::JuMP.Model, ind_idx::LogicalVariableIndex, method::AbstractReformulationMethod)
    #reformulate each constraint and add to the model
    bv_idx = _indicator_to_binary(model)[ind_idx]
    bvref = JuMP.VariableRef(model, bv_idx)
    for cidx in _indicator_to_constraints(model)[ind_idx]
        cdata = _disjunct_constraints(model)[cidx]
        _reformulate_disjunct_constraint(model, cdata.constraint, bvref, method)
    end
end

# reformulation fallback for individual disjunct constraints
function _reformulate_disjunct_constraint(
    ::JuMP.Model,  
    con::JuMP.AbstractConstraint, 
    ::JuMP.VariableRef,
    method::AbstractReformulationMethod
)
    error("$method reformulation for constraint $con is not supported yet.")
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
function _reformulate_logical_constraint(model::JuMP.Model, lvec::Vector{LogicalVariableRef}, set::Union{MOIAtMost, MOIAtLeast, MOIExactly})
    return _reformulate_selector(model, set, set.value, lvec)
end
function _reformulate_logical_constraint(model::JuMP.Model, lexpr::_LogicalExpr, ::_MOI.EqualTo{Bool})
    return _reformulate_proposition(model, lexpr)
end