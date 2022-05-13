"""
    Disjunct{C <: Tuple}

A type for storing a mathematical disjunct object. Principally, it is comprised 
of constraints and an indicator variable which is true when the disjunct is 
satisfied. 

**Fields**
- `constraints::C`: A tuple of constraint collections where each collection is a 
                    JuMP container and each constraint in the container is some 
                    kind of `JuMP.AbstractConstraint`.
- `indicator::JuMP.VariableRef`: The boolean/binary variable associated with the 
                                 disjunct.
"""
struct Disjunct{C <: Tuple}
    constraints::C # TODO maybe make vector of constraints instead
    indicator::JuMP.VariableRef # TODO maybe create our own boolean var type
end

"""
    DisjunctionConstraint <: JuMP.AbstractConstraint

A type for a disjunction constraint that is comprised of a collection of 
disjuncts of type [`Disjunct`](@ref) which are each enforced with exclusive-or 
logic as per standard generalized disjunctive programming theory.

**Fields**
- `disjuncts::Vector{Disjunct}`: The disjuncts that comprise the constraint.
"""
struct DisjunctionConstraint <: JuMP.AbstractConstraint
    disjuncts::Vector{Disjunct}
end

"""
    ConstraintData

A type for storing [`DisjunctionConstraint`](@ref)s and any meta-data they 
possess.

**Fields**
- `constraint::DisjunctionConstraint`: The disjunctive constraint object.
- `name::String`: The name of the constraint.
"""
mutable struct ConstraintData
    constraint::DisjunctionConstraint
    name::String
end

"""
    DisjunctionIndex

A type for storing the index of a [`DisjunctionConstraint`](@ref).

**Fields**
- `value::Int64`: The index value.
"""
struct DisjunctionIndex
    value::Int64
end

"""
    DisjunctiveConstraintRef

A type for looking up disjunction constraints.
"""
struct DisjunctiveConstraintRef
    model::JuMP.Model
    index::DisjunctionIndex
end

## Extend the CleverDicts key access methods
# index_to_key
function _MOIUC.index_to_key(::Type{DisjunctionIndex}, index::Int64)
    return DisjunctionIndex(index)
end

# key_to_index
function _MOIUC.key_to_index(key::DisjunctionIndex)
    return key.value
end

# TODO create types for storing propositions

"""
    AbstractSolutionMethod

An abstract type for solution methods used to solve `GDPModel`s.
"""
abstract type AbstractSolutionMethod end

"""
    AbstractReformulationMethod <: AbstractReformulationMethod

An abstract type for reformulation approaches used to solve `GDPModel`s.
"""
abstract type AbstractReformulationMethod <: AbstractReformulationMethod end

"""
    BigM <: AbstractReformulationMethod

A type for using the big-M reformulation approach for disjunction constraints.
"""
struct BigM <: AbstractReformulationMethod end # TODO add fields if needed

"""
    Hull <: AbstractReformulationMethod

A type for using the convex hull reformulation approach for disjunctive 
constraints.
"""
struct Hull <: AbstractReformulationMethod end # TODO add fields if needed

"""
    GDPData

The core type for storing information in a [`GDPModel`](@ref).
"""
mutable struct GDPData
    # Costraints
    constraints::_MOIUC.CleverDicts{DisjunctionIndex, ConstraintData}
    # TODO account for propositions

    # Solution data
    solution_method::Union{Nothing, AbstractSolutionMethod}
    ready_to_optimize::Bool
    # TODO track meta-data of any constraints/variables we add to the model

    # Default constructor
    function GDPData()
        new(_MOIUC.CleverDicts{DisjunctionIndex, ConstraintData}(), 
            nothing,
            false
            )
    end
end
