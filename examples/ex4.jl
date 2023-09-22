using JuMP
using DisjunctiveProgramming

# Example with proposition reformulation
# Proposition:
# ¬((Y[1] ∧ ¬Y[2]) ⇔ (Y[3] ∨ Y[4]))

m = GDPModel()
@variable(m, Y[1:4], LogicalVariable)
@constraint(m, ¬((Y[1] ∧ ¬Y[2]) ⇔ (Y[3] ∨ Y[4])) ∈ MOI.EqualTo(true))
reformulate_model(m, BigM())
print(m)
# Feasibility
# Subject to
#  -Y[1] ≥ -1
#  Y[2] ≥ 0
#  -Y[1] + Y[2] - Y[3] ≥ -1
#  Y[4] ≥ 0
#  Y[1] + Y[3] + Y[4] ≥ 1
#  -Y[2] + Y[3] + Y[4] ≥ 0
#  Y[3] ≥ 0
#  -Y[1] + Y[2] - Y[4] ≥ -1
#  Y[1] binary
#  Y[2] binary
#  Y[3] binary
#  Y[4] binary