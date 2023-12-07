using DisjunctiveProgramming
using Test

const DP = DisjunctiveProgramming

include("utilities.jl")

# RUN ALL THE TESTS
include("aqua.jl")
include("model.jl")
include("jump.jl")
include("variables/query.jl")
include("variables/logical.jl")
include("constraints/selector.jl")
include("constraints/proposition.jl")
include("constraints/disjunct.jl")
include("constraints/indicator.jl")
include("constraints/bigm.jl")
include("constraints/hull.jl")
include("constraints/fallback.jl")
include("constraints/disjunction.jl")
include("print.jl")
include("solve.jl")