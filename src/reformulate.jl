function reformulate(m, disj, bin_var, reformulation, param)
    vars = setdiff(all_variables(m), m[bin_var])
    @expression(m, original_model_variables, vars)
    for (i,constr) in enumerate(disj)
        if constr isa Vector || constr isa Tuple
            for (j,constr_j) in enumerate(constr)
                apply_reformulation(m, constr_j, bin_var, reformulation, param, i, j)
            end
        elseif constr isa ConstraintRef || typeof(constr) <: Array || constr isa JuMP.Containers.DenseAxisArray
            apply_reformulation(m, constr, bin_var, reformulation, param, i)
        end
    end
    if reformulation == :CHR
        add_disaggregated_constr(m, disj, vars)
    end
end

function apply_reformulation(m, constr, bin_var, reformulation, param, i, j = missing)
    param = get_reform_param(param, i, j) #M or eps
    if constr isa ConstraintRef
        call_reformulation(reformulation, m, constr, bin_var, i, missing, param)
    elseif typeof(constr) <: Array
        for k in Iterators.product([1:s for s in size(constr)]...)
            call_reformulation(reformulation, m, constr, bin_var, i, k, param)
        end
    elseif constr isa JuMP.Containers.DenseAxisArray
        for k in Iterators.product([s for s in constr.axes]...)
            call_reformulation(reformulation, m, constr, bin_var, i, k, param)
        end
    end
end

function call_reformulation(reformulation, m, constr, bin_var, i, k, param)
    if reformulation == :BMR
        BMR!(m, constr, bin_var, i, k, param)
    elseif reformulation == :CHR
        CHR!(m, constr, bin_var, i, k, param)
    end
end

function get_reform_param(param, i, j)
    if param isa Number || ismissing(param)
        param = param
    elseif param isa Vector || param isa Tuple
        if param[i] isa Number
            param = param[i]
        elseif param[i] isa Vector || param[i] isa Tuple
            @assert !ismissing(j) "If constraint specific param values are provided, there must be more than one constraint in disjunct $i."
            @assert j <= length(param[i]) "If constraint specific param values are provided, a value must be provided for each constraint in disjunct $i."
            param = param[i][j]
        else
            error("Invalid param parameter provided for disjunct $i.")
        end
    else
        error("Invalid param parameter provided for disjunct $i.")
    end
end

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
    bin_var_ref = variable_by_name(ref.model, "$bin_var[$i]")
    if ref isa NonlinearConstraintRef
        nl_bigM(ref, bin_var_ref, M)
    elseif ref isa ConstraintRef
        lin_bigM(ref, bin_var_ref, M)
    end
end

function apply_interval_arithmetic(ref)
    #convert constraints into Expr to replace variables with interval sets and determine bounds
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
    ref_func_expr = Meta.parse(ref_func)
    #create a map of variables to their bounds
    interval_map = Dict()
    vars = all_variables(ref.model) #get all variable names
    for var in vars
        ub = has_upper_bound(var) ? upper_bound(var) : (is_binary(var) ? 1 : Inf)
        lb = has_lower_bound(var) ? lower_bound(var) : (is_binary(var) ? 0 : Inf)
        interval_map[string(var)] = lb..ub
    end
    ref_func_expr = replace_vars!(ref_func_expr, interval_map)
    #get bounds on the entire expression
    func_bounds = eval(ref_func_expr)
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

function lin_bigM(ref, bin_var_ref, M)
    add_to_function_constant(ref, -M)
    set_normalized_coefficient(ref, bin_var_ref , M)
end

function nl_bigM(ref, bin_var_ref, M)
    #extract info
    vars = ref.model[:original_model_variables]

    #create symbolic variables (using Symbolics.jl)
    sym_vars = []
    for var in vars
        var_sym = Symbol(var)
        push!(sym_vars, eval(:(Symbolics.@variables($var_sym)))[1])
    end
    bin_var_sym = Symbol(bin_var_ref)
    sym_bin_var = eval(:(Symbolics.@variables($bin_var_sym)))[1]

    #parse ref
    op, lhs, rhs = parse_NLconstraint(ref)
    gx = eval(lhs) #convert the LHS of the constraint into a Symbolic expression
    gx = gx - M*(1-sym_bin_var) #add bigM

    #update constraint
    replace_NLconstraint(ref, gx, op, rhs)
end

function CHR!(m, constr, bin_var, i, k, eps)
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
    bin_var_ref = variable_by_name(ref.model, "$bin_var[$i]")
    for var in m[:original_model_variables]
        #get bounds for disaggregated variable
        @assert has_upper_bound(var) || is_binary(var) "Variable $var does not have an upper bound."
        # @assert has_lower_bound(var) || is_binary(var) "Variable $var does not have a lower bound."
        UB = is_binary(var) ? 1 : upper_bound(var)
        LB = has_lower_bound(var) ? lower_bound(var) : 0 #set lower bound for disaggregated variable to 0 if binary or no lower bound given
        #create disaggregated variable
        var_i = Symbol("$(var)_$i")
        if !(var_i in keys(object_dictionary(m)))
            eval(:(@variable($m, $LB <= $var_i <= $UB)))
            eval(:(@constraint($m, $LB * $bin_var_ref <= $var_i)))
            eval(:(@constraint($m, $var_i <= $UB * $bin_var_ref)))
            is_binary(var) && set_binary(m[var_i])
        end
    end
    #create convex hull constraint
    if ref isa NonlinearConstraintRef || constraint_object(ref).func isa QuadExpr
        nl_perspective_function(ref, bin_var_ref, i, eps)
    elseif ref isa ConstraintRef
        lin_perspective_function(ref, bin_var_ref, i)
    end
end

function lin_perspective_function(ref, bin_var_ref, i)
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

function nl_perspective_function(ref, bin_var_ref, i, eps)
    #extract info
    vars = ref.model[:original_model_variables]

    #create symbolic variables (using Symbolics.jl)
    sym_vars = []
    sym_i_vars = []
    for var in vars
        var_sym = Symbol(var) #original variable
        push!(sym_vars, eval(:(Symbolics.@variables($var_sym)))[1])
        var_i_sym = Symbol("$(var)_$i") #disaggregated variable
        push!(sym_i_vars, eval(:(Symbolics.@variables($var_i_sym)))[1])
    end
    ϵ = eps #epsilon parameter for perspective function (See Furman, Sawaya, Grossmann [2020] perspecive function)
    λ = Num(Symbolics.Sym{Float64}(Symbol(bin_var_ref)))
    FSG1 = Num(Symbolics.Sym{Float64}(gensym())) #this will become: [(1-ϵ)⋅λ + ϵ] (See Furman, Sawaya, Grossmann [2020] perspecive function)
    FSG2 = Num(Symbolics.Sym{Float64}(gensym())) #this will become: ϵ⋅(1-λ) (See Furman, Sawaya, Grossmann [2020] perspecive function)

    #parse ref
    op, lhs, rhs = parse_NLconstraint(ref)
    gx = eval(lhs) #convert the LHS of the constraint into a Symbolic expression

    #use symbolic substitution to obtain the following expression:
    #[(1-ϵ)⋅λ + ϵ]⋅g(v/[(1-ϵ)⋅λ + ϵ]) - ϵ⋅g(0)⋅(1-λ) <= 0
    #first term
    g1 = FSG1*substitute(gx, Dict(var => var_i/FSG1 for (var,var_i) in zip(sym_vars,sym_i_vars)))
    #second term
    g2 = FSG2*substitute(gx, Dict(var => 0 for var in sym_vars))
    #create perspective function and simplify
    pers_func = simplify(g1 - g2, expand = true)
    #replace FSG expressions & simplify
    pers_func = substitute(pers_func, Dict(FSG1 => (1-ϵ)*λ+ϵ,
                                           FSG2 => ϵ*(1-λ)))
    pers_func = simplify(pers_func)

    replace_NLconstraint(ref, pers_func, op, rhs)
end

function parse_NLconstraint(ref)
    #check function has a single comparrison operator (<=, >=, ==)
    ref_str = string(ref)
    # ref_str = replace(ref_str," = " => " == ") #replace = for == in NLconstraint (for older versions of JuMP)
    ref_str = split(ref_str,": ")[end] #remove name if Quadratic Constraint has a name

    #convert ref_str into an Expr and extract comparrison operator (<=, >=, ==),
    #constraint function, and RHS
    ref_expr = Meta.parse(ref_str).args
    op = eval(ref_expr[1]) #comparrison operator
    @assert op in [>=, <=, ==] "$ref must be one of the following: GreaterThan, LessThan, or EqualTo."
    lhs = ref_expr[2] #LHS of the constraint
    rhs = ref_expr[3] #RHS of constraint

    return op, lhs, rhs
end

function replace_NLconstraint(ref, sym_expr, op, rhs)
    #convert sym_expr to Expr
    #use build_function from Symbolics.jl to convert sym_expr into an Expr
    #where any operators (i.e. exp, *, <=) are replaced by the actual
    #operator (not the symbol).
    #This is done to later replace the symbolic variables with JuMP variables,
    #without messing with the math operators.
    if ref isa NonlinearConstraintRef
        expr = Base.remove_linenums!(build_function(sym_expr)).args[2].args[1]
    elseif ref isa ConstraintRef
        expr = Base.remove_linenums!(build_function(op(sym_expr,rhs))).args[2].args[1]
    end

    #replace symbolic variables by their JuMP variables
    m = ref.model
    replace_JuMPvars!(expr, m)
    #replace the math operators by symbols
    replace_operators!(expr)
    if ref isa NonlinearConstraintRef
        # determine bounds of original constraint (note: if op is ==, both bounds are set to rhs)
        upper_b = (op == >=) ? Inf : rhs
        lower_b = (op == <=) ? -Inf : rhs
        # replace NL constraint currently in the model with the reformulated one
        m.nlp_data.nlconstr[ref.index.value] = JuMP._NonlinearConstraint(JuMP._NonlinearExprData(m, expr), lower_b, upper_b)
    elseif ref isa ConstraintRef
        #add a nonlinear constraint with the perspective function
        add_NL_constraint(m, expr)
        #delete old constraint
        delete(m, ref)
    end
end

function replace_JuMPvars!(expr, model)
    if expr isa Symbol #replace symbolic variables with JuMP variables
        return variable_by_name(model, string(expr))
    elseif expr isa Expr #run recursion
        for i in eachindex(expr.args)
            expr.args[i] = replace_JuMPvars!(expr.args[i], model)
        end
    end
    expr
end

function replace_operators!(expr)
    if expr isa Expr #run recursion
        for i in eachindex(expr.args)
            expr.args[i] = replace_operators!(expr.args[i])
        end
    elseif expr isa Function #replace Function with its symbol
        return Symbol(expr)
    end
    expr
end

function replace_vars!(expr, intervals)
    if string(expr) in keys(intervals) #check if expression is one of the model variables in the intervals dict
        return intervals[string(expr)] #replace expression with interval
    elseif expr isa Expr
        if length(expr.args) == 1 #run recursive relation on the leaf node on expression tree
            expr.args[i] = replace_vars!(expr.args[i], intervals)
        else #run recursive relation on each internal node of the expression tree, but skip the first element, which will always be the operator (this will avoid issues if the user creates a model variable called exp)
            for i in 2:length(expr.args)
                expr.args[i] = replace_vars!(expr.args[i], intervals)
            end
        end
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
