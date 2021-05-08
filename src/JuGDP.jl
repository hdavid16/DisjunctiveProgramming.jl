module JuGDP

using JuMP

export add_disjunction
export @disjunction

include("reformulate.jl")

include("disjunction.jl")
include("macros.jl")

end # module
