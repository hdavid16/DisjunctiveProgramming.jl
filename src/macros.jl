################################################################################
#                                BASIC HELPERS
################################################################################
# Escape when needed
# taken from https://github.com/jump-dev/JuMP.jl/blob/709d41b78e56efb4f2c54414266b30932010bd5a/src/macros.jl#L895-L897
_esc_non_constant(x::Number) = x
_esc_non_constant(x::Expr) = isexpr(x,:quote) ? x : esc(x)
_esc_non_constant(x) = esc(x)

# Ensure a model argument is valid
# Inspired from https://github.com/jump-dev/JuMP.jl/blob/d9cd5fb16c2d0a7e1c06aa9941923492fc9a28b5/src/macros.jl#L38-L44
_valid_model(error_fn::Function, model::JuMP.AbstractModel, name) = nothing
function _valid_model(error_fn::Function, model, name)
    error_fn("Expected $name to be an `JuMP.AbstractModel`, but it has type ", 
           typeof(model))
end

# Check if a macro julia variable can be registered 
# Adapted from https://github.com/jump-dev/JuMP.jl/blob/d9cd5fb16c2d0a7e1c06aa9941923492fc9a28b5/src/macros.jl#L66-L86
function _error_if_cannot_register(
    error_fn::Function, 
    model::JuMP.AbstractModel, 
    name::Symbol
    )
    if haskey(JuMP.object_dictionary(model), name)
       error_fn("An object of name $name is already attached to this model. If ",
               "this is intended, consider using the anonymous construction ",
               "syntax, e.g., `x = @macro_name(model, ...)` where the name ",
               "of the object does not appear inside the macro. Alternatively, ",
               "use `unregister(model, :$(name))` to first unregister the ",
               "existing name from the model. Note that this will not delete ",
               "the object; it will just remove the reference at ",
               "`model[:$(name)]`")
    end
    return
end
function _error_if_cannot_register(error_fn::Function, ::JuMP.AbstractModel, name)
    error_fn("Invalid name `$name`.")
end

# Inspired from https://github.com/jump-dev/JuMP.jl/blob/246cccb0d3167d5ed3df72fba97b1569476d46cf/src/macros.jl#L332-L377
function _finalize_macro(
    error_fn::Function,
    model::Expr,
    code::Any,
    source::LineNumberNode,
    register_name::Union{Nothing,Symbol}
    )
    @assert Meta.isexpr(model, :escape)
    if model.args[1] isa Symbol
        code = quote
            let $model = $model
                $code
            end
        end
    end
    if register_name !== nothing
        sym_name = Meta.quot(register_name)
        code = quote
            _error_if_cannot_register($error_fn, $model, $sym_name)
            $(esc(register_name)) = $model[$sym_name] = $code
        end
    end
    is_valid_code = :(_valid_model($error_fn, $model, $(Meta.quot(model.args[1]))))
    return Expr(:block, source, is_valid_code, code)
end

################################################################################
#                                DISJUNCTION MACRO
################################################################################
"""
    @disjunction(model, expr, kw_args...)

Add a disjunction described by the expression `expr`, 
which must be a `Vector` of `LogicalVariableRef`s.

    @disjunction(model, ref[i=..., j=..., ...], expr, kw_args...)

Add a group of disjunction described by the expression `expr` parameterized
by `i`, `j`, ..., which must be a `Vector` of `LogicalVariableRef`s. 

In both of the above calls, a [`Disjunct`](@ref) tag can be added to create 
nested disjunctions.

The recognized keyword arguments in `kw_args` are the following:
-  `base_name`: Sets the name prefix used to generate constraint names. 
    It corresponds to the constraint name for scalar constraints, otherwise, 
    the constraint names are set to `base_name[...]` for each index `...` 
        of the axes `axes`.
-  `container`: Specify the container type.
-  `exactly1`: Specify a `Bool` whether a constraint should be added to 
   only allow selecting one disjunct in the disjunction.

To create disjunctions without macros, see [`disjunction`](@ref).
"""
macro disjunction(args...)
    # define error message function
    error_fn = _JuMPC.build_error_fn(:disjunction, args, __source__)

    # process the inputs
    pos_args, kwargs = _JuMPC.parse_macro_arguments(
        error_fn, 
        args,
        num_positional_args = 2:4,
        valid_kwargs = [:container, :base_name, :exactly1]
    )

    # initial processing of positional arguments
    model_sym = popfirst!(pos_args)
    model = esc(model_sym)
    y = first(pos_args)
    extra = pos_args[2:end]
    if isexpr(args[2], :block)
        error_fn("Invalid syntax. Did you mean to use `@disjunctions`?")
    end

    # TODO: three cases lead to problems when julia variables are used for Disjunct tags
    # which violate the cases considered in the table further below. The three cases are
    # (i) @disjunction(m, Y[1, :], tag[1]) --> gets confused for @disjunction(m, name[...], Y[1, :]) (Case 2 below)
    # (ii) @disjunction(m, Y, tagref) --> gets confused for @disjunction(m, name, Y) (Case 1 below)
    # (iii) @disjunction(m, Y[1, :], tagref) --> gets confused for @disjunction(m, name[...], Y) (Case 2 below)

    # Determine if a reference/container argument was given by the user
    # There are 9 cases to consider:
    # Case | y                                  | type of y | y.head
    # -----+------------------------------------+-----------+------------
    #  1   | name                               | Symbol    | NA
    #  2   | name[1:2]                          | Expr      | :ref
    #  3   | name[i = 1:2, j = 1:2; i + j >= 3] | Expr      | :typed_vcat
    #  4   | [1:2]                              | Expr      | :vect
    #  5   | [i = 1:2, j = 1:2; i + j >= 3]     | Expr      | :vcat
    #  6   | [Y[1], Y[2]] or [Y[i] for i in I]  | Expr      | :vect or :comprehension
    #  7   | Y                                  | Symbol    | NA
    #  8   | Y[1, :]                            | Expr      | :ref 
    #  9   | some very wrong syntax             | Expr      | anything else

    # Case 8
    if isexpr(y, :ref) && (isempty(extra) || isexpr(extra[1], :call)) 
        c = nothing
        x = _esc_non_constant(y)
    # Cases 2, 3, 5
    elseif isexpr(y, (:vcat, :ref, :typed_vcat))
        length(extra) >= 1 || error_fn("No disjunction expression was given, please see docs for accepted `@disjunction` syntax..")
        c = y
        x = _esc_non_constant(popfirst!(extra))
    # Cases 1, 4
    elseif (isa(y, Symbol) || isexpr(y, :vect)) && 
        !isempty(extra) && 
        (isa(extra[1], Symbol) || isexpr(extra[1], (:vect, :comprehension, :ref)))
        c = y
        x = _esc_non_constant(popfirst!(extra))
    # Cases 6, 7
    elseif isa(y, Symbol) || isexpr(y, (:vect, :comprehension))
        c = nothing
        x = _esc_non_constant(y)
    # Case 9
    else
        error_fn("Unrecognized syntax, please see docs for accepted `@disjunction` syntax.")
    end

    # make sure param is something reasonable (I don't think this is needed)
    # if !(c isa Union{Nothing, Symbol, Expr})
    #     error_fn("Expected `$c` to be a disjunction name.")
    # end

    # process the container input
    name, idxvars, inds = Containers.parse_ref_sets(
        error_fn,
        c;
        invalid_index_variables = [model_sym],
    )

    # process the name
    name_expr = _JuMPC.build_name_expr(name, idxvars, kwargs)

    # make the creation code
    creation_code = :( _disjunction($error_fn, $model, $x, $name_expr) )
    _JuMPC.add_additional_args(creation_code, extra, kwargs; kwarg_exclude = [:container, :base_name])
    code = _JuMPC.container_code(idxvars, inds, creation_code, kwargs)

    # finalize the macro
    return _finalize_macro(error_fn, model, code, __source__, name)
end

# Pluralize the @disjunction macro
# Inspired from https://github.com/jump-dev/JuMP.jl/blob/9037ed9334720bd04bc372e5915cc042a4895e5b/src/macros.jl#L1489-L1547
"""
    @disjunctions(model, args...)

Adds groups of disjunctions at once, in the same fashion as the `@disjunction` macro.

The model must be the first argument, and multiple disjunctions can be added on multiple 
lines wrapped in a `begin ... end` block.

The macro returns a tuple containing the disjunctions that were defined.

## Example

```julia
model = GDPModel();
@variable(model, w);
@variable(model, x);
@variable(model, Y[1:4], LogicalVariable);
@constraint(model, [i=1:2], w == i, Disjunct(Y[i]));
@constraint(model, [i=3:4], x == i, Disjunct(Y[i]));
@disjunctions(model, begin
    [Y[1], Y[2]]
    [Y[3], Y[4]]
end);
````
"""
macro disjunctions(m, x)
    if !(isa(x, Expr) && x.head == :block)
        error(
            "Invalid syntax for @disjunctions. The second argument must be a `begin end` " *
            "block. For example:\n" *
            "```julia\n@disjunctions(model, begin\n    # ... lines here ...\nend)\n```."
        )
    end
    @assert isa(x.args[1], LineNumberNode)
    lastline = x.args[1]
    code = Expr(:tuple)
    singular = Expr(:., DisjunctiveProgramming, :($(QuoteNode(Symbol("@disjunction")))))
    for it in x.args
        if isa(it, LineNumberNode)
            lastline = it
        elseif isexpr(it, :tuple) # line with commas
            args = []
            # Keyword arguments have to appear like:
            # x, (start = 10, lower_bound = 5)
            # because of the precedence of "=".
            for ex in it.args
                if isexpr(ex, :tuple) # embedded tuple
                    append!(args, ex.args)
                else
                    push!(args, ex)
                end
            end
            macro_call = esc(
                Expr(
                    :macrocall,
                    singular,
                    lastline,
                    m,
                    args...,
                ),
            )
            push!(code.args, macro_call)
        else # stand-alone symbol or expression
            macro_call = esc(
                Expr(
                    :macrocall,
                    singular,
                    lastline,
                    m,
                    it,
                ),
            )
            push!(code.args, macro_call)
        end
    end
    return code
end