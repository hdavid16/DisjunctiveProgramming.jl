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
                    _copy_expression(con.func, new_model),
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
# Constant
function _copy_expression(c::Number, new_model::JuMP.Model)
    return c
end

function _copy_expression(var::JuMP.VariableRef, new_model::JuMP.Model)
    return JuMP.VariableRef(new_model, JuMP.index(var))
end

function _copy_expression(aff::JuMP.AffExpr, new_model::JuMP.Model)
    new_expr = JuMP.AffExpr()
    for (var, coeff) in aff.terms
        new_var = _copy_expression(var, new_model)
        new_expr.terms[new_var] = coeff
    end

    return new_expr
end

"""

"""
function _copy_expression(quad::JuMP.QuadExpr, new_model::JuMP.Model)
    new_expr = JuMP.QuadExpr()
    for (var, coeff) in quad.aff.terms
        new_var = _copy_expression(var, new_model)
        new_expr.aff.terms[new_var] = coeff
    end
    for (pair, coeff) in quad.terms
        vara = JuMP.VariableRef(new_model, JuMP.index(pair.a))
        varb = JuMP.VariableRef(new_model, JuMP.index(pair.b))
        new_term = JuMP.UnorderedPair{JuMP.VariableRef}(vara, varb)
        new_expr.terms[new_term] = coeff
    end

    return new_expr
end

"""

"""
function _copy_expression(nlp::JuMP.NonlinearExpr, new_model::JuMP.Model)
    #TODO: use stack to avoid recursion stackoverflow error for deeply nested expression
    new_args = Vector{Any}()
    for arg in nlp.args
        push!(new_args, _copy_expression(arg, new_model))
    end

    return JuMP.NonlinearExpr(nlp.head, new_args)
end