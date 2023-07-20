using JuMP
using DisjunctiveProgramming

#TODO: Add proposition for exactly 1 disjunct selected

## Model 1: 
#   1 variable: x
#   1 disjunction:
#       2 disjuncts: 
#           1st disjucnt: MOI.Interval linear constraint (1)
#           2nd disjunct: MOI.GreaterThan & MOI.LessThan linear constraints (2)

m = GDPModel()
@variable(m, -5 ≤ x ≤ 10)
@variable(m, Y[1:2], LogicalVariable)
disjunct_1 = Disjunct(
    tuple(
        build_constraint(error, 1*x, MOI.Interval(0,3))
    ),
    Y[1]
)
disjunct_2 = Disjunct(
    tuple(
        build_constraint(error, 1*x, MOI.GreaterThan(5)),
        build_constraint(error, 1*x, MOI.LessThan(9))
    ),
    Y[2]
)
disjunction = add_constraint(m, 
    build_constraint(error, [disjunct_1, disjunct_2]),
    "Disjunction"
)
logic_1 = LogicalConstraint(
    exactly(1, Y[1], Y[2])
)
selector = add_constraint(m,
    logic_1,
    "Exclussive Selector"
)
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

##
m_bigm = copy(m)
DisjunctiveProgramming._reformulate_disjunctive_constraints(m_bigm, BigM())
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

##
m_hull = copy(m)
DisjunctiveProgramming._reformulate_disjunctive_constraints(m_hull, Hull())
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

##
m_ind = copy(m)
DisjunctiveProgramming._reformulate_disjunctive_constraints(m_ind, Indicator())
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