function reformulate(m, disj, bin_var, reformulation, M, eps)
    vars = setdiff(all_variables(m), m[bin_var])
    @expression(m, original_model_variables, vars)
    for (i,constr) in enumerate(disj)
        if constr isa Vector || constr isa Tuple
            for (j,constr_j) in enumerate(constr)
                init_reformulation(m, constr_j, bin_var, reformulation, M, eps, i, j)
            end
        elseif constr isa ConstraintRef || typeof(constr) <: Array || constr isa JuMP.Containers.DenseAxisArray
            init_reformulation(m, constr, bin_var, reformulation, M, eps, i)
        end
    end
    if reformulation == :CHR
        add_disaggregated_constr(m, disj, vars)
    end
end

function init_reformulation(m, constr, bin_var, reformulation, M, eps, i, j = missing)
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
        eval(:($reformulation($m, $constr, $bin_var, $i, $j; M = $M, eps = $eps)))
    elseif typeof(constr) <: Array
        for k in Iterators.product([1:s for s in size(constr)]...)
            eval(:($reformulation($m, $constr, $bin_var, $i, $j, $k; M = $M, eps = $eps)))
        end
    elseif constr isa JuMP.Containers.DenseAxisArray
        for k in Iterators.product([s for s in constr.axes]...)
            eval(:($reformulation($m, $constr, $M, $bin_var, $i, $j, $k; M = $M, eps = $eps)))
        end
    end
end

function BMR(m, constr, bin_var, i, j, k = missing; M, eps)
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

function CHR(m, constr, bin_var, i, j, k = missing; M = missing, eps)
    if ismissing(k)
        if constr isa NonlinearConstraintRef #NOTE: CAN'T CHECK IF NL CONSTR IS VALID
            # @assert constr in keys(object_dictionary(m)) "$constr is not a named reference in the model."
        elseif constr isa ConstraintRef
            @assert is_valid(m,constr) "$constr is not a valid constraint in the model."
        end
        ref = constr
    else
        if constr isa NonlinearConstraintRef #NOTE: CAN'T CHECK IF NL CONSTR IS VALID
            # @assert constr in keys(object_dictionary(m)) "$constr is not a named reference in the model."
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
        if !(var_i in keys(object_dictionary(m)))
            eval(:(@variable($m, $LB <= $var_i <= $UB)))
            eval(:(@constraint($m, $LB * $bin_var_ref <= $var_i)))
            eval(:(@constraint($m, $var_i <= $UB * $bin_var_ref)))
        end
    end
    #create convex hull constraint
    if ref isa NonlinearConstraintRef
        nl_perspective_function(ref, bin_var_ref, i, j, k, eps)
    elseif ref isa ConstraintRef
        lin_perspective_function(ref, bin_var_ref, i, j, k, eps)
    end
end

function lin_perspective_function(ref, bin_var_ref, i, j, k, eps)
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

function nl_perspective_function(ref, bin_var_ref, i, j, k, eps)
    #extract info
    m = ref.model
    disj_name = replace("$(bin_var_ref)", "_binary" => "")
    vars = m[:original_model_variables]
    j = ismissing(j) ? "" : "_$j"
    k = ismissing(k) ? "" : "_$k"

    #check function has a single comparrison operator (<=, >=, ==)
    ref_str = string(ref)
    @assert length(findall(r"[<>]", ref_str)) <= 1 "$ref must be one of the following: GreaterThan, LessThan, or EqualTo."

    #create symbolic variables (using Symbolics.jl v0.1.25)
    sym_vars = []
    for var in vars
        var_sym = Symbol(var)
        push!(sym_vars, eval(:(Symbolics.@variables($var_sym)))[1])
    end
    ϵ = eps #epsilon parameter for perspective function (See Furman, Sawaya, Grossmann [2020] perspecive function)
    λ = Num(Symbolics.Sym{Float64}(Symbol(bin_var_ref)))
    FSG1 = Num(Symbolics.Sym{Float64}(gensym())) #this will become: [(1-ϵ)⋅λ + ϵ] (See Furman, Sawaya, Grossmann [2020] perspecive function)
    FSG2 = Num(Symbolics.Sym{Float64}(gensym())) #this will become: ϵ⋅(1-λ) (See Furman, Sawaya, Grossmann [2020] perspecive function)

    #convert ref_str into an Expr and extract comparrison operator (<=, >=, ==),
    #constraint function, and RHS
    ref_sym = Meta.parse(ref_str)
    ref_expr = ref_sym.args
    op = eval(ref_expr[1]) #comparrison operator
    rhs = ref_expr[3] #RHS of constraint
    gx = eval(ref_expr[2]) #convert the LHS of the constraint into a Symbolic function

    #use symbolic substitution to obtain the following expression:
    #[(1-ϵ)⋅λ + ϵ]⋅g(v/[(1-ϵ)⋅λ + ϵ]) - ϵ⋅g(0)⋅(1-λ) <= 0
    #first term
    g1 = FSG1*substitute(gx, Dict(var => var/FSG1 for var in sym_vars))
    #second term
    g2 = FSG2*substitute(gx, Dict(var => 0 for var in sym_vars))
    #create perspective function and simplify
    pers_func = simplify(g1 - g2, expand = true)
    #replace FSG expressions & simplify
    pers_func = substitute(pers_func, Dict(FSG1 => (1-ϵ)*λ+ϵ,
                                           FSG2 => ϵ*(1-λ)))
    pers_func = simplify(pers_func)

    #convert pers_func to Expr
    #use build_function from Symbolics.jl to convert pers_func into an Expr
    #where any operators (i.e. exp, *, <=) are replaced by the actual
    #operator (not the symbol).
    #This is done to later replace the symbolic variables with JuMP variables,
    #without messing with the math operators.
    pers_func_expr = Base.remove_linenums!(build_function(op(pers_func,rhs))).args[2].args[1]

    #replace symbolic variables by their JuMP variables
    replace_JuMPvars!(pers_func_expr, m)
    #replace the math operators by symbols
    replace_operators!(pers_func_expr)
    #add the constraint
    add_NL_constraint(m, pers_func_expr)

    #NOTE: the NLconstraint defined by `ref` needs to be deleted. However, this
    #   is not currently possible: https://github.com/jump-dev/JuMP.jl/issues/2355.
    #   As of today (5/12/21), JuMP is behind on its support for nonlinear systems.

    #NOTE: the new NLconstraint cannot be assigned a name (not an option in add_NL_constraint)
    # pers_func_name = Symbol("perspective_func_$(disj_name)$(j)$(k)")
end

function replace_JuMPvars!(expr, model)
    if expr isa Symbol
        return variable_by_name(model, string(expr))
    elseif expr isa Expr
        for i in eachindex(expr.args)
            expr.args[i] = replace_JuMPvars!(expr.args[i], model)
        end
    end
    expr
end

function replace_operators!(expr)
    if expr isa Expr
        for i in eachindex(expr.args)
            expr.args[i] = replace_operators!(expr.args[i])
        end
    elseif !isa(expr, Symbol) && !isa(expr, Number) && !isa(expr, VariableRef)
        return Symbol(expr)
    end
    expr
end

function add_disaggregated_constr(m, disj, vars)
    for var in vars
        d_vars = []
        for i in 1:length(disj)
            var_i = Symbol("$(var)_$i")
            var_i in keys(object_dictionary(m)) && push!(d_vars, m[var_i])
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
