# https://optimization.cbe.cornell.edu/index.php?title=Disjunctive_inequalities#Big-M_Reformulation[1][2]
using DisjunctiveProgramming
using HiGHS

m = GDPModel(HiGHS.Optimizer)
@variable(m, 0 ≤ x[1:2] ≤ 20)
@variable(m, Y[1:2], LogicalVariable)
@constraint(m, [i = 1:2], [2,5][i] ≤ x[i] ≤ [6,9][i], DisjunctConstraint(Y[1]))
@constraint(m, [i = 1:2], [8,10][i] ≤ x[i] ≤ [11,15][i], DisjunctConstraint(Y[2]))
@disjunction(m, Y)
@constraint(m, Y in Exactly(1)) #logical constraint
@objective(m, Max, sum(x))
print(m)
# Max x[1] + x[2]
# Subject to
#  x[1] ≥ 0
#  x[2] ≥ 0
#  x[1] ≤ 20
#  x[2] ≤ 20

##
optimize!(m, method = BigM(100, false)) #specify M value and disable M-tightening
print(m)
# Max x[1] + x[2]
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

##
optimize!(m, method = Hull())
print(m)
# Max x[1] + x[2]
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