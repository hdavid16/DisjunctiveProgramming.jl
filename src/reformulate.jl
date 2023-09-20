################################################################################
#                              REFORMULATE
################################################################################
"""
    reformulate_model(model::JuMP.Model, method::AbstractSolutionMethod)

Reformulate a `GDPModel` using the specified `method`. Prior to reformulation,
all previous reformulation variables and constraints are deleted.
"""
function reformulate_model(model::JuMP.Model, method::AbstractSolutionMethod)
    #clear all previous reformulations
    _clear_reformulations(model)
    #reformulate
    _reformulate_logical_variables(model)
    _reformulate_disjunctions(model, method)
    _reformulate_logical_constraints(model)
    #set solution method
    _set_solution_method(model, method)
    _set_ready_to_optimize(model, true)
end

function _clear_reformulations(model::JuMP.Model)
    for (cidx, cshape) in _reformulation_constraints(model)
        JuMP.delete(model, JuMP.ConstraintRef(model, cidx, cshape))
    end
    empty!(gdp_data(model).reformulation_constraints)
    for vidx in _reformulation_variables(model)
        JuMP.delete(model, JuMP.VariableRef(model, vidx))
    end
    empty!(gdp_data(model).reformulation_variables)
end

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
function _reformulate_all_disjunctions(model::JuMP.Model, method::AbstractReformulationMethod)
    for (_, disj) in _disjunctions(model)
        disj.constraint.nested && continue #only reformulate top level disjunctions
        ref_cons = reformulate_disjunction(model, disj.constraint, method)
        for (i, ref_con) in enumerate(ref_cons)
            name = isempty(disj.name) ? "" : string(disj.name,"_$i")
            cref = JuMP.add_constraint(model, ref_con, name)
            push!(_reformulation_constraints(model), (JuMP.index(cref), _map_con_shape(ref_con)))
        end
    end
end
function _reformulate_disjunctions(model::JuMP.Model, method::AbstractReformulationMethod)
    _reformulate_all_disjunctions(model, method)
end
function _reformulate_disjunctions(model::JuMP.Model, method::Hull)
    _query_variable_bounds(model, method)
    _reformulate_all_disjunctions(model, method)
end

# disjuncts
"""
    reformulate_disjunction(
        model::JuMP.Model, 
        disj::Disjunction,
        method::AbstractReformulationMethod
    ) where {T<:Disjunction}

Reformulate a disjunction using the specified `method`. Current reformulation methods include
`BigM`, `Hull`, and `Indicator`. This method can be extended for other reformualtion techniques.

The `disj` field is the `ConstraintData` object for the disjunction, stored in the 
`disjunctions` field of the `GDPData` object.
"""
# generic fallback (e.g., BigM, Indicator)
function reformulate_disjunction(model::JuMP.Model, disj::Disjunction, method::AbstractReformulationMethod)
    ref_cons = Vector{JuMP.AbstractConstraint}()
    for d in disj.indicators
        push!(ref_cons, _reformulate_disjunct(model, d, method)...)
    end

    return ref_cons
end
# hull specific
function reformulate_disjunction(model::JuMP.Model, disj::Disjunction, method::Hull)
    ref_cons = Vector{JuMP.AbstractConstraint}()
    disj_vrefs = _get_disjunction_variables(model, disj)
    hull = _Hull(method, disj_vrefs)
    for d in disj.indicators #reformulate each disjunct
        _disaggregate_variables(model, d, disj_vrefs, hull) #disaggregate variables for that disjunct
        push!(ref_cons, _reformulate_disjunct(model, d, hull)...)
    end
    for vref in disj_vrefs #create sum constraint for disaggregated variables
        push!(ref_cons, _aggregate_variable(model, vref, hull))
    end

    return ref_cons
end
function reformulate_disjunction(model::JuMP.Model, disj::Disjunction, method::_Hull)
    reformulate_disjunction(model, disj, Hull(method.value, method.variable_bounds))
end

# individual disjuncts
function _reformulate_disjunct(model::JuMP.Model, ind_ref::LogicalVariableRef, method::AbstractReformulationMethod)
    #reformulate each constraint and add to the model
    lv_idx = JuMP.index(ind_ref)
    bv_idx = _indicator_to_binary(model)[lv_idx]
    bvref = JuMP.VariableRef(model, bv_idx)
    ref_cons = Vector{JuMP.AbstractConstraint}()
    for cidx in _indicator_to_constraints(model)[lv_idx]
        cdata = _index_to_constraint(model, cidx)
        push!(ref_cons, reformulate_disjunct_constraint(model, cdata.constraint, bvref, method)...)
    end

    return ref_cons
end

_index_to_constraint(model::JuMP.Model, cidx::DisjunctConstraintIndex) = _disjunct_constraints(model)[cidx]
_index_to_constraint(model::JuMP.Model, cidx::DisjunctionIndex) = _disjunctions(model)[cidx]

# reformulation for nested disjunction
function reformulate_disjunct_constraint(
    model::JuMP.Model,  
    con::Disjunction, 
    bvref::JuMP.VariableRef,
    method::AbstractReformulationMethod
)
    ref_cons = reformulate_disjunction(model, con, method)
    new_ref_cons = Vector{JuMP.AbstractConstraint}()
    for ref_con in ref_cons
        push!(new_ref_cons, reformulate_disjunct_constraint(model, ref_con, bvref, method)...) #nested = false only for the parent disjunction (only adds the constraints when they have moved up all the way)
    end
    
    return new_ref_cons
end

# reformulation fallback for individual disjunct constraints
function reformulate_disjunct_constraint(
    model::JuMP.Model,  
    con::JuMP.AbstractConstraint, 
    bvref::JuMP.VariableRef,
    method::AbstractReformulationMethod
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