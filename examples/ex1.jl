using JuMP
using JuGDP

m = Model()
@variable(m, -1<=x<=10)

@constraint(m, con1, x<=3)
@constraint(m, con2, 0<=x)
@constraint(m, con3, x<=9)
@constraint(m, con4, 5<=x)

@disjunction(m,(con1,con2),con3,con4,reformulation=:CHR)

# add_disjunction(m,(con1,con2),con3,con4,reformulation=:CHR)

# @constraint(m, c1, 0<=x[1]<=3)
# c1_obj=constraint_object(c1)
# delete(m, c1)
# unregister(m, :c1)
# @constraint(m, c1_lt, c1_obj.set.lower <= c1_obj.func)
# @constraint(m, c1_gt, c1_obj.func <= c1_obj.set.upper)
