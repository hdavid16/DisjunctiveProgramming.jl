################################################################################
#                              LOGICAL VARIABLES
################################################################################
"""

Create binary (indicator) variables for logic variables.
"""
function _reformulate_logical_variables(model::JuMP.Model)
    for (lv_idx, lv_data) in _logical_variables(model)
        var = JuMP.ScalarVariable(_variable_info(binary=true))
        bvref = JuMP.add_variable(model, var, lv_data.name)
        _indicator_to_binary(model)[lv_idx] = JuMP.index(bvref)
    end
end

################################################################################
#                              DISJUNCTIONS
################################################################################
"""

"""
function _reformulate_disjunctions(model::JuMP.Model, method::AbstractReformulationMethod)
    for (disj_idx, disj) in _disjunctions(model)
        _reformulate_disjuncts(model, disj_idx, disj, method)
    end
end

function _reformulate_disjuncts(model::JuMP.Model, disj_idx::DisjunctionIndex, disj::ConstraintData{T}, method::Union{BigM,Indicator}) where {T<:Disjunction}
    for d in disj.constraint.disjuncts
        _reformulate_disjunct(model, d, method)
    end
end

function _reformulate_disjuncts(model::JuMP.Model, disj_idx::DisjunctionIndex, disj::ConstraintData{T}, method::Hull) where {T<:Disjunction}
    disj_vrefs = _get_disjunction_variables(disj)
    _update_variable_bounds.(disj_vrefs) 
    for d in disj.constraint.disjuncts #reformulate each disjunct
        _disaggregate_variables(model, d, disj_vrefs) #disaggregate variables for that disjunct
        _reformulate_disjunct(model, d, method)
    end
    for vref in disj_vrefs #create sum constraint for disaggregated variables
        _aggregate_variable(model, vref, disj_idx)
    end
end

"""

"""
function _reformulate_disjunct(model::JuMP.Model, d::Disjunct, method::AbstractReformulationMethod)
    #reformulate each constraint and add to the model
    ind_idx = JuMP.index(d.indicator) #logical indicator
    bv_idx = _indicator_to_binary(model)[ind_idx]
    bvref = JuMP.VariableRef(model, bv_idx)
    for con in d.constraints
        cdata = _disjunct_constraints(model)[JuMP.index(con)]
        _reformulate_disjunctive_constraint(model, cdata.constraint, bvref, method)
    end
end

"""

"""
function _reformulate_disjunctive_constraint(
    model::JuMP.Model,
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.LessThan}
    #TODO: need to pass _error to build_constraint
    M = method.tighten ? _get_tight_M(method, con) : _get_M(method, con)
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con.func - M*(1-bvref), con.set)
    )
end
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM,
) where {T, S <: _MOI.GreaterThan}
    #TODO: need to pass _error to build_constraint
    M = method.tighten ? _get_tight_M(method, con) : _get_M(method, con)
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con.func + M*(1-bvref), con.set)
    )
end
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.Interval}
    #TODO: need to pass _error to build_constraint
    M = method.tighten ? _get_tight_M(method, con) : _get_M(method, con)
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con.func + M[1]*(1-bvref), _MOI.GreaterThan(con.set.lower))
    )
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con.func - M[2]*(1-bvref), _MOI.LessThan(con.set.upper))
    )
end
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.EqualTo}
    #TODO: need to pass _error to build_constraint
    M = method.tighten ? _get_tight_M(method, con) : _get_M(method, con)
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con.func + M[1]*(1-bvref), _MOI.GreaterThan(con.set.value))
    )
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con.func - M[2]*(1-bvref), _MOI.LessThan(con.set.value))
    )
end

"""

"""
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::Hull
) where {T <: Union{JuMP.AffExpr, JuMP.QuadExpr}, S <: _MOI.LessThan}
    #TODO: need to pass _error to build_constraint
    con_func = _disaggregate_expression(model, con.func, bvref, method)
    con_func -= con.set.upper * bvref
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con_func, _MOI.LessThan(0))
    )
end
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::Hull
) where {T <: JuMP.NonlinearExpr, S <: _MOI.LessThan}
    #TODO: need to pass _error to build_constraint
    ϵ = method.value
    con_func = _disaggregate_nl_expression(model, con.func, bvref, method)
    con_func0 = value(v -> 0.0, con.func)
    if isinf(con_func0)
        error("Operator `$(con.func.head)` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    con_func = ((1-ϵ)*bvref+ϵ)*con_func - ϵ*(1-bvref)*con_func0 - con.set.upper*bvref
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con_func, _MOI.LessThan(0))
    )
end
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::Hull
) where {T <: Union{JuMP.AffExpr, JuMP.QuadExpr}, S <: _MOI.GreaterThan}
    #TODO: need to pass _error to build_constraint
    con_func = _disaggregate_expression(model, con.func, bvref, method)
    con_func -= con.set.lower * bvref
    
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con_func, _MOI.GreaterThan(0))
    )
end
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::Hull
) where {T <: JuMP.NonlinearExpr, S <: _MOI.GreaterThan}
    #TODO: need to pass _error to build_constraint
    ϵ = method.value
    con_func = _disaggregate_nl_expression(model, con.func, bvref, method)
    con_func0 = value(v -> 0.0, con.func)
    if isinf(con_func0)
        error("Operator `$(con.func.head)` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    con_func = ((1-ϵ)*bvref+ϵ)*con_func - ϵ*(1-bvref)*con_func0 - con.set.lower*bvref
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con_func, _MOI.GreaterThan(0))
    )
end
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::Hull
) where {T <: Union{JuMP.AffExpr, JuMP.QuadExpr}, S <: _MOI.Interval}
    #TODO: need to pass _error to build_constraint
    con_func = _disaggregate_expression(model, con.func, bvref, method)
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con_func - con.set.lower*bvref, _MOI.GreaterThan(0))
    )
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con_func - con.set.upper*bvref, _MOI.LessThan(0))
    )
end
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::Hull
) where {T <: JuMP.NonlinearExpr, S <: _MOI.Interval}
    #TODO: need to pass _error to build_constraint
    ϵ = method.value
    con_func = _disaggregate_nl_expression(model, con.func, bvref, method)
    con_func0 = value(v -> 0.0, con.func)
    if isinf(con_func0)
        error("Operator `$(con.func.head)` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    con_func = ((1-ϵ)*bvref+ϵ) * con_func - ϵ*(1-bvref)*con_func0
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con_func - con.set.upper*bvref, _MOI.LessThan(0))
    )
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con_func - con.set.lower*bvref, _MOI.GreaterThan(0))
    )
end
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::Hull
    ) where {T <: Union{JuMP.AffExpr, JuMP.QuadExpr}, S <: _MOI.EqualTo}
    #TODO: need to pass _error to build_constraint
    con_func = _disaggregate_expression(model, con.func, bvref, method)
    con_func -= con.set.value * bvref
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con_func, _MOI.EqualTo(0))
    )
end
function _reformulate_disjunctive_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::Hull
    ) where {T <: JuMP.NonlinearExpr, S <: _MOI.EqualTo}
    #TODO: need to pass _error to build_constraint
    ϵ = method.value
    con_func = _disaggregate_nl_expression(model, con.func, bvref, method)
    con_func0 = value(v -> 0.0, con.func)
    if isinf(con_func0)
        error("Operator `$(con.func.head)` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    con_func = ((1-ϵ)*bvref+ϵ)*con_func - ϵ*(1-bvref)*con_func0 - con.set.value*bvref
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, con_func, _MOI.EqualTo(0))
    )
end

"""

"""
function _reformulate_disjunctive_constraint(
    model::JuMP.Model,
    con::JuMP.ScalarConstraint{JuMP.AffExpr, S},
    bvref::JuMP.VariableRef,
    ::Indicator
) where {S}
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, [1*bvref, con.func], _MOI.Indicator{_MOI.ACTIVATE_ON_ONE}(con.set))
    )
end

# define fallbacks for other constraint types
function _reformulate_disjunctive_constraint(
    ::JuMP.Model,  
    con::JuMP.AbstractConstraint, 
    ::JuMP.VariableRef,
    method::AbstractReformulationMethod
)
    error("$method reformulation for constraint $con is not supported yet.")
end

################################################################################
#                              LOGICAL CONSTRAINTS
################################################################################

"""

"""
function _reformulate_logical_constraints(model::JuMP.Model)
    for (_, lcon) in _logical_constraints(model)
        _reformulate_logical_constraint(model, lcon.constraint.func, lcon.constraint.set)
    end
end

function _reformulate_logical_constraint(model::JuMP.Model, lvec::Vector{LogicalVariableRef}, set::Union{MOIAtMost, MOIAtLeast, MOIExactly})
    return _reformulate_selector(model, set, set.value, lvec)
end

function _reformulate_logical_constraint(model::JuMP.Model, lexpr::_LogicalExpr, ::_MOI.EqualTo{Bool})
    return _reformulate_proposition(model, lexpr)
end

function _reformulate_selector(model::JuMP.Model, ::MOIAtLeast, val::Number, lvrefs::Vector{LogicalVariableRef})
    bvrefs = Vector{Any}(_indicator_to_binary_ref.(lvrefs))
    return JuMP.add_constraint(model,
        JuMP.build_constraint(error, JuMP.NonlinearExpr(:+, bvrefs), _MOI.GreaterThan(val))
    )
end
function _reformulate_selector(model::JuMP.Model, ::MOIAtMost, val::Number, lvrefs::Vector{LogicalVariableRef})
    bvrefs = Vector{Any}(_indicator_to_binary_ref.(lvrefs))
    return JuMP.add_constraint(model,
        JuMP.build_constraint(error, JuMP.NonlinearExpr(:+, bvrefs), _MOI.LessThan(val))
    )
end
function _reformulate_selector(model::JuMP.Model, ::MOIExactly, val::Number, lvrefs::Vector{LogicalVariableRef})
    bvrefs = Vector{Any}(_indicator_to_binary_ref.(lvrefs))
    return JuMP.add_constraint(model,
        JuMP.build_constraint(error, JuMP.NonlinearExpr(:+, bvrefs), _MOI.EqualTo(val))
    )
end
function _reformulate_selector(model::JuMP.Model, ::MOIAtLeast, lvref::LogicalVariableRef, lvrefs::Vector{LogicalVariableRef})
    bvref = _indicator_to_binary_ref(lvref)
    bvrefs = Vector{Any}(_indicator_to_binary_ref.(lvrefs))
    return JuMP.add_constraint(model,
        build_constraint(error, JuMP.NonlinearExpr(:-, Any[JuMP.NonlinearExpr(:+, bvrefs), bvref]), _MOI.GreaterThan(0))
    )
end
function _reformulate_selector(model::JuMP.Model, ::MOIAtMost, lvref::LogicalVariableRef, lvrefs::Vector{LogicalVariableRef})
    bvref = _indicator_to_binary_ref(lvref)
    bvrefs = Vector{Any}(_indicator_to_binary_ref.(lvrefs))
    return JuMP.add_constraint(model,
        build_constraint(error, JuMP.NonlinearExpr(:-, Any[JuMP.NonlinearExpr(:+, bvrefs), bvref]), _MOI.LessThan(0))
    )
end
function _reformulate_selector(model::JuMP.Model, ::MOIExactly, lvref::LogicalVariableRef, lvrefs::Vector{LogicalVariableRef})
    bvref = _indicator_to_binary_ref(lvref)
    bvrefs = Vector{Any}(_indicator_to_binary_ref.(lvrefs))
    return JuMP.add_constraint(model,
        build_constraint(error, JuMP.NonlinearExpr(:-, Any[JuMP.NonlinearExpr(:+, bvrefs), bvref]), _MOI.EqualTo(0))
    )
end

function _reformulate_proposition(model::JuMP.Model, lexpr::_LogicalExpr)
    expr = _to_cnf(lexpr)
    if expr.head == :∧
        func = JuMP.AffExpr()
        for arg in expr.args
            func = _reformulate_clause(model, arg)
            JuMP.add_constraint(model,
                JuMP.build_constraint(error, func, _MOI.GreaterThan(1))
            )
        end
    else
        error("Expression was not converted to proper Conjunctive Normal Form:\n$expr")
    end
end

function _reformulate_clause(model::JuMP.Model, lvref::LogicalVariableRef)
    func = 1 * _indicator_to_binary_ref(lvref)
    return func
end

function _reformulate_clause(model::JuMP.Model, lexpr::_LogicalExpr)
    if lexpr.head != :∨
        error("Expression was not converted to proper Conjunctive Normal Form:\n$lexpr")
    end
    func = JuMP.AffExpr() #initialize func expression
    for literal in lexpr.args
        if literal isa LogicalVariableRef
            func += _indicator_to_binary_ref(literal)
        elseif literal.head == :¬ && length(literal.args) == 1 && literal.args[1] isa LogicalVariableRef
            func += (1 - _indicator_to_binary_ref(literal.args[1]))
        else
            error("Expression was not converted to proper Conjunctive Normal Form:\n$literal")
        end
    end

    return func
end