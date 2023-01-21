using JuMP
using DisjunctiveProgramming

m = Model()
@variable(m, -5 ≤ x ≤ 10)
@disjunction(
    m,
    0 ≤ x ≤ 3,
    5 ≤ x ≤ 9,
    reformulation=:big_m,
    name=:y
)
choose!(m, 1, m[:y]...; mode = :exactly, name = "XOR") #XOR constraint
@proposition(m, y[1] ∨ y[2], name = "prop") #this is a redundant proposition

print(m)

# ┌ Warning: disj_y[1] : x in [0.0, 3.0] uses the `MOI.Interval` set. Each instance of the interval set has been split into two constraints, one for each bound.
# ┌ Warning: disj_y[2] : x in [5.0, 9.0] uses the `MOI.Interval` set. Each instance of the interval set has been split into two constraints, one for each bound.
# Feasibility
# Subject to
#  XOR : y[1] + y[2] == 1.0         <- XOR constraint
#  prop : y[1] + y[2] >= 1.0         <- reformulated logical proposition (name is the proposition)
#  disj_y[1,lb] : -x + 5 y[1] <= 5.0       <- left-side of constraint in 1st disjunct (name is assigned to disj_y[1][lb])
#  disj_y[1,ub] : x + 7 y[1] <= 10.0       <- right-side of constraint in 1st disjunct (name is assigned to disj_y[1][ub])
#  disj_y[2,lb] : -x + 10 y[2] <= 5.0      <- left-side of constraint in 2nd disjunct (name is assigned to disj_y[2][lb])
#  disj_y[2,ub] : x + y[2] <= 10.0         <- right-side of constraint in 2nd disjunct (name is assigned to disj_y[2][ub])
#  x >= -5.0                                <- variable lower bound
#  x <= 10.0                                <- variable upper bound
#  y[1] binary                              <- indicator variable (1st disjunct) is binary
#  y[2] binary                              <- indicator variable (2nd disjunct) is binary