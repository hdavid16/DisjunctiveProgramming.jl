################################################################################
#                              LOGICAL VARIABLES
################################################################################
"""

Create binary (indicator) variables for logic variables.
"""
function _reformulate_logical_variables(model::JuMP.Model)
    for (lv_idx, lv_data) in _logical_variables(model)
        lv = lv_data.variable
        var = JuMP.ScalarVariable(_variable_info(binary=true, start_value = lv.start_value, fix_value = lv.fix_value))
        bvref = JuMP.add_variable(model, var, lv_data.name)
        bv_idx = JuMP.index(bvref)
        push!(_reformulation_variables(model), bv_idx)
        _indicator_to_binary(model)[lv_idx] = bv_idx
    end
end

################################################################################
#                              DISJUNCTIONS
################################################################################
# disjunctions
function _reformulate_disjunctions(model::JuMP.Model, method::AbstractReformulationMethod)
    for (_, disj) in _disjunctions(model)
        _reformulate_disjuncts(model, disj, method)
    end
end
# disjuncts
function _reformulate_disjuncts(model::JuMP.Model, disj::ConstraintData{T}, method::Union{BigM,Indicator}) where {T<:Disjunction}
    for d in disj.constraint.disjuncts
        _reformulate_disjunct(model, d, method)
    end
end
function _reformulate_disjuncts(model::JuMP.Model, disj::ConstraintData{T}, method::Hull) where {T<:Disjunction}
    disj_vrefs = _get_disjunction_variables(model, disj)
    _update_variable_bounds.(disj_vrefs)
    hull = _Hull(method.value, disj_vrefs)
    for d in disj.constraint.disjuncts #reformulate each disjunct
        _disaggregate_variables(model, d, disj_vrefs, hull) #disaggregate variables for that disjunct
        _reformulate_disjunct(model, d, hull)
    end
    for vref in disj_vrefs #create sum constraint for disaggregated variables
        _aggregate_variable(model, vref, hull)
    end
end

# individual disjuncts
function _reformulate_disjunct(model::JuMP.Model, ind_idx::LogicalVariableIndex, method::AbstractReformulationMethod)
    #reformulate each constraint and add to the model
    bv_idx = _indicator_to_binary(model)[ind_idx]
    bvref = JuMP.VariableRef(model, bv_idx)
    for cidx in _indicator_to_constraints(model)[ind_idx]
        cdata = _disjunct_constraints(model)[cidx]
        _reformulate_disjunct_constraint(model, cdata.constraint, bvref, method)
    end
end

# BigM: individual disjunct constraints
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.LessThan}
    M = _get_M_value(method, con.func, con.set)
    new_func = JuMP.@expression(model, con.func - M*(1-bvref))
    reform_con = JuMP.add_constraint(model, 
        JuMP.build_constraint(error, new_func, con.set)
    )
    push!(_reformulation_constraints(model), 
        (JuMP.index(reform_con), JuMP.ScalarShape())
    )
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.Nonpositives, R}
    M = JuMP.@expression(model, [i=1:con.set.dimension],
        _get_M_value(method, con.func[i], con.set)
    )
    new_func = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] - M[i]*(1-bvref)
    )
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func, con.set)
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.VectorShape()))
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM,
) where {T, S <: _MOI.GreaterThan}
    M = _get_M_value(method, con.func, con.set)
    new_func = JuMP.@expression(model, con.func + M*(1-bvref))
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func, con.set)
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.ScalarShape()))
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef,
    method::BigM,
) where {T, S <: _MOI.Nonnegatives, R}
    M = JuMP.@expression(model, [i=1:con.set.dimension],
        _get_M_value(method, con.func[i], con.set)
    )
    new_func = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] + M[i]*(1-bvref)
    )
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func, con.set)
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.VectorShape()))
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: Union{_MOI.Interval, _MOI.EqualTo}}
    M = _get_M_value(method, con.func, con.set)
    new_func_gt = JuMP.@expression(model, con.func + M[1]*(1-bvref))
    new_func_lt = JuMP.@expression(model, con.func - M[2]*(1-bvref))
    set_values = _set_values(con.set)
    reform_con_gt = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func_gt, _MOI.GreaterThan(set_values[1]))
    )
    reform_con_lt = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func_lt, _MOI.LessThan(set_values[2]))
    )
    push!(_reformulation_constraints(model), 
        (JuMP.index(reform_con_gt), JuMP.ScalarShape()), 
        (JuMP.index(reform_con_lt), JuMP.ScalarShape())
    )
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef,
    method::BigM
) where {T, S <: _MOI.Zeros, R}
    M = JuMP.@expression(model, [i=1:con.set.dimension],
        _get_M_value(method, con.func[i], con.set)
    )
    new_func_nn = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] + M[i][1]*(1-bvref)
    )
    new_func_np = JuMP.@expression(model, [i=1:con.set.dimension], 
        con.func[i] - M[i][2]*(1-bvref)
    )
    reform_con_nn = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func_nn, _MOI.Nonnegatives(con.set.dimension))
    )
    reforn_con_np = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func_np, _MOI.Nonpositives(con.set.dimension))
    )
    push!(_reformulation_constraints(model), 
        (JuMP.index(reform_con_nn), JuMP.VectorShape()), 
        (JuMP.index(reform_con_np), JuMP.VectorShape())
    )
end

# Hull: individual disjunct constraints
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef, 
    method::_Hull
) where {T <: Union{JuMP.AffExpr, JuMP.QuadExpr}, S <: Union{_MOI.LessThan, _MOI.GreaterThan, _MOI.EqualTo}}
    new_func = _disaggregate_expression(model, con.func, bvref, method)
    set_value = _set_value(con.set)
    JuMP.add_to_expression!(new_func, -set_value*bvref)
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func, S(0))
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.ScalarShape()))
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef, 
    method::_Hull
) where {T <: Union{JuMP.AffExpr, JuMP.QuadExpr}, S <: Union{_MOI.Nonpositives, _MOI.Nonnegatives, _MOI.Zeros}, R}
    new_func = JuMP.@expression(model, [i=1:con.set.dimension],
        _disaggregate_expression(model, con.func[i], bvref, method)
    )
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func, con.set)
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.VectorShape()))
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::_Hull
) where {T <: JuMP.GenericNonlinearExpr, S <: Union{_MOI.LessThan, _MOI.GreaterThan, _MOI.EqualTo}}
    con_func = _disaggregate_nl_expression(model, con.func, bvref, method)
    con_func0 = JuMP.value(v -> 0.0, con.func)
    if isinf(con_func0)
        error("Operator `$(con.func.head)` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    ϵ = method.value
    set_value = _set_value(con.set)
    new_func = JuMP.@expression(model, ((1-ϵ)*bvref+ϵ)*con_func - ϵ*(1-bvref)*con_func0 - set_value*bvref)
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func, S(0))
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.ScalarShape()))
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.VectorConstraint{T, S, R}, 
    bvref::JuMP.VariableRef,
    method::_Hull
) where {T <: JuMP.GenericNonlinearExpr, S <: Union{_MOI.Nonpositives, _MOI.Nonnegatives, _MOI.Zeros}, R}
    con_func = JuMP.@expression(model, [i=1:con.set.dimension],
        _disaggregate_nl_expression(model, con.func[i], bvref, method)
    )
    con_func0 = JuMP.value.(v -> 0.0, con.func)
    if any(isinf.(con_func0))
        error("At least of of the operators `$([func.head for func in con.func])` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    ϵ = method.value
    new_func = JuMP.@expression(model, [i=1:con.set.dimension], 
        ((1-ϵ)*bvref+ϵ)*con_func[i] - ϵ*(1-bvref)*con_func0[i]
    )
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func, con.set)
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.VectorShape()))
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::_Hull
) where {T <: Union{JuMP.AffExpr, JuMP.QuadExpr}, S <: _MOI.Interval}
    new_func = _disaggregate_expression(model, con.func, bvref, method)
    new_func_gt = JuMP.@expression(model, new_func - con.set.lower*bvref)
    new_func_lt = JuMP.@expression(model, new_func - con.set.upper*bvref)
    reform_con_gt = JuMP.add_constraint(model, 
        JuMP.build_constraint(error, new_func_gt, _MOI.GreaterThan(0))
    )
    reform_con_lt = JuMP.add_constraint(model, 
        JuMP.build_constraint(error, new_func_lt, _MOI.LessThan(0))
    )
    push!(_reformulation_constraints(model), 
        (JuMP.index(reform_con_gt), JuMP.ScalarShape()), 
        (JuMP.index(reform_con_lt), JuMP.ScalarShape())
    )
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model, 
    con::JuMP.ScalarConstraint{T, S}, 
    bvref::JuMP.VariableRef,
    method::_Hull
) where {T <: JuMP.GenericNonlinearExpr, S <: _MOI.Interval}
    con_func = _disaggregate_nl_expression(model, con.func, bvref, method)
    con_func0 = JuMP.value(v -> 0.0, con.func)
    if isinf(con_func0)
        error("Operator `$(con.func.head)` is not defined at 0, causing the perspective function on the Hull reformulation to fail.")
    end
    ϵ = method.value
    new_func = JuMP.@expression(model, ((1-ϵ)*bvref+ϵ) * con_func - ϵ*(1-bvref)*con_func0)
    new_func_gt = JuMP.@expression(model, new_func - con.set.lower*bvref)
    new_func_lt = JuMP.@expression(model, new_func - con.set.upper*bvref)
    reform_con_gt = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func_gt, _MOI.GreaterThan(0))
    )
    reform_con_lt = JuMP.add_constraint(model,
        JuMP.build_constraint(error, new_func_lt, _MOI.LessThan(0))
    )
    push!(_reformulation_constraints(model), 
        (JuMP.index(reform_con_gt), JuMP.ScalarShape()), 
        (JuMP.index(reform_con_lt), JuMP.ScalarShape())
    )
end

# Indicator: individual disjunct constraints
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

# define fallbacks for other constraint types
function _reformulate_disjunct_constraint(
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
    bvrefs = _indicator_to_binary_ref.(lvrefs)
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, JuMP.@expression(model, sum(bvrefs)), _MOI.GreaterThan(val))
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.ScalarShape()))
end
function _reformulate_selector(model::JuMP.Model, ::MOIAtMost, val::Number, lvrefs::Vector{LogicalVariableRef})
    bvrefs = _indicator_to_binary_ref.(lvrefs)
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, JuMP.@expression(model, sum(bvrefs)), _MOI.LessThan(val))
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.ScalarShape()))
end
function _reformulate_selector(model::JuMP.Model, ::MOIExactly, val::Number, lvrefs::Vector{LogicalVariableRef})
    bvrefs = _indicator_to_binary_ref.(lvrefs)
    reform_con = JuMP.add_constraint(model,
        JuMP.build_constraint(error, JuMP.@expression(model, sum(bvrefs)), _MOI.EqualTo(val))
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.ScalarShape()))
end
function _reformulate_selector(model::JuMP.Model, ::MOIAtLeast, lvref::LogicalVariableRef, lvrefs::Vector{LogicalVariableRef})
    bvref = _indicator_to_binary_ref(lvref)
    bvrefs = Vector{Any}(_indicator_to_binary_ref.(lvrefs))
    reform_con = JuMP.add_constraint(model,
        build_constraint(error, JuMP.@expression(model, sum(bvrefs) - bvref), _MOI.GreaterThan(0))
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.ScalarShape()))
end
function _reformulate_selector(model::JuMP.Model, ::MOIAtMost, lvref::LogicalVariableRef, lvrefs::Vector{LogicalVariableRef})
    bvref = _indicator_to_binary_ref(lvref)
    bvrefs = Vector{Any}(_indicator_to_binary_ref.(lvrefs))
    reform_con = JuMP.add_constraint(model,
        build_constraint(error, JuMP.@expression(model, sum(bvrefs) - bvref), _MOI.LessThan(0))
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.ScalarShape()))
end
function _reformulate_selector(model::JuMP.Model, ::MOIExactly, lvref::LogicalVariableRef, lvrefs::Vector{LogicalVariableRef})
    bvref = _indicator_to_binary_ref(lvref)
    bvrefs = Vector{Any}(_indicator_to_binary_ref.(lvrefs))
    reform_con = JuMP.add_constraint(model,
        build_constraint(error, JuMP.@expression(model, sum(bvrefs) - bvref), _MOI.EqualTo(0))
    )
    push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.ScalarShape()))
end

function _reformulate_proposition(model::JuMP.Model, lexpr::_LogicalExpr)
    expr = _to_cnf(lexpr)
    if expr.head == :∧
        for arg in expr.args
            _add_proposition(model, arg)
        end
    elseif expr.head == :∨ && all(_isa_literal.(expr.args))
        _add_proposition(model, expr)
    else
        error("Expression was not converted to proper Conjunctive Normal Form:\n$expr")
    end
end

_isa_literal(v::LogicalVariableRef) = true
_isa_literal(v::_LogicalExpr) = (v.head == :¬) && (length(v.args) == 1) && _isa_literal(v.args[1])
_isa_literal(v) = false

function _add_proposition(model::JuMP.Model, arg::Union{LogicalVariableRef,_LogicalExpr})
    func = _reformulate_clause(model, arg)
    if !isempty(func.terms) && !all(iszero.(values(func.terms)))
        con = JuMP.build_constraint(error, func, _MOI.GreaterThan(1))
        reform_con = JuMP.add_constraint(model, con)
        push!(_reformulation_constraints(model), (JuMP.index(reform_con), JuMP.ScalarShape()))
    end
    return
end

function _reformulate_clause(model::JuMP.Model, lvref::LogicalVariableRef)
    func = 1 * _indicator_to_binary_ref(lvref)
    return func
end

function _reformulate_clause(model::JuMP.Model, lexpr::_LogicalExpr)
    func = JuMP.AffExpr() #initialize func expression
    if _isa_literal(lexpr)
        func += (1 - _reformulate_clause(model, lexpr.args[1]))
    elseif lexpr.head == :∨
        for literal in lexpr.args
            if literal isa LogicalVariableRef
                func += _reformulate_clause(model, literal)
            elseif _isa_literal(literal)
                func += (1 - _reformulate_clause(model, literal.args[1]))
            else
                error("Expression was not converted to proper Conjunctive Normal Form:\n$literal is not a literal.")
            end
        end
    else
        error("Expression was not converted to proper Conjunctive Normal Form:\n$lexpr.")
    end
    
    return func
end