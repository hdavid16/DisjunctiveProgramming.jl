################################################################################
#                              LOGICAL VARIABLES
################################################################################

"""
    LogicalVariable <: JuMP.AbstractVariable

A variable type the logical variables associated with disjuncts in a [`Disjunction`](@ref).

**Fields**
- `fix_value::Union{Nothing, Bool}`: A fixed boolean value if there is one.
- `start_value::Union{Nothing, Bool}`: An initial guess if there is one.
"""
struct LogicalVariable <: JuMP.AbstractVariable 
    fix_value::Union{Nothing, Bool}
    start_value::Union{Nothing, Bool}
end

"""
    LogicalVariableData

A type for storing [`LogicalVariable`](@ref)s and any meta-data they 
possess.

**Fields**
- `variable::LogicalVariable`: The variable object.
- `name::String`: The name of the variable.
"""
mutable struct LogicalVariableData
    variable::LogicalVariable
    name::String
end

"""
    LogicalVariableIndex

A type for storing the index of a [`LogicalVariable`](@ref).

**Fields**
- `value::Int64`: The index value.
"""
struct LogicalVariableIndex
    value::Int64
end

"""
    LogicalVariableRef

A type for looking up logical variables.
"""
struct LogicalVariableRef <: JuMP.AbstractVariableRef
    model::JuMP.Model # TODO: generalize for AbstractModels
    index::LogicalVariableIndex
end

################################################################################
#                        LOGICAL PROPOSITION SETS
################################################################################
struct IsTrue <: _MOI.AbstractScalarSet end

################################################################################
#                        LOGICAL SELECTOR (CARDINALITY) SETS
################################################################################
# TODO check required methods for AbstractVectorSet: 
# All AbstractVectorSets of type S must implement:
# •  dimension, unless the dimension is
#    stored in the set.dimension field
# •  Utilities.set_dot, unless the dot
#    product between two vectors in the set
#    is equivalent to LinearAlgebra.dot.
"""
    _MOIAtLeast <: _MOI.AbstractVectorSet

MOI level set for AtLeast constraints, see [`AtLeast`](@ref) for recommended syntax.
"""
struct _MOIAtLeast <: _MOI.AbstractVectorSet
    dimension::Int
end

"""
    _MOIAtMost <: _MOI.AbstractVectorSet

MOI level set for AtMost constraints, see [`AtMost`](@ref) for recommended syntax.
"""
struct _MOIAtMost <: _MOI.AbstractVectorSet
    dimension::Int
end

"""
    _MOIExactly <: _MOI.AbstractVectorSet

MOI level set for Exactly constraints, see [`Exactly`](@ref) for recommended syntax.
"""
struct _MOIExactly <: _MOI.AbstractVectorSet
    dimension::Int
end

# Create our own JuMP level sets to infer the dimension using the expression
"""
    AtLeast{T<:Union{Int,LogicalVariableRef}} <: JuMP.AbstractVectorSet

Convenient alias for using [`_MOIAtLeast`](@ref).
"""
struct AtLeast{T<:Union{Int,LogicalVariableRef}} <: JuMP.AbstractVectorSet
    value::T
end

"""
    AtMost{T<:Union{Int,LogicalVariableRef}} <: JuMP.AbstractVectorSet

Convenient alias for using [`_MOIAtMost`](@ref).
"""
struct AtMost{T<:Union{Int,LogicalVariableRef}} <: JuMP.AbstractVectorSet
    value::T
end

"""
    Exactly <: JuMP.AbstractVectorSet

Convenient alias for using [`_MOIExactly`](@ref).
"""
struct Exactly{T<:Union{Int,LogicalVariableRef}} <: JuMP.AbstractVectorSet
    value::T 
end

# Extend JuMP.moi_set as needed
JuMP.moi_set(set::AtLeast, dim::Int) = _MOIAtLeast(dim)
JuMP.moi_set(set::AtMost, dim::Int) = _MOIAtMost(dim)
JuMP.moi_set(set::Exactly, dim::Int) = _MOIExactly(dim)

################################################################################
#                              LOGICAL CONSTRAINTS
################################################################################
const _LogicalExpr = JuMP.GenericNonlinearExpr{LogicalVariableRef}

"""
    ConstraintData{C <: JuMP.AbstractConstraint}

A type for storing constraint objects in [`GDPData`](@ref) and any meta-data 
they possess.

**Fields**
- `constraint::C`: The constraint.
- `name::String`: The name of the proposition.
"""
mutable struct ConstraintData{C <: JuMP.AbstractConstraint}
    constraint::C
    name::String
end

"""
    LogicalConstraintIndex

A type for storing the index of a logical constraint.

**Fields**
- `value::Int64`: The index value.
"""
struct LogicalConstraintIndex
    value::Int64
end

"""
    LogicalConstraintRef

A type for looking up logical constraints.
"""
struct LogicalConstraintRef
    model::JuMP.Model # TODO: generalize for AbstractModels
    index::LogicalConstraintIndex
end

################################################################################
#                              DISJUNCT CONSTRAINTS
################################################################################
"""
    DisjunctConstraint

Used as a tag for constraints that will be used in disjunctions. This is done via 
the following syntax:
```julia-repl
julia> @constraint(model, [constr_expr], DisjunctConstraint)

julia> @constraint(model, [constr_expr], DisjunctConstraint(lvref))
```
where `lvref` is a [`LogicalVariableRef`](@ref) that will ultimately be associated 
with the disjunct the constraint is added to. If no `lvref` is given, then one is 
generated when the disjunction is created.
"""
struct DisjunctConstraint
    indicator::LogicalVariableRef
end

# Create internal type for temporarily packaging constraints for disjuncts
struct _DisjunctConstraint{C <: JuMP.AbstractConstraint, L <: LogicalVariableRef}
    constr::C
    lvref::L
end

"""
    DisjunctConstraintIndex

A type for storing the index of a [`DisjunctConstraint`](@ref).

**Fields**
- `value::Int64`: The index value.
"""
struct DisjunctConstraintIndex
    value::Int64
end

"""
    DisjunctConstraintRef

A type for looking up disjunctive constraints.
"""
struct DisjunctConstraintRef
    model::JuMP.Model # TODO: generalize for AbstractModels
    index::DisjunctConstraintIndex
end

################################################################################
#                              DISJUNCTIONS
################################################################################
"""
    Disjunction <: JuMP.AbstractConstraint

A type for a disjunctive constraint that is comprised of a collection of 
disjuncts of indicated by a unique [`LogicalVariableRef`](@ref).

**Fields**
- `indicators::Vector{LogicalVariableRef}`: The references to the logical variables 
(indicators) that uniquely identify each disjunct in the disjunction.
- `nested::Bool`: Is this disjunction nested within another disjunction?
"""
struct Disjunction <: JuMP.AbstractConstraint
    indicators::Vector{LogicalVariableRef}
    nested::Bool
end

"""
    DisjunctionIndex

A type for storing the index of a [`Disjunction`](@ref).

**Fields**
- `value::Int64`: The index value.
"""
struct DisjunctionIndex
    value::Int64
end

"""
    DisjunctionRef

A type for looking up disjunctive constraints.
"""
struct DisjunctionRef
    model::JuMP.Model # TODO: generalize for AbstractModels
    index::DisjunctionIndex
end

################################################################################
#                              CLEVER DICTS
################################################################################

## Extend the CleverDicts key access methods
# index_to_key
function _MOIUC.index_to_key(::Type{LogicalVariableIndex}, index::Int64)
    return LogicalVariableIndex(index)
end
function _MOIUC.index_to_key(::Type{DisjunctConstraintIndex}, index::Int64)
    return DisjunctConstraintIndex(index)
end
function _MOIUC.index_to_key(::Type{DisjunctionIndex}, index::Int64)
    return DisjunctionIndex(index)
end
function _MOIUC.index_to_key(::Type{LogicalConstraintIndex}, index::Int64)
    return LogicalConstraintIndex(index)
end

# key_to_index
function _MOIUC.key_to_index(key::LogicalVariableIndex)
    return key.value
end
function _MOIUC.key_to_index(key::DisjunctConstraintIndex)
    return key.value
end
function _MOIUC.key_to_index(key::DisjunctionIndex)
    return key.value
end
function _MOIUC.key_to_index(key::LogicalConstraintIndex)
    return key.value
end

################################################################################
#                              SOLUTION METHODS
################################################################################

"""
    AbstractSolutionMethod

An abstract type for solution methods used to solve `GDPModel`s.
"""
abstract type AbstractSolutionMethod end

"""
    AbstractReformulationMethod <: AbstractSolutionMethod

An abstract type for reformulation approaches used to solve `GDPModel`s.
"""
abstract type AbstractReformulationMethod <: AbstractSolutionMethod end

"""
    BigM <: AbstractReformulationMethod

A type for using the big-M reformulation approach for disjunctive constraints.

**Fields**
- `value::Float64`: Big-M value (default = `1e9`).
- `tight::Bool`: Attempt to tighten the Big-M value (default = `true`)?
"""
struct BigM <: AbstractReformulationMethod
    value::Float64
    tighten::Bool
    variable_bounds::Dict{JuMP.VariableRef, Tuple{Float64, Float64}} # TODO support other number types?
    function BigM(val = 1e9, tight = true)
        new(val, tight, Dict{JuMP.VariableRef, Tuple{Float64, Float64}}())
    end
end # TODO add fields if needed

"""
    Hull <: AbstractReformulationMethod

A type for using the convex hull reformulation approach for disjunctive 
constraints.

**Fields**
- `value::Float64`: epsilon value for nonlinear hull reformulations (default = `1e-6`).
"""
struct Hull <: AbstractReformulationMethod # TODO add fields if needed
    value::Float64
    variable_bounds::Dict{JuMP.VariableRef, Tuple{Float64, Float64}} # TODO support other number types?
    function Hull(ϵ::Float64 = 1e-6)
        new(ϵ, Dict{JuMP.VariableRef, Tuple{Float64, Float64}}())
    end
    function Hull(ϵ::Float64, v_bounds::Dict{JuMP.VariableRef, Tuple{Float64, Float64}})
        new(ϵ, v_bounds)
    end
end


# temp struct to store variable disaggregations (reset for each disjunction)
mutable struct _Hull <: AbstractReformulationMethod
    value::Float64
    variable_bounds::Dict{JuMP.VariableRef, Tuple{Float64, Float64}} # TODO support other number types?
    disjunction_variables::Dict{JuMP.VariableRef, Vector{JuMP.VariableRef}}
    disjunct_variables::Dict{Tuple{JuMP.VariableRef,JuMP.VariableRef}, JuMP.VariableRef}
    function _Hull(method::Hull, vrefs::Set{JuMP.VariableRef})
        new(
            method.value,
            method.variable_bounds,
            Dict{JuMP.VariableRef, Vector{JuMP.VariableRef}}(vref => Vector{JuMP.VariableRef}() for vref in vrefs), 
            Dict{Tuple{JuMP.VariableRef,JuMP.VariableRef}, JuMP.VariableRef}()
        )
    end
end

"""
    Indicator <: AbstractReformulationMethod

A type for using indicator constraint approach for linear disjunctive constraints.
"""
struct Indicator <: AbstractReformulationMethod end

"""
    MOIDisjunction <: AbstractReformulationMethod
A reformulation type for reformulating disjunctions into their MathOptInterface 
set representations [`DisjucntionSet`](@ref) which are then added to the model.
"""
struct MOIDisjunction <: AbstractReformulationMethod end

"""
    DisjunctionSet{S <: MOI.AbstractSet} <: MOI.AbstractVectorSet
A MathOptInterface set for representing disjunctions in the format vector of 
functions in set to enable:
```julia
@constraint(model, [funcs...] in DisjunctionSet(n, idxs, sets))
```
where the vector of functions `funcs` is a flattened version of all the disjunct 
constraint functions where the indicator variable is listed first, `n` is the 
length of `[funcs...]`, `idxs` is a vector of the indices tracking where each 
disjunct begins (i.e., it stores the indices of the indicator variables in 
`[funcs...]`), and `sets` is a uses a vector of vectors structure for the MOI sets 
that correspond to all the disjunct constraint functions.
"""
struct DisjunctionSet{S <: _MOI.AbstractSet} <: _MOI.AbstractVectorSet 
    dimension::Int
    disjunct_indices::Vector{Int}
    constraint_sets::Vector{Vector{S}}
end

################################################################################
#                              GDP Data
################################################################################
"""
    GDPData

The core type for storing information in a [`GDPModel`](@ref).
"""
mutable struct GDPData
    # Objects
    logical_variables::_MOIUC.CleverDict{LogicalVariableIndex, LogicalVariableData}
    logical_constraints::_MOIUC.CleverDict{LogicalConstraintIndex, ConstraintData}
    disjunct_constraints::_MOIUC.CleverDict{DisjunctConstraintIndex, ConstraintData}
    disjunctions::_MOIUC.CleverDict{DisjunctionIndex, ConstraintData{Disjunction}}

    # Indicator variable mappings
    indicator_to_binary::Dict{LogicalVariableRef, JuMP.VariableRef}
    indicator_to_constraints::Dict{LogicalVariableRef, Vector{Union{DisjunctConstraintRef, DisjunctionRef}}}

    # Reformulation variables and constraints
    reformulation_variables::Vector{JuMP.VariableRef}
    reformulation_constraints::Vector{JuMP.ConstraintRef}

    # Solution data
    solution_method::Union{Nothing, AbstractSolutionMethod}
    ready_to_optimize::Bool

    # Default constructor
    function GDPData()
        new(_MOIUC.CleverDict{LogicalVariableIndex, LogicalVariableData}(),
            _MOIUC.CleverDict{LogicalConstraintIndex, ConstraintData}(),
            _MOIUC.CleverDict{DisjunctConstraintIndex, ConstraintData}(),
            _MOIUC.CleverDict{DisjunctionIndex, ConstraintData{Disjunction}}(),
            Dict{LogicalVariableRef, JuMP.VariableRef}(),
            Dict{LogicalVariableRef, Vector{Union{DisjunctConstraintRef, DisjunctionRef}}}(),
            Vector{JuMP.VariableRef}(),
            Vector{JuMP.ConstraintRef}(),
            nothing,
            false,
            )
    end
    function GDPData(args...)
        new(args...)
    end
end
