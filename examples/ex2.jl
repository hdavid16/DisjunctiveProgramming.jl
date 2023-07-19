# https://optimization.mccormick.northwestern.edu/index.php/Disjunctive_inequalities
using JuMP
using DisjunctiveProgramming

m = GDPModel()
@variable(m, -5 ≤ x[1:2] ≤ 10)
@variable(m, Y[1:2], LogicalVariable)
disjunct_1 = Disjunct(
    (
        build_constraint(error, 1*x[1], MOI.Interval(0,3)),
        build_constraint(error, 1*x[2], MOI.Interval(0,4))
    ),
    Y[1]
)
disjunct_2 = Disjunct(
    (
        build_constraint(error, 1*x[1], MOI.Interval(5,9)),
        build_constraint(error, 1*x[2]^2 + x[1]*log(x[2]), MOI.Interval(4,6))
    ),
    Y[2]
)
disjunction = add_constraint(m, 
    build_constraint(error, [disjunct_1, disjunct_2]),
    "Disjunction"
)
print(m)
# Feasibility
# Subject to
#  x[1] >= -5.0
#  x[2] >= -5.0
#  x[1] <= 10.0
#  x[2] <= 10.0

##
m_bigm = copy(m)
DisjunctiveProgramming._reformulate(m_bigm, BigM())
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
DisjunctiveProgramming._reformulate(m_hull, Hull())
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