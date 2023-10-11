################################################################################
#                              BIG-M VALUE
################################################################################
# Get Big-M value for a particular constraint
function _get_M_value(func::JuMP.AbstractJuMPScalar, set::_MOI.AbstractSet, method::BigM)
    if method.tighten
        M = _get_tight_M(func, set, method)
    else
        M = _get_M(func, set, method)
    end
    return M
end

# Get the tightest Big-M value for a particular constraint
function _get_tight_M(func::JuMP.AbstractJuMPScalar, set::_MOI.AbstractSet, method::BigM)
    M = min.(method.value, _calculate_tight_M(func, set, method)) #broadcast for when S <: MOI.Interval or MOI.EqualTo or MOI.Zeros
    if any(isinf.(M))
        error("A finite Big-M value must be used. The value obtained was $M.")
    end
    return M
end

# Get user-specified Big-M value
function _get_M(::JuMP.AbstractJuMPScalar, ::Union{_MOI.LessThan, _MOI.GreaterThan, _MOI.Nonnegatives, _MOI.Nonpositives}, method::BigM)
    M = method.value
    if isinf(M)
        error("A finite Big-M value must be used. The value given was $M.")
    end
    return M
end
function _get_M(::JuMP.AbstractJuMPScalar, ::Union{_MOI.Interval, _MOI.EqualTo, _MOI.Zeros}, method::BigM)
    M = method.value
    if isinf(M)
        error("A finite Big-M value must be used. The value given was $M.")
    end
    return [M, M]
end

# Apply interval arithmetic on a linear constraint to infer the tightest Big-M value from the bounds on the constraint.
function _calculate_tight_M(func::JuMP.AffExpr, set::_MOI.LessThan, method::BigM)
    return _interval_arithmetic_LessThan(func, -set.upper, method)
end
function _calculate_tight_M(func::JuMP.AffExpr, set::_MOI.GreaterThan, method::BigM)
    return _interval_arithmetic_GreaterThan(func, -set.lower, method)
end
function _calculate_tight_M(func::JuMP.AffExpr, ::_MOI.Nonpositives, method::BigM)
    return _interval_arithmetic_LessThan(func, 0.0, method)
end
function _calculate_tight_M(func::JuMP.AffExpr, ::_MOI.Nonnegatives, method::BigM)
    return _interval_arithmetic_GreaterThan(func, 0.0, method)
end
function _calculate_tight_M(func::JuMP.AffExpr, set::_MOI.Interval, method::BigM)
    return (
        _interval_arithmetic_GreaterThan(func, -set.lower, method),
        _interval_arithmetic_LessThan(func, -set.upper, method)
    )
end
function _calculate_tight_M(func::JuMP.AffExpr, set::_MOI.EqualTo, method::BigM)
    return (
        _interval_arithmetic_GreaterThan(func, -set.value, method),
        _interval_arithmetic_LessThan(func, -set.value, method)
    )
end
function _calculate_tight_M(func::JuMP.AffExpr, ::_MOI.Zeros, method::BigM)
    return (
        _interval_arithmetic_GreaterThan(func, 0.0, method),
        _interval_arithmetic_LessThan(func, 0.0, method)
    )
end
# fallbacks for other scalar constraints
_calculate_tight_M(func::Union{JuMP.QuadExpr, JuMP.NonlinearExpr}, set::Union{_MOI.Interval, _MOI.EqualTo, _MOI.Zeros}, method::BigM) = (Inf, Inf)
_calculate_tight_M(func::Union{JuMP.QuadExpr, JuMP.NonlinearExpr}, set::Union{_MOI.LessThan, _MOI.GreaterThan, _MOI.Nonnegatives, _MOI.Nonpositives}, method::BigM) = Inf
_calculate_tight_M(func, set, method::BigM) = error("BigM method not implemented for constraint type $(typeof(func)) in $(typeof(set))")

# get variable bounds for interval arithmetic
function _update_variable_bounds(vref::JuMP.VariableRef, method::BigM)
    if JuMP.is_binary(vref)
        lb = 0
    elseif !JuMP.has_lower_bound(vref)
        lb = -Inf
    else
        lb = JuMP.lower_bound(vref)
    end
    if JuMP.is_binary(vref)
        ub = 1
    elseif !JuMP.has_upper_bound(vref)
        ub = Inf
    else
        ub = JuMP.upper_bound(vref)
    end
    return lb, ub
end

# perform interval arithmetic to update the initial M value
function _interval_arithmetic_LessThan(func::JuMP.AffExpr, M::Float64, method::BigM)
    for (var,coeff) in func.terms
        JuMP.is_binary(var) && continue #skip binary variables
        if coeff > 0
            M += coeff*method.variable_bounds[var][2]
        else
            M += coeff*method.variable_bounds[var][1]
        end
    end
    return M + func.constant
end
function _interval_arithmetic_GreaterThan(func::JuMP.AffExpr, M::Float64, method::BigM)
    for (var,coeff) in func.terms
        JuMP.is_binary(var) && continue #skip binary variables
        if coeff < 0
            M += coeff*method.variable_bounds[var][2]
        else
            M += coeff*method.variable_bounds[var][1]
        end
    end
    return -(M + func.constant)
end

################################################################################
#                              BIG-M REFORMULATION
################################################################################
function reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.LessThan}
    M = _get_M_value(con.func, con.set, method)
    new_func = JuMP.@expression(model, con.func - M*(1-bvref))
    reform_con = JuMP.build_constraint(error, new_func, con.set)    
    return [reform_con]
end
function reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.Nonpositives, R}
    M = [_get_M_value(func, con.set, method) for func in con.func]
    new_func = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] - M[i]*(1-bvref)
    )
    reform_con = JuMP.build_constraint(error, new_func, con.set)    
    return [reform_con]
end
function reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.GreaterThan}
    M = _get_M_value(con.func, con.set, method)
    new_func = JuMP.@expression(model, con.func + M*(1-bvref))
    reform_con = JuMP.build_constraint(error, new_func, con.set)
    return [reform_con]
end
function reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.Nonnegatives, R}
    M = [_get_M_value(func, con.set, method) for func in con.func]
    new_func = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] + M[i]*(1-bvref)
    )
    reform_con = JuMP.build_constraint(error, new_func, con.set)
    return [reform_con]
end
function reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: Union{_MOI.Interval, _MOI.EqualTo}}
    M = _get_M_value(con.func, con.set, method)
    new_func_gt = JuMP.@expression(model, con.func + M[1]*(1-bvref))
    new_func_lt = JuMP.@expression(model, con.func - M[2]*(1-bvref))
    set_values = _set_values(con.set)
    reform_con_gt = JuMP.build_constraint(error, new_func_gt, _MOI.GreaterThan(set_values[1]))
    reform_con_lt = JuMP.build_constraint(error, new_func_lt, _MOI.LessThan(set_values[2]))
    return [reform_con_gt, reform_con_lt]
end
function reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.Zeros, R}
    M = [_get_M_value(func, con.set, method) for func in con.func]
    new_func_nn = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] + M[i][1]*(1-bvref)
    )
    new_func_np = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] - M[i][2]*(1-bvref)
    )
    reform_con_nn = JuMP.build_constraint(error, new_func_nn, _MOI.Nonnegatives(con.set.dimension))
    reform_con_np = JuMP.build_constraint(error, new_func_np, _MOI.Nonpositives(con.set.dimension))
    return [reform_con_nn, reform_con_np]
end