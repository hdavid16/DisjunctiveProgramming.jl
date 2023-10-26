using DisjunctiveProgramming
using HiGHS

## Example 1: Linear GDP 

# Disjunction Method 1: Assign Logical Variables Explicitly
m = GDPModel()
@variable(m, -5 ≤ x ≤ 10)
@variable(m, Y[1:2], Logical)
@constraint(m, 0 ≤ x ≤ 3, Disjunct(Y[1]))
@constraint(m, 5 ≤ x, Disjunct(Y[2]))
@constraint(m, x ≤ 9, Disjunct(Y[2]))
@disjunction(m, [Y[1], Y[2]])  # can also just call `disjunction` instead
@objective(m, Max, x)

# Reformulate logical variables and logical constraints
print(m)
# Max x
# Subject to
#  x ≥ -5
#  x ≤ 10

## Indicator Constraints reformulation (NOTE: HiGHS doesn't support indicator constraints)
reformulate_model(m, Indicator())
print(m)
# Max x
# Subject to
#  Y[1] + Y[2] = 1
#  Y[2] => {-x ≤ -5}
#  Y[2] => {x ≤ 9}
#  x ≥ -5
#  x ≤ 10
#  Y[1] binary
#  Y[2] binary
#  Y[1] => {x ∈ [0, 3]}

## BigM reformulation
set_optimizer(m, HiGHS.Optimizer)
optimize!(m, method = BigM())
print(m)
# Max x
# Subject to
#  Y[1] + Y[2] = 1
#  x - 5 Y[1] ≥ -5
#  x + 7 Y[1] ≤ 10
#  -x + 10 Y[2] ≤ 5
#  x + Y[2] ≤ 10
#  x ≥ -5
#  x ≤ 10
#  Y[1] binary
#  Y[2] binary

## Hull reformulation
optimize!(m, method = Hull())
print(m)
# Max x
# Subject to
#  -x + x_Y[1] + x_Y[2] = 0
#  Y[1] + Y[2] = 1
#  x_Y[1] ≥ 0
#  x_Y[1]_lower_bound : -5 Y[1] - x_Y[1] ≤ 0
#  x_Y[1]_upper_bound : -10 Y[1] + x_Y[1] ≤ 0
#  x_Y[2]_lower_bound : -5 Y[2] - x_Y[2] ≤ 0
#  x_Y[2]_upper_bound : -10 Y[2] + x_Y[2] ≤ 0
#  -3 Y[1] + x_Y[1] ≤ 0
#  5 Y[2] - x_Y[2] ≤ 0
#  -9 Y[2] + x_Y[2] ≤ 0
#  x ≥ -5
#  x_Y[1] ≥ -5
#  x_Y[2] ≥ -5
#  x ≤ 10
#  x_Y[1] ≤ 10
#  x_Y[2] ≤ 10
#  Y[1] binary
#  Y[2] binary