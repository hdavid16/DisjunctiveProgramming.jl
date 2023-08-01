"""
    LogicalVariable <: JuMP.AbstractVariable

A variable type the logical variables associated with 
[`Disjunct`](@ref)s.

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
    model::JuMP.Model
    index::LogicalVariableIndex
end

#######################################################################

"""

"""
struct DisjunctConstraintIndex
    value::Int64
end

"""

"""
struct DisjunctConstraint{T, S} <: JuMP.AbstractConstraint
    func::T
    set::S
    indicator::Union{Nothing, LogicalVariableRef}
end

"""

"""
mutable struct DisjunctConstraintData
    constraint::DisjunctConstraint
    name::String
end

"""

"""
struct DisjunctConstraintRef
    model::JuMP.Model
    index::DisjunctConstraintIndex
end

#######################################################################

"""
    Disjunct{C <: Tuple}

A type for storing a mathematical disjunct object. Principally, it is comprised 
of constraints and an indicator variable which is true when the disjunct is 
satisfied. 

**Fields**
- `constraints::C`: A tuple of constraint collections where each collection is a 
                    JuMP container and each constraint in the container is some 
                    kind of `JuMP.AbstractConstraint`.
- `indicator::LogicalVariableRef`: The logical/binary variable associated with the 
                                   disjunct.
"""
struct Disjunct{C <: Tuple}
    constraints::C # TODO maybe make vector of constraints instead
    indicator::LogicalVariableRef
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
    Disjunction <: JuMP.AbstractConstraint

A type for a disjunctive constraint that is comprised of a collection of 
disjuncts of type [`Disjunct`](@ref).

**Fields**
- `disjuncts::Vector{Disjunct}`: The disjuncts that comprise the constraint.
"""
struct Disjunction <: JuMP.AbstractConstraint
    disjuncts::Vector{Disjunct}
end

"""
    DisjunctionData

A type for storing [`Disjunction`](@ref)s and any meta-data they 
possess.

**Fields**
- `constraint::Disjunction`: The disjunctive constraint object.
- `name::String`: The name of the constraint.
"""
mutable struct DisjunctionData
    constraint::Disjunction
    name::String
end

"""
    DisjunctionRef

A type for looking up disjunctive constraints.
"""
struct DisjunctionRef
    model::JuMP.Model
    index::DisjunctionIndex
end

#######################################################################

"""

"""
const LogicalExpr = JuMP.NonlinearExpr{LogicalVariableRef}

"""
    LogicalConstraint <: JuMP.AbstractConstraint

A type for a logical constraint that is comprised of an expression on LogicalVariables 
    with logic operators.

**Fields**
- `expression::LogicalExpr`: The logical constraint.
"""
struct LogicalConstraint <: JuMP.AbstractConstraint
    expression::LogicalExpr
    set::_MOI.EqualTo
end

"""
    LogicalConstraintData

A type for storing [`LogicalConstraint`](@ref)s and any meta-data they possess.

**Fields**
- `constraint::LogicalConstraint`: The logical constraint.
- `name::String`: The name of the proposition.
"""
mutable struct LogicalConstraintData
    constraint::LogicalConstraint
    name::String
end

"""
    LogicalConstraintIndex

A type for storing the index of a [`LogicalConstraint`](@ref).

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
    model::JuMP.Model
    index::LogicalConstraintIndex
end

#######################################################################

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
- `value::Float64`: Big-M value.
- `tight::Bool`: Attempt to tighten the Big-M value (default = `true`)?
"""
struct BigM <: AbstractReformulationMethod
    value::Float64
    tighten::Bool
    function BigM(val = 1e9, tight = true)
        new(val, tight)
    end
end # TODO add fields if needed

"""
    Hull <: AbstractReformulationMethod

A type for using the convex hull reformulation approach for disjunctive 
constraints.

**Fields**
- `value::Float64`: epsilon value for nonlinear hull reformulations.
"""
struct Hull <: AbstractReformulationMethod # TODO add fields if needed
    value::Float64
    function Hull(ϵ = 1e-6)
        new(ϵ)
    end
end

"""
    Indicator <: AbstractReformulationMethod

A type for using indicator constraint approach for linear disjunctive constraints.
"""
struct Indicator <: AbstractReformulationMethod end

"""
    GDPData

The core type for storing information in a [`GDPModel`](@ref).
"""
mutable struct GDPData
    # Objects
    logical_variables::_MOIUC.CleverDict{LogicalVariableIndex, LogicalVariableData}
    logical_constraints::_MOIUC.CleverDict{LogicalConstraintIndex, LogicalConstraintData}
    disjunct_constraints::_MOIUC.CleverDict{DisjunctConstraintIndex, DisjunctConstraintData}
    disjunct_constraint_map::Dict{DisjunctConstraintIndex, LogicalVariableIndex}
    disjunctions::_MOIUC.CleverDict{DisjunctionIndex, DisjunctionData}
    
    # Solution data
    solution_method::Union{Nothing, AbstractSolutionMethod}
    ready_to_optimize::Bool

    # Map of disaggregated variables 
    disaggregated_variables::Dict{Symbol, JuMP.VariableRef}
    indicator_variables::Dict{LogicalVariableRef, JuMP.VariableRef}
    variable_bounds::Dict{JuMP.VariableRef, Tuple{Float64, Float64}}

    # TODO track meta-data of any constraints/variables we add to the model

    # Default constructor
    function GDPData()
        new(_MOIUC.CleverDict{LogicalVariableIndex, LogicalVariableData}(),
            _MOIUC.CleverDict{LogicalConstraintIndex, LogicalConstraintData}(),
            _MOIUC.CleverDict{DisjunctConstraintIndex, DisjunctConstraintData}(),
            Dict{DisjunctConstraintIndex, LogicalVariableIndex}(),
            _MOIUC.CleverDict{DisjunctionIndex, DisjunctionData}(), 
            nothing,
            false,
            Dict{Symbol, JuMP.VariableRef}(),
            Dict{LogicalVariableRef, JuMP.VariableRef}(),
            Dict{JuMP.VariableRef, Tuple{Float64, Float64}}()
            )
    end
    function GDPData(args...)
        new(args...)
    end
end
