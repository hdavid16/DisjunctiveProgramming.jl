module DisjunctiveProgramming

using JuMP, Symbolics, Suppressor

export add_disjunction!, add_proposition!
export @disjunction, @proposition
export choose!

include("constraint.jl")
include("logic.jl")
include("utils.jl")
include("bigm.jl")
include("hull.jl")
include("reformulate.jl")
include("macros.jl")

end # module
