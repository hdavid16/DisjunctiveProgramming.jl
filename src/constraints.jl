################################################################################
#                         HELPER SET MAPPING FUNCTIONS
################################################################################
# helper functions to get teh value of an MOI set
_set_value(set::_MOI.LessThan) = set.upper
_set_value(set::_MOI.GreaterThan) = set.lower
_set_value(set::_MOI.EqualTo) = set.value
_set_values(set::_MOI.Interval) = (set.lower, set.upper)
# helper functions to check parsing of vector constraints for disjuncts
function _scalar_to_vec_set(set::_MOI.LessThan{Bool}, dim::Int)
    @assert _set_value(set) == false "Error parsing constraint set."
    return _MOI.Nonpositives(dim)
end
function _scalar_to_vec_set(set::_MOI.GreaterThan{Bool}, dim::Int)
    @assert _set_value(set) == false "Error parsing constraint set."
    return _MOI.Nonnegatives(dim)
end
function _scalar_to_vec_set(set::_MOI.EqualTo{Bool}, dim::Int)
    @assert _set_value(set) == false "Error parsing constraint set."
    return _MOI.Zeros(dim)
end
# helper functions to reformulate vector constraints ot indicators
_vec_to_scalar_set(set::_MOI.Nonpositives) = _MOI.LessThan(0)
_vec_to_scalar_set(set::_MOI.Nonnegatives) = _MOI.GreaterThan(0)
_vec_to_scalar_set(set::_MOI.Zeros) = _MOI.EqualTo(0)

################################################################################
#                         BOILERPLATE EXTENSION METHODS
################################################################################
for (RefType, loc) in ((:DisjunctConstraintRef, :disjunct_constraints), 
                       (:DisjunctionRef, :disjunctions), 
                       (:LogicalConstraintRef, :logical_constraints))
    @eval begin
        @doc """
            JuMP.owner_model(cref::$($RefType))

        Return the model associated with `cref`.
        """
        JuMP.owner_model(cref::$RefType) = cref.model

        @doc """
            JuMP.index(cref::$($RefType))

        Return the index associated with `cref`.
        """
        JuMP.index(cref::$RefType) = cref.index

        @doc """
            JuMP.is_valid(model::JuMP.Model, cref::$($RefType))

        Return `Bool` whether the reference is valid.
        """
        function JuMP.is_valid(model::JuMP.Model, cref::$RefType) # TODO: generalize for AbstractModel
            return model === JuMP.owner_model(cref)
        end

        # Get the ConstraintData object
        function _constraint_data(cref::$RefType)
            return gdp_data(JuMP.owner_model(cref)).$loc[JuMP.index(cref)]
        end

        @doc """
            JuMP.name(cref::$($RefType))

        Return the name associated with `cref`.
        """
        function JuMP.name(cref::$RefType)
            return _constraint_data(cref).name
        end

        @doc """
            JuMP.set_name(cref::$($RefType), name::String)

        Return the name associated with `cref`.
        """
        function JuMP.set_name(cref::$RefType, name::String)
            _constraint_data(cref).name = name
            _set_ready_to_optimize(JuMP.owner_model(cref), false)
            return
        end

        @doc """
            JuMP.constraint_object(cref::$($RefType))

        Return the constraint object associated with `cref`.
        """
        function JuMP.constraint_object(cref::$RefType)
            return _constraint_data(cref).constraint
        end

        # Extend comparisons
        function Base.:(==)(cref1::$RefType, cref2::$RefType)
            return cref1.model === cref2.model && cref1.index == cref2.index
        end

        # Extend copy
        Base.copy(cref::$RefType) = cref
        @doc """
            Base.getindex(map::JuMP.GenericReferenceMap, cref::$($RefType))

        ...
        """
        function Base.getindex(map::JuMP.ReferenceMap, cref::$RefType)
            $RefType(map.model, JuMP.index(cref))
        end
    end
end

function JuMP.delete(model::JuMP.Model, cref::DisjunctionRef)
    @assert JuMP.is_valid(model, cref) "Disjunctive constraint does not belong to model."
    cidx = JuMP.index(cref)
    dict = _disjunctions(model)
    #delete each logical variable
    for lv_idx in dict[cidx].constraint.disjuncts
        JuMP.delete(model, LogicalVariableRef(model, lv_idx))
    end
    #delete from gdp_data
    delete!(dict, cidx)
    #not ready to optimize
    _set_ready_to_optimize(model, false)
    return 
end
function JuMP.delete(model::JuMP.Model, cref::DisjunctConstraintRef)
    @assert JuMP.is_valid(model, cref) "Disjunctive constraint does not belong to model."
    cidx = JuMP.index(cref)
    dict = _disjunct_constraints(model)
    #delete from gdp_data
    delete!(dict, cidx)
    #not ready to optimize
    _set_ready_to_optimize(model, false)
    return 
end
function JuMP.delete(model::JuMP.Model, cref::LogicalConstraintRef)
    @assert JuMP.is_valid(model, cref) "Logical constraint does not belong to model."
    cidx = JuMP.index(cref)
    dict = _logical_constraints(model)
    #delete from gdp_data
    delete!(dict, cidx)
    #not ready to optimize
    _set_ready_to_optimize(model, false)
    return 
end

################################################################################
#                              Disjunct Constraints
################################################################################
"""
    JuMP.build_constraint(
        _error::Function, 
        func, 
        set::_MOI.AbstractSet,
        tag::Union{Type{DisjunctConstraint}, DisjunctConstraint}
    )::_DisjunctConstraint

Extend `JuMP.build_constraint` to add constraints to disjuncts. This in 
combination with `JuMP.add_constraint` enables the use of 
`@constraint(model, [name], constr_expr, tag)`, where tag can either be
`DisjunctConstraint` or `DisjunctConstraint(::Type{LogicalVariableRef})`.
In the former, an arbitrary [`LogicalVariable`](@ref) is created. In the latter,
the user can specify the `LogicalVariable` to use as the indicator for the 
`_DisjunctConstraint` being created.
"""
function JuMP.build_constraint(
    _error::Function, 
    func, 
    set::_MOI.AbstractSet,
    ::Type{DisjunctConstraint}
)
    return _DisjunctConstraint(JuMP.build_constraint(_error, func, set), nothing)
end
function JuMP.build_constraint(
    _error::Function,
    func::Vector{T},
    set::Union{_MOI.LessThan{Bool}, _MOI.GreaterThan{Bool}, _MOI.EqualTo{Bool}},
    ::Type{DisjunctConstraint}
) where {T <: JuMP.AbstractJuMPScalar}
    dim = length(func)
    mapped_set = _scalar_to_vec_set(set,dim)
    return _DisjunctConstraint(JuMP.build_constraint(_error, func, mapped_set), nothing)
end

# DisjunctConstraint with indicator variable
function JuMP.build_constraint(
    _error::Function, 
    func, 
    set::_MOI.AbstractSet, 
    tag::DisjunctConstraint
)
    constr = JuMP.build_constraint(_error, func, set)
    return _DisjunctConstraint(constr, tag.indicator)
end
function JuMP.build_constraint(
    _error::Function, 
    func::Vector{T}, 
    set::Union{_MOI.LessThan{Bool}, _MOI.GreaterThan{Bool}, _MOI.EqualTo{Bool}},
    tag::DisjunctConstraint
) where {T <: JuMP.AbstractJuMPScalar}
    dim = length(func)
    mapped_set = _scalar_to_vec_set(set,dim)
    constr = JuMP.build_constraint(_error, func, mapped_set)
    return _DisjunctConstraint(constr, tag.indicator)
end

# Allow intervals to handle tags
function JuMP.build_constraint(
    _error::Function, 
    func::JuMP.AbstractJuMPScalar, 
    lb::Real, 
    ub::Real,
    tag::Union{Type{DisjunctConstraint}, DisjunctConstraint}
)
    constr = JuMP.build_constraint(_error, func, lb, ub)
    func = JuMP.jump_function(constr)
    set = JuMP.moi_set(constr)
    return JuMP.build_constraint(_error, func, set, tag)
end

## Dispatch on _DisjunctConstraint to update indicator mappings if needed
# Do nothing
function _add_indicator_var(::_DisjunctConstraint{C, Nothing}, idx, model) where {C}
    return
end

# Add the variable mappings
function _add_indicator_var(
    con::_DisjunctConstraint{C, LogicalVariableRef}, 
    idx, 
    model
    ) where {C}
    JuMP.is_valid(model, con.lvref) || error("Logical variable belongs to a different model.")
    ind_idx = JuMP.index(con.lvref)
    _constraint_to_indicator(model)[idx] = ind_idx
    if haskey(_indicator_to_constraints(model), ind_idx)
        push!(_indicator_to_constraints(model)[ind_idx], idx)
    else
        _indicator_to_constraints(model)[ind_idx] = [idx]
    end
    return
end

"""
    JuMP.add_constraint(
        model::JuMP.Model,
        con::_DisjunctConstraint,
        name::String = ""
    )::DisjunctConstraintRef

Extend `JuMP.add_constraint` to add a [`_DisjunctConstraint`](@ref) to a [`GDPModel`](@ref). 
The constraint is added to the `GDPData` in the `.ext` dictionary of the `GDPModel`.
"""
function JuMP.add_constraint(
    model::JuMP.Model,
    con::_DisjunctConstraint,
    name::String = ""
)
    is_gdp_model(model) || error("Can only add disjunct constraints to `GDPModel`s.")
    data = ConstraintData(con.constr, name)
    idx = _MOIUC.add_item(gdp_data(model).disjunct_constraints, data)
    _add_indicator_var(con, idx, model)
    return DisjunctConstraintRef(model, idx)
end

# Helper function to access the logical variable index
function _indicator_index(cref::DisjunctConstraintRef)
    dict = _constraint_to_indicator(JuMP.owner_model(cref))
    return get(dict, JuMP.index(cref), nothing)
end

################################################################################
#                              DISJUNCTIONS
################################################################################
## Dispatch off raw input types to check and parse into standard format
# Vector of constrants given for each disjunct
function _process_structure(
    _error, 
    s::Vector{Vector{DisjunctConstraintRef}}, 
    model,
    name
    )
    # check that all crefs belong to model and consistently (don't) use indicators
    has_indicator = !isnothing(_indicator_index(first(first(s))))
    for crefs in s
        for cref in crefs
            if !JuMP.is_valid(model, cref)
                _error("`$cref` is not a valid constraint reference for this model.")
            elseif has_indicator != !isnothing(_indicator_index(cref))
                _error("Cannot create a disjunction where logical variable " *
                       "indicators have only been added to a subset of constraints.") 
            end
        end
    end

    # convert to indicator structure and create indicators if needed
    indicators = Vector{LogicalVariableRef}(undef, length(s))
    if has_indicator
        for (i, crefs) in enumerate(s)
            ind_idx = _indicator_index(first(crefs))
            if any(_indicator_index(c) != ind_idx for c in crefs)
                _error("Constraints in same disjunct cannot use different logical variables.")
            end
            indicators[i] = LogicalVariableRef(model, ind_idx)
        end
        return _parse_structure(_error, indicators, model)
    else 
        for (i, crefs) in enumerate(s)
            var = LogicalVariable(nothing, nothing)
            lvref = JuMP.add_variable(model, var, "$(name)_$i")
            indicators[i] = lvref
            _indicator_to_constraints(model)[JuMP.index(lvref)] = [JuMP.index(cref) for cref in crefs]
        end
        return indicators
    end
end

# Vector containing uniform constraint containers is given for each disjunct
function _process_structure(
    _error, 
    s::Vector{<:Vector{<:AbstractArray{<:DisjunctConstraintRef}}}, 
    model,
    name
    )
    vectorized_structure = Vector{Vector{DisjunctConstraintRef}}(undef, length(s))
    for (i, d) in enumerate(s)
        vectorized_structure[i] = DisjunctConstraintRef[]
        for arr in d
            for cref in arr
                push!(vectorized_structure[i], cref)
            end
        end
    end
    return _process_structure(_error, vectorized_structure, model, name)
end

# TODO account for disjuncts with mixed constraint containers

# TODO account for nested disjunction inputs with crefs

# Vector{LogicalVariableRef}
function _process_structure(_error, s::Vector{LogicalVariableRef}, model, name)
    allunique(s) ||_error("Not all the logical indicator variables are unique.")
    for lvref in s
        if !JuMP.is_valid(model, lvref)
            _error("`$lvref` is not a valid logical variable reference.")
        elseif !haskey(_indicator_to_constraints(model), JuMP.index(lvref))
            _error("`$lvref` is not associated with any constraints.")
        end
    end
    return s
end

# TODO account for nested disjunction inputs with indicators

# TODO maybe replace Vectors for Tuple structured input to avoid nuance mistakes

# fallback
function _process_structure(_error, s, model, name)
    _error("Unrecognized disjunction input structure.") # TODO add details on proper syntax
end

# Write the main function for creating disjunctions that is macro friendly
function _disjunction(
    _error::Function,
    model::JuMP.Model, # TODO: generalize to AbstractModel
    structure::Vector,
    name::String
)
    is_gdp_model(model) || error("Can only add disjunctions to `GDPModel`s.")

    # build the disjunction
    indicators = _process_structure(_error, structure, model, name)
    disjunction = Disjunction(JuMP.index.(indicators))

    # add it to the model
    disjunction_data = ConstraintData(disjunction, name)
    idx = _MOIUC.add_item(_disjunctions(model), disjunction_data)

    _set_ready_to_optimize(model, false)
    return DisjunctionRef(model, idx)
end

# Fallback disjunction build for nonvector structure
function _disjunction(
    _error::Function,
    model::JuMP.Model, # TODO: generalize to AbstractModel
    structure,
    name::String
)
    _error("Unrecognized disjunction input structure.")
end

# Disjunction build for nested disjunctions
function _disjunction(
    _error::Function,
    model::JuMP.Model, # TODO: generalize to AbstractModel
    structure,
    name::String,
    ::Type{DisjunctConstraint}
)
    dref = _disjunction(_error, model, structure, name)
    obj = JuMP.constraint_object(dref)
    return JuMP.add_constraint(model, _DisjunctConstraint(obj, nothing), name)
end

# Disjunction build for nested disjunctions with indicator variable given
function _disjunction(
    _error::Function,
    model::JuMP.Model, # TODO: generalize to AbstractModel
    structure,
    name::String,
    tag::DisjunctConstraint
)
    dref = _disjunction(_error, model, structure, name)
    obj = JuMP.constraint_object(dref)
    return JuMP.add_constraint(model, _DisjunctConstraint(obj, tag.indicator), name)
end

# General fallback for additional arguments
function _disjunction(
    _error::Function,
    model::JuMP.Model, # TODO: generalize to AbstractModel
    structure,
    name::String,
    extra...
)
    for arg in extra
        _error("Unrecognized argument `$arg`.")
    end
end

"""
    disjunction(
        model::JuMP.Model, 
        structure, 
        name::String = ""; 
        nested::Bool = false,
        indicator::Union{LogicalVariableRef, Nothing} = nothing
    )

Function to add a [`Disjunction`](@ref) to a [`GDPModel`](@ref). 
If no indicator is passed, an anonymous [`LogicalVariable`](@ref) is created.
"""
function disjunction(
    model::JuMP.Model, 
    structure, 
    name::String = ""; 
    nested::Bool = false,
    indicator::Union{LogicalVariableRef, Nothing} = nothing
) # TODO add kw argument to build exactly 1 constraint
    if !isnothing(indicator)
        return _disjunction(error, model, structure, name, DisjunctConstraint(indicator))
    elseif nested
        return _disjunction(error, model, structure, name, DisjunctConstraint)
    else
        return _disjunction(error, model, structure, name)
    end
end

################################################################################
#                              LOGICAL CONSTRAINTS
################################################################################
JuMP.operator_to_set(_error::Function, ::Val{:⟹}) = _error(
    "Cannot use ⟹ in a MOI set (invalid right-hand side). If you are seeing this error, " *
    "you likely added a logical constraint of the form A ⟹ B == true. " *
    "Instead, you should enclose the constraint function in parenthesis: " *
    "(A ⟹ B) == true."
)
JuMP.operator_to_set(_error::Function, ::Val{:⇔}) = _error(
    "Cannot use ⇔ in a MOI set (invalid right-hand side). If you are seeing this error, " *
    "you likely added a logical constraint of the form A ⇔ B == true. " *
    "Instead, you should enclose the constraint function in parenthesis: " *
    "(A ⇔ B) == true."
)

"""
    JuMP.build_constraint(
        _error::Function, 
        func::AbstractVector{<:Union{Number, LogicalVariableRef, _LogicalExpr}}, # allow any vector-like JuMP container
        set::_MOI.AbstractVectorSet # Keep general to allow CP sets from MOI
    )

Extend `JuMP.build_constraint` to add logical cardinality constraints to a [`GDPModel`](@ref). 
This in combination with `JuMP.add_constraint` enables the use of 
`@constraint(model, [name], logical_expr in set)`, where set can be either of the following
cardinality sets: `AtLeast(n)`, `AtMost(n)`, or `Exactly(n)`.

## Example

To select exactly 1 logical variable `Y` to be `true`, do 
(the same can be done with `AtLeast(n)` and `AtMost(n)`):

```jldoctest
julia> model = GDPModel();
julia> @variable(model, Y[i = 1:2], LogicalVariable);
julia> @constraint(model, [Y[1], Y[2]] in Exactly(1));
```

    JuMP.build_constraint(
        _error::Function, 
        func::_LogicalExpr,
        set::_MOI.EqualTo{Bool}
    )

Extend `JuMP.build_constraint` to add logical propositional constraints to a [`GDPModel`](@ref). 
This in combination with `JuMP.add_constraint` enables the use of 
`@constraint(model, [name], logical_expr == true/false)` to define a Boolean expression that must
either be true or false.
"""
function JuMP.build_constraint(
    _error::Function, 
    func::AbstractVector{<:Union{Number, LogicalVariableRef, _LogicalExpr}}, # allow any vector-like JuMP container
    set::_MOI.AbstractVectorSet # Keep general to allow CP sets from MOI
    )
    return JuMP.VectorConstraint(func, set)
end

# EqualTo{Bool} w/ LogicalExpr
function JuMP.build_constraint(
    _error::Function, 
    func::_LogicalExpr,
    set::_MOI.EqualTo{Bool}
    )
    new_set = _MOI.EqualTo(true)
    if set.value #set = EqualTo(true)
        return JuMP.ScalarConstraint(func, set)
    elseif func.head == :- && isone(func.args[2]) # func.args[2] is 1.0 (true)
        return JuMP.ScalarConstraint(func.args[1], new_set)
    elseif func.head == :- #func.args[2] is 0.0 (false)
        new_func = _LogicalExpr(:¬, Any[func.args[1]])
        return JuMP.ScalarConstraint(new_func, new_set)
    else #set = EqualTo(false)
        new_func = _LogicalExpr(:¬, Any[func])
        return JuMP.ScalarConstraint(new_func, new_set)
    end 
end

# EqualTo{Bool} w/ LogicalVariableRef
function JuMP.build_constraint(
    _error::Function, 
    lvref::LogicalVariableRef,
    set::_MOI.EqualTo{Bool}
    )
    set.value && return JuMP.ScalarConstraint(lvref, set)
    new_set = MOI.EqualTo(true)
    return JuMP.ScalarConstraint(_LogicalExpr(:¬, Any[lvref]), new_set)
end

# EqualTo{Bool} w/ affine LogicalVariableRef expr (caused by offset)
function JuMP.build_constraint(
    _error::Function, 
    aff::JuMP.GenericAffExpr{C, LogicalVariableRef},
    set::_MOI.EqualTo{Bool}
    ) where {C}
    if !isone(length(aff.terms)) || !isone(first(aff.terms)[2])
        _error("Cannot add or substract logical variables.")
    end
    lvref = first(keys(aff.terms))
    if aff.constant == -1
        return JuMP.ScalarConstraint(lvref, MOI.EqualTo(true))
    elseif iszero(aff.constant)
        new_func = _LogicalExpr(:¬, Any[lvref])
        return JuMP.ScalarConstraint(new_func, MOI.EqualTo(true))
    else
        _error("Cannot add or subtract constants to logical variables")
    end
end

# EqualTo sets where the boolean was converted to a number
function JuMP.build_constraint(
    _error::Function, 
    expr::Union{LogicalVariableRef, JuMP.GenericAffExpr{C, LogicalVariableRef}, _LogicalExpr}, 
    set::_MOI.EqualTo
    ) where {C}
    if !(isone(set.value) || iszero(set.value))
        _error("Uncrecognized set `$set` for logical constraint. Should use " *
               "syntax `logical_expr == true`.")
    end
    JuMP.build_constraint(_error, expr, _MOI.EqualTo(isone(set.value)))
end

# Fallback for Affine/Quad expressions (TODO: we can remove this restriction if needed)
function JuMP.build_constraint(
    _error::Function,
    expr::Union{JuMP.GenericAffExpr{C, LogicalVariableRef}, JuMP.GenericQuadExpr{C, LogicalVariableRef}},
    set::_MOI.AbstractScalarSet
) where {C}
    _error("Cannot add, subtract, or multiply with logical variables.")
end

# Fallback for other set types (TODO: we could relax this later if needed)
function JuMP.build_constraint(
    _error::Function,
    expr::Union{LogicalVariableRef, _LogicalExpr},
    set::_MOI.AbstractScalarSet
)
    _error("Invalid set `$set` for logical constraint.")
end

"""
    function JuMP.add_constraint(
        model::JuMP.Model,
        c::JuMP.ScalarConstraint{<:F, S},
        name::String = ""
    ) where {F <: Union{LogicalVariableRef, _LogicalExpr}, S}

Extend `JuMP.add_constraint` to allow creating logical proposition constraints 
for a [`GDPModel`](@ref) with the `@constraint` macro.

    function JuMP.add_constraint(
        model::JuMP.Model,
        c::JuMP.VectorConstraint{<:F, S, Shape},
        name::String = ""
    ) where {F <: Union{Number, LogicalVariableRef, _LogicalExpr}, S, Shape}

Extend `JuMP.add_constraint` to allow creating logical cardinality constraints
for a [`GDPModel`](@ref) with the `@constraint` macro.
"""
function JuMP.add_constraint(
    model::JuMP.Model,
    c::JuMP.ScalarConstraint{<:F, S},
    name::String = ""
) where {F <: Union{LogicalVariableRef, _LogicalExpr}, S}
    is_gdp_model(model) || error("Can only add logical constraints to `GDPModel`s.")
    @assert all(JuMP.is_valid.(model, _get_constraint_variables(model, c))) "Constraint variables do not belong to model."
    c = JuMP.ScalarConstraint(c.func, _MOI.EqualTo(isone(c.set.value))) #intercept set and covert to Bool
    constr_data = ConstraintData(c, name)
    idx = _MOIUC.add_item(_logical_constraints(model), constr_data)
    _set_ready_to_optimize(model, false)
    return LogicalConstraintRef(model, idx)
end
function JuMP.add_constraint(
    model::JuMP.Model,
    c::JuMP.VectorConstraint{<:F, S, Shape},
    name::String = ""
) where {F <: Union{Number, LogicalVariableRef, _LogicalExpr}, S, Shape}
    is_gdp_model(model) || error("Can only add logical constraints to `GDPModel`s.")
    @assert all(JuMP.is_valid.(model, _get_constraint_variables(model, c))) "Constraint variables do not belong to model."
    constr_data = ConstraintData(c, name)
    idx = _MOIUC.add_item(_logical_constraints(model), constr_data)
    _set_ready_to_optimize(model, false)
    return LogicalConstraintRef(model, idx)
end

# TODO create bridges for MOI sets for and use BridgeableConstraint with build_constraint
