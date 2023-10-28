# Nested GDP: https://arxiv.org/pdf/2303.04375.pdf
using DisjunctiveProgramming

##
m = GDPModel()
@variable(m, 1 ≤ x[1:2] ≤ 9)
@variable(m, Y[1:2], Logical)
@variable(m, W[1:2], Logical)
@objective(m, Max, sum(x))
@constraint(m, y1[i=1:2], [1,4][i] ≤ x[i] ≤ [3,6][i], Disjunct(Y[1]))
@constraint(m, w1[i=1:2], [1,5][i] ≤ x[i] ≤ [2,6][i], Disjunct(W[1]))
@constraint(m, w2[i=1:2], [2,4][i] ≤ x[i] ≤ [3,5][i], Disjunct(W[2]))
@constraint(m, y2[i=1:2], [8,1][i] ≤ x[i] ≤ [9,2][i], Disjunct(Y[2]))
@disjunction(m, inner, [W[1], W[2]], Disjunct(Y[1]))
@disjunction(m, outer, [Y[1], Y[2]])

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