# https://optimization.mccormick.northwestern.edu/index.php/Disjunctive_inequalities
using JuMP
using DisjunctiveProgramming

m = Model()
@variable(m, 0<=x[1:2]<=10)

@constraint(m, con1[i=1:2], 0 <= x[i]<=[3,4][i])
@constraint(m, con2[i=1:2], [5,4][i] <= x[i] <= [9,6][i])

@disjunction(m,con1,con2,reformulation=:BMR,name=:y)

print(m)