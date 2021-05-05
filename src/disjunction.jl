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
    #apply reformulation
    for (i,constr) in enumerate(disj)
        var_name = Symbol("disj_ind_$i") #create disjunction indicator binary
        eval(:(@variable($m,$var_name,Bin)))
        if constr isa Tuple || constr isa Vector
            for (j,constr_j) in enumerate(constr)
                @assert constr_j in keys(m.obj_dict) "$constr_j is not a constraint in the model."
                @assert is_valid(m,m[constr_j]) "$constr_j is not a valid constraint in the model."
                constr_set = constraint_object(m[constr_j]).set
                set_fields = fieldnames(typeof(constr_set))
                @assert length(set_fields) == 1 "A reformulation cannot be done on constraint $constr_j because it is not one of the following GreaterThan, LessThan, or EqualTo."

                if reformulation == :BMR
                    apply_BigM(M, m, constr_j, constr_set, set_fields, vars, var_name)
                elseif reformulation == :CHR

                end
            end
        else
            @assert constr in keys(m.obj_dict) "$constr is not a constraint in the model."
            @assert is_valid(m,m[constr]) "$constr is not a valid constraint in the model."
            constr_set = constraint_object(m[constr]).set
            set_fields = fieldnames(typeof(constr_set))
            @assert length(set_fields) == 1 "A reformulation cannot be done on constraint $constr because it is not one of the following GreaterThan, LessThan, or EqualTo."

            if reformulation == :BMR
                apply_BigM(M, m, constr, constr_set, set_fields, vars, var_name)
            elseif reformulation == :(:CHR)

            end
        end
    end
end

function infer_BigM(m, constr, constr_set, set_fields, vars)
    @assert :value in set_fields || :lower in set_fields || :upper in set_fields "$constr must be one the following: GreaterThan, LessThan, or EqualTo."
    BigM = 0 #initialize BigM
    for var in vars
        coeff = normalized_coefficient(m[constr],var)
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

function apply_BigM(M, m, constr, constr_set, set_fields, vars, var_name)
    if M isa Number
        BigM = M
    elseif M isa Vector || M isa Tuple
        @assert M[i] isa Number "$constr was passed more than 1 BigM value"
        BigM = M[i]
    else
        BigM = infer_BigM(m, constr, constr_set, set_fields, vars)
    end
    add_to_function_constant(m[constr], -BigM)
    ref = m[constr]
    eval(:(set_normalized_coefficient($ref, $var_name , $BigM)))
end
