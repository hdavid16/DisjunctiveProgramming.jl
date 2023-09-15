################################################################################
#                              BIG-M VALUE
################################################################################
# Get Big-M value for a particular constraint
function _get_M_value(method::BigM, func::JuMP.AbstractJuMPScalar, set::_MOI.AbstractSet)
    if method.tighten
        M = _get_tight_M(method, func, set)
    else
        M = _get_M(method, func, set)
    end
    return M
end

# Get the tightest Big-M value for a particular constraint
function _get_tight_M(method::BigM, func::JuMP.AbstractJuMPScalar, set::_MOI.AbstractSet)
    M = min.(method.value, _calculate_tight_M(func, set)) #broadcast for when S <: MOI.Interval or MOI.EqualTo or MOI.Zeros
    if any(isinf.(M))
        error("A finite Big-M value must be used. The value obtained was $M.")
    end
    return M
end

# Get user-specified Big-M value
function _get_M(method::BigM, ::JuMP.AbstractJuMPScalar, ::Union{_MOI.LessThan, _MOI.GreaterThan, _MOI.Nonnegatives, _MOI.Nonpositives})
    M = method.value
    if isinf(M)
        error("A finite Big-M value must be used. The value given was $M.")
    end
    return M
end
function _get_M(method::BigM, ::JuMP.AbstractJuMPScalar, ::Union{_MOI.Interval, _MOI.EqualTo, _MOI.Zeros})
    M = method.value
    if isinf(M)
        error("A finite Big-M value must be used. The value given was $M.")
    end
    return [M, M]
end

# Apply interval arithmetic on a linear constraint to infer the tightest Big-M value from the bounds on the constraint.
function _calculate_tight_M(func::JuMP.AffExpr, set::_MOI.LessThan)
    return _interval_arithmetic_LessThan(func, -set.upper)
end
function _calculate_tight_M(func::JuMP.AffExpr, set::_MOI.GreaterThan)
    return _interval_arithmetic_GreaterThan(func, -set.lower)
end
function _calculate_tight_M(func::JuMP.AffExpr, ::_MOI.Nonpositives)
    return _interval_arithmetic_LessThan(func, 0.0)
end
function _calculate_tight_M(func::JuMP.AffExpr, ::_MOI.Nonnegatives)
    return _interval_arithmetic_GreaterThan(func, 0.0)
end
function _calculate_tight_M(func::JuMP.AffExpr, set::_MOI.Interval)
    return (
        _interval_arithmetic_GreaterThan(func, -set.lower),
        _interval_arithmetic_LessThan(func, -set.upper)
    )
end
function _calculate_tight_M(func::JuMP.AffExpr, set::_MOI.EqualTo)
    return (
        _interval_arithmetic_GreaterThan(func, -set.value),
        _interval_arithmetic_LessThan(func, -set.value)
    )
end
function _calculate_tight_M(func::JuMP.AffExpr, ::_MOI.Zeros)
    return (
        _interval_arithmetic_GreaterThan(func, 0.0),
        _interval_arithmetic_LessThan(func, 0.0)
    )
end
# fallbacks for other scalar constraints
_calculate_tight_M(func::Union{JuMP.QuadExpr, JuMP.NonlinearExpr}, set::Union{_MOI.Interval, _MOI.EqualTo, _MOI.Zeros}) = (Inf, Inf)
_calculate_tight_M(func::Union{JuMP.QuadExpr, JuMP.NonlinearExpr}, set::Union{_MOI.LessThan, _MOI.GreaterThan, _MOI.Nonnegatives, _MOI.Nonpositives}) = Inf
_calculate_tight_M(func, set) = error("BigM method not implemented for constraint type $(typeof(func)) in $(typeof(set))")

# perform interval arithmetic to update the initial M value
function _interval_arithmetic_LessThan(func::JuMP.AffExpr, M::Float64)
    for (var,coeff) in func.terms
        JuMP.is_binary(var) && continue #skip binary variables
        if coeff > 0
            JuMP.has_upper_bound(var) || return Inf
            M += coeff*JuMP.upper_bound(var)
        else
            JuMP.has_lower_bound(var) || return Inf
            M += coeff*JuMP.lower_bound(var)
        end
    end
    return M + func.constant
end
function _interval_arithmetic_GreaterThan(func::JuMP.AffExpr, M::Float64)
    for (var,coeff) in func.terms
        JuMP.is_binary(var) && continue #skip binary variables
        if coeff < 0
            JuMP.has_upper_bound(var) || return Inf
            M += coeff*JuMP.upper_bound(var)
        else
            JuMP.has_lower_bound(var) || return Inf
            M += coeff*JuMP.lower_bound(var)
        end
    end
    return -(M + func.constant)
end