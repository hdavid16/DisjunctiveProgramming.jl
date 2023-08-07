################################################################################
#                              VARIABLE ITERATION
################################################################################

"""

"""
function _get_disjunction_variables(disj::ConstraintData{Disjunction})
    vars = Set{JuMP.VariableRef}()
    for d in disj.constraint.disjuncts
        _interrogate_variables(v -> push!(vars, v), d)
    end
    return vars
end

# Constant
function _interrogate_variables(interrogator::Function, c::Number)
    return
end

# VariableRef
function _interrogate_variables(interrogator::Function, var::JuMP.VariableRef)
    interrogator(var)
    return
end

# AffExpr
function _interrogate_variables(interrogator::Function, aff::JuMP.AffExpr)
    for (var, _) in aff.terms
        interrogator(var)
    end
    return
end

# QuadExpr
function _interrogate_variables(interrogator::Function, quad::JuMP.QuadExpr)
    for (pair, _) in quad.terms
        interrogator(pair.a)
        interrogator(pair.b)
    end
    _interrogate_variables(interrogator, quad.aff)
    return
end

# NonlinearExpr
function _interrogate_variables(interrogator::Function, nlp::JuMP.NonlinearExpr)
    for arg in nlp.args
        _interrogate_variables(interrogator, arg)
    end
    # TODO avoid recursion. See InfiniteOpt.jl for alternate method that avoids stackoverflow errors with deeply nested expressions:
    # https://github.com/infiniteopt/InfiniteOpt.jl/blob/cb6dd6ae40fe0144b1dd75da0739ea6e305d5357/src/expressions.jl#L520-L534
    return
end

# Constraint
function _interrogate_variables(interrogator::Function, con::JuMP.ScalarConstraint)
    _interrogate_variables(interrogator, con.func)
end

# AbstractArray
function _interrogate_variables(interrogator::Function, arr::AbstractArray)
    _interrogate_variables.(interrogator, ex)
    return
end

# Disjunct
function _interrogate_variables(interrogator::Function, d::Disjunct)
    for con in d.constraints
        model, idx = con.model, con.index
        cdata = _disjunct_constraints(model)[idx]
        _interrogate_variables(interrogator, cdata.constraint)
    end
    return
end

# Fallback
function _interrogate_variables(interrogator::Function, other)
    error("Cannot extract variables from object of type $(typeof(other)) inside of a disjunctive constraint.")
end

################################################################################
#                              VARIABLE DISAGGREGATION
################################################################################

"""

"""
function _update_variable_bounds(vref::JuMP.VariableRef)
    model, idx = vref.model, vref.index
    if (vref in keys(_variable_bounds(model))) || JuMP.is_binary(vref) #skip if binary or if bounds already stored
        return
    elseif !JuMP.has_lower_bound(vref) || !JuMP.has_upper_bound(vref)
        error("Variable $vref must have both lower and upper bounds defined when using the Hull reformulation.")
    else
        lb = min(0, JuMP.lower_bound(vref))
        ub = max(0, JuMP.upper_bound(vref))
        _variable_bounds(model)[idx] = (lb, ub)
    end
end

"""

"""
function _disaggregate_variables(model::JuMP.Model, d::Disjunct, vrefs::Set{JuMP.VariableRef})
    #create disaggregated variables for that disjunct
    for vref in vrefs
        JuMP.is_binary(vref) && continue #skip binary variables
        _disaggregate_variable(model, d, vref) #create disaggregated var
    end
end

"""

"""
function _disaggregate_variable(model::JuMP.Model, d::Disjunct, vref::JuMP.VariableRef)
    #create disaggregated (disjunct) vref
    v_idx = JuMP.index(vref) #variable
    lb, ub = _variable_bounds(model)[v_idx]
    dvar = JuMP.ScalarVariable(_variable_info(lower_bound = lb, upper_bound = ub))
    dvref = JuMP.add_variable(model, dvar, "$(vref)_$(d.indicator)")
    dv_idx = JuMP.index(dvref) #disaggregated (disjunct) variable
    #get binary indicator variable
    ind_idx = JuMP.index(d.indicator) #logical indicator
    bv_idx = _indicator_to_binary(model)[ind_idx]
    bvref = JuMP.VariableRef(model, bv_idx)
    #store disaggregated (disjunct) variable
    d_idx = _indicator_to_disjunction(model)[ind_idx] #disjunction index
    _global_to_disjunct_variable(model)[v_idx, bv_idx] = dv_idx
    if haskey(_global_to_disjunction_variables(model), (v_idx, d_idx))
        push!(_global_to_disjunction_variables(model)[v_idx, d_idx], dv_idx)
    else
        _global_to_disjunction_variables(model)[v_idx, d_idx] = [dv_idx]
    end
    #create bounding constraints
    vname = JuMP.name(vref)
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, lb*bvref - dvref, _MOI.LessThan(0)),
        "$vname lower bounding"
    )
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, dvref - ub*bvref, _MOI.LessThan(0)),
        "$vname upper bounding"
    )

    return dvref
end

function _aggregate_variable(model::JuMP.Model, vref::JuMP.VariableRef, disj_idx::DisjunctionIndex)
    JuMP.is_binary(vref) && return #skip binary variables
    idx = JuMP.index(vref)
    con_expr = -vref + sum(JuMP.VariableRef(model, idx) for idx in _global_to_disjunction_variables(model)[idx, disj_idx])
    con = JuMP.build_constraint(error, con_expr, _MOI.EqualTo(0))
    con_ref = JuMP.add_constraint(model, con, "$vref aggregation")

    return con_ref
end

################################################################################
#                              DISAGGREGATE CONSTRAINT
################################################################################

"""

"""
function _disaggregate_expression(model::JuMP.Model, aff::JuMP.AffExpr, bvref::JuMP.VariableRef, ::Hull)
    new_expr = JuMP.AffExpr()
    for (vref, coeff) in aff.terms
        JuMP.is_binary(vref) && continue #skip binary variables
        v_idx, bv_idx = JuMP.index(vref), JuMP.index(bvref)
        dv_idx = _global_to_disjunct_variable(model)[v_idx, bv_idx]
        dvref = JuMP.VariableRef(model, dv_idx)
        new_expr.terms[dvref] = coeff
        new_expr.terms[bvref] = aff.constant
    end
    return new_expr
end

function _disaggregate_expression(model::JuMP.Model, quad::JuMP.QuadExpr, bvref::JuMP.VariableRef, method::Hull)
    #get affine part
    new_expr = _disaggregate_expression(model, quad.aff, bvref, method)
    #get nonlinear part
    ϵ = method.value
    for (pair, coeff) in quad.terms
        a_idx, b_idx, bv_idx = JuMP.index(pair.a), JuMP.index(pair.b), JuMP.index(bvref)
        da_idx = _disaggregated_variables(model)[a_idx, bv_idx]
        db_idx = _disaggregated_variables(model)[b_idx, bv_idx]
        da_ref = JuMP.VariableRef(model, da_idx)
        db_ref = JuMP.VariableRef(model, db_idx)
        new_expr += coeff * da_ref * db_ref / ((1-ϵ)*bvref+ϵ)
    end

    return new_expr
end

function _disaggregate_nl_expression(model::JuMP.Model, c::Number, ::JuMP.VariableRef, ::Hull)
    return c
end

function _disaggregate_nl_expression(model::JuMP.Model, vref::JuMP.VariableRef, bvref::JuMP.VariableRef, method::Hull)
    ϵ = method.value
    v_idx, bv_idx = JuMP.index(vref), JuMP.index(bvref)
    dv_idx = _global_to_disjunct_variable(model)[v_idx, bv_idx]
    dvref = JuMP.VariableRef(model, dv_idx)
    new_var = dvref / ((1-ϵ)*bvref+ϵ)

    return new_var
end

function _disaggregate_nl_expression(model::JuMP.Model, aff::JuMP.AffExpr, bvref::JuMP.VariableRef, ::Hull)
    new_expr = JuMP.AffExpr(aff.constant)
    for (vref, coeff) in aff.terms
        JuMP.is_binary(vref) && continue #skip binary variables
        v_idx, bv_idx = JuMP.index(vref), JuMP.index(bvref)
        dv_idx = _global_to_disjunct_variable(model)[v_idx, bv_idx]
        dvref = JuMP.VariableRef(model, dv_idx)
        new_expr += coeff * dvref / ((1-ϵ)*bvref+ϵ)
    end

    return new_expr
end

function _disaggregate_nl_expression(model::JuMP.Model, quad::JuMP.QuadExpr, bvref::JuMP.VariableRef, method::Hull)
    #get affine part
    new_expr = _disaggregate_nl_expression(model, quad.aff, bvref, method)
    #get quadratic part
    ϵ = method.value
    for (pair, coeff) in quad.terms
        a_idx, b_idx, bv_idx = JuMP.index(pair.a), JuMP.index(pair.b), JuMP.index(bvref)
        da_idx = _disaggregated_variables(model)[a_idx, bv_idx]
        db_idx = _disaggregated_variables(model)[b_idx, bv_idx]
        da_ref = JuMP.VariableRef(model, da_idx)
        db_ref = JuMP.VariableRef(model, db_idx)
        new_expr += coeff * da_ref * db_ref / ((1-ϵ)*bvref+ϵ)^2
    end

    return new_expr
end

function _disaggregate_nl_expression(model::JuMP.Model, nlp::JuMP.NonlinearExpr, bvref::JuMP.VariableRef, method::Hull)
    new_args = Vector{Any}(undef, length(nlp.args))
    for arg in nlp.args
        new_arg = _disaggregate_nl_expression(model, arg, bvref, method)
        push!(new_args, new_arg)
    end
    new_expr = JuMP.NonlinearExpr(nlp.head, new_args)

    return new_expr
end