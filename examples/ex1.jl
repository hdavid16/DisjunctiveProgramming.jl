using JuMP
using DisjunctiveProgramming
using HiGHS

## Example 1a: Linear GDP 

# Disjunction Method 1: Assign Logical Variables Explicitly
m = GDPModel(HiGHS.Optimizer)
@variable(m, -5 ≤ x ≤ 10)
@variable(m, Y[1:2], LogicalVariable)
@constraint(m, 0 ≤ x ≤ 3, DisjunctConstraint(Y[1]))
@constraint(m, 5 ≤ x, DisjunctConstraint(Y[2]))
@constraint(m, x ≤ 9, DisjunctConstraint(Y[2]))
@disjunction(m, [Y[1], Y[2]])
@constraint(m, Y in Exactly(1)) 
@objective(m, Max, x)

# Reformulate logical variables and logical constraints
print(m)
# Max x
# Subject to
#  x ≥ -5
#  x ≤ 10

## BigM reformulation
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
#  x aggregation : -x + x_Y[1] + x_Y[2] = 0
#  Y[1] + Y[2] = 1
#  x_Y[1] ≥ 0
#  x_Y[1] lower bounding : -5 Y[1] - x_Y[1] ≤ 0
#  x_Y[1] upper bounding : -10 Y[1] + x_Y[1] ≤ 0
#  -3 Y[1] + x_Y[1] ≤ 0
#  x_Y[2] lower bounding : -5 Y[2] - x_Y[2] ≤ 0
#  x_Y[2] upper bounding : -10 Y[2] + x_Y[2] ≤ 0
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

## Example 1b: Same as Example 1a, but using alternate syntax for disjunction creation and reformulation to MIP via indicator constraints.

# Disjunction Method 2: Create Logical Variables from Disjunctions
m = GDPModel() # optimizer not specified since HiGHS doesn't support indicator constraints
@variable(m, -5 ≤ x ≤ 10)
@constraint(m, disjunct_1_con, 0 ≤ x ≤ 3, DisjunctConstraint)
@constraint(m, disjunct_2_con_a, 5 ≤ x, DisjunctConstraint)
@constraint(m, disjunct_2_con_b, x ≤ 9, DisjunctConstraint)
@disjunction(m, disjunction, [[disjunct_1_con], [disjunct_2_con_a, disjunct_2_con_b]])
Y = disjunction_indicators(disjunction)
@constraint(m, Y in Exactly(1)) 
@objective(m, Max, x)

## Indicator Constraints reformulation
reformulate_model(m, Indicator())
print(m)
# Max x
# Subject to
#  disjunction_1 + disjunction_2 = 1
#  disjunction_2 => {-x ≤ -5}
#  disjunction_2 => {x ≤ 9}
#  x ≥ -5
#  x ≤ 10
#  disjunction_1 binary
#  disjunction_2 binary
#  disjunction_1 => {x ∈ [0, 3]}