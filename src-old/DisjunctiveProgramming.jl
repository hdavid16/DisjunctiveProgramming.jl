module DisjunctiveProgramming

using JuMP, IntervalArithmetic, Symbolics, Suppressor

export add_disjunction!, add_proposition!, reformulate_disjunction
export @disjunction, @proposition

include("constraint.jl")
include("logic.jl")
include("bounds.jl")
include("utils.jl")
include("bigm.jl")
include("hull.jl")
include("reformulate.jl")
include("macros.jl")

end # module
