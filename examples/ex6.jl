using DisjunctiveProgramming

## Multi-level Nested GDP
m = GDPModel()
@variable(m, -5 <= x[1:3] <= 5)

@variable(m, y[1:2], Logical)
@constraint(m, x[1] <= -2, Disjunct(y[1]))
@constraint(m, x[1] >= 2, Disjunct(y[2]))
@constraint(m, x[2] == -1, Disjunct(y[2]))
@constraint(m, x[3] == 1, Disjunct(y[2]))
disjunction(m, y)

@variable(m, w[1:2], Logical)
@constraint(m, x[2] <= -3, Disjunct(w[1]))
@constraint(m, x[2] >= 3, Disjunct(w[2]))
@constraint(m, x[3] == 0, Disjunct(w[2]))
disjunction(m, w, Disjunct(y[1]))

@variable(m, z[1:2], Logical)
@constraint(m, x[3] <= -4, Disjunct(z[1]))
@constraint(m, x[3] >= 4, Disjunct(z[2]))
disjunction(m, z, Disjunct(w[1]))

##
reformulate_model(m, BigM())
print(m)
# Feasibility
# Subject to
#  y[1] + y[2] = 1
#  -y[1] + w[1] + w[2] = 0
#  -w[1] + z[1] + z[2] = 0
#  x[3] - 9 z[2] ≥ -5
#  x[2] - 8 w[2] ≥ -5
#  x[3] - 5 w[2] ≥ -5
#  x[1] - 7 y[2] ≥ -5
#  x[2] - 4 y[2] ≥ -5
#  x[3] - 6 y[2] ≥ -5
#  x[1] + 7 y[1] ≤ 5
#  x[2] + 8 w[1] ≤ 5
#  x[3] + 9 z[1] ≤ 5
#  x[3] + 5 w[2] ≤ 5
#  x[2] + 6 y[2] ≤ 5
#  x[3] + 4 y[2] ≤ 5
#  x[1] ≥ -5
#  x[2] ≥ -5
#  x[3] ≥ -5
#  x[1] ≤ 5
#  x[2] ≤ 5
#  x[3] ≤ 5
#  y[1] binary
#  y[2] binary
#  w[1] binary
#  w[2] binary
#  z[1] binary
#  z[2] binary
