# DisjunctiveProgramming.jl
Generalized Disjunctive Programming extension to JuMP

## Installation

```julia
using Pkg
Pkg.add("DisjunctiveProgramming")
```

## Disjunctions

After defining a JuMP model, disjunctions can be added to the model by specifying which of the original JuMP model constraints should be assigned to each disjunction. The constraints that are assigned to the disjunctions will no longer be general model constraints, but will belong to the disjunction that they are assigned to. These constraints must be either `GreaterThan`, `LessThan`, or `EqualTo` constraints. Constraints that are of `Interval` type are currently not supported. It is assumed that the disjuncts belonging to a disjunction are proper disjunctions (mutually exclussive) and only one of them will be selected.

When a disjunction is defined using the `@disjunction` macro, the disjunctions are reformulated to algebraic constraints via the Big-M method (`reformulation = :BMR`) or the Convex Hull (`reformulation = :CHR`) as described [here](https://optimization.mccormick.northwestern.edu/index.php/Disjunctive_inequalities). For the Convex Hull Reformulation on a nonlinear model, the perspective function proposed in [Furman, et al. [2020]](https://link.springer.com/article/10.1007/s10589-020-00176-0) is used.

When calling the `@disjunction` macro, a `name::Symbol` keyword argument can be specified to define the name of the indicator variable to be used for that disjunction. Otherwise, (`name = missing`) a symbolic name will be generated with the prefix `disj`.

For Big-M reformulations, the user may provide an `M` object that represents the BigM value(s). The `M` object can be a `Number` that is applied to all constraints in the disjuncts, or a `Vector`/`Tuple` of values that are used for each of the disjuncts. For Convex-Hull reformulations, the user may provide an `ϵ` value for the perspective function (default is `ϵ = 1e-6`). The `ϵ` object can be a `Number` that is applied to all perspective functions, or a `Vector`/`Tuple` of values that are used for each of the disjuncts.

For empty disjuncts, use `nothing` for their positional argument (e.g., `@disjunction(m, con1, nothing, reformulation = :BMR)`).

NOTE: `:gdp_variable_refs` and `:gdp_variable_names` are forbidden JuMP model object names when using *DisjunctiveProgramming.jl*. They are used to store the variable names and variable references in the original model.

## Logical Propositions

Boolean logic can be included in the model by using the `@proposition` macro. This macro will take an expression that uses only binary variables from the model (typically a subset of the indicator variables used in the disjunctions) and one or more of the following Boolean operators: `∨` (or, typed with `\vee + tab`), `∧` (and, typed with `\wedge + tab`), `¬` (negation, typed with `\neg + tab`), `⇒` (implication, typed with `\Rightarrow + tab`), `⇔` (double implication or equivalence, typed with `\Leftrightarrow + tab`).

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
@proposition(m, y[1] ∨ y[2])

print(m)

Feasibility
Subject to
 y[1] + y[2] == 1.0 #XOR constraint
 y[1] + y[2] >= 1.0 #from the logical proposition
 con1[1] : x[1] + 7 y[1] <= 10.0
 con1[2] : x[2] + 6 y[1] <= 10.0
 con2[1] : -x[1] <= 0.0
 con2[2] : -x[2] <= 0.0
 con3[1] : -x[1] + 5 y[2] <= 0.0
 con3[2] : -x[2] + 4 y[2] <= 0.0
 con4[1] : x[1] + y[2] <= 10.0
 con4[2] : x[2] + 4 y[2] <= 10.0
 x[1] >= 0.0
 x[2] >= 0.0
 x[1] <= 10.0
 x[2] <= 10.0
 y[1] binary
 y[2] binary
```
