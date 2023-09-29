using DisjunctiveProgramming
using JuMP
using Test

const DP = DisjunctiveProgramming

struct DummyReformulation <: AbstractReformulationMethod end

# Utilities to test macro error exception
# Taken from https://github.com/jump-dev/JuMP.jl/blob/master/test/utilities.jl
function strip_line_from_error(err::ErrorException)
    return ErrorException(replace(err.msg, r"^At.+\:[0-9]+\: `@" => "In `@"))
end
strip_line_from_error(err::LoadError) = strip_line_from_error(err.error)
strip_line_from_error(err) = err
macro test_macro_throws(errortype, m)
    quote
        @test_throws(
            $(esc(strip_line_from_error(errortype))),
            try
                @eval $m
            catch err
                throw(strip_line_from_error(err))
            end
        )
    end
end

include("aqua.jl")
include("model.jl")
include("variables/query.jl")
include("variables/logical.jl")
include("constraints/selector.jl")
include("constraints/proposition.jl")
include("constraints/indicator.jl")
include("disjunction.jl")
include("solve.jl")