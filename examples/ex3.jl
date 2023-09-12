using JuMP
using DisjunctiveProgramming

m = GDPModel()
@variable(m, -5 ≤ x ≤ 10)
@variable(m, Y[1:2], LogicalVariable)
@constraint(m, exp(x) <= 2, DisjunctConstraint(Y[1]))
@constraint(m, x >= -3, DisjunctConstraint(Y[1]))
@constraint(m, exp(x) >= 3, DisjunctConstraint(Y[2]))
@constraint(m, x >= 5, DisjunctConstraint(Y[2]))
@disjunction(m, Y)
@constraint(m, Y in Exactly(1)) #logical constraint
DisjunctiveProgramming._reformulate_logical_variables(m)
DisjunctiveProgramming._reformulate_logical_constraints(m)
print(m)
# Feasibility
# Subject to
#  Y[1] + Y[2] = 1
#  x ≥ -5
#  x ≤ 10
#  Y[1] binary
#  Y[2] binary

##
m_bigm = copy(m)
DisjunctiveProgramming._reformulate_disjunctions(m_bigm, BigM())
print(m_bigm)
# Feasibility
# Subject to
#  (exp(x) - 3.0) + (-1000000000 Y[2] + 1000000000) ≥ 0
#  (exp(x) - 2.0) - (-1000000000 Y[1] + 1000000000) ≤ 0
#  Y[1] + Y[2] = 1
#  x - 2 Y[1] ≥ -5
#  x - 10 Y[2] ≥ -5
#  x ≥ -5
#  x ≤ 10
#  Y[1] binary
#  Y[2] binary

##
m_hull = copy(m)
DisjunctiveProgramming._reformulate_disjunctions(m_hull, Hull())
print(m_hull)
# Feasibility
# Subject to
#  (((0.999999 Y[2] + 1.0e-6) * (exp(x_Y[2] / (0.999999 Y[2] + 1.0e-6)) - 3.0)) - (2.0e-6 Y[2] - 2.0e-6)) - (0) ≥ 0
#  (((0.999999 Y[1] + 1.0e-6) * (exp(x_Y[1] / (0.999999 Y[1] + 1.0e-6)) - 2.0)) - (1.0e-6 Y[1] - 1.0e-6)) - (0) ≤ 0
#  Y[1] + Y[2] = 1
#  x aggregation : -x + x_Y[1] + x_Y[2] = 0
#  3 Y[1] + x_Y[1] ≥ 0
#  -5 Y[2] + x_Y[2] ≥ 0
#  x_Y[1] lower bounding : -5 Y[1] - x_Y[1] ≤ 0
#  x_Y[1] upper bounding : -10 Y[1] + x_Y[1] ≤ 0
#  x_Y[2] lower bounding : -5 Y[2] - x_Y[2] ≤ 0
#  x_Y[2] upper bounding : -10 Y[2] + x_Y[2] ≤ 0
#  x ≥ -5
#  x_Y[1] ≥ -5
#  x_Y[2] ≥ -5
#  x ≤ 10
#  x_Y[1] ≤ 10
#  x_Y[2] ≤ 10
#  Y[1] binary
#  Y[2] binary