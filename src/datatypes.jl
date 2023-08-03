################################################################################
#                              LOGICAL VARIABLES
################################################################################

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
    model::JuMP.Model # TODO: generalize for AbstractModels
    index::LogicalVariableIndex
end

################################################################################
#                              LOGICAL CONSTRAINTS
################################################################################
# Logical sets
# struct MOIIsTrue <: _MOI.AbstractScalarSet end # we can just use MOI.Equalto(true) instead behind the scenes
# struct IsTrue <: JuMP.AbstractScalarSet end # we can probably avoid having to make a new set
# JuMP.moi_set(set::IsTrue) = MOIIsTrue()

# abstract type MOIFirstOrderSet <: _MOI.AbstractVectorSet end # This is probably not needed
"""
    _MOIAtLeast <: MOI.AbstractVectorSet

MOI level set for AtLeast constraints, see [`AtLeast`](@ref) for recommended syntax.
"""
struct MOIAtLeast <: _MOI.AbstractVectorSet
    value::Int
    dimension::Int
end
"""
    _MOIAtMost <: MOI.AbstractVectorSet

MOI level set for AtMost constraints, see [`AtMost`](@ref) for recommended syntax.
"""
struct MOIAtMost <: _MOI.AbstractVectorSet
    value::Int
    dimension::Int
end


"""
    _MOIExactly <: _MOI.AbstractVectorSet

MOI level set for Exactly constraints, see [`Exactly`](@ref) for recommended syntax.
"""
struct MOIExactly <: _MOI.AbstractVectorSet
    value::Int
    dimension::Int
end

# Create our own JuMP level sets to infer the dimension using the expression
"""
    AtLeast <: JuMP.AbstractVectorSet

Convenient alias for using [`MOIAtLeast`](@ref).
"""
struct AtLeast <: JuMP.AbstractVectorSet
    value::Int
end

"""
    AtMost <: JuMP.AbstractVectorSet

Convenient alias for using [`MOIAtMost`](@ref).
"""
struct AtMost <: JuMP.AbstractVectorSet
    value::Int
end

"""
    Exactly <: JuMP.AbstractVectorSet

Convenient alias for using [`MOIExactly`](@ref).
"""
struct Exactly <: JuMP.AbstractVectorSet
    value::Int
end

# Extend JuMP.moi_set as needed
JuMP.moi_set(set::AtLeast, dim::Int) = MOIAtLeast(set.value, dim)
JuMP.moi_set(set::AtMost, dim::Int) = MOIAtMost(set.value, dim)
JuMP.moi_set(set::Exactly, dim::Int) = MOIExactly(set.value, dim)


const _LogicalExpr = JuMP.NonlinearExpr{LogicalVariableRef}


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

"""
struct DisjunctConstraintIndex
    value::Int64
end

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

"""

"""
struct DisjunctConstraintRef
    model::JuMP.Model # TODO: generalize for AbstractModels
    index::DisjunctConstraintIndex
end

################################################################################
#                              DISJUNCTIONS
################################################################################
"""
    Disjunct

A type for storing a mathematical disjunct object. Principally, it is comprised 
of constraints and an indicator variable which is true when the disjunct is 
satisfied. 

**Fields**
- `constraints::Vector{DisjunctConstraintRef}`: The constraints of the disjunct 
    where these have been preivously added using the `DisjunctConstraint` tag. 
    This can also accept Disjunctions which have been additionally stored as 
    disjunct constraints.
- `indicator::LogicalVariableRef`: The logical variable associated with the 
                                   disjunct.
"""
struct Disjunct
    constraints::Vector{DisjunctConstraintRef}
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
    function BigM(val = 1e9, tight = true)
        new(val, tight)
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
    function Hull(ϵ = 1e-6)
        new(ϵ)
    end
end

"""
    Indicator <: AbstractReformulationMethod

A type for using indicator constraint approach for linear disjunctive constraints.
"""
struct Indicator <: AbstractReformulationMethod end

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
    constraint_to_indicator::Dict{DisjunctConstraintIndex, LogicalVariableIndex}
    indicator_to_constraints::Dict{LogicalVariableIndex, Vector{DisjunctConstraintIndex}}
    
    # Solution data
    solution_method::Union{Nothing, AbstractSolutionMethod}
    ready_to_optimize::Bool

    # Map of disaggregated variables 
    disaggregated_variables::Dict{Symbol, JuMP.VariableRef}
    indicator_variables::Dict{LogicalVariableRef, JuMP.VariableRef}
    variable_bounds::Dict{JuMP.VariableRef, Tuple{Float64, Float64}} # TODO allow for other precision

    # TODO track meta-data of any constraints/variables we add to the model

    # Default constructor
    function GDPData()
        new(_MOIUC.CleverDict{LogicalVariableIndex, LogicalVariableData}(),
            _MOIUC.CleverDict{LogicalConstraintIndex, ConstraintData}(),
            _MOIUC.CleverDict{DisjunctConstraintIndex, ConstraintData}(),
            _MOIUC.CleverDict{DisjunctionIndex, ConstraintData{Disjunction}}(), 
            Dict{DisjunctConstraintIndex, LogicalVariableIndex}(),
            Dict{LogicalVariableIndex, Vector{DisjunctConstraintIndex}}(),
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
