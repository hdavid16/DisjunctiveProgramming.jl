# https://optimization.mccormick.northwestern.edu/index.php/Disjunctive_inequalities
using JuMP
using DisjunctiveProgramming

m = GDPModel()
@variable(m, -5 ≤ x[1:2] ≤ 10)
@variable(m, Y[1:2], LogicalVariable)
@constraint(m, [i = 1:2], 0 ≤ x[i] ≤ [3,4][i], DisjunctConstraint(Y[1]))
@constraint(m, [i = 1:2], [5,4][i] ≤ x[i] ≤ [9,6][i], DisjunctConstraint(Y[2]))
@disjunction(m, Y)
DisjunctiveProgramming._reformulate_logical_variables(m)
print(m)
# Feasibility
# Subject to
#  x[1] >= -5.0
#  x[2] >= -5.0
#  x[1] <= 10.0
#  x[2] <= 10.0

##
m_bigm = copy(m)
DisjunctiveProgramming._reformulate_disjunctions(m_bigm, BigM())
print(m_bigm)
# Feasibility
# Subject to
#  x[1] - 5 Y[1] >= -5.0
#  x[2] - 5 Y[1] >= -5.0
#  x[1] - 10 Y[2] >= -5.0
#  x[2] - 9 Y[2] >= -5.0
#  x[1] + 7 Y[1] <= 10.0
#  x[2] + 6 Y[1] <= 10.0
#  x[1] + Y[2] <= 10.0
#  x[2] + 4 Y[2] <= 10.0
#  x[1] >= -5.0
#  x[2] >= -5.0
#  x[1] <= 10.0
#  x[2] <= 10.0
#  Y[1] binary
#  Y[2] binary

##
m_hull = copy(m)
DisjunctiveProgramming._reformulate_disjunctions(m_hull, Hull())
print(m_hull)
# Feasibility
# Subject to
#  x[1] - x[1]_Y[1] - x[1]_Y[2] == 0.0
#  x[2] - x[2]_Y[1] - x[2]_Y[2] == 0.0
#  x[1]_Y[1] >= 0.0
#  x[2]_Y[1] >= 0.0
#  -5 Y[2] + x[1]_Y[2] >= 0.0
#  -4 Y[2] + x[2]_Y[2] >= 0.0
#  -5 Y[1] - x[1]_Y[1] <= 0.0
#  -10 Y[1] + x[1]_Y[1] <= 0.0
#  -5 Y[2] - x[1]_Y[2] <= 0.0
#  -10 Y[2] + x[1]_Y[2] <= 0.0
#  -5 Y[1] - x[2]_Y[1] <= 0.0
#  -10 Y[1] + x[2]_Y[1] <= 0.0
#  -5 Y[2] - x[2]_Y[2] <= 0.0
#  -10 Y[2] + x[2]_Y[2] <= 0.0
#  -3 Y[1] + x[1]_Y[1] <= 0.0
#  -4 Y[1] + x[2]_Y[1] <= 0.0
#  -9 Y[2] + x[1]_Y[2] <= 0.0
#  -6 Y[2] + x[2]_Y[2] <= 0.0
#  x[1] >= -5.0
#  x[2] >= -5.0
#  x[1]_Y[1] >= -5.0
#  x[1]_Y[2] >= -5.0
#  x[2]_Y[1] >= -5.0
#  x[2]_Y[2] >= -5.0
#  x[1] <= 10.0
#  x[2] <= 10.0
#  x[1]_Y[1] <= 10.0
#  x[1]_Y[2] <= 10.0
#  x[2]_Y[1] <= 10.0
#  x[2]_Y[2] <= 10.0
#  Y[1] binary
#  Y[2] binary