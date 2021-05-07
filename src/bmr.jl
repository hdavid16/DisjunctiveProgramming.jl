function BMR(M, m, constr, bin_var, i, j = missing)
    if M isa Number || ismissing(M)
        M = M
    elseif M isa Vector || M isa Tuple
        if M[i] isa Number
            M = M[i]
        elseif M[i] isa Vector || M[i] isa Tuple
            @assert j <= length(M[i]) "If constraint specific M values are provided, a value must be provided for each constraint in disjunct $i."
            M = M[i][j]
        else
            error("Invalid M parameter provided for disjunct $i.")
        end
    else
        error("Invalid M parameter provided for disjunct $i.")
    end
    if constr isa ConstraintRef
        add_BigM(m, constr, M, bin_var, i)
    elseif typeof(constr) <: Array
        for k in Iterators.product([1:s for s in size(constr)]...)
            add_BigM(m, constr, M, bin_var, i, k)
        end
    elseif constr isa JuMP.Containers.DenseAxisArray
        for k in Iterators.product([s for s in constr.axes]...)
            add_BigM(m, constr, M, bin_var, i, k)
        end
    end
end

function add_BigM(m, constr, M, bin_var, i, k = missing)
    if ismissing(k)
        @assert is_valid(m,constr) "$constr is not a valid constraint in the model."
        ref = constr
    else
        @assert is_valid(m,constr[k...]) "$constr is not a valid constraint in the model."
        ref = constr[k...]
    end
    if ismissing(M)
        M = infer_BigM(ref, k)
        @warn "No M value passed for $ref. M = $M was inferred from the variable bounds."
    end
    add_to_function_constant(ref, -M)
    bin_var_ref = variable_by_name(ref.model, "$bin_var[$i]")
    set_normalized_coefficient(ref, bin_var_ref , M)
end

function infer_BigM(ref, k = missing)
    constr_set = constraint_object(ref).set
    set_fields = fieldnames(typeof(constr_set))
    @assert length(set_fields) == 1 "A reformulation cannot be done on constraint $ref because it is not one of the following GreaterThan, LessThan, or EqualTo."
    @assert :value in set_fields || :lower in set_fields || :upper in set_fields "$ref must be one the following: GreaterThan, LessThan, or EqualTo."
    vars = all_variables(ref.model) #get all variable names
    M = 0 #initialize M
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
                error("M parameter cannot be infered due to lack of variable bounds for variable $var.")
            end
            M += coeff*bound
        elseif coeff < 0
            if :lower in set_fields && has_bounds[2]
                bound = upper_bound(var)
            elseif :upper in set_fields || :value in set_fields && has_bounds[1]
                bound = lower_bound(var)
            else
                error("M parameter cannot be infered due to lack of variable bounds for variable $var.")
            end
            M += coeff*bound
        end
    end
    if :lower in set_fields
        M -= constr_set.lower
    elseif :upper in set_fields
        M -= constr_set.upper
    elseif :value in set_fields
        M -= constr_set.value
    end
end
