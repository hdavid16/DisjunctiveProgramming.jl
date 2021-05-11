push!(LOAD_PATH,"../src/")
using DisjunctiveProgramming
using Documenter
makedocs(
         sitename = "DisjunctiveProgramming.jl",
         modules  = [DisjunctiveProgramming],
         pages=[
                "Home" => "index.md"
               ])
deploydocs(;
    repo="github.com/hdavid16/DisjunctiveProgramming.jl",
)
