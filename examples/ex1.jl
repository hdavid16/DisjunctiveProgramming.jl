using JuMP
using DisjunctiveProgramming

#TODO: Add proposition for exactly 1 disjunct selected

## Example 1: 

# Disjunction Method 1: Assign Logical Variables Explicitly
m = GDPModel()
@variable(m, -5 ≤ x ≤ 10)
@variable(m, Y[1:2], LogicalVariable)
@constraint(m, disjunct_1_con, 0 ≤ x ≤ 3, DisjunctConstraint(Y[1]))
@constraint(m, disjunct_2_con_a, 5 ≤ x, DisjunctConstraint(Y[2]))
@constraint(m, disjunct_2_con_b, x ≤ 9, DisjunctConstraint(Y[2]))
@disjunction(m, disjunction, [Y[1], Y[2]])

# Disjunction Method 2: Same as Method 1, but using Indicator Constraint notation --> not currently supported
# m = GDPModel()
# @variable(m, -5 ≤ x ≤ 10)
# @variable(m, Y[1:2], LogicalVariable)
# @constraint(m, disjunct_1_con, Y[1] => {0 ≤ x ≤ 3})
# @constraint(m, disjunct_2_con_a, Y[2] => {5 ≤ x})
# @constraint(m, disjunct_2_con_b, Y[2] => {x ≤ 9})
# disjunction = add_disjunction(m, Y, "Disjunction")

# Disjunction Method 3: Create Logical Variables from Disjunctions
m = GDPModel()
@variable(m, -5 ≤ x ≤ 10)
@constraint(m, disjunct_1_con, 0 ≤ x ≤ 3, DisjunctConstraint)
@constraint(m, disjunct_2_con_a, 5 ≤ x, DisjunctConstraint)
@constraint(m, disjunct_2_con_b, x ≤ 9, DisjunctConstraint)
@disjunction(m, d2, [[disjunct_1_con], [disjunct_2_con_a, disjunct_2_con_b]])
Y = disjunction_indicators(d2)

# Logical Constraint Method 1: Use func in set notation
@constraint(m, exclussinve, Y in Exactly(1))

# Logical Constraint Method 2: Use NonlinearExpr that gets parsed to func in set notation --> not currently supported
# @constraint(m, exclussive, exactly(1, Y))

# Reformulate logical variables and logical constraints
DisjunctiveProgramming._reformulate_logical_variables(m)
DisjunctiveProgramming._reformulate_logical_constraints(m)
print(m)
# Feasibility
# Subject to
#  x ≥ -5
#  x ≤ 10
#  Y[1] binary
#  Y[2] binary
#  (Y[1] + Y[2]) = 1

## BigM reformulation
m_bigm = copy(m)
DisjunctiveProgramming._reformulate_disjunctions(m_bigm, BigM())
print(m_bigm)
# Feasibility
# Subject to
#  x - 5 Y[1] ≥ -5
#  x - 10 Y[2] ≥ -5
#  x + 7 Y[1] ≤ 10
#  x + Y[2] ≤ 10
#  x ≥ -5
#  x ≤ 10
#  Y[1] binary
#  Y[2] binary
#  (Y[1] + Y[2]) = 1

## Hull reformulation
m_hull = copy(m)
DisjunctiveProgramming._reformulate_disjunctions(m_hull, Hull())
print(m_hull)
# Feasibility
# Subject to
#  x - x_Y[1] - x_Y[2] = 0
#  x_Y[1] ≥ 0
#  -5 Y[2] + x_Y[2] ≥ 0
#  -5 Y[1] - x_Y[1] ≤ 0
#  -10 Y[1] + x_Y[1] ≤ 0
#  -3 Y[1] + x_Y[1] ≤ 0
#  -5 Y[2] - x_Y[2] ≤ 0
#  -10 Y[2] + x_Y[2] ≤ 0
#  -9 Y[2] + x_Y[2] ≤ 0
#  x ≥ -5
#  x_Y[1] ≥ -5
#  x_Y[2] ≥ -5
#  x ≤ 10
#  x_Y[1] ≤ 10
#  x_Y[2] ≤ 10
#  Y[1] binary
#  Y[2] binary
#  (Y[1] + Y[2]) = 1

## Indicator Constraints reformulation
m_ind = copy(m)
DisjunctiveProgramming._reformulate_disjunctions(m_ind, Indicator())
print(m_ind)
# Feasibility
# Subject to
#  Y[2] => {x ≤ 9}
#  x ≥ -5
#  x ≤ 10
#  Y[1] binary
#  Y[2] binary
#  (Y[1] + Y[2]) = 1
#  Y[1] => {x ∈ [0, 3]}
#  Y[2] => {x ≥ 5}