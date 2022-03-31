function BMR!(m, constr, bin_var, i, k, M)
    if ismissing(k)
        @assert is_valid(m,constr) "$constr is not a valid constraint in the model."
        ref = constr
    else
        @assert is_valid(m,constr[k...]) "$constr is not a valid constraint in the model."
        ref = constr[k...]
    end
    if ismissing(M)
        M = apply_interval_arithmetic(ref)
        # @warn "No M value passed for $ref. M = $M was inferred from the variable bounds."
    end
    if ref isa NonlinearConstraintRef
        nonlinear_bigM(ref, bin_var, M, i)
    elseif ref isa ConstraintRef
        linear_bigM(ref, bin_var, M, i)
    end
end

function linear_bigM(ref, bin_var, M, i)
    bin_var_ref = ref.model[bin_var][i]
    add_to_function_constant(ref, -M)
    set_normalized_coefficient(ref, bin_var_ref , M)
end

function nonlinear_bigM(ref, bin_var, M, i)
    #create symbolic variables (using Symbolics.jl)
    for var_ref in ref.model[:Original_VarRefs]
        var_sym = Symbol(var_ref)
        eval(:(Symbolics.@variables($var_sym)[1]))
    end
    bin_var_sym = Symbol("$bin_var[$i]")
    λ = Num(Symbolics.Sym{Float64}(bin_var_sym))
    
    #parse ref
    op, lhs, rhs = parse_NLconstraint(ref)
    replace_Symvars!(lhs, ref.model) #convert JuMP variables into Symbolic variables
    gx = eval(lhs) #convert the LHS of the constraint into a Symbolic expression
    gx = gx - M*(1-λ) #add bigM
    
    #update constraint
    replace_NLconstraint(ref, gx, op, rhs)
end