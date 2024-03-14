import DisjunctiveProgramming as DP
using DisjunctiveProgramming
using Test

import Pkg
Pkg.add(url = "https://github.com/infiniteopt/InfiniteOpt.jl", rev = "master")

include("utilities.jl")

# RUN ALL THE TESTS
# include("aqua.jl") # temporary ignore until compat is finalized
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
include("extensions/InfiniteDisjunctiveProgramming.jl")
