# DisjunctiveProgramming.jl
Generalized Disjunctive Programming extension to JuMP

## Installation

```julia
using Pkg
Pkg.add("DisjunctiveProgramming")
```

## Disjunctions

Disjunctions can be applied to standard JuMP models with constraints of that are either `GreaterThan`, `LessThan`, or `EqualTo`. Reformulations on constraints that are `Interval` are not supported. The disjunctions can be reformulated via the Big-M method or the Convex Hull as described [here](https://optimization.mccormick.northwestern.edu/index.php/Disjunctive_inequalities). The user may provide an `M` object that represents the BigM value(s). The `M` object can be a `Number` that is applied to all constraints in the disjuncts, or a `Vector`/`Tuple` of values that are used for each of the disjuncts.

For the Convex Hull Reformulation, the perspective function proposed in [Furman, et al. [2020]](https://link.springer.com/article/10.1007/s10589-020-00176-0) is used.

NOTE: `:Original_VarRefs` and `:Original_VarNames` are forbidden model object names when using DisjunctiveProgramming.jl.

## Caveats

Due to limitations in [Symbolics.jl](https://symbolics.juliasymbolics.org/dev/manual/variables/), does not support JuMP models that have variable containers that are `DenseAxisArrays` or `SparseAxisArrays` for use in nonlinear constraints.

## Example

The example below is from the [Northwestern University Process Optimization Open Textbook](https://optimization.mccormick.northwestern.edu/index.php/Disjunctive_inequalities).

To perform the Big-M reformulation, `:BMR` is passed to the `reformulation` keyword argument. If nothing is passed to the keyword argument `M`, tight Big-M values will be inferred from the variable bounds using IntervalArithmetic.jl. If `x` is not bounded, Big-M values must be provided for either the whole system (e.g., `M = 10`) or for each of the constraint arrays in the example (e.g., `M = ((10,10),(10,10))`).

To perform the Convex-Hull reformulation, `reformulation = :CHR`. Variables must have bounds for the reformulation to work. 

```julia
using JuMP
using DisjunctiveProgramming

m = Model()
@variable(m, 0<=x[1:2]<=10)

@constraint(m, con1[i=1:2], x[i] <= [3,4][i])
@constraint(m, con2[i=1:2], zeros(2)[i] <= x[i])
@constraint(m, con3[i=1:2], [5,4][i] <= x[i])
@constraint(m, con4[i=1:2], x[i] <= [9,6][i])

@disjunction(m,(con1,con2),(con3,con4), reformulation=:BMR, name = :y)

print(m)

# Feasibility
# Subject to
#  y[1] + y[2] == 1.0
#  con1[1] : x[1] + 7 y[1] <= 10.0
#  con1[2] : x[2] + 6 y[1] <= 10.0
#  con2[1] : -x[1] <= 0.0
#  con2[2] : -x[2] <= 0.0
#  con3[1] : -x[1] + 5 y[2] <= 0.0
#  con3[2] : -x[2] + 4 y[2] <= 0.0
#  con4[1] : x[1] + y[2] <= 10.0
#  con4[2] : x[2] + 4 y[2] <= 10.0
#  x[1] >= 0.0
#  x[2] >= 0.0
#  x[1] <= 10.0
#  x[2] <= 10.0
#  y[1] binary
#  y[2] binary
```
