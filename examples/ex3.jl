using JuMP
using JuGDP

m = Model()
@variable(m, -1<=x<=10)

@constraint(m, con1, x<=3)
@constraint(m, con2, 0<=x)
@constraint(m, con3, x<=9)
@constraint(m, con4, 5<=x)

M = 10
code=@disjunction(m,(con1,con2),con3,con4,
                reformulation=:CHR,M=M)
