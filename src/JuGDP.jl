module JuGDP

using JuMP, IntervalArithmetic

export add_disjunction
export @disjunction

include("reformulate.jl")
include("disjunction.jl")
include("macro.jl")

end # module
