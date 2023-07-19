using JuMP
using DisjunctiveProgramming

m = GDPModel()
@variables(m, begin
    -5 ≤ x ≤ 10 
end)
@variable(m, Y[1:2], LogicalVariable)
disjunct_1 = Disjunct(
    tuple(
        build_constraint(error, exp(x), MOI.LessThan(2)),
        build_constraint(error, 1*x, MOI.GreaterThan(-3))
    ),
    Y[1]
)
disjunct_2 = Disjunct(
    tuple(
        build_constraint(error, exp(x), MOI.GreaterThan(3)),
        build_constraint(error, 1*x, MOI.GreaterThan(5))
    ),
    Y[2]
)
disjunction = add_constraint(m, 
    build_constraint(error, [disjunct_1, disjunct_2]),
    "Disjunction"
)
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
#  (x ^ 3) ∈ [-1, 1]
#  (x ^ 3) ∈ [-1, 1]
#  ((((0.999999 Y[1] + 1.0e-6) * exp((x_Y[1] / (0.999999 Y[1] + 1.0e-6)))) - (-1.0e-6 Y[1] + 1.0e-6)) - 2 Y[1]) ≤ 0
#  ((((0.999999 Y[2] + 1.0e-6) * exp((x_Y[2] / (0.999999 Y[2] + 1.0e-6)))) - (-1.0e-6 Y[2] + 1.0e-6)) - 3 Y[2]) ≥ 0