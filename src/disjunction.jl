function add_disjunction(m::Model,disj...;reformulation=:BMR,BigM=missing,kw_args...)
    @assert m isa Model "A valid JuMP Model must be provided."
    @assert reformulation in [:BMR, :CHR] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."

    #create binary indicator variables for each disjunction
    bin_var = Symbol("disj_binary_",gensym())
    eval(:(@variable($m, $bin_var[i = 1:length($disj)], Bin)))
    #enforce exclussive OR
    eval(:(@constraint($m,sum($bin_var[i] for i = 1:length($disj)) == 1)))
    #apply reformulation
    for (i,constr) in enumerate(disj)
        if constr isa Vector || constr isa Tuple
            for (j,constr_j) in enumerate(constr)
                if reformulation == :BMR
                    apply_BigM(BigM, m, constr_j, bin_var, i, j)
                elseif reformulation == :CHR

                end
            end
        elseif constr isa ConstraintRef || typeof(constr) <: Array || constr isa JuMP.Containers.DenseAxisArray
            if reformulation == :BMR
                apply_BigM(BigM, m, constr, bin_var, i)
            elseif reformulation == :(:CHR)

            end
        end
    end
end

function apply_BigM(BigM, m, constr, bin_var, i, j = missing)
    if BigM isa Number || ismissing(BigM)
        BigM = BigM
    elseif BigM isa Vector || BigM isa Tuple
        if BigM[i] isa Number
            BigM = BigM[i]
        elseif BigM[i] isa Vector || BigM[i] isa Tuple
            @assert j <= length(BigM[i]) "If constraint specific BigM values are provided, a value must be provided for each constraint in disjunct $i."
            BigM = BigM[i][j]
        else
            error("Invalid BigM parameter provided for disjunct $i.")
        end
    else
        error("Invalid BigM parameter provided for disjunct $i.")
    end
    if constr isa ConstraintRef
        set_BigM(m, constr, BigM, bin_var, i)
    elseif typeof(constr) <: Array
        for k in Iterators.product([1:s for s in size(constr)]...)
            set_BigM(m, constr, BigM, bin_var, i, k)
        end
    elseif constr isa JuMP.Containers.DenseAxisArray
        for k in Iterators.product([s for s in constr.axes]...)
            set_BigM(m, constr, BigM, bin_var, i, k)
        end
    end
end

function set_BigM(m, constr, BigM, bin_var, i, k = missing)
    if ismissing(k)
        @assert is_valid(m,constr) "$constr is not a valid constraint in the model."
        ref = constr
    else
        @assert is_valid(m,constr[k...]) "$constr is not a valid constraint in the model."
        ref = constr[k...]
    end
    if ismissing(BigM)
        BigM = infer_BigM(ref, k)
        @warn "No BigM value passed for $ref. BigM = $BigM was inferred from the variable bounds."
    end
    add_to_function_constant(ref, -BigM)
    bin_var_ref = variable_by_name(ref.model, "$bin_var[$i]")
    set_normalized_coefficient(ref, bin_var_ref , BigM)
end

function infer_BigM(ref, k = missing)
    constr_set = constraint_object(ref).set
    set_fields = fieldnames(typeof(constr_set))
    @assert length(set_fields) == 1 "A reformulation cannot be done on constraint $ref because it is not one of the following GreaterThan, LessThan, or EqualTo."
    @assert :value in set_fields || :lower in set_fields || :upper in set_fields "$ref must be one the following: GreaterThan, LessThan, or EqualTo."
    vars = all_variables(ref.model) #get all variable names
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
end
