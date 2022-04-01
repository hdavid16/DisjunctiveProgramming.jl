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
    vars = ref.model[:gdp_variable_refs]
    for var in vars
        UB = has_upper_bound(var) ? upper_bound(var) : (is_binary(var) ? 1 : Inf)
        LB = has_lower_bound(var) ? lower_bound(var) : (is_binary(var) ? 0 : -Inf)
        interval_map[string(var)] = LB..UB
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

function parse_NLconstraint(ref)
    #check function has a single comparrison operator (<=, >=, ==)
    ref_str = string(ref)
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

function replace_Symvars!(expr, model; force_binary = false)
    #replace JuMP variables with symbolic variables
    if expr isa Expr
        name = join(split(string(expr)," "))
        var = variable_by_name(model, name)
        if !isnothing(var)
            force_binary && @assert is_binary(var) "Only binary variables are allowed in $expr."
            expr = Symbol(name)
        else
            for i in eachindex(expr.args)
                expr.args[i] = replace_Symvars!(expr.args[i], model)
            end
        end
    end

    return expr
end

function replace_JuMPvars!(expr, model)
    #replace symbolic variables with JuMP variables
    if expr isa Symbol
        var = variable_by_name(model, string(expr))
        !isnothing(var) && return var
    elseif expr isa Expr #run recursion
        for i in eachindex(expr.args)
            expr.args[i] = replace_JuMPvars!(expr.args[i], model)
        end
    end

    return expr
end

function replace_operators!(expr)
    #replace operators with their symbol. NOTE: Is this still needed for the CHR of nl constraints? (check this)
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
    if string(expr) in keys(intervals) #check if expression is one of the model variables in the intervals dict
        return intervals[string(expr)] #replace expression with interval
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