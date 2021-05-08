# https://optimization.mccormick.northwestern.edu/index.php/Disjunctive_inequalities
using JuMP
using JuGDP

m = Model()
@variable(m, -1<=x[1:2]<=10)

b=[3,4]
@constraint(m, con1[i=1:2], x[i]<=[3,4][i])
@constraint(m, con2, 0<=x[1])
@constraint(m, con3, 0<=x[2])
@constraint(m, con4[i=1:2], [5,4][i]<=x[i])
@constraint(m, con5, x[1] <= 9)
@constraint(m, con6, x[2] <= 6)

@disjunction(m,(con1,con2,con3),(con4,con5,con6),reformulation=:CHR)
