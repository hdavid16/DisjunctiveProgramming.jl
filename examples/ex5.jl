# https://arxiv.org/pdf/2303.04375.pdf
using DisjunctiveProgramming

##
m = GDPModel()
@variable(m, 1 ≤ x[1:2] ≤ 9)
@variable(m, Y[1:2], Logical)
@variable(m, W[1:2], Logical)
@objective(m, Max, sum(x))
@constraint(m, y1[i=1:2], [1,4][i] ≤ x[i] ≤ [3,6][i], DisjunctConstraint(Y[1]))
@constraint(m, w1[i=1:2], [1,5][i] ≤ x[i] ≤ [2,6][i], DisjunctConstraint(W[1]))
@constraint(m, w2[i=1:2], [2,4][i] ≤ x[i] ≤ [3,5][i], DisjunctConstraint(W[2]))
@constraint(m, y2[i=1:2], [8,1][i] ≤ x[i] ≤ [9,2][i], DisjunctConstraint(Y[2]))
@disjunction(m, inner, [W[1], W[2]], DisjunctConstraint(Y[1]))
@disjunction(m, outer, [Y[1], Y[2]])
@constraint(m, Y in Exactly(1))
@constraint(m, W in Exactly(Y[1]))

##
reformulate_model(m, BigM())
print(m)

##
reformulate_model(m, Hull())
print(m)

##
using Polyhedra, CDDLib, Plots
relax_integrality(m)
lib = CDDLib.Library(:exact)
poly = polyhedron(vrep(polyhedron(m, lib)),lib)
proj = project(poly,1:2)
plot(proj, xlims = (0,10), ylims = (0,7), xticks = 0:10, yticks = 0:10)