function add_disjunction(m::Model,disj...;reformulation=:BMR,BigM=missing,kw_args...)
    @assert m isa Model "A valid JuMP Model must be provided."
    @assert reformulation in [:BMR, :CHR] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."

    #Big-M
    if reformulation == :BMR
        M = BigM
        if ismissing(M)
            @warn "No BigM value passed for use in Big-M Reformulation. BigM values will be inferred from variable bounds."
        end
    end
    #get all variable names
    vars = all_variables(m)
    #create binary indicator varialbes for each disjunction
    bin_var = Symbol("disj_binary_",gensym())
    eval(:(@variable($m, $bin_var[i = 1:length($disj)], Bin)))
    eval(:(@constraint($m,sum($bin_var[i] for i = 1:length($disj)) == 1)))
    #apply reformulation
    for (i,constr) in enumerate(disj)
        if constr isa Tuple || constr isa Vector || Meta.isexpr(constr,:tuple) || Meta.isexpr(constr,:vect)
            for (j,constr_j) in enumerate(constr)
                if reformulation == :BMR
                    apply_BigM(M, m, constr_j, vars, bin_var, i, j)
                elseif reformulation == :CHR

                end
            end
        elseif constr isa Symbol
            if reformulation == :BMR
                apply_BigM(M, m, constr, vars, bin_var, i)
            elseif reformulation == :(:CHR)

            end
        end
    end
end

function infer_BigM(m, constr, vars, k = missing)
    @assert constr in keys(m.obj_dict) "$constr is not a constraint in the model."
    if ismissing(k)
        @assert is_valid(m,m[constr]) "$constr is not a valid constraint in the model."
        ref = m[constr]
    else
        @assert is_valid(m,m[constr][k]) "$constr is not a valid constraint in the model."
        ref = m[constr][k]
    end
    constr_set = constraint_object(ref).set
    set_fields = fieldnames(typeof(constr_set))
    @assert length(set_fields) == 1 "A reformulation cannot be done on constraint $ref because it is not one of the following GreaterThan, LessThan, or EqualTo."
    @assert :value in set_fields || :lower in set_fields || :upper in set_fields "$ref must be one the following: GreaterThan, LessThan, or EqualTo."
    BigM = 0 #initialize BigM
    for var in vars
        coeff = normalized_coefficient(ref,var)
        iszero(coeff) && continue
        has_bounds = (has_lower_bound(var), has_upper_bound(var))
        if coeff > 0
            if :lower in set_fields && has_bounds[1]
                bound = lower_bound(var)
            elseif :upper in set_fields || :value in set_fields && has_bounds[2]
                bound = upper_bound(var)
            else
                error("BigM parameter cannot be infered due to lack of variable bounds for variable $var.")
            end
            BigM += coeff*bound
        elseif coeff < 0
            if :lower in set_fields && has_bounds[2]
                bound = upper_bound(var)
            elseif :upper in set_fields || :value in set_fields && has_bounds[1]
                bound = lower_bound(var)
            else
                error("BigM parameter cannot be infered due to lack of variable bounds for variable $var.")
            end
            BigM += coeff*bound
        end
    end
    if :lower in set_fields
        BigM -= constr_set.lower
    elseif :upper in set_fields
        BigM -= constr_set.upper
    elseif :value in set_fields
        BigM -= constr_set.value
    end

    return BigM
end

function apply_BigM(M, m, constr, vars, bin_var, i, j = missing)
    if M isa Number
        BigM = M
        set_BigM(m, constr, BigM, bin_var, i)
    elseif M isa Vector || M isa Tuple
        if M[i] isa Number
            BigM = M[i]
        elseif M[i] isa Vector || M[i] isa Tuple
            BigM = M[i][j]
        else
            error("Invalid BigM parameter provided for disjunct $i.")
        end
        set_BigM(m, constr, BigM, bin_var, i)
    elseif m[constr] isa ConstraintRef
        BigM = infer_BigM(m, constr, vars)
        set_BigM(m, constr, BigM, bin_var, i)
    elseif m[constr] isa Vector
        for k in 1:length(m[constr])
            BigM = infer_BigM(m, constr, vars, k)
            set_BigM(m, con, BigM, bin_var, i, k)
        end
    elseif m[constr] isa JuMP.Containers.DenseAxisArray
        for k in m[constr].axes[1]
            BigM = infer_BigM(m, constr, vars, k)
            set_BigM(m, con, BigM, bin_var, i, k)
        end
    end

end

function set_BigM(m, constr, BigM, bin_var, i, k = missing)
    add_to_function_constant(m[constr], -BigM)
    if ismissing(k)
        ref = m[constr]
    else
        ref = m[constr][k]
    end
    eval(:(set_normalized_coefficient($ref, $bin_var[$i] , $BigM)))
end
