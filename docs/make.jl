using DisjunctiveProgramming
using Documenter
makedocs(
    sitename = "DisjunctiveProgramming.jl",
    modules  = [DisjunctiveProgramming],
    pages=[
        "Home" => "index.md"
    ],
    checkdocs = :none
)
deploydocs(;
    repo="github.com/hdavid16/DisjunctiveProgramming.jl",
)
