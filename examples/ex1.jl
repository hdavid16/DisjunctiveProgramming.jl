using JuMP
using DisjunctiveProgramming

m = Model()
@variable(m, -1<=x<=10)

@constraint(m, con1, 0 <= x <= 3)
@constraint(m, con2, 5 <= x <= 9)

@disjunction(m,con1,con2,reformulation=:CHR,name=:y)
@proposition(m, y[1] ∨ y[2]) #this is a redundant proposition

print(m)