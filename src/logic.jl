# logic operators
_logic_operators = [
    :Ξ, :exactly, :Λ, :atmost, :Γ, :atleast,
    :∨, :lor, :∧, :land, 
    :⇔, :(<-->), :iff, :equals,
    :⇒, :(-->), :implies, :¬, :lneg
]

# # Define all the logic functions/operators that use 3+ arguments
# for (name, func) in (
#     (:Ξ, :Ξ), (:Ξ, :exactly), # \Xi + tab
#     (:Λ, :Λ), (:Λ, :atmost), # \Lambda + tab
#     (:Γ, :Γ), (:Γ, :atleast) # \Gamma + tab
# )
#     # make an expression constructor
#     @eval begin 
#         function $func(
#             v1::Union{LogicalVariableRef, LogicalExpr, Number}, 
#             v2::Union{LogicalVariableRef, LogicalExpr},
#             v3::Union{LogicalVariableRef, LogicalExpr},
#             v...
#             )
#             return LogicalExpr(Symbol($name), Any[v1, v2, v3, v...])
#         end
#     end
# end

# Define all the logic functions/operators that use 2+ arguments
for (name, func) in (
    (:∨, :∨), (:∨, :lor), # \vee + tab
    (:∧, :∧), (:∧, :land), # \wedge + tab
)
    # make an expression constructor
    @eval begin 
        function $func(
            v1::Union{LogicalVariableRef, LogicalExpr}, 
            v2::Union{LogicalVariableRef, LogicalExpr},
            v...
            )
            return LogicalExpr(Symbol($name), Any[v1, v2, v...])
        end
    end
end

# Define all the logic functions/operators that use 2 arguments
for (name, func) in (
    (:⇔, :⇔), (:⇔, :(<-->)), (:⇔, :iff), (:⇔, :equals), # \Leftrightarrow + tab
    (:⇒, :⇒), (:⇒, :(-->)), (:⇒, :implies), # \Rightarrow + tab
    (:Ξ, :Ξ), (:Ξ, :exactly), # \Xi + tab
    (:Λ, :Λ), (:Λ, :atmost), # \Lambda + tab
    (:Γ, :Γ), (:Γ, :atleast) # \Gamma + tab
)
    # make an expression constructor
    @eval begin 
        function $func(
            v1::Union{LogicalVariableRef, LogicalExpr}, 
            v2::Union{LogicalVariableRef, LogicalExpr}
            )
            return LogicalExpr(Symbol($name), Any[v1, v2])
        end
    end
end

# Define all the logic functions/operators that use 1 argument
for (name, func) in ((:¬, :¬), (:¬, :lneg))
    # make an expression constructor
    @eval begin 
        function $func(v::Union{LogicalVariableRef, LogicalExpr})
            return LogicalExpr(Symbol($name), Any[v])
        end
    end
end

"""

"""
function _to_cnf(lexpr::LogicalExpr)
    #NOTE: some redundant constraints may be created in the process.
    #   For example A ∨ ¬B ∨ B is always true and is reformulated 
    #   to the redundant constraint A ≥ 0.
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
    _flatten(lexpr::LogicalRef)

Flatten netsed OR / AND operators and replace them with their n-ary form.
For example, ∨(∨(A, B), C) is replaced with ∨(A, B, C).
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
            elseif arg.head == :¬ && arg.args[1] isa LogicalVariableRef
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