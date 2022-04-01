function to_cnf!(m::Model, expr::Expr)
    #********
    #NOTE: Check if already in CNF?
    #********
    expr_copy = copy(expr)
    replace_Symvars!(expr, m)
    eliminate_equivalence!(expr)
    eliminate_implication!(expr)
    eliminate_xor!(expr)
    move_negations_inwards!(expr)
    clause_list = [:()]
    wrong_clauses = clause_list
    while !isempty(wrong_clauses)
        distribute_and_over_or!(expr)
        clause_list = extract_clauses(expr)
        wrong_clauses = filter(i -> occursin("∧",string(i)), clause_list)
    end
    # @assert isempty(wrong_clauses) "AND operator found in one or more clauses:\n$(join(wrong_clauses,"\n"))."
    unique!(clause_list)
    for clause in clause_list
        replace_JuMPvars!(clause, m)
        replace_logic_operators!(clause)
    end
    lhs = [eval(clause) for clause in clause_list]
    drop_zeros!.(lhs)
    unique!(lhs)
    clause_sym = Symbol(expr_copy)
    m[clause_sym] = @constraint(m, [i = eachindex(lhs)], lhs[i] >= 1)
end

function eliminate_equivalence!(expr)
    if expr isa Expr
        if expr.args[1] == :⇔
            @assert length(expr.args) == 3 "Double implication cannot have more than two clauses."
            A = expr.args[2]
            B = expr.args[3]
            expr.args[1] = :∧
            expr.args[2] = :($A ⇒ $B)
            expr.args[3] = :($B ⇒ $A)
        end
        for i in eachindex(expr.args)
            expr.args[i] = eliminate_equivalence!(expr.args[i])
        end
    end

    return expr
end

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

function eliminate_xor!(expr)
    # A ⊻ B = ¬(A ⇔ B) = (A ∨ B) ∧ ¬(A ∧ B)
    if expr isa Expr
        if expr.args[1] == :⊻
            @assert length(expr.args) == 3 "Implication cannot have more than two clauses."
            A = expr.args[2]
            B = expr.args[3]
            expr.args[1] = :∧
            expr.args[2] = :($A ∨ $B)
            expr.args[3] = :(¬$A ∨ ¬$B)
        end
        for i in eachindex(expr.args)
            expr.args[i] = eliminate_xor!(expr.args[i])
        end
    end

    return expr
end

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

function negate_or!(expr)
    @assert expr.args[1] == :∨ "Cannot call negate_or! unless the top operator is an OR operator."
    expr.args[1] = :∧ #flip OR to AND
    expr.args[2] = :(¬$(expr.args[2]))
    expr.args[3] = :(¬$(expr.args[3]))
    
    return expr
end

function negate_and!(expr)
    @assert expr.args[1] == :∧ "Cannot call negate_and! unless the top operator is an AND operator."
    expr.args[1] = :∨ #flip AND to OR
    expr.args[2] = :(¬$(expr.args[2]))
    expr.args[3] = :(¬$(expr.args[3]))
    
    return expr
end

function negate_negation!(expr)
    @assert expr.args[1] == :¬ "Cannot call negate_negation! unless the top operator is a Negation operator."
    @assert length(expr.args) == 2 "Negation cannot have more than one clause."
    expr = expr.args[2] #remove negation
    
    return expr
end

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