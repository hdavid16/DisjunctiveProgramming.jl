"""
    _calculate_tight_M

Apply interval arithmetic on a linear constraint to infer the tightest Big-M value from the bounds on the constraint.
"""
function _calculate_tight_M(con::DisjunctConstraint{JuMP.AffExpr, S}) where {S <: _MOI.LessThan}
    return _interval_arithmetic_LessThan(con, -con.set.upper)
end
function _calculate_tight_M(con::DisjunctConstraint{JuMP.AffExpr, S}) where {S <: _MOI.GreaterThan}
    return _interval_arithmetic_GreaterThan(con, -con.set.lower)
end
function _calculate_tight_M(con::DisjunctConstraint{JuMP.AffExpr, S}) where {S <: _MOI.Interval}
    return [
        _interval_arithmetic_GreaterThan(con, -con.set.lower),
        _interval_arithmetic_LessThan(con, -con.set.upper)
    ]
end
function _calculate_tight_M(con::DisjunctConstraint{JuMP.AffExpr, S}) where {S <: _MOI.EqualTo}
    return [
        _interval_arithmetic_GreaterThan(con, -con.set.value),
        _interval_arithmetic_LessThan(con, -con.set.value)
    ]
end
# fallbacks for other scalar constraints
_calculate_tight_M(con::DisjunctConstraint{T, S}) where {T <: Union{JuMP.QuadExpr, JuMP.NonlinearExpr}, S <: Union{_MOI.Interval, _MOI.EqualTo}} = [Inf, Inf]
_calculate_tight_M(con::DisjunctConstraint{T, S}) where {T <: Union{JuMP.QuadExpr, JuMP.NonlinearExpr}, S <: Union{_MOI.LessThan, _MOI.GreaterThan}} = Inf

"""

"""
function _interval_arithmetic_LessThan(con::DisjunctConstraint{JuMP.AffExpr, T}, M::Float64) where {T}
    for (var,coeff) in con.func.terms
        JuMP.is_binary(var) && continue #skip binary variables
        if coeff > 0
            JuMP.has_upper_bound(var) || return Inf
            M += coeff*JuMP.upper_bound(var)
        else
            JuMP.has_lower_bound(var) || return Inf
            M += coeff*JuMP.lower_bound(var)
        end
    end
    
    return M + con.func.constant
end

"""

"""
function _interval_arithmetic_GreaterThan(con::DisjunctConstraint{JuMP.AffExpr, T}, M::Float64) where {T}
    for (var,coeff) in con.func.terms
        JuMP.is_binary(var) && continue #skip binary variables
        if coeff < 0
            JuMP.has_upper_bound(var) || return Inf
            M += coeff*JuMP.upper_bound(var)
        else
            JuMP.has_lower_bound(var) || return Inf
            M += coeff*JuMP.lower_bound(var)
        end
    end
    
    return -(M + con.func.constant)
end