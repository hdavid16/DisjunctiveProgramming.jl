function _copy(logical_constraints::_MOIUC.CleverDict{LogicalConstraintIndex, ConstraintData, T1, T2}, new_model::JuMP.Model) where {T1, T2}
    new_logical_cons = _MOIUC.CleverDict{LogicalConstraintIndex, ConstraintData}()
    for (_, LCD) in logical_constraints
        new_lcon = JuMP.build_constraint(error,
            _copy(LCD.constraint.func, new_model),
            _copy(LCD.constraint.set, new_model)
        )
        new_LCD = ConstraintData(new_lcon, LCD.name)
        _MOIUC.add_item(new_logical_cons, new_LCD)
    end

    return new_logical_cons
end

function _copy(disjunct_constraints::_MOIUC.CleverDict{DisjunctConstraintIndex, ConstraintData, T1, T2}, new_model::JuMP.Model) where {T1, T2}
    new_disjunct_cons = _MOIUC.CleverDict{DisjunctConstraintIndex, ConstraintData}()
    for (_, DCD) in disjunct_constraints
        new_disjunct_con = JuMP.build_constraint(error,
            _copy(DCD.constraint.func, new_model),
            DCD.constraint.set
        )
        new_DCD = ConstraintData(new_disjunct_con, DCD.name)
        _MOIUC.add_item(new_disjunct_cons, new_DCD)
    end
    
    return new_disjunct_cons
end

_copy(::Nothing, new_model::JuMP.Model) = nothing

function _copy(set::S, new_mode::JuMP.Model) where {S<:Union{_MOI.EqualTo, MOIAtLeast, MOIAtMost, MOIExactly}}
    return set
end

function _copy(set::MOIAtLeast{T}, new_model::JuMP.Model) where {T<:LogicalVariableRef}
    return MOIAtLeast{T}(
        LogicalVariableRef(new_model, JuMP.index(set.value)), 
        set.dimension
    )
end

function _copy(set::MOIAtMost{T}, new_model::JuMP.Model) where {T<:LogicalVariableRef}
    return MOIAtMost{T}(
        LogicalVariableRef(new_model, JuMP.index(set.value)), 
        set.dimension
    )
end

function _copy(set::MOIExactly{T}, new_model::JuMP.Model) where {T<:LogicalVariableRef}
    return MOIExactly{T}(
        LogicalVariableRef(new_model, JuMP.index(set.value)), 
        set.dimension
    )
end

function _copy(c::Number, new_model::JuMP.Model)
    return c
end

function _copy(var::JuMP.VariableRef, new_model::JuMP.Model)
    return JuMP.VariableRef(new_model, JuMP.index(var))
end

function _copy(lvar::LogicalVariableRef, new_model::JuMP.Model)
    return LogicalVariableRef(new_model, JuMP.index(lvar))
end

function _copy(lvec::Vector{LogicalVariableRef}, new_model::JuMP.Model)
    return _copy.(lvec, new_model)
end

function _copy(aff::JuMP.AffExpr, new_model::JuMP.Model)
    new_expr = JuMP.AffExpr(aff.constant)
    for (var, coeff) in aff.terms
        new_var = _copy(var, new_model)
        new_expr.terms[new_var] = coeff
    end

    return new_expr
end

function _copy(quad::JuMP.QuadExpr, new_model::JuMP.Model)
    new_expr = JuMP.QuadExpr()
    new_expr.aff = _copy(quad.aff, new_model)
    for (pair, coeff) in quad.terms
        vara = JuMP.VariableRef(new_model, JuMP.index(pair.a))
        varb = JuMP.VariableRef(new_model, JuMP.index(pair.b))
        new_term = JuMP.UnorderedPair{JuMP.VariableRef}(vara, varb)
        new_expr.terms[new_term] = coeff
    end

    return new_expr
end

function _copy(nlp::JuMP.NonlinearExpr, new_model::JuMP.Model)
    #TODO: use stack to avoid recursion stackoverflow error for deeply nested expression
    new_args = Vector{Any}(undef, length(nlp.args))
    for (i,arg) in enumerate(nlp.args)
        new_args[i] = _copy(arg, new_model)
    end
    return JuMP.NonlinearExpr(nlp.head, new_args)
end