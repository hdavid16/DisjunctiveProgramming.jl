################################################################################
#                              INDICATOR REFORMULATION
################################################################################
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.ScalarConstraint{T, S},
    bvref::JuMP.VariableRef,
    method::Indicator,
    name::String,
    nested::Bool
) where {T, S}
    reform_con = JuMP.build_constraint(error, [1*bvref, con.func], _MOI.Indicator{_MOI.ACTIVATE_ON_ONE}(con.set))
    if !nested
        con_name = isempty(name) ? name : string(name, "_", bvref)
        _add_reformulated_constraint(model, reform_con, con_name)
    end
    
    return [reform_con]
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.VectorConstraint{T, S},
    bvref::JuMP.VariableRef,
    method::Indicator,
    name::String,
    nested::Bool
) where {T, S}
    set = _vec_to_scalar_set(con.set)
    reform_cons = Vector{JuMP.VectorConstraint}()
    for (i, func) in enumerate(con.func)
        reform_con = JuMP.build_constraint(error, [1*bvref, func], _MOI.Indicator{_MOI.ACTIVATE_ON_ONE}(set))
        push!(reform_cons, reform_con)
        if !nested
            con_name = isempty(name) ? name : string(name, "_", bvref, "_$i")
            _add_reformulated_constraint(model, reform_con, con_name)
        end
    end

    return reform_cons
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.VectorConstraint{T, S},
    bvref::JuMP.VariableRef,
    method::Indicator,
    name::String,
    nested::Bool
) where {T, S <: _MOI.Indicator}
    if !nested
        con_name = isempty(name) ? name : string(name, "_", bvref)
        _add_reformulated_constraint(model, con, con_name)
    end
    
    return [con]
end