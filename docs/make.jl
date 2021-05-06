push!(LOAD_PATH,"../src/")
using JuGDP
using Documenter
makedocs(
         sitename = "JuGDP.jl",
         modules  = [JuGDP],
         pages=[
                "Home" => "index.md"
               ])
deploydocs(;
    repo="github.com/hdavid16/JuGDP.jl",
)
