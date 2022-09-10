"""
    choose!(m::Model, n::Int, vars::VariableRef...; mode)

Add constraint to select n elements from the list of variables. Options for mode
are `:at_least`, `:at_most`, `:exactly`.
"""
function choose!(m::Model, n::Int, vars::VariableRef...; mode=:exactly, name="")
    @assert length(vars) >= n "Not enough variables passed."
    @assert all(is_valid.(m, vars)) "Invalid VariableRefs passed."
    add_selection!(m, n, vars...; mode, name)
end
function choose!(m::Model, var::VariableRef, vars::VariableRef...; mode=:exactly, name="")
    @assert all(is_valid.(m, vcat(var,vars))) "Invalid VariableRefs passed."
    add_selection!(m, var, vars...; mode, name)
end
function add_selection!(m::Model, n, vars::VariableRef...; mode::Symbol, name::String)
    display(n)
    if mode == :exactly
        con = @constraint(m, sum(vars) == n)
    elseif mode == :at_least
        con = @constraint(m, sum(vars) ≥ n)
    elseif mode == :at_most
        con = @constraint(m, sum(vars) ≤ n)
    end
    if !isempty(name)
        set_name(con, name)
        m[Symbol(name)] = con
    end
end

"""
    add_proposition!(m::Model, expr::Expr)

Convert logical proposition expression into conjunctive normal form.
"""
function add_proposition!(m::Model, expr::Expr)
    expr_name = Symbol("{$expr}") #get name to register reformulated logical proposition
    replace_Symvars!(expr, m; logical_proposition = true) #replace all JuMP variables with Symbolic variables
    clause_list = to_cnf!(expr)
    #replace symbolic variables with JuMP variables and boolean operators with their algebraic counterparts
    for clause in clause_list
        replace_JuMPvars!(clause, m)
        replace_logic_operators!(clause)
    end
    #generate and simplify JuMP expressions for the lhs of the algebraic constraints
    lhs = eval.(clause_list)
    drop_zeros!.(lhs)
    unique!(lhs)
    #generate JuMP constraints for the logical proposition
    if length(lhs) == 1
        m[expr_name] = @constraint(m, lhs[1] >= 1, base_name = string(expr_name))
    else
        m[expr_name] = @constraint(m, [i = eachindex(lhs)], lhs[i] >= 1, base_name = string(expr_name))
    end
end

"""
    to_cnf!(expr::Expr)

Convert an expression of symbolic Boolean variables and operators to CNF.
"""
function to_cnf!(expr::Expr)
    check_logical_proposition(expr) #check that valid boolean symbols and variables are used in the logical proposition
    eliminate_equivalence!(expr) #eliminate ⇔
    eliminate_implication!(expr) #eliminmate ⇒
    move_negations_inwards!(expr) #expand ¬
    clause_list = distribute_and_over_or_recursively!(expr) #distribute ∧ over ∨ recursively
    @assert !isempty(clause_list) "Conversion to CNF failed."

    return clause_list
end

"""
    check_logical_proposition(expr::Expr)

Validate logical proposition provided.
"""
function check_logical_proposition(expr::Expr)
    #NOTE: this is quick and dirty (uses Suppressor.jl). A more robust approach should traverse the expression tree to verify that only valid boolean symbols and model variables are used.
    dump_str = @capture_out dump(expr, maxdepth = typemax(Int)) #caputre dump
    dump_arr = split(dump_str,"\n") #split by \n
    filter!(i -> occursin("1:",i), dump_arr) #filter only first args in each subexpression
    @assert all(occursin.("1: Symbol ",dump_arr)) "Logical expression does not use valid Boolean symbols: ∨, ∧, ¬, ⇒, ⇔."
    operator_list = map(i -> split(i, "Symbol ")[2], dump_arr)
    @assert isempty(setdiff(operator_list, ["∨", "∧", "¬", "⇒", "⇔", "variables"])) "Logical expression does not use valid model variables or allowed Boolean symbols (∨, ∧, ¬, ⇒, ⇔)."
end

"""
    eliminate_equivalence!(expr)

Eliminate equivalence logical operator.
"""
function eliminate_equivalence!(expr)
    if expr isa Expr
        if expr.args[1] == :⇔
            @assert length(expr.args) == 3 "Double implication cannot have more than two clauses."
            A1 = expr.args[2]
            B1 = expr.args[3]
            A2 = A1 isa Expr ? copy(A1) : A1
            B2 = B1 isa Expr ? copy(B1) : B1
            expr.args[1] = :∧
            expr.args[2] = :($A1 ⇒ $B1)
            expr.args[3] = :($B2 ⇒ $A2)
        end
        for i in eachindex(expr.args)
            expr.args[i] = eliminate_equivalence!(expr.args[i])
        end
    end

    return expr
end

"""
    eliminate_implication!(expr)

Eliminate implication logical operator.
"""
function eliminate_implication!(expr)
    if expr isa Expr
        if expr.args[1] == :⇒
            @assert length(expr.args) == 3 "Implication cannot have more than two clauses."
            A = expr.args[2]
            expr.args[1] = :∨
            expr.args[2] = :(¬$A)
        end
        for i in eachindex(expr.args)
            expr.args[i] = eliminate_implication!(expr.args[i])
        end
    end

    return expr
end

"""
    move_negations_inwards!(expr)

Move negation inwards in logical proposition expression.
"""
function move_negations_inwards!(expr)
    if expr isa Expr
        if expr.args[1] == :¬
            @assert length(expr.args) == 2 "Negation cannot have more than one clause."
            A = expr.args[2]
            if A isa Expr #only modify if an expression (not a Symbolic variable) is being negated
                if A.args[1] == :∨
                    expr.args = negate_or!(A).args
                elseif A.args[1] == :∧
                    expr.args = negate_and!(A).args
                elseif A.args[1] == :¬
                    expr = negate_negation!(A)
                end
            end
        end
        if expr isa Expr
            for i in eachindex(expr.args)
                expr.args[i] = move_negations_inwards!(expr.args[i])
            end
        end
    end

    return expr
end

"""
    negate_or!(expr)

Negate OR boolean operator.
"""
function negate_or!(expr)
    @assert expr.args[1] == :∨ "Cannot call negate_or! unless the top operator is an OR operator."
    expr.args[1] = :∧ #flip OR to AND
    expr.args[2] = :(¬$(expr.args[2]))
    expr.args[3] = :(¬$(expr.args[3]))
    
    return expr
end

"""
    negate_and!(expr)

Negate AND boolean operator.
"""
function negate_and!(expr)
    @assert expr.args[1] == :∧ "Cannot call negate_and! unless the top operator is an AND operator."
    expr.args[1] = :∨ #flip AND to OR
    expr.args[2] = :(¬$(expr.args[2]))
    expr.args[3] = :(¬$(expr.args[3]))
    
    return expr
end

"""
    negate_negation!(expr)

Negate negation boolean operator.
"""
function negate_negation!(expr)
    @assert expr.args[1] == :¬ "Cannot call negate_negation! unless the top operator is a Negation operator."
    @assert length(expr.args) == 2 "Negation cannot have more than one clause."
    expr = expr.args[2] #remove negation
    
    return expr
end

"""
    distribute_and_over_or!(expr)

Distribute AND over OR boolean operators.
"""
function distribute_and_over_or!(expr)
    if expr isa Expr
        if expr.args[1] == :∨
            # op = expr.args[1]
            A = expr.args[2] #first clause
            B = expr.args[3] #second clause
            if A isa Expr && A.args[1] == :∧ #first clause has AND
                C = A.args[2] #first subclause
                D = A.args[3] #second subclause
                expr.args[1] = :∧ #flip OR to AND in main expr
                expr.args[2] = :($C ∨ $B)
                expr.args[3] = :($D ∨ $B)
            elseif B isa Expr && B.args[1] == :∧ #second clause has AND
                C = B.args[2] #first subclause
                D = B.args[3] #second subclause
                expr.args[1] = :∧ #flip OR to AND in main expr
                expr.args[2] = :($C ∨ $A)
                expr.args[3] = :($D ∨ $A)
            end
        end
        for i in eachindex(expr.args)
            expr.args[i] = distribute_and_over_or!(expr.args[i])
        end
    end

    return expr
end

"""
    extract_clauses(expr)

Extract clauses from conjunctive normal form.
"""
function extract_clauses(expr)
    clauses = []
    if expr isa Expr
        if expr.args[1] == :∨
            push!(clauses, expr)
        else
            for i in 2:length(expr.args)
                push!(clauses, extract_clauses(expr.args[i])...)
            end
        end
    end

    return clauses
end

"""
    distribute_and_over_or_recursively!(expr)

Distribute AND over OR boolean operators recursively throughout the expression tree.
"""
function distribute_and_over_or_recursively!(expr)
    distribute_and_over_or!(expr)
    clause_list = extract_clauses(expr)
    wrong_clauses = filter(i -> occursin("∧",string(i)), clause_list)
    if !isempty(wrong_clauses)
        clause_list = distribute_and_over_or_recursively!(expr)
    end

    return unique!(clause_list)
end

"""
    replace_logic_operators!(expr)

Replace ∨ for +; replace ¬ for 1 - var.
"""
function replace_logic_operators!(expr)
    if expr isa Expr
        if expr.args[1] == :∨
            expr.args[1] = :(+)
        elseif expr.args[1] == :¬
            A = expr.args[2]
            expr = :(1 - $A)
        end
        for i in 2:length(expr.args)
            expr.args[i] = replace_logic_operators!(expr.args[i])
        end
    end

    return expr
end