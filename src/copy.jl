"""

"""
function _copy_disjunctions(disjunctions::_MOIUC.CleverDict{DisjunctionIndex, DisjunctiveConstraintData}, new_model::JuMP.Model)
    new_disjunctions = _MOIUC.CleverDict{DisjunctionIndex, DisjunctiveConstraintData}()
    for (_, DCD) in disjunctions
        new_disjunction = similar(DCD.constraint.disjuncts)
        for (ix, disj) in enumerate(DCD.constraint.disjuncts)
            new_disj_con = JuMP.AbstractConstraint[]
            for con in disj.constraints
                new_con = JuMP.build_constraint(error,
                    _copy_constraint(con, new_model),
                    con.set 
                )
                push!(new_disj_con, new_con)
            end
            new_disj = Disjunct(tuple(new_disj_con...), disj.indicator)
            new_disjunction[ix] = new_disj
        end
        new_DCD = DisjunctiveConstraintData(
            JuMP.build_constraint(error, new_disjunction), 
            DCD.name
        )
        _MOIUC.add_item(new_disjunctions, new_DCD)
    end
    
    return new_disjunctions
end

"""

"""
function _copy_constraint(con::JuMP.ScalarConstraint{JuMP.AffExpr, T}, new_model::JuMP.Model) where {T}
    new_con_func = JuMP.AffExpr()
    for (var, coeff) in con.func.terms
        new_var = JuMP.VariableRef(new_model, JuMP.index(var))
        new_con_func.terms[new_var] = coeff
    end

    return new_con_func
end

"""

"""
function _copy_constraint(con::JuMP.ScalarConstraint{JuMP.QuadExpr, T}, new_model::JuMP.Model) where {T}
    new_con_func = JuMP.QuadExpr()
    for (var, coeff) in con.func.aff.terms
        new_var = JuMP.VariableRef(new_model, JuMP.index(var))
        new_con_func.aff.terms[new_var] = coeff
    end
    for (pair, coeff) in con.func.terms
        vara = JuMP.VariableRef(new_model, JuMP.index(pair.a))
        varb = JuMP.VariableRef(new_model, JuMP.index(pair.b))
        new_term = JuMP.UnorderedPair{VariableRef}(vara, varb)
        new_con_func.terms[new_term] = coeff
    end

    return new_con_func
end