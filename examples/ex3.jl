using JuMP
using DisjunctiveProgramming

m = GDPModel()
@variable(m, -5 ≤ x ≤ 10)
@variable(m, Y[1:2], LogicalVariable)
@constraint(m, disj1_con_a, Y[1] => {exp(x) <= 2})
@constraint(m, disj1_con_b, Y[1] => {x >= -3})
@constraint(m, disj2_con_a, Y[2] => {exp(x) >= 3})
@constraint(m, disj2_con_b, Y[2] => {x >= 5})
disjunction = add_disjunction(m, Y, "Disjunction")
DisjunctiveProgramming._reformulate_logical_variables(m)
print(m)
# Feasibility
# Subject to
#  x ≥ -5
#  x ≤ 10

##
m_bigm = copy(m)
DisjunctiveProgramming._reformulate_disjunctive_constraints(m_bigm, BigM())
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
DisjunctiveProgramming._reformulate_disjunctive_constraints(m_hull, Hull())
print(m_hull)

# Feasibility
# Subject to
#  x - x_Y[1] - x_Y[2] = 0
#  3 Y[1] + x_Y[1] ≥ 0
#  -5 Y[2] + x_Y[2] ≥ 0
#  con : 2 x ≤ 9
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