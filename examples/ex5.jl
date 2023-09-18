# https://arxiv.org/pdf/2303.04375.pdf

using JuMP
using DisjunctiveProgramming
using HiGHS

##
m = GDPModel(HiGHS.Optimizer)
@variable(m, 1 ≤ x[1:2] ≤ 9)
@variable(m, Y[1:2], LogicalVariable)
@variable(m, W[1:2], LogicalVariable)
@objective(m, Max, sum(x))
@constraint(m, [i=1:2], [1,4][i] ≤ x[i] ≤ [3,6][i], DisjunctConstraint(Y[1]))
@constraint(m, [1,5] .≤ x .≤ [2,6], DisjunctConstraint(W[1]))
@constraint(m, [2,4] .≤ x .≤ [3,5], DisjunctConstraint(W[2]))
@constraint(m, [8,1] .≤ x .≤ [9,2], DisjunctConstraint(Y[1]))