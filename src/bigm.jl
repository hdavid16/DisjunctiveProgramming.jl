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
    bin_var_ref = constr.model[bin_var][i]
    add_to_function_constant(constr, -M)
    set_normalized_coefficient(constr, bin_var_ref , M)
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