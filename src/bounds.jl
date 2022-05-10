"""
    apply_interval_arithmetic(constr)

Apply interval arithmetic on a constraint to find the bounds on the constraint.
"""
function apply_interval_arithmetic(constr)
    #convert constraints into Expr to replace variables with interval sets and determine bounds
    constr_type, constr_func_expr, constr_rhs = parse_constraint(constr)
    #create a map of variables to their bounds
    interval_map = Dict()
    vars = all_variables(constr.model)#constr.model[:gdp_variable_constrs]
    obj_dict = object_dictionary(constr.model)
    bounds_dict = :variable_bounds_dict in keys(obj_dict) ? obj_dict[:variable_bounds_dict] : Dict() #NOTE: should pass as an keyword argument
    for var in vars
        LB, UB = get_bounds(var, bounds_dict)
        interval_map[string(var)] = LB..UB
    end
    constr_func_expr = replace_intevals!(constr_func_expr, interval_map)
    #get bounds on the entire expression
    func_bounds = eval(constr_func_expr)
    Mlo = func_bounds.lo - constr_rhs
    Mhi = func_bounds.hi - constr_rhs
    M = constr_type == :(<=) ? Mhi : Mlo
    isinf(M) && error("M parameter for $constr cannot be infered due to lack of variable bounds.")
    return M
end

"""
    get_bounds(var::VariableRef)

Get bounds on a variable.

    get_bounds(var::VariableRef, bounds_dict::Dict)

Get bounds on a variable. Check if a bounds dictionary has ben provided with bounds for that value.

    get_bounds(var::AbstractArray, bounds_dict::Dict, LB, UB)
    
Update lower bound `LB` and upper bound `UB` on a variable container.
    
    get_bounds(var::Array{VariableRef}, bounds_dict::Dict)
    
Get lower and upper bounds on a variable array.
    
    get_bounds(var::Containers.DenseAxisArray, bounds_dict::Dict)
    
Get lower and upper bounds on a variable DenseAxisArray.
    
    get_gounds(var::Containers.SparseAxisArray, bounds_dict::Dict)

Get lower and upper bounds on a variable SparseAxisArray.
"""
function get_bounds(var::VariableRef)
    LB = has_lower_bound(var) ? lower_bound(var) : (is_binary(var) ? 0 : -Inf)
    UB = has_upper_bound(var) ? upper_bound(var) : (is_binary(var) ? 1 : Inf)
    return LB, UB
end
function get_bounds(var::VariableRef, bounds_dict::Dict)
    if string(var) in keys(bounds_dict)
        return bounds_dict[string(var)]
    else
        return get_bounds(var)
    end
end
function get_bounds(var::AbstractArray, bounds_dict::Dict, LB, UB)
    #populate UB and LB
    for idx in eachindex(var)
        LB[idx], UB[idx] = get_bounds(var[idx], bounds_dict)
    end
    return LB, UB
end
function get_bounds(var::Array{VariableRef}, bounds_dict::Dict)
    #initialize
    LB, UB = zeros(size(var)), zeros(size(var))
    return get_bounds(var, bounds_dict, LB, UB)
end
function get_bounds(var::Containers.DenseAxisArray, bounds_dict::Dict)
    #initialize
    LB = Containers.DenseAxisArray(zeros(size(var)), axes(var)...)
    UB = Containers.DenseAxisArray(zeros(size(var)), axes(var)...)
    return get_bounds(var, bounds_dict, LB, UB)
end
function get_gounds(var::Containers.SparseAxisArray, bounds_dict::Dict)
    #initialize
    idxs = keys(var.data)
    LB = Containers.SparseAxisArray(Dict(idx => 0. for idx in idxs))
    UB = Containers.SparseAxisArray(Dict(idx => 0. for idx in idxs))
    return get_bounds(var, bounds_dict, LB, UB)
end