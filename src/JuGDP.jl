module JuGDP

using JuMP

export add_disjunction
export @disjunction

include("disjunction.jl")
include("macros.jl")

end # module
