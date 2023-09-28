using DisjunctiveProgramming
using JuMP
using Test

const DP = DisjunctiveProgramming

include("aqua.jl")
include("variables/query.jl")
include("variables/logical.jl")
include("constraints/logical.jl")
include("model.jl")
include("solve.jl")