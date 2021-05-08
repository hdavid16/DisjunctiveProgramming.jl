function CHR(M, m, disj, bin_var)
    vars = setdiff(all_variables(m), bin_var)
    @expression(m, original_model_variables, vars)
    for (i,constr) in enumerate(disj)
        if constr isa Vector || constr isa Tuple
            for (j,constr_j) in enumerate(constr)
                apply_CHR(M, m, constr_j, bin_var, i, j)
            end
        elseif constr isa ConstraintRef || typeof(constr) <: Array || constr isa JuMP.Containers.DenseAxisArray
            apply_CHR(M, m, constr, bin_var, i)
        end
    end
    for var in vars
        d_vars = []
        for i in 1:length(disj)
            var_i = Symbol("$(var)_$i")
            var_i in keys(m.obj_dict) && push!(d_vars, m[var_i])
        end
        !isempty(d_vars) && eval(:(@constraint($m, $var == sum($d_vars))))
    end
    # unregister(m, :original_model_variables)
end

function apply_CHR(M, m, constr, bin_var, i, j = missing)
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
        disaggregate_vars(m, constr, M, bin_var, i)
    elseif typeof(constr) <: Array
        for k in Iterators.product([1:s for s in size(constr)]...)
            disaggregate_vars(m, constr, M, bin_var, i, k)
        end
    elseif constr isa JuMP.Containers.DenseAxisArray
        for k in Iterators.product([s for s in constr.axes]...)
            disaggregate_vars(m, constr, M, bin_var, i, k)
        end
    end
end

function disaggregate_vars(m, constr, M, bin_var, i, k = missing)
    if ismissing(k)
        @assert is_valid(m,constr) "$constr is not a valid constraint in the model."
        ref = constr
    else
        @assert is_valid(m,constr[k...]) "$constr is not a valid constraint in the model."
        ref = constr[k...]
    end
    bin_var_ref = variable_by_name(ref.model, string(bin_var[i]))
    for var in m[:original_model_variables]
        coeff = normalized_coefficient(ref,var)
        iszero(coeff) && continue
        if ismissing(M)
            if has_upper_bound(var)
                M = upper_bound(var)
            else
                error("Variable $var does not have an upper bound, an M value must be specified")
            end
        end
        var_i = Symbol("$(var)_$i")
        if !(var_i in keys(m.obj_dict))
            eval(:(@variable($m, 0 <= $var_i <= $M)))
            eval(:(@constraint($m, $var_i <= $M * $bin_var_ref)))
        end
        rhs = normalized_rhs(ref)
        set_normalized_rhs(ref,0)
        set_normalized_coefficient(ref, var, 0)
        set_normalized_coefficient(ref, m[var_i], coeff)
        set_normalized_coefficient(ref, bin_var_ref, -rhs)
    end
end
