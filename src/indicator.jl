################################################################################
#                              INDICATOR REFORMULATION
################################################################################
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.ScalarConstraint{T, S},
    bvref::JuMP.VariableRef,
    ::Indicator
) where {T, S}
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, [1*bvref, con.func], _MOI.Indicator{_MOI.ACTIVATE_ON_ONE}(con.set))
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.VectorShape()))
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.VectorConstraint{T, S},
    bvref::JuMP.VariableRef,
    ::Indicator
) where {T, S}
    set = _vec_to_scalar_set(con.set)
    for func in con.func
        reform_con = JuMP.add_constraint(model,
            JuMP.build_constraint(error, [1*bvref, func], _MOI.Indicator{_MOI.ACTIVATE_ON_ONE}(set))
        )
        push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.VectorShape()))
    end
end