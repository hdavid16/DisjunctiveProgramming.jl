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

################################################################################
#                              BIG-M REFORMULATION
################################################################################
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM,
    name::String,
    nested::Bool
) where {T, S <: _MOI.LessThan}
    M = _get_M_value(method, con.func, con.set)
    new_func = JuMP.@expression(model, con.func - M*(1-bvref))
    reform_con = JuMP.build_constraint(error, new_func, con.set)
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
    method::BigM,
    name::String,
    nested::Bool
) where {T, S <: _MOI.Nonpositives, R}
    M = [_get_M_value(method, func, con.set) for func in con.func]
    new_func = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] - M[i]*(1-bvref)
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
    method::BigM,
    name::String,
    nested::Bool
) where {T, S <: _MOI.GreaterThan}
    M = _get_M_value(method, con.func, con.set)
    new_func = JuMP.@expression(model, con.func + M*(1-bvref))
    reform_con = JuMP.build_constraint(error, new_func, con.set)
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
    method::BigM,
    name::String,
    nested::Bool
) where {T, S <: _MOI.Nonnegatives, R}
    M = [_get_M_value(method, func, con.set) for func in con.func]
    new_func = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] + M[i]*(1-bvref)
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
    method::BigM,
    name::String,
    nested::Bool
) where {T, S <: Union{_MOI.Interval, _MOI.EqualTo}}
    M = _get_M_value(method, con.func, con.set)
    new_func_gt = JuMP.@expression(model, con.func + M[1]*(1-bvref))
    new_func_lt = JuMP.@expression(model, con.func - M[2]*(1-bvref))
    set_values = _set_values(con.set)
    reform_con_gt = JuMP.build_constraint(error, new_func_gt, _MOI.GreaterThan(set_values[1]))
    reform_con_lt = JuMP.build_constraint(error, new_func_lt, _MOI.LessThan(set_values[2]))
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
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef,
    method::BigM,
    name::String,
    nested::Bool
) where {T, S <: _MOI.Zeros, R}
    M = [_get_M_value(method, func, con.set) for func in con.func]
    new_func_nn = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] + M[i][1]*(1-bvref)
    )
    new_func_np = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] - M[i][2]*(1-bvref)
    )
    reform_con_nn = JuMP.build_constraint(error, new_func_nn, _MOI.Nonnegatives(con.set.dimension))
    reform_con_np = JuMP.build_constraint(error, new_func_np, _MOI.Nonpositives(con.set.dimension))
    if !nested
        con_name1 = isempty(name) ? name : string(name, "_", bvref, "_1")
        con_name2 = isempty(name) ? name : string(name, "_", bvref, "_2")
        _add_reformulated_constraint(model, reform_con_nn, con_name1)
        _add_reformulated_constraint(model, reform_con_np, con_name2)
    end

    return [reform_con_nn, reform_con_np]
end