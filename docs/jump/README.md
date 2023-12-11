![Logo](https://raw.githubusercontent.com/hdavid16/DisjunctiveProgramming.jl/master/logo.png)

[`DisjunctiveProgramming.jl`](https://github.com/hdavid16/DisjunctiveProgramming.jl) is a 
`JuMP` extension for expressing and solving Generalized Disjunctive Programs. 
[Generalized Disjunctive Programming](chrome-extension://efaidnbmnnnibpcajpcglclefindmkaj/http://egon.cheme.cmu.edu/Papers/IMAGrossmannRuiz.pdf) 
(GDP) is a modeling paradigm for easily modeling logical conditions which can be reformulated
into a variety of mixed-integer programs. 

| **Current Version**                     | **Documentation**                                                               | **Build Status**                                                                                | **Citation** |
|:---------------------------------------:|:-------------------------------------------------------------------------------:|:-----------------------------------------------------------------------------------------------:|:--------------------------------------:|
| [![](https://docs.juliahub.com/DisjunctiveProgramming/version.svg)](https://juliahub.com/ui/Packages/General/DisjunctiveProgramming) | [![](https://img.shields.io/badge/docs-stable-blue.svg)](https://hdavid16.github.io/DisjunctiveProgramming.jl/stable/) | [![Build Status](https://github.com/infiniteopt/InfiniteOpt.jl/workflows/CI/badge.svg?branch=master)](https://github.com/hdavid16/DisjunctiveProgramming.jl/actions?query=workflow%3ACI) [![codecov.io](https://codecov.io/gh/hdavid16/DisjunctiveProgramming.jl/graph/badge.svg?token=3FRPGMWF0J)](https://codecov.io/gh/hdavid16/DisjunctiveProgramming.jl) | [![arXiv](https://img.shields.io/badge/arXiv-2304.10492-b31b1b.svg)](https://arxiv.org/abs/2304.10492) |

`DisjunctiveProgramming` builds upon `JuMP` to add support GDP modeling objects which include:
- Logical variables (``Y \in \{\text{False}, \text{True}\}``)
- Disjunctions
- Logical constraints (also known as propositions)
- Cardinality constraints

It also supports automatic conversion of the GDP model into a regular mixed-integer `JuMP` model 
via a variety of reformulations which include:
- Big-M
- Hull
- Indicator constraints
Moreover, `DisjunctiveProgramming` provides an extension API to easily add new reformulation methods.

## License
`InfiniteOpt` is licensed under the [MIT "Expat" license](https://github.com/hdavid16/DisjunctiveProgramming.jl/blob/master/LICENSE).

## Installation
`DisjunctiveProgramming.jl` is a registered [Julia](https://julialang.org/) package and 
can be installed by entering the following in the REPL.

```julia
julia> import Pkg; Pkg.add("DisjunctiveProgramming")
```

## Documentation
Please visit our [documentation pages](https://hdavid16.github.io/DisjunctiveProgramming.jl/stable/) 
to learn more.

## Citing
[![arXiv](https://img.shields.io/badge/arXiv-2304.10492-b31b1b.svg)](https://arxiv.org/abs/2304.10492)

If you use DisjunctiveProgramming.jl in your research, we would greatly appreciate your 
citing it.
```latex
@article{perez2023disjunctiveprogramming,
  title={DisjunctiveProgramming. jl: Generalized Disjunctive Programming Models and Algorithms for JuMP},
  author={Perez, Hector D and Joshi, Shivank and Grossmann, Ignacio E},
  journal={arXiv preprint arXiv:2304.10492},
  year={2023}
}
```
