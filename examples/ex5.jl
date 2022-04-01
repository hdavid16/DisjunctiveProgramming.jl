using JuMP
using DisjunctiveProgramming

m = Model()
@variable(m, -10 ≤ x[1:2] ≤ 10)
# @variable(m, z[1:2], Bin) #create binary variable for disjunction

nl_con1 = @NLconstraint(m, exp(x[1]) >= 1)
nl_con2 = @NLconstraint(m, exp(x[2]) <= 2)

@disjunction(m, nl_con1, nl_con2, reformulation=:CHR, name=:z)

print(m)