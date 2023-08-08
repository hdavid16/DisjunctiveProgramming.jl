using JuMP
using DisjunctiveProgramming

m = GDPModel()
@variable(m, -5 ≤ x ≤ 10)
@variable(m, Y[1:2], LogicalVariable)
disj1_con_a = @constraint(m, exp(x) <= 2, DisjunctConstraint(Y[1]))
disj1_con_b = @constraint(m, x >= -3, DisjunctConstraint(Y[1]))
disj2_con_a = @constraint(m, exp(x) >= 3, DisjunctConstraint(Y[2]))
disj2_con_b = @constraint(m, x >= 5, DisjunctConstraint(Y[2]))
disjunction = @disjunction(m, Y)
DisjunctiveProgramming._reformulate_logical_variables(m)
print(m)
# Feasibility
# Subject to
#  x ≥ -5
#  x ≤ 10

##
m_bigm = copy(m)
DisjunctiveProgramming._reformulate_disjunctions(m_bigm, BigM())
print(m_bigm)
# Feasibility
# Subject to
#  x - 2 Y[1] ≥ -5
#  x - 10 Y[2] ≥ -5
#  x ≥ -5
#  x ≤ 10
#  Y[1] binary
#  Y[2] binary
#  (exp(x) - -1000000000 Y[1] + 1000000000) ≤ 2
#  (exp(x) + -1000000000 Y[2] + 1000000000) ≥ 3

##
m_hull = copy(m)
DisjunctiveProgramming._reformulate_disjunctions(m_hull, Hull())
print(m_hull)

# Feasibility
# Subject to
#  x - x_Y[1] - x_Y[2] = 0
#  3 Y[1] + x_Y[1] ≥ 0
#  -5 Y[2] + x_Y[2] ≥ 0
#  -5 Y[1] - x_Y[1] ≤ 0
#  -10 Y[1] + x_Y[1] ≤ 0
#  -5 Y[2] - x_Y[2] ≤ 0
#  -10 Y[2] + x_Y[2] ≤ 0
#  x ≥ -5
#  x_Y[1] ≥ -5
#  x_Y[2] ≥ -5
#  x ≤ 10
#  x_Y[1] ≤ 10
#  x_Y[2] ≤ 10
#  y binary
#  Y[1] binary
#  Y[2] binary
#  ((((0.999999 Y[1] + 1.0e-6) * exp((x_Y[1] / (0.999999 Y[1] + 1.0e-6)))) - (-1.0e-6 Y[1] + 1.0e-6)) - 2 Y[1]) ≤ 0
#  ((((0.999999 Y[2] + 1.0e-6) * exp((x_Y[2] / (0.999999 Y[2] + 1.0e-6)))) - 2*(-1.0e-6 Y[2] + 1.0e-6)) - 3 Y[2]) ≥ 0