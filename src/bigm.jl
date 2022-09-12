"""
    big_m_reformulation!(constr::ConstraintRef, bin_var, M, i, j, k)

Perform Big-M reformulation on a linear or quadratic constraint at index k of constraint j in disjunct i.

    big_m_reformulation!(constr::NonlinearConstraintRef, bin_var, M, i, j, k)

Perform Big-M reformulaiton on a nonlinear constraint at index k of constraint j in disjunct i.

    big_m_reformulation!(constr::AbstractArray{<:ConstraintRef}, bin_var, M, i, j, k)

Perform Big-M reformulation on a constraint at index k of constraint j in disjunct i.
"""
function big_m_reformulation!(constr::ConstraintRef, bin_var, M, i, j, k)
    M = get_reform_param(M, i, j, k; constr)
    add_to_function_constant(constr, -M)
    set_normalized_coefficient(constr, constr.model[bin_var][i] , M)
end
function big_m_reformulation!(constr::NonlinearConstraintRef, bin_var, M, i, j, k)
    M = get_reform_param(M, i, j, k; constr)
    #create symbolic variables (using Symbolics.jl)
    for var_ref in get_constraint_variables(constr.model, constr)
        symbolic_variable(var_ref)
    end
    bin_var_sym = Symbol("$bin_var[$i]")
    λ = Num(Symbolics.Sym{Float64}(bin_var_sym))
    
    #parse constr
    op, lhs, rhs = parse_constraint(constr)
    replace_Symvars!(lhs, constr.model) #convert JuMP variables into Symbolic variables
    gx = eval(lhs) #convert the LHS of the constraint into a Symbolic expression
    gx = gx - M*(1-λ) #add bigM
    
    #update constraint
    replace_constraint(constr, bin_var, gx, op, rhs)
end
big_m_reformulation!(constr::AbstractArray{<:ConstraintRef}, bin_var, M, i, j, k) =
    big_m_reformulation(constr[k], bin_var, M, i, j, k)

"""
    infer_bigm(constr)

Apply interval arithmetic on a constraint to infer the tightest Big-M value from the bounds on the constraint.
"""
function infer_bigm(constr::ConstraintRef)
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
infer_bigm(constr::NonlinearConstraintRef) = error("$constr is a nonlinear constraint and a tight Big-M parameter cannot be inferred via interval arithmetic.")