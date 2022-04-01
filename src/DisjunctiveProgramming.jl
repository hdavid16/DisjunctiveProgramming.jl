module DisjunctiveProgramming

using JuMP, IntervalArithmetic, Symbolics

export add_disjunction
export @disjunction, @proposition

include("logic.jl")
include("utils.jl")
include("big_M.jl")
include("convex_hull.jl")
include("reformulate.jl")
include("macro.jl")

end # module
