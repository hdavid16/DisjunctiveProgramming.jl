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
    if reformulation == :BMR
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
    end
    if constr isa ConstraintRef
        eval(:($reformulation($m, $constr, $bin_var, $i, $j; M = $M)))
    elseif typeof(constr) <: Array
        for k in Iterators.product([1:s for s in size(constr)]...)
            eval(:($reformulation($m, $constr, $bin_var, $i, $j, $k; M = $M)))
        end
    elseif constr isa JuMP.Containers.DenseAxisArray
        for k in Iterators.product([s for s in constr.axes]...)
            eval(:($reformulation($m, $constr, $M, $bin_var, $i, $j, $k; M = $M)))
        end
    end
end

function BMR(m, constr, bin_var, i, j, k = missing; M)
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
        ref_rhs = 0 #Could be calculated with: parse(Float64,split(ref_str, " ")[end]). NOTE: @NLconstraint will always have a 0 RHS.
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
        ref_func = replace(ref_func, "$var" => "($lb..$ub)")
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

function CHR(m, constr, bin_var, i, j, k = missing; M = missing)
    if ismissing(k)
        if constr isa NonlinearConstraintRef #NOTE: CAN'T CHECK IF NL CONSTR IS VALID
            # @assert constr in keys(m.obj_dict) "$constr is not a named reference in the model."
        elseif constr isa ConstraintRef
            @assert is_valid(m,constr) "$constr is not a valid constraint in the model."
        end
        ref = constr
    else
        if constr isa NonlinearConstraintRef #NOTE: CAN'T CHECK IF NL CONSTR IS VALID
            # @assert constr in keys(m.obj_dict) "$constr is not a named reference in the model."
        elseif constr isa ConstraintRef
            @assert is_valid(m,constr[k...]) "$constr is not a valid constraint in the model."
        end
        ref = constr[k...]
    end
    bin_var_ref = variable_by_name(ref.model, string(bin_var[i]))
    for var in m[:original_model_variables]
        #get bounds for disaggregated variable
        @assert has_upper_bound(var) "Variable $var does not have an upper bound."
        @assert has_lower_bound(var) "Variable $var does not have a lower bound."
        UB = upper_bound(var)
        LB = lower_bound(var)
        #create disaggregated variable
        var_i = Symbol("$(var)_$i")
        if !(var_i in keys(m.obj_dict))
            eval(:(@variable($m, $LB <= $var_i <= $UB)))
            eval(:(@constraint($m, $LB * $bin_var_ref <= $var_i)))
            eval(:(@constraint($m, $var_i <= $UB * $bin_var_ref)))
        end
    end
    #create convex hull constraint
    if ref isa NonlinearConstraintRef
        nl_perspective_function(ref, bin_var_ref, i, j, k)
    elseif ref isa ConstraintRef
        lin_perspective_function(ref, bin_var_ref, i, j, k)
    end
end

function nl_perspective_function(ref, bin_var_ref, i, j, k)
    #extract info
    ref_str = string(ref)
    m = ref.model
    disj_name = replace("$(bin_var_ref)", "_binary" => "")
    vars = m[:original_model_variables]

    #get function and operator for NLconstraint
    @assert length(findall(r"[<>]", ref_str)) <= 1 "$ref must be one of the following: GreaterThan, LessThan, or EqualTo."
    ref_func = split(ref_str, r"[=<>]")[1]
    ref_op = occursin(">=", ref_str) ? ">=" : (occursin("<=", ref_str) ? "<=" : "==")

    #create and fix epsilon variable for the perspective function (Furman and Sawaya formulation)
    eps = Symbol("$(disj_name)_eps")
    eval(:(@variable($m, $eps)))
    fix(variable_by_name(m, "$eps"), 1e-6) #fix epsilon to default value of 1e-6

    #create symbolic variables (using Symbolics.jl v0.1.25)
    sym_vars1, sym_vars2 = [],[]
    for var in vars
        var_sym1 = Symbol(var)
        var_sym2 = Symbol("m[:$var]")
        push!(sym_vars1, eval(:(Symbolics.@variables($var_sym1)))[1])
        push!(sym_vars2, eval(:(Symbolics.@variables($var_sym2)))[1])
    end
    ϵ = Num(Symbolics.Sym{Float64}(Symbol("m[:$eps]")))
    λ = Num(Symbolics.Sym{Float64}(Symbol("m[:$bin_var_ref]")))
    furman_sawaya = Num(Symbolics.Sym{Float64}(gensym()))

    #convert ref_func into a symbolic expression
    ref_sym = eval(Meta.parse(ref_func))

    #use symbolic substitution to obtain the following expression:
    # [(1-ϵ)⋅λ + ϵ]⋅g(v/[(1-ϵ)⋅λ + ϵ]) - ϵ⋅g(0)⋅(1-λ) <= 0
    g = furman_sawaya*substitute(ref_sym, Dict(var1 => var2/furman_sawaya for (var1,var2) in zip(sym_vars1, sym_vars2)))
    g0 = ϵ*(1-λ)*substitute(ref_sym, Dict(var => 0 for var in sym_vars1))
    pers_func = simplify(g - g0, expand = true) #perform symbolic simplifications
    pers_func = substitute(pers_func, Dict(furman_sawaya => (1-ϵ)*λ+ϵ))
    pers_func = simplify(pers_func)

    #convert symbolic expression of the perspective funciton to a string and remove unnecessary strings
    pers_func_str = string(pers_func, ref_op, 0)
    pers_func_str = replace(pers_func_str, "var\"" => "") #remove prefix to symbols starting with m[: (for the JuMP variables)
    pers_func_str = replace(pers_func_str, "]\"" => "]") #remove sufix to symbols ending with ] (for the JuMP variables)

    #create name for perspective function constraint
    j = ismissing(j) ? "" : j
    k = ismissing(k) ? "" : k
    pers_func_name = Symbol("perspective_func_$(disj_name)_$(j)_$k")

    #NOTE: the new NLconstraint needs to be defined by the expression in pers_func_str.
    #This has been attempted by running the following:
    # pers_func_sym = Meta.parse(pers_func_str)
    # eval(:(@NLconstraint($m,$pers_func_name,$pers_func_sym)))
    #However, this effor has been unsuccessful due to the variable scope (hygene).
    #An expression needs to be created for $pers_func_sym which uses interpolation
    #   (i.e., $VariableRef) for each of the variables in sym_vars, ϵ, λ

    #NOTE: the NLconstraint defined by `ref` needs to be deleted. However, this
    #   is not currently possible: https://github.com/jump-dev/JuMP.jl/issues/2355.
    #   As of today (5/12/21), JuMP is behind on its support for nonlinear systems.

    #NOTE: some ideas to extract information from pers_func_str
    #Find the locations of all of the model variables in pers_func_str:
    #   model_refs_loc = findall(r"m\[:(.*?)\]",pers_func_str)
    #Get a unique list of model variables in pers_func_str:
    #   model_refs = unique([pers_func_str[loc] for loc in model_refs_loc])
    #Get the VariableRef for each of these variables and store in a Dict:
    #   model_refs_dict = Dict(model_ref => variable_by_name(m, string(split(split("$model_ref",":")[2],"]")[1]))
    #                          for model_ref in model_refs)
end

function lin_perspective_function(ref, bin_var_ref, i, j, k)
    #check constraint type
    ref_obj = constraint_object(ref)
    @assert ref_obj.set isa MOI.LessThan || ref_obj.set isa MOI.GreaterThan || ref_obj.set isa MOI.EqualTo "$ref must be one the following: GreaterThan, LessThan, or EqualTo."
    for var in ref.model[:original_model_variables]
        #check var is present in the constraint
        coeff = normalized_coefficient(ref,var)
        iszero(coeff) && continue
        #modify constraint using convex hull
        rhs = normalized_rhs(ref) #get rhs
        var_i_ref = variable_by_name(ref.model, "$(var)_$i")
        set_normalized_rhs(ref,0) #set rhs to 0
        set_normalized_coefficient(ref, var, 0) #remove original variable
        set_normalized_coefficient(ref, var_i_ref, coeff) #add disaggregated variable
        set_normalized_coefficient(ref, bin_var_ref, -rhs) #add binary variable
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

################################################################################
###                             DEPRECATED                                   ###
################################################################################
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
