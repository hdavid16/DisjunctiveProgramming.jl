function reformulate_disjunction(m, disj, bin_var, reformulation, param)
    # #update disjunction ids
    # if :Disjunction_Counter in keys(object_dictionary(m))
    #     add_to_expression!(m[:Disjunction_Counter], 1) #increase counter by 1
    # else #first time @disjunction has been run, so initialize at 1
    #     @expression(m, Disjunction_Counter, AffExpr(1))
    # end
    # #get disjunction id #
    # id = Int(constant(m[:Disjunction_Counter]))
    #get original variable refs and variable names
    vars = setdiff(all_variables(m), m[bin_var])
    var_names = unique(Symbol.([split("$var","[")[1] for var in vars]))
    if !in(:Original_VarRefs, keys(object_dictionary(m)))
        @expression(m, Original_VarRefs, vars)
    end
    if !in(:Original_VarNames, keys(object_dictionary(m)))
        @expression(m, Original_VarNames, var_names)
    end
    #run reformulation
    reformulate(m, disj, bin_var, reformulation, param)
    if reformulation == :CHR
        add_disaggregated_constr(m, disj, vars)
    end
end

function reformulate(m, disj, bin_var, reformulation, param)
    for (i,constr) in enumerate(disj)
        if constr isa Tuple
            for (j,constr_j) in enumerate(constr)
                apply_reformulation(m, constr_j, bin_var, reformulation, param, i, j)
            end
        elseif constr isa ConstraintRef || constr isa Array || constr isa Containers.DenseAxisArray || constr isa Containers.SparseAxisArray
            apply_reformulation(m, constr, bin_var, reformulation, param, i)
        end
    end
end

function apply_reformulation(m, constr, bin_var, reformulation, param, i, j = missing)
    param = get_reform_param(param, i, j) #M or eps
    if constr isa ConstraintRef
        call_reformulation(reformulation, m, constr, bin_var, i, missing, param)
    elseif constr isa Array
        for k in Iterators.product([1:s for s in size(constr)]...)
            call_reformulation(reformulation, m, constr, bin_var, i, k, param)
        end
    elseif constr isa Containers.DenseAxisArray
        for k in Iterators.product([s for s in constr.axes]...)
            call_reformulation(reformulation, m, constr, bin_var, i, k, param)
        end
    elseif constr isa Containers.SparseAxisArray
        for (k, c) in constr.data
            call_reformulation(reformulation, m, c, bin_var, i, k, param)
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
    ref_func_expr, ref_type, ref_rhs = parse_ref(ref)
    #create a map of variables to their bounds
    interval_map = Dict()
    vars = ref.model[:Original_VarRefs]
    for var in vars
        UB = has_upper_bound(var) ? upper_bound(var) : (is_binary(var) ? 1 : Inf)
        LB = has_lower_bound(var) ? lower_bound(var) : (is_binary(var) ? 0 : -Inf)
        interval_map[string(var)] = LB..UB
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

function parse_ref(ref)
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

    return ref_func_expr, ref_type, ref_rhs
end

function lin_bigM(ref, bin_var_ref, M)
    add_to_function_constant(ref, -M)
    set_normalized_coefficient(ref, bin_var_ref , M)
end

function nl_bigM(ref, bin_var_ref, M)
    #create symbolic variables (using Symbolics.jl)
    sym_vars = []
    # vars = ref.model[:Original_VarRefs]
    # for var in vars
    #     var_sym = Symbol(var)
    #     push!(sym_vars, eval(:(Symbolics.@variables($var_sym)))[1])
    # end
    var_names = ref.model[:Original_VarNames]
    for var in var_names
        if ref.model[var] isa VariableRef
            var_sym = var
        elseif ref.model[var] isa Vector{VariableRef}
            index_string = join([1:s for s in size(ref.model[var])],",")
            var_sym = Symbol("$var[$index_string]")
        end
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
    ref = ismissing(k) ? constr : constr[k...] #get constraint
    @assert is_valid(m,ref) "$constr is not a valid constraint in the model."
    #create convex hull constraint
    if ref isa NonlinearConstraintRef || constraint_object(ref).func isa QuadExpr
        nl_perspective_function(ref, bin_var, i, eps)
    elseif ref isa ConstraintRef
        lin_perspective_function(ref, bin_var, i)
    end
end

function disaggregate_variables(m, disj, bin_var)
    #check that variables are bounded
    var_refs = m[:Original_VarRefs]
    @assert all((has_upper_bound.(var_refs) .&& has_lower_bound.(var_refs)) .|| is_binary.(var_refs)) "All variables must be bounded to perform the Convex-Hull reformulation."
    #reformulate variables
    for var_name in m[:Original_VarNames]
        var = m[var_name]
        #define UB and LB
        if var isa VariableRef
            LB, UB = get_bounds(var)
        elseif var isa Array{VariableRef} || var isa Containers.DenseAxisArray || var isa Containers.SparseAxisArray
            #initialize UB and LB with same container type as variable
            if var isa Array{VariableRef} || var isa Containers.DenseAxisArray
                idxs = Iterators.product(axes(var)...)
                LB, UB = zeros(size(var)), zeros(size(var))
                if var isa Containers.DenseAxisArray
                    LB = Containers.DenseAxisArray(LB, axes(var)...)
                    UB = Containers.DenseAxisArray(UB, axes(var)...)
                end
            elseif var isa Containers.SparseAxisArray
                idxs = keys(var.data)
                LB = Containers.SparseAxisArray(Dict(idx => 0. for idx in idxs))
                UB = Containers.SparseAxisArray(Dict(idx => 0. for idx in idxs))
            end
            #populate UB and LB
            for idx in eachindex(var)
                LB[idx], UB[idx] = get_bounds(var[idx])
            end
        end
        #disaggregate variable and add bounding constraints
        for i in eachindex(disj)
            var_name_i = Symbol("$(var_name)_$bin_var$i")
            if var isa VariableRef
                #create and register anonymous variable
                m[var_name_i] = add_disaggregated_variable(m, LB, UB, var, "$var_name_i")
            elseif var isa Array{VariableRef} || var isa Containers.DenseAxisArray
                #create array of anonymous variables
                var_i_array = [
                    add_disaggregated_variable(m, LB[idx...], UB[idx...], var[idx...], "$var_name_i[$(join(idx,","))]")
                    for idx in idxs
                ]
                #containerize if DenseAxisArray
                if var isa Containers.DenseAxisArray
                    var_i_array = Containers.DenseAxisArray(var_i_array, axes(var)...)
                end
                #register disaggregated variable
                m[var_name_i] = var_i_array
            elseif var isa Containers.SparseAxisArray
                #create dictionary of anonymous variables
                var_i_dict = Dict(
                    idx => add_disaggregated_variable(m, LB[idx], UB[idx], var[idx], "$var_name_i[$(join(idx,","))]")
                    for idx in idxs
                )
                #register disaggregated variable
                m[var_name_i] = Containers.SparseAxisArray(var_i_dict)
            end
            #apply bounding constraints on disaggregated variable
            lb_constr = LB * m[bin_var][i] .- m[var_name_i]
            @constraint(m, lb_constr .<= 0)
            ub_constr = m[var_name_i] .- UB * m[bin_var][i]
            @constraint(m, ub_constr .<= 0)
        end
    end
end

function get_bounds(var::VariableRef)
    LB = is_binary(var) ? 0 : lower_bound(var)
    UB = is_binary(var) ? 1 : upper_bound(var)

    return LB, UB
end

function add_disaggregated_variable(m, LB, UB, var, base_name)
    #********
    #NOTE: NEED TO CHECK IF DISAGGREGATED VARIABLE ALREADY exists
    #********
    @variable(
        m, 
        lower_bound = LB, 
        upper_bound = UB, 
        binary = is_binary(var), 
        integer = is_integer(var),
        base_name = base_name
    )
end

function lin_perspective_function(ref, bin_var, i)
    #check constraint type
    ref_obj = constraint_object(ref)
    @assert ref_obj.set isa MOI.LessThan || ref_obj.set isa MOI.GreaterThan || ref_obj.set isa MOI.EqualTo "$ref must be one the following: GreaterThan, LessThan, or EqualTo."
    bin_var_ref = ref.model[bin_var][i]
    for var_name in ref.model[:Original_VarNames]
        var = ref.model[var_name]
        var_name_i = Symbol("$(var_name)_$bin_var$i")
        var_i = ref.model[var_name_i]
        if var isa VariableRef
            add_lin_perspective_function(ref, bin_var_ref, var, var_i)
        else
            for idx in eachindex(var)
                add_lin_perspective_function(ref, bin_var_ref, var[idx], var_i[idx])
            end
        end
    end
end

function add_lin_perspective_function(ref, bin_var_ref, var_ref, var_i_ref)
    #check var_ref is present in the constraint
    coeff = normalized_coefficient(ref,var_ref)
    iszero(coeff) && return #if not present, exit
    #modify constraint using convex hull
    rhs = normalized_rhs(ref) #get rhs
    set_normalized_rhs(ref, 0) #set rhs to 0
    set_normalized_coefficient(ref, var_ref, 0) #remove original variable
    set_normalized_coefficient(ref, var_i_ref, coeff) #add disaggregated variable
    set_normalized_coefficient(ref, bin_var_ref, -rhs) #add binary variable
end

function nl_perspective_function(ref, bin_var, i, eps)
    #create symbolic variables (using Symbolics.jl)
    sym_vars = []
    sym_i_vars = []
    bin_var_ref = ref.model[bin_var][i]
    for var_name in ref.model[:Original_VarNames]
        var = ref.model[var_name]
        var_name_i = Symbol("$(var_name)_$bin_var$i")
        var_i = ref.model[var_name_i]
        if var isa VariableRef
            var_sym = var_name
            var_i_sym = var_name_i #disaggregated variable
        elseif var isa Array{VariableRef}
            index_string = join([1:s for s in size(ref.model[var])],",")
            var_sym = Symbol("$var_name[$index_string]")
            var_i_sym = Symbol("$var_name_i[$index_string]")
        else
            error("Symbolic manipulation not possible for DenseAxisArray or SparseAxisArray variables.")
        end
        push!(sym_vars, eval(:(Symbolics.@variables($var_sym)))[1])
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
    #update constraint
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
        if expr.args[1] == getindex
            var = expr.args[2]
            idx = join(expr.args[3:end],",")
            expr = variable_by_name(model, "$var[$idx]")
        else
            for i in eachindex(expr.args)
                expr.args[i] = replace_JuMPvars!(expr.args[i], model)
            end
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
