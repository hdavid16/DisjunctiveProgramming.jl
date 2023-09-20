using JuMP
using DisjunctiveProgramming

##
m = GDPModel()
@variable(m, -5 <= x[1:3] <= 5)

@variable(m, y[1:2], LogicalVariable)
@constraint(m, x[1] <= -2, DisjunctConstraint(y[1]))
@constraint(m, x[1] >= 2, DisjunctConstraint(y[2]))
@constraint(m, x[2] == -1, DisjunctConstraint(y[2]))
@constraint(m, x[3] == 1, DisjunctConstraint(y[2]))
@disjunction(m, y)
@constraint(m, y in Exactly(1))

@variable(m, w[1:2], LogicalVariable)
@constraint(m, x[2] <= -3, DisjunctConstraint(w[1]))
@constraint(m, x[2] >= 3, DisjunctConstraint(w[2]))
@constraint(m, x[3] == 0, DisjunctConstraint(w[2]))
@disjunction(m, w, DisjunctConstraint(y[1]))
@constraint(m, w in Exactly(y[1]))

@variable(m, z[1:2], LogicalVariable)
@constraint(m, x[3] <= -4, DisjunctConstraint(z[1]))
@constraint(m, x[3] >= 4, DisjunctConstraint(z[2]))
@disjunction(m, z, DisjunctConstraint(w[1]))
@constraint(m, z in Exactly(w[1]))

##
reformulate_model(m, BigM())
print(m)
