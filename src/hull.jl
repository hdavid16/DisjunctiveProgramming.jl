################################################################################
#                              VARIABLE DISAGGREGATION
################################################################################
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
function _disaggregate_variables(model::JuMP.Model, lvref::LogicalVariableRef, vrefs::Set{JuMP.VariableRef}, disag_vars::_Hull)
    #create disaggregated variables for that disjunct
    for vref in vrefs
        JuMP.is_binary(vref) && continue #skip binary variables
        _disaggregate_variable(model, lvref, vref, disag_vars) #create disaggregated var for that disjunct
    end
end
function _disaggregate_variable(model::JuMP.Model, lvref::LogicalVariableRef, vref::JuMP.VariableRef, disag_vars::_Hull)
    #create disaggregated (disjunct) vref
    v_idx = JuMP.index(vref) #variable
    lb, ub = _variable_bounds(model)[v_idx]
    lv_idx = JuMP.index(lvref)
    dvref = JuMP.@variable(model, base_name = "$(vref)_$(lvref)", lower_bound = lb, upper_bound = ub)
    dv_idx = JuMP.index(dvref) #disaggregated (disjunct) variable
    push!(_reformulation_variables(model), dv_idx)
    #get binary indicator variable
    bv_idx = _indicator_to_binary(model)[lv_idx]
    bvref = JuMP.VariableRef(model, bv_idx)
    #temp storage
    push!(disag_vars.disjunction[vref], dvref)
    disag_vars.disjunct[vref, bvref] = dvref
    #create bounding constraints
    dvname = JuMP.name(dvref)
    new_con_lb_ref = JuMP.add_constraint(model,
        JuMP.build_constraint(error, lb*bvref - dvref, _MOI.LessThan(0)),
        "$dvname lower bounding"
    )
    new_con_ub_ref = JuMP.add_constraint(model,
        JuMP.build_constraint(error, dvref - ub*bvref, _MOI.LessThan(0)),
        "$dvname upper bounding"
    )
    push!(_reformulation_constraints(model), 
        (JuMP.index(new_con_lb_ref), JuMP.ScalarShape()), 
        (JuMP.index(new_con_ub_ref), JuMP.ScalarShape())
    )

    return dvref
end

################################################################################
#                              VARIABLE AGGREGATION
################################################################################
function _aggregate_variable(model::JuMP.Model, vref::JuMP.VariableRef, disag_vars::_Hull, nested::Bool)
    JuMP.is_binary(vref) && return #skip binary variables
    con_expr = JuMP.@expression(model, -vref + sum(disag_vars.disjunction[vref]))
    con = JuMP.build_constraint(error, con_expr, _MOI.EqualTo(0))
    if !nested
        _add_reformulated_constraint(model, con, "$(vref)_aggregation")
    end

    return con
end

################################################################################
#                              CONSTRAINT DISAGGREGATION
################################################################################
# affine expression
function _disaggregate_expression(model::JuMP.Model, aff::JuMP.AffExpr, bvref::JuMP.VariableRef, method::_Hull)
    new_expr = JuMP.@expression(model, aff.constant*bvref) #multiply constant by binary indicator variable
    for (vref, coeff) in aff.terms
        if JuMP.is_binary(vref) || !haskey(method.disjunct, (vref, bvref)) #keep any binary variables or nested disaggregated variables unchanged 
            JuMP.add_to_expression!(new_expr, coeff*vref)
        else #replace other vars with disaggregated form
            dvref = method.disjunct[vref, bvref]
            JuMP.add_to_expression!(new_expr, coeff*dvref)
        end
    end
    return new_expr
end
# quadratic expression
# TODO review what happens when there are bilinear terms with binary variables involved since these are not being disaggregated 
#   (e.g., complementarity constraints; though likely irrelevant)...
function _disaggregate_expression(model::JuMP.Model, quad::JuMP.QuadExpr, bvref::JuMP.VariableRef, method::_Hull)
    #get affine part
    new_expr = _disaggregate_expression(model, quad.aff, bvref, method)
    #get nonlinear part
    ϵ = method.value
    for (pair, coeff) in quad.terms
        da_ref = method.disjunct[pair.a, bvref]
        db_ref = method.disjunct[pair.b, bvref]
         new_expr += coeff * da_ref * db_ref / ((1-ϵ)*bvref+ϵ)
    end

    return new_expr
end
# constant in NonlinearExpr
function _disaggregate_nl_expression(model::JuMP.Model, c::Number, ::JuMP.VariableRef, ::_Hull)
    return c
end
# variable in NonlinearExpr
function _disaggregate_nl_expression(model::JuMP.Model, vref::JuMP.VariableRef, bvref::JuMP.VariableRef, method::_Hull)
    ϵ = method.value
    dvref = method.disjunct[vref, bvref]
    new_var = dvref / ((1-ϵ)*bvref+ϵ)
    return new_var
end
# affine expression in NonlinearExpr
function _disaggregate_nl_expression(model::JuMP.Model, aff::JuMP.AffExpr, bvref::JuMP.VariableRef, method::_Hull)
    new_expr = aff.constant
    ϵ = method.value
    for (vref, coeff) in aff.terms
        if JuMP.is_binary(vref) #keep any binary variables undisaggregated
            dvref = vref
        else #replace other vars with disaggregated form
            dvref = method.disjunct[vref, bvref]
        end
         new_expr += coeff * dvref / ((1-ϵ)*bvref+ϵ)
    end
    return new_expr
end
# quadratic expression in NonlinearExpr
function _disaggregate_nl_expression(model::JuMP.Model, quad::JuMP.QuadExpr, bvref::JuMP.VariableRef, method::_Hull)
    #get affine part
    new_expr = _disaggregate_nl_expression(model, quad.aff, bvref, method)
    #get quadratic part
    ϵ = method.value
    for (pair, coeff) in quad.terms
        da_ref = method.disjunct[pair.a, bvref]
        db_ref = method.disjunct[pair.b, bvref]
        new_expr += coeff * da_ref * db_ref / ((1-ϵ)*bvref+ϵ)^2
    end
    return new_expr
end
# nonlinear expression in NonlinearExpr
function _disaggregate_nl_expression(model::JuMP.Model, nlp::JuMP.NonlinearExpr, bvref::JuMP.VariableRef, method::_Hull)
    new_args = Vector{Any}(undef, length(nlp.args))
    for (i,arg) in enumerate(nlp.args)
        new_args[i] = _disaggregate_nl_expression(model, arg, bvref, method)
    end
    new_expr = JuMP.NonlinearExpr(nlp.head, new_args)
    return new_expr
end

################################################################################
#                              HULL REFORMULATION
################################################################################
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef, 
    method::_Hull,
    name::String,
    nested::Bool
) where {T <: Union{JuMP.AffExpr, JuMP.QuadExpr}, S <: Union{_MOI.LessThan, _MOI.GreaterThan, _MOI.EqualTo}}
    new_func = _disaggregate_expression(model, con.func, bvref, method)
    set_value = _set_value(con.set)
    new_func -= set_value*bvref
    reform_con = JuMP.build_constraint(error, new_func, S(0))
    if !nested
        con_name = isempty(name) ? name : string(name, "_", bvref)
        _add_reformulated_constraint(model, reform_con, con_name)
    end

    return [reform_con]
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef, 
    method::_Hull,
    name::String,
    nested::Bool
) where {T <: Union{JuMP.AffExpr, JuMP.QuadExpr}, S <: Union{_MOI.Nonpositives, _MOI.Nonnegatives, _MOI.Zeros}, R}
    new_func = JuMP.@expression(model, [i=1:con.set.dimension],
        _disaggregate_expression(model, con.func[i], bvref, method)
    )
    reform_con = JuMP.build_constraint(error, new_func, con.set)
    if !nested
        con_name = isempty(name) ? name : string(name, "_", bvref)
        _add_reformulated_constraint(model, reform_con, con_name)
    end

    return [reform_con]
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::_Hull,
    name::String,
    nested::Bool
) where {T <: JuMP.GenericNonlinearExpr, S <: Union{_MOI.LessThan, _MOI.GreaterThan, _MOI.EqualTo}}
    con_func = _disaggregate_nl_expression(model, con.func, bvref, method)
    con_func0 = JuMP.value(v -> 0.0, con.func)
    if isinf(con_func0)
        error("Operator `$(con.func.head)` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    ϵ = method.value
    set_value = _set_value(con.set)
    new_func = JuMP.@expression(model, ((1-ϵ)*bvref+ϵ)*con_func - ϵ*(1-bvref)*con_func0 - set_value*bvref)
    reform_con = JuMP.build_constraint(error, new_func, S(0))
    if !nested
        con_name = isempty(name) ? name : string(name, "_", bvref)
        _add_reformulated_constraint(model, reform_con, con_name)
    end

    return [reform_con]
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef,
    method::_Hull,
    name::String,
    nested::Bool
) where {T <: JuMP.GenericNonlinearExpr, S <: Union{_MOI.Nonpositives, _MOI.Nonnegatives, _MOI.Zeros}, R}
    con_func = JuMP.@expression(model, [i=1:con.set.dimension],
        _disaggregate_nl_expression(model, con.func[i], bvref, method)
    )
    con_func0 = JuMP.value.(v -> 0.0, con.func)
    if any(isinf.(con_func0))
        error("At least of of the operators `$([func.head for func in con.func])` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    ϵ = method.value
    new_func = JuMP.@expression(model, [i=1:con.set.dimension], 
        ((1-ϵ)*bvref+ϵ)*con_func[i] - ϵ*(1-bvref)*con_func0[i]
    )
    reform_con = JuMP.build_constraint(error, new_func, con.set)
    if !nested
        con_name = isempty(name) ? name : string(name, "_", bvref)
        _add_reformulated_constraint(model, reform_con, con_name)
    end

    return [reform_con]
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::_Hull,
    name::String,
    nested::Bool
) where {T <: Union{JuMP.AffExpr, JuMP.QuadExpr}, S <: _MOI.Interval}
    new_func = _disaggregate_expression(model, con.func, bvref, method)
    new_func_gt = JuMP.@expression(model, new_func - con.set.lower*bvref)
    new_func_lt = JuMP.@expression(model, new_func - con.set.upper*bvref)
    reform_con_gt = JuMP.build_constraint(error, new_func_gt, _MOI.GreaterThan(0))
    reform_con_lt = JuMP.build_constraint(error, new_func_lt, _MOI.LessThan(0))
    if !nested
        con_name1 = isempty(name) ? name : string(name, "_", bvref, "_1")
        con_name2 = isempty(name) ? name : string(name, "_", bvref, "_2")
        _add_reformulated_constraint(model, reform_con_gt, con_name1)
        _add_reformulated_constraint(model, reform_con_lt, con_name2)
    end

    return [reform_con_gt, reform_con_lt]
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::_Hull,
    name::String,
    nested::Bool
) where {T <: JuMP.GenericNonlinearExpr, S <: _MOI.Interval}
    con_func = _disaggregate_nl_expression(model, con.func, bvref, method)
    con_func0 = JuMP.value(v -> 0.0, con.func)
    if isinf(con_func0)
        error("Operator `$(con.func.head)` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    ϵ = method.value
    new_func = JuMP.@expression(model, ((1-ϵ)*bvref+ϵ) * con_func - ϵ*(1-bvref)*con_func0)
    new_func_gt = JuMP.@expression(model, new_func - con.set.lower*bvref)
    new_func_lt = JuMP.@expression(model, new_func - con.set.upper*bvref)
    reform_con_gt = JuMP.build_constraint(error, new_func_gt, _MOI.GreaterThan(0))
    reform_con_lt = JuMP.build_constraint(error, new_func_lt, _MOI.LessThan(0))
    if !nested
        con_name1 = isempty(name) ? name : string(name, "_", bvref, "_1")
        con_name2 = isempty(name) ? name : string(name, "_", bvref, "_2")
        _add_reformulated_constraint(model, reform_con_gt, con_name1)
        _add_reformulated_constraint(model, reform_con_lt, con_name2)
    end

    return [reform_con_gt, reform_con_lt]
end