# example with proposition reformulations

m = GDPModel()
@variable(m, Y[1:4], LogicalVariable)
lexpr =
    LogicalExpr(:¬, Any[
        LogicalExpr(:⇔, Any[
                LogicalExpr(:∧, Any[
                    Y[1], 
                    LogicalExpr(:¬, Any[Y[2]])
                ])
                ,
                LogicalExpr(:∨, Any[Y[3], Y[4]])
            ]
        )
    ])
DisjunctiveProgramming._eliminate_equivalence(lexpr) |>
DisjunctiveProgramming._eliminate_implication |>
DisjunctiveProgramming._move_negations_inward

# logical_con = add_constraint(m, logic_1, "logic_con")
# DisjunctiveProgramming._reformulate_logical_variables(m)
# DisjunctiveProgramming._reformulate_logical_constraints(m)
# print(m)