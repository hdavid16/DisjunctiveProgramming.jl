# DisjunctiveProgramming.jl
Generalized Disjunctive Programming (GDP) extension to JuMP, based on the GDP modeling paradigm described in [Perez and Grossmann, 2023](https://arxiv.org/abs/2303.04375).

## Installation

```julia
using Pkg
Pkg.add("DisjunctiveProgramming")
```

## Model

A generalized disjunctive programming (GDP) model is created using `GDPModel()`, where the optimizer can be passed at model creation, along with other keyword arguments supported by JuMP Models. 

```julia
using DisjunctiveProgramming
using HiGHS

model = GDPModel(HiGHS.Optimizer)
```

A `GDPModel` is a `JuMP Model` with a `GDPData` field in the model's `.ext` dictionary, which stores the following:

- `Logical Variables`: Indicator variables used for the various disjuncts involved in the model's disjunctions.
- `Logical Constraints`: Selector (cardinality) or proposition (Boolean) constraints describing the relationships between the logical variables.
- `Disjunct Constraints`: Constraints associated with each disjunct in the model.
- `Disjunctions`: Disjunction constraints.
- `Solution Method`: The reformulation technique or solution method. Currently supported methods include Big-M, Hull, and Indicator Constraints.
- `Reformulation Variables`: List of JuMP variables created when reformulating a GDP model into a MIP model.
- `Reformulation Constraints`: List of constraints created when reformulating a GDP model into a MIP model.
- `Ready to Optimize`: Flag indicating if the model can be optimized.

Additionally, the following mapping dictionaries are stored in `GDPData`:

- `Indicator to Binary`: Maps the Logical variables to their respective reformulated Binary variables.
- `Indicator to Constraints`: Maps the Logical variables to the disjunct constraints associated with them.

A GDP Model's `GDPData` can be accessed via:

```julia
data = gdp_data(model)
```

## Logical Variables

Logical variables are JuMP `AbstractVariable`s with two fields: `fix_value` and `start_value`. These can be optionally specified at variable creation. Logical variables are created with the `@variable` JuMP macro by adding the tag `LogicalVariable` as the last keyword argument. As with the regular `@variable` macro, variables can be named and indexed: 

```julia
@variable(model, Y[1:3], LogicalVariable)
```

## Logical Constraints

Two types of logical constraints are supported:

1. `Selector` or cardinality constraints: A subset of Logical variables is passed and `Exactly`, `AtMost`, or `AtLeast` `n` of these is allowed to be `True`. These constraints are specified with the `func` $\in$ `set` notation in `MathOptInterface` in a `@constraint` JuMP macro. It is not assumed that disjunctions have an `Exactly(1)` constraint enforced on their disjuncts upon creation. This constraint must be explicitly specified.

    ```julia
    @constraint(model, [Y[1], Y[2]] in Exactly(1))
    ```

2. `Proposition` or Boolean constraints: These describe the relationships between Logical variables via Boolean algebra. Supported logical operators include:

    - `∨` or `logical_or` (OR, typed with `\vee + tab`).
    - `∧` or `logical_and` (AND, typed with `\wedge + tab`).
    - `¬` or `logical_not` (NOT, typed with `\neg + tab`).
    - `⟹` of `implies` (Implication, typed with `\Longrightarrow + tab`).
    - `⇔` or `iff` (double implication or equivalence, typed with `\Leftrightarrow + tab`).

    The `@constraint` JuMP macro is used to create these constraints with the `IsTrue` set:

    ```julia
    @constraint(model, (Y[1] ⟹ Y[2]) in IsTrue())
    ```

    _Note_: The parenthesis in the example above around the implication clause are only required when the parent logical operator is `⟹` or `⇔` to avoid parsing errors.

    Logical propositions can be reformulated to IP constraints by automatic reformulation to [Conjunctive Normal Form](https://en.wikipedia.org/wiki/Conjunctive_normal_form).

## Disjunctions

Disjunctions are built by first defining the constraints associated with each disjunct. This is done via the `@constraint` JuMP macro with the extra `DisjunctConstraint` tag specifying the Logical variable associated with the constraint:

```julia
@variable(model, x)
@constraint(model, x ≤ 100, DisjunctConstraint(Y[1]))
@constraint(model, x ≥ 200, DisjunctConstraint(Y[2]))
```

After all disjunct constraints associated with a disjunction have been defined, the disjunction is created with the `@disjunction` macro, where the disjunction is defined as a `Vector` of Logical variables associated with each disjunct:

```julia
@disjunction(model, [Y[1], Y[2]])
```

Disjunctions can be nested by passing an additional `DisjunctConstraint` tag. The Logical variable in the `DisjunctConstraint` tag specifies which disjunct, the nested disjunction belongs to:

```julia
@disjunction(model, Y[1:2], DisjunctConstraint(Y[3]))
```

Empty disjuncts are supported in GDP models. When used, the only constraints enforced on the model when the empty disjunct is selected are the global constraints and any other disjunction constraints defined.

## MIP Reformulations

The following reformulation methods are currently supported:

1. [Big-M](https://optimization.cbe.cornell.edu/index.php?title=Disjunctive_inequalities#Big-M_Reformulation[1][2]): The `BigM` struct is created with the following optional arguments:

    - `value`: Big-M value to use. Default: `1e9`. Big-M values are currently global to the model. Constraint specific Big-M values can be supported in future releases.
    - `tighten`: Boolean indicating if tightening the Big-M value should be attempted (currently supported only for linear disjunct constraints when variable bounds have been set or specified in the `variable_bounds` field). Default: `true`.
    - `variable_bounds`: Dictionary specifying the lower and upper bounds for each `VariableRef` (e.g., `Dict(x => (lb, ub))`). Default: populate when calling the reformulation method.

2. [Hull](https://optimization.cbe.cornell.edu/index.php?title=Disjunctive_inequalities#Convex-Hull_Reformulation[1][2]): The `Hull` struct is created with the following optional arguments:

    - `value`: `ϵ` value to use when reformulating quadratic or nonlinear constraints via the perspective function proposed by [Furman, et al. [2020]](https://link.springer.com/article/10.1007/s10589-020-00176-0). Default: `1e-6`. `ϵ` values are currently global to the model. Constraint specific tolerances can be supported in future releases.
    - `variable_bounds`: Dictionary specifying the lower and upper bounds for each `VariableRef` (e.g., `Dict(x => (lb, ub))`). Default: populate when calling the reformulation method.

3. [Indicator](https://jump.dev/JuMP.jl/stable/manual/constraints/#Indicator-constraints): This method reformulates each disjunct constraint into an indicator constraint with the Boolean reformulation counterpart of the Logical variable used to define the disjunct constraint.

## Example

The example below is from the [Cornell University Computational Optimization Open Textbook](https://optimization.cbe.cornell.edu/index.php?title=Disjunctive_inequalities#Big-M_Reformulation[1][2]).

```julia
using JuMP
using DisjunctiveProgramming

m = GDPModel()
@variable(m, 0 ≤ x[1:2] ≤ 20)
@variable(m, Y[1:2], LogicalVariable)
@constraint(m, [i = 1:2], [2,5][i] ≤ x[i] ≤ [6,9][i], DisjunctConstraint(Y[1]))
@constraint(m, [i = 1:2], [8,10][i] ≤ x[i] ≤ [11,15][i], DisjunctConstraint(Y[2]))
@disjunction(m, Y)
@constraint(m, Y in Exactly(1)) #logical constraint

## Big-M
reformulate_model(m, BigM(100, false)) #specify M value and disable M-tightening
print(m)
# Feasibility
# Subject to
#  Y[1] + Y[2] = 1
#  x[1] - 100 Y[1] ≥ -98
#  x[2] - 100 Y[1] ≥ -95
#  x[1] - 100 Y[2] ≥ -92
#  x[2] - 100 Y[2] ≥ -90
#  x[1] + 100 Y[1] ≤ 106
#  x[2] + 100 Y[1] ≤ 109
#  x[1] + 100 Y[2] ≤ 111
#  x[2] + 100 Y[2] ≤ 115
#  x[1] ≥ 0
#  x[2] ≥ 0
#  x[1] ≤ 20
#  x[2] ≤ 20
#  Y[1] binary
#  Y[2] binary

## Hull
reformulate_model(m, Hull())
print(m)
# Feasibility
# Subject to
#  -x[2] + x[2]_Y[1] + x[2]_Y[2] = 0
#  -x[1] + x[1]_Y[1] + x[1]_Y[2] = 0
#  Y[1] + Y[2] = 1
#  -2 Y[1] + x[1]_Y[1] ≥ 0
#  -5 Y[1] + x[2]_Y[1] ≥ 0
#  -8 Y[2] + x[1]_Y[2] ≥ 0
#  -10 Y[2] + x[2]_Y[2] ≥ 0
#  x[2]_Y[1]_lower_bound : -x[2]_Y[1] ≤ 0
#  x[2]_Y[1]_upper_bound : -20 Y[1] + x[2]_Y[1] ≤ 0
#  x[1]_Y[1]_lower_bound : -x[1]_Y[1] ≤ 0
#  x[1]_Y[1]_upper_bound : -20 Y[1] + x[1]_Y[1] ≤ 0
#  x[2]_Y[2]_lower_bound : -x[2]_Y[2] ≤ 0
#  x[2]_Y[2]_upper_bound : -20 Y[2] + x[2]_Y[2] ≤ 0
#  x[1]_Y[2]_lower_bound : -x[1]_Y[2] ≤ 0
#  x[1]_Y[2]_upper_bound : -20 Y[2] + x[1]_Y[2] ≤ 0
#  -6 Y[1] + x[1]_Y[1] ≤ 0
#  -9 Y[1] + x[2]_Y[1] ≤ 0
#  -11 Y[2] + x[1]_Y[2] ≤ 0
#  -15 Y[2] + x[2]_Y[2] ≤ 0
#  x[1] ≥ 0
#  x[2] ≥ 0
#  x[2]_Y[1] ≥ 0
#  x[1]_Y[1] ≥ 0
#  x[2]_Y[2] ≥ 0
#  x[1]_Y[2] ≥ 0
#  x[1] ≤ 20
#  x[2] ≤ 20
#  x[2]_Y[1] ≤ 20
#  x[1]_Y[1] ≤ 20
#  x[2]_Y[2] ≤ 20
#  x[1]_Y[2] ≤ 20
#  Y[1] binary
#  Y[2] binary

## Indicator
reformulate_model(m, Indicator())
print(m)
# Feasibility
# Subject to
#  Y[1] + Y[2] = 1
#  x[1] ≥ 0
#  x[2] ≥ 0
#  x[1] ≤ 20
#  x[2] ≤ 20
#  Y[1] binary
#  Y[2] binary
#  Y[1] => {x[1] ∈ [2, 6]}
#  Y[1] => {x[2] ∈ [5, 9]}
#  Y[2] => {x[1] ∈ [8, 11]}
#  Y[2] => {x[2] ∈ [10, 15]}
```
