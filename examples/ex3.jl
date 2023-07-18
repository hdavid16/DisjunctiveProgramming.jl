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
print(m)
# Feasibility
# Subject to
#  x ≥ -5
#  x ≤ 10

##
m_bigm = copy(m)
DisjunctiveProgramming._reformulate(m_bigm, BigM())
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
DisjunctiveProgramming._reformulate(m_hull, Hull())
print(m_hull)
##
@disjunction(
    m,
    begin
        exp(x) ≤ 2
        -3 ≤ x
    end,
    begin
        3 ≤ exp(x)
        5 ≤ x
    end,
    reformulation=:hull,
    name=:z
)
print(m)

# Feasibility
# Subject to
#  XOR(disj_z) : z[1] + z[2] == 1.0             <- XOR constraint
#  x_aggregation : x - x_z1 - x_z2 == 0.0       <- aggregation of disaggregated variables
#  x_z1_lb : -5 z[1] - x_z1 <= 0.0              <- lower-bound constraint on disaggregated variable x_z1 (x in 1st disjunct)
#  x_z1_ub : -10 z[1] + x_z1 <= 0.0             <- upper-bound constraint on disaggregated variable x_z1 (x in 1st disjunct)
#  x_z2_lb : -5 z[2] - x_z2 <= 0.0              <- lower-bound constraint on disaggregated variable x_z2 (x in 2nd disjunct)
#  x_z2_ub : -10 z[2] + x_z2 <= 0.0             <- upper-bound constraint on disaggregated variable x_z2 (x in 2nd disjunct)
#  x >= -5.0                                    <- lower-bound on x
#  x_z1 >= -5.0                                 <- lower-bound on x_z1 (disaggregated x in 1st disjunct)
#  x_z2 >= -5.0                                 <- lower-bound on x_z2 (disaggregated x in 2nd disjunct)
#  x <= 10.0                                    <- upper-bound on x
#  x_z1 <= 10.0                                 <- upper-bound on x_z1 (disaggregated x in 1st disjunct)
#  x_z2 <= 10.0                                 <- upper-bound on x_z2 (disaggregated x in 2nd disjunct)
#  z[1] >= 0.0                                  <- lower bound on binary
#  z[2] >= 0.0                                  <- lower bound on binary
#  z[1] <= 1.0                                  <- upper bound on binary
#  z[2] <= 1.0                                  <- upper bound on binary
#  z[1] binary                                  <- indicator variable (1st disjunct) is binary
#  z[2] binary                                  <- indicator variable (2nd disjunct) is binary
#  Perspective Functions:
#  (-1.0e-6 + -1.9999989999999999 * z[1]) + (1.0e-6 + 0.999999 * z[1]) * exp(x_z1 / (1.0e-6 + 0.999999 * z[1])) <= 0
#  (1.0000000000000002e-6 + 2.999999 * z[2]) + (-1.0e-6 + -0.999999 * z[2]) * exp(x_z2 / (1.0e-6 + 0.999999 * z[2])) <= 0
#  -1.0 * x_z1 + -3.0 * z[1] <= 0
#  -1.0 * x_z2 + 5.0 * z[2] <= 0

(
    (0.999999 Y[1] + 1.0e-6) * (
        (0.999999 Y[1] + 1.0e-6) * exp((x_Y[1] / (0.999999 Y[1] + 1.0e-6))) - 2.0
    )
)
-
-2.0e-6 Y[1] + 2.0e-6