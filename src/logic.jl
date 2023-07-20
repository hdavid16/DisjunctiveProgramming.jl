"""

"""
function _to_cnf(lexpr::LogicalExpr)
    lexpr |> 
        _eliminate_equivalence |>  
        _eliminate_implication |> 
        _move_negations_inward |> 
        _distribute_and_over_or |>
        _flatten
end

"""
    _eliminate_equivalence!(expr)

Eliminate equivalence logical operator.
"""
function _eliminate_equivalence(lvar::LogicalVariableRef)
    return lvar
end
function _eliminate_equivalence(lexpr::LogicalExpr)
    if lexpr.head == :⇔
        if length(lexpr.args) != 2 
            error("The equivalence operator must have two clauses.")
        end
        A = _eliminate_equivalence(lexpr.args[1])
        B = _eliminate_equivalence(lexpr.args[2])
        new_lexpr = LogicalExpr(:∧, Any[
            LogicalExpr(:⇒, Any[A, B]),
            LogicalExpr(:⇒, Any[B, A])
        ])
    else
        new_lexpr = LogicalExpr(lexpr.head, Any[
            _eliminate_equivalence(arg) for arg in lexpr.args
        ])
    end

    return new_lexpr
end

"""
    eliminate_implication!(expr)

Eliminate implication logical operator.
"""
function _eliminate_implication(lvar::LogicalVariableRef)
    return lvar
end
function _eliminate_implication(lexpr::LogicalExpr)
    if lexpr.head == :⇒
        if length(lexpr.args) != 2 
            error("The implication operator must have two clauses.")
        end
        A = _eliminate_implication(lexpr.args[1])
        B = _eliminate_implication(lexpr.args[2])
        new_lexpr = LogicalExpr(:∨, Any[
            LogicalExpr(:¬, Any[A]),
            B
        ])
    else
        new_lexpr = LogicalExpr(lexpr.head, Any[
            _eliminate_implication(arg) for arg in lexpr.args
        ])
    end

    return new_lexpr
end

"""
    _move_negations_inwards(expr)

Move negation inwards in logical proposition expression.
"""
function _move_negations_inward(lvar::LogicalVariableRef)
    return lvar
end
function _move_negations_inward(lexpr::LogicalExpr)
    if lexpr.head == :¬
        if length(lexpr.args) != 1
            error("The negation operator can only have 1 clause.")
        end
        new_lexpr = _negate(lexpr.args[1])
    else
        new_lexpr = LogicalExpr(lexpr.head, Any[
            _move_negations_inward(arg) for arg in lexpr.args
        ])
    end

    return new_lexpr
end

"""

"""
function _negate(lvar::LogicalVariableRef)
    return LogicalExpr(:¬, Any[lvar])
end
function _negate(lexpr::LogicalExpr)
    if lexpr.head == :∨
        new_lexpr = _negate_or(lexpr)
    elseif lexpr.head == :∧
        new_lexpr = _negate_and(lexpr)
    elseif lexpr.head == :¬
        new_lexpr = _negate_negation(lexpr)
    else
        #TODO: maybe catch error here if other operator is present
    end

    return new_lexpr
end

"""
    _negate_or(expr)

Negate OR boolean operator.
"""
function _negate_or(lexpr::LogicalExpr)
    if length(lexpr.args) < 2 
        error("The OR operator must have at least two clauses.")
    end
    return LogicalExpr(:∧, Any[ #flip OR to AND
        _move_negations_inward(LogicalExpr(:¬, Any[arg]))
        for arg in lexpr.args
    ])
end

"""
    _negate_and(expr)

Negate AND boolean operator.
"""
function _negate_and(lexpr::LogicalExpr)
    if length(lexpr.args) < 2 
        error("The AND operator must have at least two clauses.")
    end
    return LogicalExpr(:∨, Any[ #flip AND to OR
        _move_negations_inward(LogicalExpr(:¬, Any[arg]))
        for arg in lexpr.args
    ])
end

"""
    _negate_negation(expr)

Negate negation boolean operator.
"""
function _negate_negation(lexpr::LogicalExpr)
    if length(lexpr.args) != 1
        error("The negation operator can only have 1 clause.")
    end
    return _move_negations_inward(lexpr.args[1])
end


"""
    _distribute_and_over_or(expr)

Distribute AND over OR boolean operators.
"""
function _distribute_and_over_or(lvar::LogicalVariableRef)
    return lvar
end
function _distribute_and_over_or(lexpr::LogicalExpr)
    if lexpr.head == :∨
        if length(lexpr.args) < 2 
            error("The OR operator must have at least two clauses.")
        end
        new_lexpr = _distribute_and_over_or_left(lexpr)
        new_lexpr = _distribute_and_over_or_right(new_lexpr)
    else
        new_lexpr = LogicalExpr(lexpr.head, Any[
            _distribute_and_over_or(arg) for arg in lexpr.args
        ])
    end

    return new_lexpr
end
function _distribute_and_over_or_left(lexpr::LogicalExpr)
    A = lexpr.args[1]
    B = lexpr.args[2]
    if A isa LogicalExpr && A.head == :∧ #first clause has AND
        if length(A.args) < 2 
            error("The AND operator must have at least two clauses.")
        end
        C = A.args[1] #first subclause
        D = A.args[2] #second subclause
        new_lexpr0 = LogicalExpr(:∧, Any[ #flip OR to AND in main expr
            _distribute_and_over_or(LogicalExpr(:∨, Any[C, B])),
            _distribute_and_over_or(LogicalExpr(:∨, Any[D, B]))
        ])
        if length(lexpr.args) == 2
            new_lexpr = new_lexpr0
        else    
            new_lexpr = LogicalExpr(:∨, Any[new_lexpr0, lexpr.arg[3:end]...])
        end
    else
        new_lexpr = lexpr
    end
    return new_lexpr
end
function _distribute_and_over_or_right(lexpr::LogicalExpr)
    A = lexpr.args[1] #first clause
    B = lexpr.args[2] #second clause
    if B isa LogicalExpr && lexpr.head == :∨ && B.head == :∧ #second clause has AND
        if length(B.args) < 2 
            error("The AND operator must have at least two clauses.")
        end
        C = B.args[1] #first subclause
        D = B.args[2] #second subclause
        new_lexpr0 = LogicalExpr(:∧, Any[ #flip OR to AND in main expr
            _distribute_and_over_or(LogicalExpr(:∨, Any[A, C])),
            _distribute_and_over_or(LogicalExpr(:∨, Any[A, D]))
        ])
        if length(lexpr.args) == 2
            new_lexpr = new_lexpr0
        else    
            new_lexpr = LogicalExpr(:∨, Any[new_lexpr0, lexpr.arg[3:end]...])
        end
    else
        new_lexpr = lexpr
    end
    return new_lexpr
end

"""

"""
function _flatten(lvar::LogicalVariableRef)
    return lvar
end
function _flatten(lexpr::LogicalExpr)
    if lexpr.head in (:∧, :∨)
        nary_args = Set{Any}()
        for arg in lexpr.args
            if arg isa LogicalVariableRef
                push!(nary_args, arg)
            elseif arg.head == :¬
                push!(nary_args, arg)
            elseif arg.head == lexpr.head
                arg_flat = _flatten(arg)
                for a in arg_flat.args
                    push!(nary_args, _flatten(a))
                end
            else
                return lexpr
            end
        end
        new_lexpr = LogicalExpr(lexpr.head, collect(nary_args))
    else 
        new_lexpr = LogicalExpr(lexpr.head, Any[
            _flatten(arg) for arg in lexpr.args
        ])
    end

    return new_lexpr
end
# function JuMP.flatten(expr::LogicalExpr)
#     root = LogicalExpr(expr.head, Any[])
#     nodes_to_visit = Any[(root, arg) for arg in reverse(expr.args)]
#     while !isempty(nodes_to_visit)
#         parent, arg = pop!(nodes_to_visit)
#         if !(arg isa LogicalExpr)
#             # Not a nonlinear expression, so can use recursion.
#             push!(parent.args, JuMP.flatten(arg))
#         elseif parent.head in (:∨, :∧) && arg.head == parent.head
#             # A special case: the arg can be lifted to an n-ary argument of the
#             # parent.
#             for n in reverse(arg.args)
#                 push!(nodes_to_visit, (parent, n))
#             end
#         else
#             # The default case for nonlinear expressions. Put the args on the
#             # stack, so that we may walk them later.
#             for n in reverse(arg.args)
#                 push!(nodes_to_visit, (arg, n))
#             end
#             empty!(arg.args)
#             push!(parent.args, arg)
#         end
#     end
#     return root
# end

# """
#     add_proposition!(m::JuMP.Model, expr::Expr; name::String = "")

# Convert logical proposition expression into conjunctive normal form.
# """
# function add_proposition!(m::JuMP.Model, expr::Expr; name::String = "")
#     if isempty(name)
#         name = "{$expr}" #get name to register reformulated logical proposition
#     end
#     replace_Symvars!(expr, m; logical_proposition = true) #replace all JuMP variables with Symbolic variables
#     clause_list = to_cnf!(expr)
#     #replace symbolic variables with JuMP variables and boolean operators with their algebraic counterparts
#     for clause in clause_list
#         replace_JuMPvars!(clause, m)
#         replace_logic_operators!(clause)
#     end
#     #generate and simplify JuMP expressions for the lhs of the algebraic constraints
#     lhs = eval.(clause_list)
#     drop_zeros!.(lhs)
#     unique!(lhs)
#     #generate JuMP constraints for the logical proposition
#     if length(lhs) == 1
#         m[Symbol(name)] = @constraint(m, lhs[1] >= 1, base_name = name)
#     else
#         m[Symbol(name)] = @constraint(m, [i = eachindex(lhs)], lhs[i] >= 1, base_name = name)
#     end
# end

# """
#     to_cnf!(expr::Expr)

# Convert an expression of symbolic Boolean variables and operators to CNF.
# """
# function to_cnf!(expr::Expr)
#     check_logical_proposition(expr) #check that valid boolean symbols and variables are used in the logical proposition
#     eliminate_equivalence!(expr) #eliminate ⇔
#     eliminate_implication!(expr) #eliminmate ⇒
#     move_negations_inwards!(expr) #expand ¬
#     clause_list = distribute_and_over_or_recursively!(expr) #distribute ∧ over ∨ recursively
#     @assert !isempty(clause_list) "Conversion to CNF failed."

#     return clause_list
# end

# """
#     check_logical_proposition(expr::Expr)

# Validate logical proposition provided.
# """
# function check_logical_proposition(expr::Expr)
#     #NOTE: this is quick and dirty (uses Suppressor.jl). A more robust approach should traverse the expression tree to verify that only valid boolean symbols and model variables are used.
#     dump_str = @capture_out dump(expr, maxdepth = typemax(Int)) #caputre dump
#     dump_arr = split(dump_str,"\n") #split by \n
#     filter!(i -> occursin("1:",i), dump_arr) #filter only first args in each subexpression
#     @assert all(occursin.("1: Symbol ",dump_arr)) "Logical expression does not use valid Boolean symbols: ∨, ∧, ¬, ⇒, ⇔."
#     operator_list = map(i -> split(i, "Symbol ")[2], dump_arr)
#     @assert isempty(setdiff(operator_list, ["∨", "∧", "¬", "⇒", "⇔", "variables"])) "Logical expression does not use valid model variables or allowed Boolean symbols (∨, ∧, ¬, ⇒, ⇔)."
# end







# """
#     distribute_and_over_or!(expr)

# Distribute AND over OR boolean operators.
# """
# function distribute_and_over_or!(expr)
#     if expr isa Expr
#         if expr.args[1] == :∨
#             # op = expr.args[1]
#             A = expr.args[2] #first clause
#             B = expr.args[3] #second clause
#             if A isa Expr && A.args[1] == :∧ #first clause has AND
#                 C = A.args[2] #first subclause
#                 D = A.args[3] #second subclause
#                 expr.args[1] = :∧ #flip OR to AND in main expr
#                 expr.args[2] = :($C ∨ $B)
#                 expr.args[3] = :($D ∨ $B)
#             elseif B isa Expr && B.args[1] == :∧ #second clause has AND
#                 C = B.args[2] #first subclause
#                 D = B.args[3] #second subclause
#                 expr.args[1] = :∧ #flip OR to AND in main expr
#                 expr.args[2] = :($C ∨ $A)
#                 expr.args[3] = :($D ∨ $A)
#             end
#         end
#         for i in eachindex(expr.args)
#             expr.args[i] = distribute_and_over_or!(expr.args[i])
#         end
#     end

#     return expr
# end

# """
#     extract_clauses(expr)

# Extract clauses from conjunctive normal form.
# """
# function extract_clauses(expr)
#     clauses = []
#     if expr isa Expr
#         if expr.args[1] == :∨
#             push!(clauses, expr)
#         else
#             for i in 2:length(expr.args)
#                 push!(clauses, extract_clauses(expr.args[i])...)
#             end
#         end
#     end

#     return clauses
# end

# """
#     distribute_and_over_or_recursively!(expr)

# Distribute AND over OR boolean operators recursively throughout the expression tree.
# """
# function distribute_and_over_or_recursively!(expr)
#     distribute_and_over_or!(expr)
#     clause_list = extract_clauses(expr)
#     wrong_clauses = filter(i -> occursin("∧",string(i)), clause_list)
#     if !isempty(wrong_clauses)
#         clause_list = distribute_and_over_or_recursively!(expr)
#     end

#     return unique!(clause_list)
# end

# """
#     replace_logic_operators!(expr)

# Replace ∨ for +; replace ¬ for 1 - var.
# """
# function replace_logic_operators!(expr)
#     if expr isa Expr
#         if expr.args[1] == :∨
#             expr.args[1] = :(+)
#         elseif expr.args[1] == :¬
#             A = expr.args[2]
#             expr = :(1 - $A)
#         end
#         for i in 2:length(expr.args)
#             expr.args[i] = replace_logic_operators!(expr.args[i])
#         end
#     end

#     return expr
# end