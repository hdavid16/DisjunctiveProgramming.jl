"""
    big_m_reformulation!(constr::ConstraintRef, bin_var, M, i, j, k)

Perform Big-M reformulation on a linear or quadratic constraint at index k of constraint j in disjunct i.

    big_m_reformulation!(constr::NonlinearConstraintRef, bin_var, M, i, j, k)

Perform Big-M reformulaiton on a nonlinear constraint at index k of constraint j in disjunct i.

    big_m_reformulation!(constr::AbstractArray{<:ConstraintRef}, bin_var, M, i, j, k)

Perform Big-M reformulation on a constraint at index k of constraint j in disjunct i.
"""
function big_m_reformulation!(constr::ConstraintRef, bin_var, M0, i, j, k)
    M = get_reform_param(M0, i, j, k; constr)
    if !ismissing(M0) && constraint_object(constr).set isa MOI.GreaterThan && M > 0
        M = -M #if a positive bigM value was provided and constraint is GreaterThan, use the negative of this number (-M*(1-y) <= func)
    end
    add_to_function_constant(constr, -M)
    set_normalized_coefficient(constr, constr.model[bin_var][i], M)
end
function big_m_reformulation!(constr::NonlinearConstraintRef, bin_var, M0, i, j, k)
    M = get_reform_param(M0, i, j, k; constr)
    #create symbolic variables (using Symbolics.jl)
    for var_ref in get_constraint_variables(constr)
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
    add_reformulated_constraint(constr, bin_var, gx, op, rhs)
end
big_m_reformulation!(constr::AbstractArray{<:ConstraintRef}, bin_var, M, i, j, k) =
    big_m_reformulation(constr[k], bin_var, M, i, j, k)

"""
    infer_bigm(constr)

Apply interval arithmetic on a constraint to infer the tightest Big-M value from the bounds on the constraint.
"""
function infer_bigm(constr::ConstraintRef)
    constr_obj = constraint_object(constr)
    constr_terms = constr_obj.func.terms
    constr_set = constr_obj.set
    #create a map of variables to their bounds
    bounds_dict = :variable_bounds_dict in keys(constr.model.ext) ? constr.model.ext[:variable_bounds_dict] : Dict()
    bounds_map = Dict(
        var => is_binary(var) ? (0,0) : get_bounds(var, bounds_dict) #NOTE: ignore binaries in tight-M calculation
        for var in get_constraint_variables(constr)
    )
    #apply interval arithmetic
    if constr_set isa MOI.LessThan
        M = -constr_set.upper
        for (var,coeff) in constr_terms
            if coeff > 0
                M += coeff*bounds_map[var][2]
            else
                M += coeff*bounds_map[var][1]
            end
        end
    elseif constr_set isa MOI.GreaterThan
        M = -constr_set.lower
        for (var,coeff) in constr_terms
            if coeff < 0
                M += coeff*bounds_map[var][2]
            else
                M += coeff*bounds_map[var][1]
            end
        end
    end
    isinf(M) && error("M parameter for $constr cannot be infered due to lack of variable bounds.")
    return M
end
infer_bigm(constr::NonlinearConstraintRef) = error("$constr is a nonlinear constraint and a tight Big-M parameter cannot be inferred via interval arithmetic.")