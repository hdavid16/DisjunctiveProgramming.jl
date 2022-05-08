function get_bounds(var::VariableRef)
    LB = is_binary(var) ? 0 : lower_bound(var)
    UB = is_binary(var) ? 1 : upper_bound(var)

    return LB, UB
end

function apply_interval_arithmetic(ref)
    #convert constraints into Expr to replace variables with interval sets and determine bounds
    ref_func_expr, ref_type, ref_rhs = parse_constraint(ref)
    #create a map of variables to their bounds
    interval_map = Dict()
    vars = all_variables(ref.model)#ref.model[:gdp_variable_refs]
    obj_dict = object_dictionary(ref.model)
    bounds_dict = :variable_bounds_dict in keys(obj_dict) ? obj_dict[:variable_bounds_dict] : Dict() #NOTE: should pass as an keyword argument
    for var in vars
        if string(var) in keys(bounds_dict)
            bnds = bounds_dict[string(var)]
            interval_map[string(var)] = bnds[1]..bnds[2]
        else
            UB = has_upper_bound(var) ? upper_bound(var) : (is_binary(var) ? 1 : Inf)
            LB = has_lower_bound(var) ? lower_bound(var) : (is_binary(var) ? 0 : -Inf)
            interval_map[string(var)] = LB..UB
        end
    end
    ref_func_expr = replace_intevals!(ref_func_expr, interval_map)
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

function parse_constraint(ref)
    if ref isa NonlinearConstraintRef
        ref_str = string(ref)
        ref_func = replace(split(ref_str, r"[=<>]")[1], " " => "") #remove operator and spaces
        ref_type = occursin(">", ref_str) ? :lower : :upper
        ref_rhs = 0 #Could be calculated with: parse(Float64,split(ref_str, " ")[end]). NOTE: @NLconstraint will always have a 0 RHS.
    elseif ref isa ConstraintRef
        ref_obj = constraint_object(ref)
        ref_str = string(ref_obj.func)
        ref_func = replace(ref_str, " " => "") #remove spaces
        ref_type = fieldnames(typeof(ref_obj.set))[1]
        ref_rhs = normalized_rhs(ref)
    end
    ref_func_expr = Meta.parse(ref_func)

    return ref_func_expr, ref_type, ref_rhs
end

function parse_NLconstraint(ref)
    #check function has a single comparrison operator (<=, >=, ==)
    ref_str = string(ref)
    ref_str = split(ref_str,": ")[end] #remove name if Quadratic Constraint has a name

    #convert ref_str into an Expr and extract comparrison operator (<=, >=, ==),
    #constraint function, and RHS
    ref_expr = Meta.parse(ref_str).args
    op = eval(ref_expr[1]) #comparrison operator
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
    #NOTE: Maybe not necessary anymore due to implementation of replace_JuMPvars
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
        # determine bounds of original constraint (if op is ==, both bounds are set to rhs)
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

function replace_Symvars!(expr, model; logical_proposition = false)
    #replace JuMP variables with symbolic variables
    name = join(split(string(expr)," "))
    var = variable_by_name(model, name)
    if !isnothing(var)
        logical_proposition && @assert is_binary(var) "Only binary variables are allowed in $expr."
        return Symbol(name)
    end
    if expr isa Expr
        for i in eachindex(expr.args)
            expr.args[i] = replace_Symvars!(expr.args[i], model)
        end
    end

    return expr
end

function replace_JuMPvars!(expr, model)
    #replace symbolic variables and any matching expressions with JuMP variables
    var = variable_by_name(model, string(expr))
    !isnothing(var) && return var
    if expr isa Expr #run recursion
        for i in eachindex(expr.args)
            expr.args[i] = replace_JuMPvars!(expr.args[i], model)
        end
    end

    return expr
end

function replace_operators!(expr)
    #replace operators with their symbol. NOTE: Is this still needed for the convex_hull_reformulation! of nl constraints? (check this)
    if expr isa Expr #run recursion
        for i in eachindex(expr.args)
            expr.args[i] = replace_operators!(expr.args[i])
        end
    elseif expr isa Function #replace Function with its symbol
        return Symbol(expr)
    end

    return expr
end

function replace_intevals!(expr, intervals)
    #replace variables with their intervals
    expr_str = replace(string(expr), ", " => ",") #remove any blank space
    if expr_str in keys(intervals) #check if expression is one of the model variables in the intervals dict
        return intervals[expr_str] #replace expression with interval
    elseif expr isa Expr
        if length(expr.args) == 1 #run recursive relation on the leaf node on expression tree
            expr.args[i] = replace_intevals!(expr.args[i], intervals)
        else #run recursive relation on each internal node of the expression tree, but skip the first element, which will always be the operator (this will avoid issues if the user creates a model variable called exp)
            for i in 2:length(expr.args)
                expr.args[i] = replace_intevals!(expr.args[i], intervals)
            end
        end
    end

    return expr
end

function symbolic_variable(var_ref)
    var_sym = Symbol(var_ref)
    return eval(:(Symbolics.@variables($var_sym)[1]))
end

function name_disaggregated_variable(var_ref, bin_var, i)
    #get disaggregated variable reference
    if occursin("[", string(var_ref))
        var_name_i = replace(string(var_ref), "[" => "_$bin_var$i[")
    else
        var_name_i = "$(var_ref)_$bin_var$i"
    end

    return var_name_i
end

function name_split_constraint(con_name, side)
    #get disaggregated variable reference
    if occursin("[", string(con_name))
        con_name = replace(string(con_name), "]" => ",$side]")
    else
        con_name = "$(con_name)[$side]"
    end

    return con_name
end

# function is_linear_func(expr::Expr, m)
#     m = eval(m)
#     if expr.head == :call
#         func = expr.args[2] isa Number ? expr.args[3] : expr.args[2]
#     elseif expr.head == :comparison
#         func = expr.args[3]
#     end
#     sym_vars = symbolic_variable.(all_variables(m))
#     func = eval(replace_Symvars!(func, m))
#     try
#         # eval(func)
#         replace_JuMPvars!(func, m)
#         return true
#     catch e
#         if e isa ErrorException
#             return false
#         end
#     end
#     # Symbolics.islinear(func, sym_vars)
# end