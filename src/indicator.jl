################################################################################
#                              INDICATOR REFORMULATION
################################################################################
#scalar disjunct constraint
function reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.ScalarConstraint{T, S},
    bvref::JuMP.VariableRef,
    method::Indicator
) where {T, S}
    reform_con = JuMP.build_constraint(error, [1*bvref, con.func], _MOI.Indicator{_MOI.ACTIVATE_ON_ONE}(con.set))
    
    return [reform_con]
end
#vectorized disjunct constraint
function reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.VectorConstraint{T, S},
    bvref::JuMP.VariableRef,
    method::Indicator
) where {T, S}
    set = _vec_to_scalar_set(con.set)
    return [JuMP.build_constraint(error, [1*bvref, f], _MOI.Indicator{_MOI.ACTIVATE_ON_ONE}(set)) for f in con.func]
    return reform_cons
end
#nested indicator reformulation
function reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.VectorConstraint{T, S},
    bvref::JuMP.VariableRef,
    method::Indicator
) where {T, S <: _MOI.Indicator}
    
    return [con]
end