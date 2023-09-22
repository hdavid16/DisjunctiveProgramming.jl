using DisjunctiveProgramming
using JuMP
using Test

const DP = DisjunctiveProgramming

include("aqua.jl")
include("logical_variables.jl")
include("model.jl")
include("variable_interrogation.jl")