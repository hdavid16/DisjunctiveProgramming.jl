# https://optimization.mccormick.northwestern.edu/index.php/Disjunctive_inequalities
using JuMP
using DisjunctiveProgramming
using HiGHS

m = GDPModel(HiGHS.Optimizer)
@variable(m, -5 ≤ x[1:2] ≤ 10)
@variable(m, Y[1:2], LogicalVariable)
@constraint(m, [i = 1:2], 0 ≤ x[i] ≤ [3,4][i], DisjunctConstraint(Y[1]))
@constraint(m, [i = 1:2], [5,4][i] ≤ x[i] ≤ [9,6][i], DisjunctConstraint(Y[2]))
@disjunction(m, Y)
@constraint(m, Y in Exactly(1)) #logical constraint
@objective(m, Max, sum(x))
print(m)
# Max x[1] + x[2]
# Subject to
#  x[1] ≥ -5
#  x[2] ≥ -5
#  x[1] ≤ 10
#  x[2] ≤ 10

##
optimize!(m, method = BigM(100, false)) #specify M value and disable M-tightening
print(m)
# Max x[1] + x[2]
# Subject to
#  Y[1] + Y[2] = 1
#  x[1] - 100 Y[1] ≥ -100
#  x[2] - 100 Y[1] ≥ -100
#  x[1] - 100 Y[2] ≥ -95
#  x[2] - 100 Y[2] ≥ -96
#  x[1] + 100 Y[1] ≤ 103
#  x[2] + 100 Y[1] ≤ 104
#  x[1] + 100 Y[2] ≤ 109
#  x[2] + 100 Y[2] ≤ 106
#  x[1] ≥ -5
#  x[2] ≥ -5
#  x[1] ≤ 10
#  x[2] ≤ 10
#  Y[1] binary
#  Y[2] binary

##
optimize!(m, method = Hull())
print(m)
# Max x[1] + x[2]
# Subject to
#  x[2] aggregation : -x[2] + x[2]_Y[1] + x[2]_Y[2] = 0
#  x[1] aggregation : -x[1] + x[1]_Y[1] + x[1]_Y[2] = 0
#  Y[1] + Y[2] = 1
#  x[1]_Y[1] ≥ 0
#  x[2]_Y[1] ≥ 0
#  -5 Y[2] + x[1]_Y[2] ≥ 0
#  -4 Y[2] + x[2]_Y[2] ≥ 0
#  x[2]_Y[1] lower bounding : -5 Y[1] - x[2]_Y[1] ≤ 0
#  x[2]_Y[1] upper bounding : -10 Y[1] + x[2]_Y[1] ≤ 0
#  x[1]_Y[1] lower bounding : -5 Y[1] - x[1]_Y[1] ≤ 0
#  x[1]_Y[1] upper bounding : -10 Y[1] + x[1]_Y[1] ≤ 0
#  -3 Y[1] + x[1]_Y[1] ≤ 0
#  -4 Y[1] + x[2]_Y[1] ≤ 0
#  x[2]_Y[2] lower bounding : -5 Y[2] - x[2]_Y[2] ≤ 0
#  x[2]_Y[2] upper bounding : -10 Y[2] + x[2]_Y[2] ≤ 0
#  x[1]_Y[2] lower bounding : -5 Y[2] - x[1]_Y[2] ≤ 0
#  x[1]_Y[2] upper bounding : -10 Y[2] + x[1]_Y[2] ≤ 0
#  -9 Y[2] + x[1]_Y[2] ≤ 0
#  -6 Y[2] + x[2]_Y[2] ≤ 0
#  x[1] ≥ -5
#  x[2] ≥ -5
#  x[2]_Y[1] ≥ -5
#  x[1]_Y[1] ≥ -5
#  x[2]_Y[2] ≥ -5
#  x[1]_Y[2] ≥ -5
#  x[1] ≤ 10
#  x[2] ≤ 10
#  x[2]_Y[1] ≤ 10
#  x[1]_Y[1] ≤ 10
#  x[2]_Y[2] ≤ 10
#  x[1]_Y[2] ≤ 10
#  Y[1] binary
#  Y[2] binary