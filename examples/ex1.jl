using JuMP
using DisjunctiveProgramming

m = Model()
@variable(m, -1<=x<=10)

@constraint(m, con1, x<=3)
@constraint(m, con2, 0<=x)
@constraint(m, con3, x<=9)
@constraint(m, con4, 5<=x)

@disjunction(m,(con1,con2),con3,con4,reformulation=:CHR,name=:y)
# @proposition(m, y[1] ∨ y[2])
# @proposition(m, 
#     (
#         ((y[1] ∨ y[2]) ∧ (¬y[1] ∨ ¬y[2]))
#         ∨
#         y[3]
#     )
#     ∧
#     (
#         ¬((y[1] ∨ y[2]) ∧ (¬y[1] ∨ ¬y[2]))
#         ∨
#         ¬y[3]
#     )
#     ∧
#     (¬y[1] ∨ ¬y[2] ∨ ¬y[3])
# )
# @proposition(m, y[1] ⊻ y[2] ⊻ y[3])

print(m)