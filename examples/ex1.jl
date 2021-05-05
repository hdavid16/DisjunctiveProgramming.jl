using JuMP, JuGDP, GLPK

m = Model(GLPK.Optimizer)
@variable(m, y)
@variable(m, -1<=x[1:2]<=10)

@constraint(m, con1, x[1]<=3)
@constraint(m, con2, 0<=x[1])
@constraint(m, con3, x[1]<=9)
@constraint(m, con4, 5<=x[1])

@disjunction(m,(:con1,:con2),:con3,:con4,reformulation=:BMR)

# @constraint(m, c1, 0<=x[1]<=3)
# c1_obj=constraint_object(c1)
# delete(m, c1)
# unregister(m, :c1)
# @constraint(m, c1_lt, c1_obj.set.lower <= c1_obj.func)
# @constraint(m, c1_gt, c1_obj.func <= c1_obj.set.upper)
