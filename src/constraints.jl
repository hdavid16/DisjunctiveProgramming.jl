################################################################################
#                         HELPER SET MAPPING FUNCTIONS
################################################################################
# helper functions to get the value of an MOI set
_set_value(set::_MOI.LessThan) = set.upper
_set_value(set::_MOI.GreaterThan) = set.lower
_set_value(set::_MOI.EqualTo) = set.value
_set_values(set::_MOI.EqualTo) = (set.value, set.value)
_set_values(set::_MOI.Interval) = (set.lower, set.upper)

# helper functions to reformulate vector constraints to indicator constraints
_vec_to_scalar_set(set::_MOI.Nonpositives) = _MOI.LessThan(0)
_vec_to_scalar_set(set::_MOI.Nonnegatives) = _MOI.GreaterThan(0)
_vec_to_scalar_set(set::_MOI.Zeros) = _MOI.EqualTo(0)

# helper functions to map jump selector to moi selector sets
_jump_to_moi_selector(set::Exactly) = _MOIExactly
_jump_to_moi_selector(set::AtLeast) = _MOIAtLeast
_jump_to_moi_selector(set::AtMost) = _MOIAtMost

# helper functions to map selectors to scalar sets
_vec_to_scalar_set(set::_MOIExactly) = _MOI.EqualTo
_vec_to_scalar_set(set::_MOIAtLeast) = _MOI.GreaterThan
_vec_to_scalar_set(set::_MOIAtMost) = _MOI.LessThan

################################################################################
#                         BOILERPLATE EXTENSION METHODS
################################################################################
for (RefType, loc) in ((:DisjunctConstraintRef, :disjunct_constraints), 
                       (:DisjunctionRef, :disjunctions), 
                       (:LogicalConstraintRef, :logical_constraints))
    @eval begin
        @doc """
            JuMP.owner_model(cref::$($RefType))

        Return the model to which `cref` belongs.
        """
        JuMP.owner_model(cref::$RefType) = cref.model

        @doc """
            JuMP.index(cref::$($RefType))

        Return the index constraint associated with `cref`.
        """
        JuMP.index(cref::$RefType) = cref.index

        @doc """
            JuMP.is_valid(model::JuMP.Model, cref::$($RefType))

        Return `true` if `cref` refers to a valid constraint in the `GDP model`.
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

        Get a constraint's name attribute.
        """
        function JuMP.name(cref::$RefType)
            return _constraint_data(cref).name
        end

        @doc """
            JuMP.set_name(cref::$($RefType), name::String)

        Set a constraint's name attribute.
        """
        function JuMP.set_name(cref::$RefType, name::String)
            _constraint_data(cref).name = name
            _set_ready_to_optimize(JuMP.owner_model(cref), false)
            return
        end

        @doc """
            JuMP.constraint_object(cref::$($RefType))

        Return the underlying constraint data for the constraint 
            referenced by `cref`.
        """
        function JuMP.constraint_object(cref::$RefType)
            return _constraint_data(cref).constraint
        end

        # Extend Base methods
        function Base.:(==)(cref1::$RefType, cref2::$RefType)
            return cref1.model === cref2.model && cref1.index == cref2.index
        end
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

# Extend delete
"""
    JuMP.delete(model::JuMP.Model, cref::DisjunctionRef)

Delete a disjunction constraint from the `GDP model`.
"""
function JuMP.delete(model::JuMP.Model, cref::DisjunctionRef)
    @assert JuMP.is_valid(model, cref) "Disjunctive constraint does not belong to model."
    cidx = JuMP.index(cref)
    dict = _disjunctions(model)
    delete!(dict, cidx)
    _set_ready_to_optimize(model, false)
    return 
end

"""
    JuMP.delete(model::JuMP.Model, cref::DisjunctConstraintRef)

Delete a disjunct constraint from the `GDP model`.
"""
function JuMP.delete(model::JuMP.Model, cref::DisjunctConstraintRef)
    @assert JuMP.is_valid(model, cref) "Disjunctive constraint does not belong to model."
    cidx = JuMP.index(cref)
    dict = _disjunct_constraints(model)
    delete!(dict, cidx)
    _set_ready_to_optimize(model, false)
    return 
end

"""
    JuMP.delete(model::JuMP.Model, cref::LogicalConstraintRef)

Delete a logical constraint from the `GDP model`.
"""
function JuMP.delete(model::JuMP.Model, cref::LogicalConstraintRef)
    @assert JuMP.is_valid(model, cref) "Logical constraint does not belong to model."
    cidx = JuMP.index(cref)
    dict = _logical_constraints(model)
    delete!(dict, cidx)
    _set_ready_to_optimize(model, false)
    return 
end

################################################################################
#                              Disjunct Constraints
################################################################################
function _check_expression(expr)
    vars = Set{JuMP.VariableRef}()
    _interrogate_variables(v -> push!(vars, v), expr) 
    if any(JuMP.is_binary.(vars)) || any(JuMP.is_integer.(vars))
        error("Disjunct constraints cannot contain binary or integer variables.")
    end
    return
end
"""
    JuMP.build_constraint(
        _error::Function, 
        func, 
        set::_MOI.AbstractScalarSet,
        tag::DisjunctConstraint
    )::_DisjunctConstraint

Extend `JuMP.build_constraint` to add constraints to disjuncts. This in 
combination with `JuMP.add_constraint` enables the use of 
`@constraint(model, [name], constr_expr, tag)`, where tag is a
`DisjunctConstraint(::Type{LogicalVariableRef})`. The user must specify the 
`LogicalVariable` to use as the indicator for the `_DisjunctConstraint` being created.
"""
function JuMP.build_constraint(
    _error::Function, 
    func, 
    set::_MOI.AbstractScalarSet, 
    tag::DisjunctConstraint
)
    _check_expression(func)
    constr = JuMP.build_constraint(_error, func, set)
    return _DisjunctConstraint(constr, tag.indicator)
end

# Allows for building DisjunctConstraints for VectorConstraints since these get parsed differently by JuMP (JuMP changes the set to a MOI.AbstractScalarSet)
for SetType in (
    JuMP.Nonnegatives, JuMP.Nonpositives, JuMP.Zeros,
    MOI.Nonnegatives, MOI.Nonpositives, MOI.Zeros
)
    @eval begin
        @doc """
            JuMP.build_constraint(
                _error::Function, 
                func, 
                set::$($SetType),
                tag::DisjunctConstraint
            )::_DisjunctConstraint

        Extend `JuMP.build_constraint` to add `VectorConstraint`s to disjuncts.
        """
        function JuMP.build_constraint(
            _error::Function, 
            func, 
            set::$SetType, 
            tag::DisjunctConstraint
        )
            _check_expression(func)
            constr = JuMP.build_constraint(_error, func, set)
            return _DisjunctConstraint(constr, tag.indicator)
        end
    end
end

# Allow intervals to handle tags
function JuMP.build_constraint(
    _error::Function, 
    func::JuMP.AbstractJuMPScalar, 
    lb::Real, 
    ub::Real,
    tag::DisjunctConstraint
)
    _check_expression(func)
    constr = JuMP.build_constraint(_error, func, lb, ub)
    func = JuMP.jump_function(constr)
    set = JuMP.moi_set(constr)
    return JuMP.build_constraint(_error, func, set, tag)
end

"""
    JuMP.add_constraint(
        model::JuMP.Model,
        con::_DisjunctConstraint,
        name::String = ""
    )::DisjunctConstraintRef

Extend `JuMP.add_constraint` to add a [`DisjunctConstraint`](@ref) to a [`GDPModel`](@ref). 
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
    _add_indicator_var(con, DisjunctConstraintRef(model, idx), model)
    return DisjunctConstraintRef(model, idx)
end

################################################################################
#                              DISJUNCTIONS
################################################################################
# Add the variable mappings
function _add_indicator_var(
    con::_DisjunctConstraint{C, LogicalVariableRef}, 
    cref, 
    model
    ) where {C <: JuMP.AbstractConstraint}
    JuMP.is_valid(model, con.lvref) || error("Logical variable belongs to a different model.")
    if !haskey(_indicator_to_constraints(model), con.lvref)
        _indicator_to_constraints(model)[con.lvref] = Vector{Union{DisjunctConstraintRef, DisjunctionRef}}()
    end
    push!(_indicator_to_constraints(model)[con.lvref], cref)
    return
end
# check disjunction
function _check_disjunction(_error, lvrefs::AbstractVector{LogicalVariableRef}, model::JuMP.Model)
    isequal(unique(lvrefs),lvrefs) || _error("Not all the logical indicator variables are unique.")
    for lvref in lvrefs
        if !JuMP.is_valid(model, lvref)
            _error("`$lvref` is not a valid logical variable reference.")
        end
    end
    return lvrefs
end

# fallback
function _check_disjunction(_error, lvrefs, model::JuMP.Model)
    _error("Unrecognized disjunction input structure.") # TODO add details on proper syntax
end

# Write the main function for creating disjunctions that is macro friendly
function _create_disjunction(
    _error::Function,
    model::JuMP.Model, # TODO: generalize to AbstractModel
    structure::AbstractVector, #generalize for containers
    name::String,
    nested::Bool
)
    is_gdp_model(model) || error("Can only add disjunctions to `GDPModel`s.")

    # build the disjunction
    indicators = _check_disjunction(_error, structure, model)
    disjunction = Disjunction(indicators, nested)

    # add it to the model
    disjunction_data = ConstraintData(disjunction, name)
    idx = _MOIUC.add_item(_disjunctions(model), disjunction_data)

    _set_ready_to_optimize(model, false)
    return DisjunctionRef(model, idx)
end

# Disjunction build for unnested disjunctions
function _disjunction(
    _error::Function,
    model::JuMP.Model, # TODO: generalize to AbstractModel
    structure::AbstractVector, #generalize for containers
    name::String
)
    return _create_disjunction(_error, model, structure, name, false)
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
    tag::DisjunctConstraint
)
    dref = _create_disjunction(_error, model, structure, name, true)
    obj = JuMP.constraint_object(dref)
    _add_indicator_var(_DisjunctConstraint(obj, tag.indicator), dref, model)
    return dref
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
        disjunct_indicators::Vector{LogicalVariableRef}
        name::String = ""
    )

Function to add a [`Disjunction`](@ref) to a [`GDPModel`](@ref).

    disjunction(
        model::JuMP.Model, 
        disjunct_indicators::Vector{LogicalVariableRef},
        nested_tag::DisjunctConstraint,
        name::String = ""
    )

Function to add a nested [`Disjunction`](@ref) to a [`GDPModel`](@ref).
"""
function disjunction(
    model::JuMP.Model, 
    disjunct_indicators, 
    name::String = ""
) # TODO add kw argument to build exactly 1 constraint
    return _disjunction(error, model, disjunct_indicators, name)
end
function disjunction(
    model::JuMP.Model, 
    disjunct_indicators, 
    nested_tag::DisjunctConstraint,
    name::String = "",
) # TODO add kw argument to build exactly 1 constraint
    return _disjunction(error, model, disjunct_indicators, name, nested_tag)
end

################################################################################
#                              LOGICAL CONSTRAINTS
################################################################################
JuMP.operator_to_set(_error::Function, ::Val{:⟹}) = _error(
    "Cannot use ⟹ in a MOI set (invalid right-hand side). If you are seeing this error, " *
    "you likely added a logical constraint of the form A ⟹ B ∈ IsTrue(). " *
    "Instead, you should enclose the constraint function in parenthesis: " *
    "(A ⟹ B) ∈ IsTrue()."
)
JuMP.operator_to_set(_error::Function, ::Val{:⇔}) = _error(
    "Cannot use ⇔ in a MOI set (invalid right-hand side). If you are seeing this error, " *
    "you likely added a logical constraint of the form A ⇔ B ∈ IsTrue(). " *
    "Instead, you should enclose the constraint function in parenthesis: " *
    "(A ⇔ B) ∈ IsTrue()."
)

"""
    function JuMP.build_constraint(
        _error::Function, 
        func::AbstractVector{T},
        set::S
    ) where {T <: Union{LogicalVariableRef, _LogicalExpr}, S <: Union{Exactly, AtLeast, AtMost}}

Extend `JuMP.build_constraint` to add logical cardinality constraints to a [`GDPModel`](@ref). 
This in combination with `JuMP.add_constraint` enables the use of 
`@constraint(model, [name], logical_expr in set)`, where set can be either of the following
cardinality sets: `AtLeast(n)`, `AtMost(n)`, or `Exactly(n)`.

## Example

To select exactly 1 logical variable `Y` to be `true`, do 
(the same can be done with `AtLeast(n)` and `AtMost(n)`):

```julia
using DisjunctiveProgramming
model = GDPModel();
@variable(model, Y[i = 1:2], LogicalVariable);
@constraint(model, [Y[1], Y[2]] in Exactly(1));
```

    JuMP.build_constraint(
        _error::Function, 
        func::_LogicalExpr,
        set::IsTrue
    )

Extend `JuMP.build_constraint` to add logical propositional constraints to a [`GDPModel`](@ref). 
This in combination with `JuMP.add_constraint` enables the use of 
`@constraint(model, [name], logical_expr in IsTrue())` to define a Boolean expression that must
either be true or false.
"""
function JuMP.build_constraint( # Cardinality logical constraint
    _error::Function, 
    func::AbstractVector{T}, # allow any vector-like JuMP container
    set::S # TODO: generalize to allow CP sets from MOI
) where {T <: LogicalVariableRef, S <: Union{Exactly, AtLeast, AtMost}}
    new_set = _jump_to_moi_selector(set)(length(func) + 1)
    new_func = Union{Number,LogicalVariableRef}[set.value, func...]
    return JuMP.VectorConstraint(new_func, new_set)
end
function JuMP.build_constraint( # Cardinality logical constraint
    _error::Function, 
    func::AbstractVector, 
    set::S # TODO: generalize to allow CP sets from MOI
) where {S <: Union{Exactly, AtLeast, AtMost}}
    _error("Selector constraints can only be applied to a Vector or Container of LogicalVariableRefs.")
end

# Proposition logical constraint: _LogicalExpr
function JuMP.build_constraint(
    _error::Function, 
    func::_LogicalExpr,
    set::IsTrue
    )
    if !(func.head in _LogicalOperatorHeads)
        _error("Unrecognized logical operator `$(func.head)`.")
    else
        return JuMP.ScalarConstraint(func, set)
    end
end

# Fallback for LogicalVariableRef in IsTrue
function JuMP.build_constraint(
    _error::Function, 
    func::LogicalVariableRef,
    set::IsTrue
    )
    _error(
        "Logical propositions must be of the form `logical_expr in IsTrue()`. " *
        "If you are trying to fix a logical variable, use `fix(logical_var, true)` instead."
    )
end

# Fallback for Affine/Quad expressions
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
    c::JuMP.ScalarConstraint{F, S},
    name::String = ""
) where {F <: Union{LogicalVariableRef, _LogicalExpr}, S <: IsTrue}
    is_gdp_model(model) || error("Can only add logical constraints to `GDPModel`s.")
    @assert all(JuMP.is_valid.(model, _get_constraint_variables(model, c))) "Constraint variables do not belong to model."
    constr_data = ConstraintData(c, name)
    idx = _MOIUC.add_item(_logical_constraints(model), constr_data)
    _set_ready_to_optimize(model, false)
    return LogicalConstraintRef(model, idx)
end
function JuMP.add_constraint(
    model::JuMP.Model,
    c::JuMP.VectorConstraint{F, S, Shape},
    name::String = ""
) where {F, S <: Union{_MOIAtLeast, _MOIAtMost, _MOIExactly}, Shape}
    is_gdp_model(model) || error("Can only add logical constraints to `GDPModel`s.")
    @assert all(JuMP.is_valid.(model, _get_constraint_variables(model, c))) "Constraint variables do not belong to model."
    constr_data = ConstraintData(c, name)
    idx = _MOIUC.add_item(_logical_constraints(model), constr_data)
    _set_ready_to_optimize(model, false)
    return LogicalConstraintRef(model, idx)
end

# TODO create bridges for MOI sets for and use BridgeableConstraint with build_constraint
