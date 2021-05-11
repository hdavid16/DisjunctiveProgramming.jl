function reformulate(m, disj, bin_var, reformulation, M)
    vars = setdiff(all_variables(m), m[bin_var])
    @expression(m, original_model_variables, vars)
    for (i,constr) in enumerate(disj)
        if constr isa Vector || constr isa Tuple
            for (j,constr_j) in enumerate(constr)
                init_reformulation(m, constr_j, bin_var, reformulation, M, i, j)
            end
        elseif constr isa ConstraintRef || typeof(constr) <: Array || constr isa JuMP.Containers.DenseAxisArray
            init_reformulation(m, constr, bin_var, reformulation, M, i)
        end
    end
    if reformulation == :CHR
        add_disaggregated_constr(m, disj, vars)
    end
end

function init_reformulation(m, constr, bin_var, reformulation, M, i, j = missing)
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
        eval(:($reformulation($m, $constr, $M, $bin_var, $i)))
    elseif typeof(constr) <: Array
        for k in Iterators.product([1:s for s in size(constr)]...)
            eval(:($reformulation($m, $constr, $M, $bin_var, $i, $k)))
        end
    elseif constr isa JuMP.Containers.DenseAxisArray
        for k in Iterators.product([s for s in constr.axes]...)
            eval(:($reformulation($m, $constr, $M, $bin_var, $i, $k)))
        end
    end
end

function BMR(m, constr, M, bin_var, i, k = missing)
    if ismissing(k)
        @assert is_valid(m,constr) "$constr is not a valid constraint in the model."
        ref = constr
    else
        @assert is_valid(m,constr[k...]) "$constr is not a valid constraint in the model."
        ref = constr[k...]
    end
    if ismissing(M)
        M = apply_interval_arithmetic(ref)
        @warn "No M value passed for $ref. M = $M was inferred from the variable bounds."
    end
    add_to_function_constant(ref, -M)
    bin_var_ref = variable_by_name(ref.model, string(bin_var[i]))
    set_normalized_coefficient(ref, bin_var_ref , M)
end

function apply_interval_arithmetic(ref)
    if ref isa NonlinearConstraintRef
        ref_str = string(ref)
        @assert length(findall(r"[<>]", ref_str)) <= 1 "$ref must be one of the following: GreaterThan, LessThan, or EqualTo."
        ref_func = replace(split(ref_str, r"[=<>]")[1], " " => "")
        ref_type = occursin(">", ref_str) ? :lower : :upper
        ref_rhs = parse(Float64,split(ref_str, " ")[end])
    elseif ref isa ConstraintRef
        ref_obj = constraint_object(ref)
        @assert ref_obj.set isa MOI.LessThan || ref_obj.set isa MOI.GreaterThan || ref_obj.set isa MOI.EqualTo "$ref must be one the following: GreaterThan, LessThan, or EqualTo."
        ref_func = string(ref_obj.func)
        ref_type = fieldnames(typeof(ref_obj.set))[1]
        ref_rhs = normalized_rhs(ref)
    end
    vars = all_variables(ref.model) #get all variable names
    for var in vars
        if has_upper_bound(var)
            ub = upper_bound(var)
        else
            ub = Inf
        end
        if has_lower_bound(var)
            lb = lower_bound(var)
        else
            lb = -Inf
        end
        ref_func = replace(ref_func, string(var) => "($lb..$ub)")
    end
    func_bounds = eval(Meta.parse(ref_func))
    if ref_type == :lower
        M = func_bounds.lo - ref_rhs

    else
        M = func_bounds.hi - ref_rhs
    end
    if isinf(M)
        error("M parameter for $ref cannot be infered due to lack of variable bounds.")
    else
        return M
    end
end

function CHR(m, constr, M, bin_var, i, k = missing)
    if ismissing(k)
        @assert is_valid(m,constr) "$constr is not a valid constraint in the model."
        ref = constr
    else
        @assert is_valid(m,constr[k...]) "$constr is not a valid constraint in the model."
        ref = constr[k...]
    end
    bin_var_ref = variable_by_name(ref.model, string(bin_var[i]))
    constr_set = constraint_object(ref).set
    set_fields = fieldnames(typeof(constr_set))
    @assert length(set_fields) == 1 "A reformulation cannot be done on constraint $ref because it is not one of the following GreaterThan, LessThan, or EqualTo."
    @assert :value in set_fields || :lower in set_fields || :upper in set_fields "$ref must be one the following: GreaterThan, LessThan, or EqualTo."
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
        #create disaggregated variable
        var_i = Symbol("$(var)_$i")
        if !(var_i in keys(m.obj_dict))
            eval(:(@variable($m, 0 <= $var_i <= $M)))
            eval(:(@constraint($m, $var_i <= $M * $bin_var_ref)))
        end
        #create convex hull constraint
        rhs = normalized_rhs(ref)
        set_normalized_rhs(ref,0)
        set_normalized_coefficient(ref, var, 0)
        set_normalized_coefficient(ref, m[var_i], coeff)
        set_normalized_coefficient(ref, bin_var_ref, -rhs)
    end
end

function add_disaggregated_constr(m, disj, vars)
    for var in vars
        d_vars = []
        for i in 1:length(disj)
            var_i = Symbol("$(var)_$i")
            var_i in keys(m.obj_dict) && push!(d_vars, m[var_i])
        end
        !isempty(d_vars) && eval(:(@constraint($m, $var == sum($d_vars))))
    end
end

###                             DEPRECATED                                   ###
function infer_BigM(ref)
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
