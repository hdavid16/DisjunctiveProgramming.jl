using JuMP
using DisjunctiveProgramming

m = Model()
@variable(m, -5 ≤ x ≤ 10)
@disjunction(
    m,
    (
        exp(x) ≤ 2,
        -3 ≤ x
    ),
    begin
        3 ≤ exp(x)
        5 ≤ x
    end,
    reformulation=:CHR,
    name=:z
)
print(m)

# Feasibility
# Subject to
#  XOR(disj_z) : z[1] + z[2] == 1.0             <- XOR constraint
#  x_aggregation : x - x_z1 - x_z2 == 0.0       <- aggregation of disaggregated variables
#  disj_z[1,2] : -x_z1 - 3 z[1] <= 0.0          <- convex-hull reformulation of 2nd constraint if 1st disjunct (named disj_z[1,2] to indicate 1st disjunct, 2nd constraint)
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
#  z[1] binary                                  <- indicator variable (1st disjunct) is binary
#  z[2] binary                                  <- indicator variable (2nd disjunct) is binary
#  Perspective Functions:
#  (-1.0e-6 + -1.9999989999999999 * z[1]) + (1.0e-6 + 0.999999 * z[1]) * exp(x_z1 / (1.0e-6 + 0.999999 * z[1])) <= 0
#  (1.0000000000000002e-6 + 2.999999 * z[2]) + (-1.0e-6 + -0.999999 * z[2]) * exp(x_z2 / (1.0e-6 + 0.999999 * z[2])) <= 0
#  -1.0 * x_z2 + 5.0 * z[2] <= 0