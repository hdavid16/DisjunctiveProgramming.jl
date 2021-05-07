module JuGDP

using JuMP

export add_disjunction
export @disjunction

include("bmr.jl")
include("disjunction.jl")
include("macros.jl")

end # module
