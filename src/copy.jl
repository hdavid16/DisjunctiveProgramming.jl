################################################################################
#                              COPY METHODS
################################################################################
# logical constraints
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

# disjunct constraints
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

# nothing
_copy(::Nothing, new_model::JuMP.Model) = nothing

# MOI sets
function _copy(set::S, new_model::JuMP.Model) where {S <: _MOI.AbstractSet}
    return set
end

# Cardinality sets
function _copy(set::S, new_model::JuMP.Model) where {S <: _MOISelector}
    return S(_copy(set.value, new_model), set.dimension)
end

# number
function _copy(c::Number, new_model::JuMP.Model)
    return c
end

# VariableRef
function _copy(var::JuMP.VariableRef, new_model::JuMP.Model)
    return JuMP.VariableRef(new_model, JuMP.index(var))
end

# LogicalVariableRef
function _copy(lvar::LogicalVariableRef, new_model::JuMP.Model)
    return LogicalVariableRef(new_model, JuMP.index(lvar))
end
function _copy(lvec::Vector{LogicalVariableRef}, new_model::JuMP.Model)
    return _copy.(lvec, new_model)
end

# Affine expression
function _copy(aff::JuMP.AffExpr, new_model::JuMP.Model)
    new_expr = zero(JuMP.AffExpr)
    for (var, coeff) in aff.terms
        new_var = _copy(var, new_model)
        JuMP.add_to_expression!(new_expr, coeff*new_var)
    end
    JuMP.add_to_expression!(new_expr, aff.constant)

    return new_expr
end

# Quadratic expression
function _copy(quad::JuMP.QuadExpr, new_model::JuMP.Model)
    new_expr = zero(JuMP.QuadExpr)
    JuMP.add_to_expression!(new_expr, _copy(quad.aff, new_model))
    for (pair, coeff) in quad.terms
        vara = _copy(pair.a, new_model)
        varb = _copy(pair.b, new_model)
        JuMP.add_to_expression!(new_expr, coeff*vara*varb)
    end

    return new_expr
end

# Nonlinear expression
function _copy(nlp::JuMP.NonlinearExpr, new_model::JuMP.Model)
    #TODO: use stack to avoid recursion stackoverflow error for deeply nested expression
    new_args = Vector{Any}(undef, length(nlp.args))
    for (i,arg) in enumerate(nlp.args)
        new_args[i] = _copy(arg, new_model)
    end
    return JuMP.NonlinearExpr(nlp.head, new_args)
end

# Vector of JuMP expressions
function _copy(expr::Vector{T}, new_model::JuMP.Model) where {T <: JuMP.AbstractJuMPScalar}
    return _copy.(expr, new_model)
end