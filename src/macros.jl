################################################################################
#                                BASIC HELPERS
################################################################################
# Macro error function
# inspired from https://github.com/jump-dev/JuMP.jl/blob/709d41b78e56efb4f2c54414266b30932010bd5a/src/macros.jl#L923-L928
function _macro_error(macroname, args, source, str...)
    error("At $(source.file):$(source.line): `@$macroname($(join(args, ", ")))`: ", 
          str...)
end

# Escape when needed
# taken from https://github.com/jump-dev/JuMP.jl/blob/709d41b78e56efb4f2c54414266b30932010bd5a/src/macros.jl#L895-L897
_esc_non_constant(x::Number) = x
_esc_non_constant(x::Expr) = isexpr(x,:quote) ? x : esc(x)
_esc_non_constant(x) = esc(x)

# Extract the name from a macro expression 
# Inspired from https://github.com/jump-dev/JuMP.jl/blob/45ce630b51fb1d72f1ff8fed35a887d84ef3edf7/src/Containers/macro.jl#L8-L17
_get_name(c::Symbol) = c
_get_name(c::Nothing) = ()
_get_name(c::AbstractString) = c
function _get_name(c::Expr)
    if isexpr(c, :string)
        return c
    else
        return c.args[1]
    end
end

# Given a base_name and idxvars, returns an expression that constructs the name
# of the object.
# Inspired from https://github.com/jump-dev/JuMP.jl/blob/709d41b78e56efb4f2c54414266b30932010bd5a/src/macros.jl#L930-L946
function _name_call(base_name, idxvars)
    if isempty(idxvars) || base_name == ""
        return base_name
    end
    ex = Expr(:call, :string, base_name, "[")
    for i in eachindex(idxvars)
        # Converting the arguments to strings before concatenating is faster:
        # https://github.com/JuliaLang/julia/issues/29550.
        esc_idxvar = esc(idxvars[i])
        push!(ex.args, :(string($esc_idxvar)))
        i < length(idxvars) && push!(ex.args, ",")
    end
    push!(ex.args, "]")
    return ex
end

# Process macro arugments 
function _extract_kwargs(args)
    arg_list = collect(args)
    if !isempty(args) && isexpr(args[1], :parameters)
        p = popfirst!(arg_list)
        append!(arg_list, p.args)
    end
    extra_kwargs = filter(x -> isexpr(x, :(=)) && x.args[1] != :container &&
                          x.args[1] != :base_name, arg_list)
    container_type = :Auto
    base_name = nothing
    for kw in arg_list
        if isexpr(kw, :(=)) && kw.args[1] == :container
            container_type = kw.args[2]
        elseif isexpr(kw, :(=)) && kw.args[1] == :base_name
            base_name = esc(kw.args[2])
        end
    end
    pos_args = filter!(x -> !isexpr(x, :(=)), arg_list)
    return pos_args, extra_kwargs, container_type, base_name
end

# Add on keyword arguments to a function call expression and escape the expressions
# Adapted from https://github.com/jump-dev/JuMP.jl/blob/d9cd5fb16c2d0a7e1c06aa9941923492fc9a28b5/src/macros.jl#L11-L36
function _add_kwargs(call, kwargs)
    for kw in kwargs
        push!(call.args, esc(Expr(:kw, kw.args...)))
    end
    return
end

# Add on positional args to a function call and escape
# Adapted from https://github.com/jump-dev/JuMP.jl/blob/a325eb638d9470204edb2ef548e93e59af56cc19/src/macros.jl#L57C1-L65C4
function _add_positional_args(call, args)
    kw_args = filter(arg -> isexpr(arg, :kw), call.args)
    filter!(arg -> !isexpr(arg, :kw), call.args)
    for arg in args
        push!(call.args, esc(arg))
    end
    append!(call.args, kw_args)
    return
end

# Determine if an expression contains any index variable symbols
function _has_idxvars(expr, idxvars)
    expr in idxvars && return true
    if expr isa Expr
        return any(_has_idxvars(a, idxvars) for a in expr.args)
    end
    return false
end

# Ensure a model argument is valid
# Inspired from https://github.com/jump-dev/JuMP.jl/blob/d9cd5fb16c2d0a7e1c06aa9941923492fc9a28b5/src/macros.jl#L38-L44
function _valid_model(_error::Function, model, name)
    is_gdp_model(model) || _error("$name is not a `GDPModel`.")
end

# Check if a macro julia variable can be registered 
# Adapted from https://github.com/jump-dev/JuMP.jl/blob/d9cd5fb16c2d0a7e1c06aa9941923492fc9a28b5/src/macros.jl#L66-L86
function _error_if_cannot_register(
    _error::Function, 
    model, 
    name::Symbol
    )
    if haskey(JuMP.object_dictionary(model), name)
        _error("An object of name $name is already attached to this model. If ",
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
function _error_if_cannot_register(_error::Function, model, name)
    return _error("Invalid name $name.")
end

# Update the creation code to register and assign the object to the name
# Inspired from https://github.com/jump-dev/JuMP.jl/blob/d9cd5fb16c2d0a7e1c06aa9941923492fc9a28b5/src/macros.jl#L88-L120
function _macro_assign_and_return(_error, code, name, model)
    return quote
        _error_if_cannot_register($_error, $model, $(quot(name)))
        $(esc(name)) = $code
        $model[$(quot(name))] = $(esc(name))
    end
end

# Wrap the macro generated code for better stacttraces (assumes model is escaped)
# Inspired from https://github.com/jump-dev/JuMP.jl/blob/d9cd5fb16c2d0a7e1c06aa9941923492fc9a28b5/src/macros.jl#L46-L64
function _finalize_macro(_error, model, code, source::LineNumberNode)
    return Expr(:block, source, 
                :(_valid_model($_error, $model, $(quot(model.args[1])))), code)
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

The recognized keyword arguments in `kw_args` are the following:
-  `base_name`: Sets the name prefix used to generate constraint names. 
    It corresponds to the constraint name for scalar constraints, otherwise, 
    the constraint names are set to `base_name[...]` for each index `...` 
        of the axes `axes`.
-  `container`: Specify the container type.
"""
macro disjunction(model, args...)
    # prepare the model 
    esc_model = esc(model)

    # define error message function
    _error(str...) = _macro_error(:disjunction, (model, args...),
                                  __source__, str...)

    # parse the arguments
    pos_args, extra_kwargs, container_type, base_name = _extract_kwargs(args)

    # initial processing of positional arguments
    length(pos_args) >= 1 || _error("Not enough arguments.")
    y = first(pos_args)
    extra = pos_args[2:end]
    if isexpr(args[1], :block)
        _error("Invalid syntax. Did you mean to use `@disjunctions`?")
    end

    # Determine if a reference/container argument was given by the user
    # There are 8 cases to consider:
    # y                                  | type of y | y.head
    # -----------------------------------+-----------+------------
    # name                               | Symbol    | NA
    # name[1:2]                          | Expr      | :ref
    # name[i = 1:2, j = 1:2; i + j >= 3] | Expr      | :typed_vcat
    # [1:2]                              | Expr      | :vect
    # [i = 1:2, j = 1:2; i + j >= 3]     | Expr      | :vcat
    # a disjunction expression           | Expr      | :vect or :comprehension
    # a disjunction expression           | Symbol    | NA
    # a disjunction expression           | Expr      | :ref 
     if isexpr(y, :ref) && (isempty(extra) || isa(extra[1], Symbol) || isexpr(extra[1], :call)) 
        c = gensym()
        x = _esc_non_constant(y)
        is_anon = true
     elseif isexpr(y, (:vcat, :ref, :typed_vcat))
        length(extra) >= 1 || _error("No disjunction expression was given.")
        c = y
        x = _esc_non_constant(popfirst!(extra))
        is_anon = isexpr(y, :vcat)
    elseif (isa(y, Symbol) || isexpr(y, :vect)) && 
        !isempty(extra) && 
        (isa(extra[1], Symbol) || isexpr(extra[1], (:vect, :comprehension, :ref)))
        c = y
        x = _esc_non_constant(popfirst!(extra))
        is_anon = isexpr(y, :vcat) || isexpr(y, :vect)
    else
        c = gensym()
        x = _esc_non_constant(y)
        is_anon = true
    end

    # process the name
    name = _get_name(c)
    if isnothing(base_name)
        base_name = is_anon ? "" : string(name)
    end
    if !isa(name, Symbol) && !is_anon
        _error("Expression $name should not be used as a disjunction name. Use " *
               "the \"anonymous\" syntax $name = @disjunction(model, " *
               "...) instead.")
    end

    # make the creation code
    if isa(c, Symbol)
        # easy case with single parameter
        creation_code = :( _disjunction($_error, $esc_model, $x, $base_name) )
        _add_positional_args(creation_code, extra)
        _add_kwargs(creation_code, extra_kwargs)
    else
        # we have a container of parameters
        idxvars, inds = JuMP.Containers.build_ref_sets(_error, c)
        if model in idxvars
            _error("Index $(model) is the same symbol as the model. Use a ",
                   "different name for the index.")
        end
        name_code = _name_call(base_name, idxvars)
        disjunction_call = :( _disjunction($_error, $esc_model, $x, $name_code) )
        _add_positional_args(disjunction_call, extra)
        _add_kwargs(disjunction_call, extra_kwargs)
        creation_code = JuMP.Containers.container_code(idxvars, inds, disjunction_call,
                                                       container_type)
    end

    # finalize the macro
    if is_anon
        macro_code = creation_code
    else
        macro_code = _macro_assign_and_return(_error, creation_code, name,
                                              esc_model)
    end
    return _finalize_macro(_error, esc_model, macro_code, __source__)
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

```jldoctest
julia> model = GDPModel();

julia> @variable(model, w);

julia> @variable(model, x);

julia> @variable(model, Y[1:4], LogicalVariable);

julia> @constraint(model, [i=1:2], w == i, DisjunctConstraint(Y[i]));

julia> @constraint(model, [i=3:4], x == i, DisjunctConstraint(Y[i]));

julia> @disjunctions(model, begin
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