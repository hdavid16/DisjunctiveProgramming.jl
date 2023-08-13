################################################################################
#                              LOGIC OPERATORS
################################################################################

# Define all the logic functions/operators that use 2+ arguments
for (name, func) in (
    (:⇔, :⇔), (:⇔, :(<-->)), (:⇔, :iff), (:⇔, :equals), # \Leftrightarrow + tab
    (:∨, :∨), (:∨, :lor), # \vee + tab
    (:∧, :∧), (:∧, :land), # \wedge + tab
)
    # make an expression constructor
    @eval begin 
        function $func(
            v1::Union{LogicalVariableRef, _LogicalExpr}, 
            v2::Union{LogicalVariableRef, _LogicalExpr},
            v...
            )
            return _LogicalExpr(Symbol($name), Any[v1, v2, v...])
        end
    end
end

# Define all the logic functions/operators that use 2 arguments
for (name, func) in (
    (:⇒, :⇒), (:⇒, :implies), # \Rightarrow + tab
    (:Ξ, :Ξ), (:Ξ, :exactly), # \Xi + tab
    (:Λ, :Λ), (:Λ, :atmost), # \Lambda + tab
    (:Γ, :Γ), (:Γ, :atleast) # \Gamma + tab
)
    # make an expression constructor
    @eval begin 
        function $func(
            v1::Union{LogicalVariableRef, _LogicalExpr}, 
            v2::Union{LogicalVariableRef, _LogicalExpr}
            )
            return _LogicalExpr(Symbol($name), Any[v1, v2])
        end
    end
end

# Define all the logic functions/operators that use 1 argument
for (name, func) in ((:¬, :¬), (:¬, :lneg))
    # make an expression constructor
    @eval begin 
        function $func(v::Union{LogicalVariableRef, _LogicalExpr})
            return _LogicalExpr(Symbol($name), Any[v])
        end
    end
end

################################################################################
#                            CONJUNCTIVE NORMAL FORM
################################################################################

"""

"""
function _to_cnf(lexpr::_LogicalExpr)
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
function _eliminate_equivalence(lexpr::_LogicalExpr)
    if lexpr.head in (:⇔, :(<-->), :iff, :equals)
        A = _eliminate_equivalence(lexpr.args[1])
        if length(lexpr.args) > 2 
            nested = _LogicalExpr(:⇔, Vector{Any}(lexpr.args[2:end]))
            B = _eliminate_equivalence(nested)
        elseif length(lexpr.args) == 2
            B = _eliminate_equivalence(lexpr.args[2])
        else
            error("The equivalence logic operator `⇔` must have at least two arguments.")
        end
        
        
        new_lexpr = _LogicalExpr(:∧, Any[
            _LogicalExpr(:⇒, Any[A, B]),
            _LogicalExpr(:⇒, Any[B, A])
        ])
    else
        new_lexpr = _LogicalExpr(lexpr.head, Any[
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
function _eliminate_implication(lexpr::_LogicalExpr)
    if lexpr.head in (:⇒, :implies)
        if length(lexpr.args) != 2 
            error("The implication operator must have two clauses.")
        end
        A = _eliminate_implication(lexpr.args[1])
        B = _eliminate_implication(lexpr.args[2])
        new_lexpr = _LogicalExpr(:∨, Any[
            _LogicalExpr(:¬, Any[A]),
            B
        ])
    else
        new_lexpr = _LogicalExpr(lexpr.head, Any[
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
function _move_negations_inward(lexpr::_LogicalExpr)
    if lexpr.head in (:¬, :lneg)
        if length(lexpr.args) != 1
            error("The negation operator can only have 1 clause.")
        end
        new_lexpr = _negate(lexpr.args[1])
    else
        new_lexpr = _LogicalExpr(lexpr.head, Any[
            _move_negations_inward(arg) for arg in lexpr.args
        ])
    end

    return new_lexpr
end

"""

"""
function _negate(lvar::LogicalVariableRef)
    return _LogicalExpr(:¬, Any[lvar])
end
function _negate(lexpr::_LogicalExpr)
    if lexpr.head in (:∨, :lor)
        new_lexpr = _negate_or(lexpr)
    elseif lexpr.head in (:∧, :land)
        new_lexpr = _negate_and(lexpr)
    elseif lexpr.head in (:¬, :lneg)
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
function _negate_or(lexpr::_LogicalExpr)
    if length(lexpr.args) < 2 
        error("The OR operator must have at least two clauses.")
    end
    return _LogicalExpr(:∧, Any[ #flip OR to AND
        _move_negations_inward(_LogicalExpr(:¬, Any[arg]))
        for arg in lexpr.args
    ])
end

"""
    _negate_and(expr)

Negate AND boolean operator.
"""
function _negate_and(lexpr::_LogicalExpr)
    if length(lexpr.args) < 2 
        error("The AND operator must have at least two clauses.")
    end
    return _LogicalExpr(:∨, Any[ #flip AND to OR
        _move_negations_inward(_LogicalExpr(:¬, Any[arg]))
        for arg in lexpr.args
    ])
end

"""
    _negate_negation(expr)

Negate negation boolean operator.
"""
function _negate_negation(lexpr::_LogicalExpr)
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
function _distribute_and_over_or(lexpr0::_LogicalExpr)
    lexpr = _flatten(lexpr0)
    if lexpr.head in (:∨, :lor)
        if length(lexpr.args) < 2 
            error("The OR operator must have at least two clauses.")
        end
        loc = findfirst(arg -> arg isa _LogicalExpr ? arg.head in (:∧, :land) : false, lexpr.args)
        if !isnothing(loc)
            new_lexpr = _LogicalExpr(:∧, Any[
                _distribute_and_over_or(
                    _LogicalExpr(:∨, Any[arg_i, lexpr.args[setdiff(1:end,loc)]...])
                )
                for arg_i in lexpr.args[loc].args
            ])
        else
            new_lexpr = lexpr
        end
    else
        new_lexpr = _LogicalExpr(lexpr.head, Any[
            _distribute_and_over_or(arg) for arg in lexpr.args
        ])
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
function _flatten(lexpr::_LogicalExpr)
    if lexpr.head in (:∧, :land, :∨, :lor)
        nary_args = Set{Any}()
        for arg in lexpr.args
            if arg isa LogicalVariableRef
                push!(nary_args, arg)
            elseif _isa_literal(arg)
                push!(nary_args, arg)
            elseif arg.head == lexpr.head
                arg_flat = _flatten(arg)
                for a in arg_flat.args
                    push!(nary_args, _flatten(a))
                end
            else
                arg_flat = _flatten(arg)
                push!(nary_args, arg_flat)
            end
        end
        new_lexpr = _LogicalExpr(lexpr.head, collect(nary_args))
    else 
        new_lexpr = _LogicalExpr(lexpr.head, Any[
            _flatten(arg) for arg in lexpr.args
        ])
    end

    return new_lexpr
end