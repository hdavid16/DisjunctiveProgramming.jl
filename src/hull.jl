################################################################################
#                              VARIABLE DISAGGREGATION
################################################################################
function _update_variable_bounds(vref::VariableRef, method::Hull)
    if is_binary(vref) #not used
        lb, ub = 0, 1
    elseif !has_lower_bound(vref) || !has_upper_bound(vref)
        error("Variable $vref must have both lower and upper bounds defined when using the Hull reformulation.")
    else
        lb = min(0, lower_bound(vref))
        ub = max(0, upper_bound(vref))
    end
    return lb, ub
end
function _disaggregate_variables(model::Model, lvref::LogicalVariableRef, vrefs::Set{VariableRef}, method::_Hull)
    #create disaggregated variables for that disjunct
    for vref in vrefs
        is_binary(vref) && continue #skip binary variables
        _disaggregate_variable(model, lvref, vref, method) #create disaggregated var for that disjunct
    end
end
function _disaggregate_variable(model::Model, lvref::LogicalVariableRef, vref::VariableRef, method::_Hull)
    #create disaggregated vref
    lb, ub = method.variable_bounds[vref]
    dvref = @variable(model, base_name = "$(vref)_$(lvref)", lower_bound = lb, upper_bound = ub)
    push!(_reformulation_variables(model), dvref)
    #get binary indicator variable
    bvref = _indicator_to_binary(model)[lvref]
    #temp storage
    if !haskey(method.disjunction_variables, vref) #NOTE: not needed because _Hull disjunction_variables is initialized with all the variables in the disjunction
        method.disjunction_variables[vref] = Vector{VariableRef}()
    end
    push!(method.disjunction_variables[vref], dvref)
    method.disjunct_variables[vref, bvref] = dvref
    #create bounding constraints
    dvname = name(dvref)
    lbname = isempty(dvname) ? "" : "$(dvname)_lower_bound"
    ubname = isempty(dvname) ? "" : "$(dvname)_upper_bound"
    new_con_lb_ref = add_constraint(model,
        build_constraint(error, lb*bvref - dvref, _MOI.LessThan(0)),
        lbname
    )
    new_con_ub_ref = add_constraint(model,
        build_constraint(error, dvref - ub*bvref, _MOI.LessThan(0)),
        ubname
    )
    push!(_reformulation_constraints(model), new_con_lb_ref, new_con_ub_ref)
    return dvref
end

################################################################################
#                              VARIABLE AGGREGATION
################################################################################
function _aggregate_variable(model::Model, ref_cons::Vector{AbstractConstraint}, vref::VariableRef, method::_Hull)
    is_binary(vref) && return #skip binary variables
    con_expr = @expression(model, -vref + sum(method.disjunction_variables[vref]))
    push!(ref_cons,
        build_constraint(error, con_expr, _MOI.EqualTo(0))
    )
    return 
end

################################################################################
#                              CONSTRAINT DISAGGREGATION
################################################################################
# variable
function _disaggregate_expression(model::Model, vref::VariableRef, bvref::VariableRef, method::_Hull)
    if is_binary(vref) || !haskey(method.disjunct_variables, (vref, bvref)) #keep any binary variables or nested disaggregated variables unchanged 
        return vref #NOTE: not needed because nested constraint of the form `vref in MOI.AbstractScalarSet` gets reformulated to an affine expression.
    else #replace with disaggregated form
        return method.disjunct_variables[vref, bvref]
    end
end
# affine expression
function _disaggregate_expression(model::Model, aff::AffExpr, bvref::VariableRef, method::_Hull)
    new_expr = @expression(model, aff.constant*bvref) #multiply constant by binary indicator variable
    for (vref, coeff) in aff.terms
        if is_binary(vref) || !haskey(method.disjunct_variables, (vref, bvref)) #keep any binary variables or nested disaggregated variables unchanged 
            add_to_expression!(new_expr, coeff*vref)
        else #replace other vars with disaggregated form
            dvref = method.disjunct_variables[vref, bvref]
            add_to_expression!(new_expr, coeff*dvref)
        end
    end
    return new_expr
end
# quadratic expression
# TODO review what happens when there are bilinear terms with binary variables involved since these are not being disaggregated 
#   (e.g., complementarity constraints; though likely irrelevant)...
function _disaggregate_expression(model::Model, quad::QuadExpr, bvref::VariableRef, method::_Hull)
    #get affine part
    new_expr = _disaggregate_expression(model, quad.aff, bvref, method)
    #get nonlinear part
    ϵ = method.value
    for (pair, coeff) in quad.terms
        da_ref = method.disjunct_variables[pair.a, bvref]
        db_ref = method.disjunct_variables[pair.b, bvref]
         new_expr += coeff * da_ref * db_ref / ((1-ϵ)*bvref+ϵ)
    end
    return new_expr
end
# constant in NonlinearExpr
function _disaggregate_nl_expression(model::Model, c::Number, ::VariableRef, method::_Hull)
    return c
end
# variable in NonlinearExpr
function _disaggregate_nl_expression(model::Model, vref::VariableRef, bvref::VariableRef, method::_Hull)
    if is_binary(vref) || !haskey(method.disjunct_variables, (vref, bvref)) #keep any binary variables or nested disaggregated variables unchanged 
        return vref
    else #replace with disaggregated form
        ϵ = method.value
        dvref = method.disjunct_variables[vref, bvref]
        return dvref / ((1-ϵ)*bvref+ϵ)
    end
end
# affine expression in NonlinearExpr
function _disaggregate_nl_expression(model::Model, aff::AffExpr, bvref::VariableRef, method::_Hull)
    new_expr = aff.constant
    ϵ = method.value
    for (vref, coeff) in aff.terms
        if is_binary(vref) || !haskey(method.disjunct_variables, (vref, bvref)) #keep any binary variables or nested disaggregated variables unchanged 
            dvref = vref
        else #replace other vars with disaggregated form
            dvref = method.disjunct_variables[vref, bvref]
        end
         new_expr += coeff * dvref / ((1-ϵ)*bvref+ϵ)
    end
    return new_expr
end
# quadratic expression in NonlinearExpr
# TODO review what happens when there are bilinear terms with binary variables involved since these are not being disaggregated 
#   (e.g., complementarity constraints; though likely irrelevant)...
function _disaggregate_nl_expression(model::Model, quad::QuadExpr, bvref::VariableRef, method::_Hull)
    #get affine part
    new_expr = _disaggregate_nl_expression(model, quad.aff, bvref, method)
    #get quadratic part
    ϵ = method.value
    for (pair, coeff) in quad.terms
        da_ref = method.disjunct_variables[pair.a, bvref]
        db_ref = method.disjunct_variables[pair.b, bvref]
        new_expr += coeff * da_ref * db_ref / ((1-ϵ)*bvref+ϵ)^2
    end
    return new_expr
end
# nonlinear expression in NonlinearExpr
function _disaggregate_nl_expression(model::Model, nlp::NonlinearExpr, bvref::VariableRef, method::_Hull)
    new_args = Vector{Any}(undef, length(nlp.args))
    for (i,arg) in enumerate(nlp.args)
        new_args[i] = _disaggregate_nl_expression(model, arg, bvref, method)
    end
    new_expr = NonlinearExpr(nlp.head, new_args)
    return new_expr
end

################################################################################
#                              HULL REFORMULATION
################################################################################
function reformulate_disjunct_constraint(
    model::Model, 
    con::ScalarConstraint{T, S}, 
    bvref::VariableRef, 
    method::_Hull
) where {T <: Union{VariableRef, AffExpr, QuadExpr}, S <: Union{_MOI.LessThan, _MOI.GreaterThan, _MOI.EqualTo}}
    new_func = _disaggregate_expression(model, con.func, bvref, method)
    set_value = _set_value(con.set)
    new_func -= set_value*bvref
    reform_con = build_constraint(error, new_func, S(0))
    return [reform_con]
end
function reformulate_disjunct_constraint(
    model::Model, 
    con::VectorConstraint{T, S, R}, 
    bvref::VariableRef, 
    method::_Hull
) where {T <: Union{VariableRef, AffExpr, QuadExpr}, S <: Union{_MOI.Nonpositives, _MOI.Nonnegatives, _MOI.Zeros}, R}
    new_func = @expression(model, [i=1:con.set.dimension],
        _disaggregate_expression(model, con.func[i], bvref, method)
    )
    reform_con = build_constraint(error, new_func, con.set)
    return [reform_con]
end
function reformulate_disjunct_constraint(
    model::Model, 
    con::ScalarConstraint{T, S}, 
    bvref::VariableRef,
    method::_Hull
) where {T <: GenericNonlinearExpr, S <: Union{_MOI.LessThan, _MOI.GreaterThan, _MOI.EqualTo}}
    con_func = _disaggregate_nl_expression(model, con.func, bvref, method)
    con_func0 = value(v -> 0.0, con.func)
    if isinf(con_func0)
        error("Operator `$(con.func.head)` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    ϵ = method.value
    set_value = _set_value(con.set)
    new_func = @expression(model, ((1-ϵ)*bvref+ϵ)*con_func - ϵ*(1-bvref)*con_func0 - set_value*bvref)
    reform_con = build_constraint(error, new_func, S(0))
    return [reform_con]
end
function reformulate_disjunct_constraint(
    model::Model, 
    con::VectorConstraint{T, S, R}, 
    bvref::VariableRef,
    method::_Hull
) where {T <: GenericNonlinearExpr, S <: Union{_MOI.Nonpositives, _MOI.Nonnegatives, _MOI.Zeros}, R}
    con_func = @expression(model, [i=1:con.set.dimension],
        _disaggregate_nl_expression(model, con.func[i], bvref, method)
    )
    con_func0 = value.(v -> 0.0, con.func)
    if any(isinf.(con_func0))
        error("At least of of the operators `$([func.head for func in con.func])` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    ϵ = method.value
    new_func = @expression(model, [i=1:con.set.dimension], 
        ((1-ϵ)*bvref+ϵ)*con_func[i] - ϵ*(1-bvref)*con_func0[i]
    )
    reform_con = build_constraint(error, new_func, con.set)
    return [reform_con]
end
function reformulate_disjunct_constraint(
    model::Model, 
    con::ScalarConstraint{T, S}, 
    bvref::VariableRef,
    method::_Hull
) where {T <: Union{VariableRef, AffExpr, QuadExpr}, S <: _MOI.Interval}
    new_func = _disaggregate_expression(model, con.func, bvref, method)
    new_func_gt = @expression(model, new_func - con.set.lower*bvref)
    new_func_lt = @expression(model, new_func - con.set.upper*bvref)
    reform_con_gt = build_constraint(error, new_func_gt, _MOI.GreaterThan(0))
    reform_con_lt = build_constraint(error, new_func_lt, _MOI.LessThan(0))
    return [reform_con_gt, reform_con_lt]
end
function reformulate_disjunct_constraint(
    model::Model, 
    con::ScalarConstraint{T, S}, 
    bvref::VariableRef,
    method::_Hull
) where {T <: GenericNonlinearExpr, S <: _MOI.Interval}
    con_func = _disaggregate_nl_expression(model, con.func, bvref, method)
    con_func0 = value(v -> 0.0, con.func)
    if isinf(con_func0)
        error("Operator `$(con.func.head)` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    ϵ = method.value
    new_func = @expression(model, ((1-ϵ)*bvref+ϵ) * con_func - ϵ*(1-bvref)*con_func0)
    new_func_gt = @expression(model, new_func - con.set.lower*bvref)
    new_func_lt = @expression(model, new_func - con.set.upper*bvref)
    reform_con_gt = build_constraint(error, new_func_gt, _MOI.GreaterThan(0))
    reform_con_lt = build_constraint(error, new_func_lt, _MOI.LessThan(0))
    return [reform_con_gt, reform_con_lt]
end