"""

"""
function _reformulate(model::JuMP.Model, method::AbstractReformulationMethod)
    for (_, disj) in disjunctions(model)
        _reformulate(model, method, disj)
    end
end

"""

"""
function _reformulate(model::JuMP.Model, method::BigM, disj::DisjunctiveConstraintData, args...)
    for d in disj.constraint.disjuncts
        #create binary variable for logic variable (indicator)
        bvar = JuMP.@variable(model, 
            base_name = string(d.indicator), 
            binary = true,
        )
        _reformulate(model, method, d, bvar)
    end
end

"""

"""
function _reformulate(model::JuMP.Model, method::Hull, disj::DisjunctiveConstraintData, args...)
    _disaggregate_variables(model, disj)
    for d in disj.constraint.disjuncts
        _reformulate(model, method, d, d.indicator)
    end
end

"""

"""
function _reformulate(model::JuMP.Model, method::AbstractReformulationMethod, d::Disjunct, args...)
    #reformulate each constraint and add to the model
    for con in d.constraints
        _reformulate(model, method, con, args...)
    end
end

"""

"""
function _reformulate(model::JuMP.Model, method::AbstractReformulationMethod, con::JuMP.AbstractArray{<:JuMP.AbstractConstraint}, args...)
    for c in con
        _reformulate(model, method, c, args...)
    end
end

"""

"""
function _reformulate(
    model::JuMP.Model, 
    method::BigM,
    con::JuMP.ScalarConstraint{T, <: _MOI.LessThan}, 
    bvar::JuMP.VariableRef,
    ) where {T}
    #TODO: need to pass _error to build_constraint
    M = _calculate_tight_M(con)
    if isinf(M)
        M = method.value
    end
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, 
            con.func - M*(1-bvar), 
            con.set
        ),
    )
end
function _reformulate(
    model::JuMP.Model, 
    method::BigM,
    con::JuMP.ScalarConstraint{T, <: _MOI.GreaterThan}, 
    bvar::JuMP.VariableRef,
    ) where {T}
    #TODO: need to pass _error to build_constraint
    M = _calculate_tight_M(con)
    if isinf(M)
        M = method.value
    end
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, 
            con.func + M*(1-bvar), 
            con.set
        ),
    )
end
function _reformulate(
    model::JuMP.Model, 
    method::BigM,
    con::JuMP.ScalarConstraint{T, <: _MOI.Interval}, 
    bvar::JuMP.VariableRef,
    ) where {T}
    #TODO: need to pass _error to build_constraint
    M = _calculate_tight_M(con)
    if isinf(first(M))
        M[1] = method.value
    end
    if isinf(last(M))
        M[2] = method.value
    end
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, 
            con.func + first(M)*(1-bvar), 
            _MOI.GreaterThan(con.set.lower)
        ),
    )
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, 
            con.func - last(M)*(1-bvar), 
            _MOI.LessThan(con.set.upper)
        ),
    )
end
function _reformulate(
    model::JuMP.Model, 
    method::BigM,
    con::JuMP.ScalarConstraint{T, <: _MOI.EqualTo}, 
    bvar::JuMP.VariableRef,
    ) where {T}
    #TODO: need to pass _error to build_constraint
    M = _calculate_tight_M(con)
    if isinf(first(M))
        M[1] = method.value
    end
    if isinf(last(M))
        M[2] = method.value
    end
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, 
            con.func + first(M)*(1-bvar), 
            _MOI.GreaterThan(con.set.value)
        ),
    )
    JuMP.add_constraint(model,
        JuMP.build_constraint(error, 
            con.func - last(M)*(1-bvar), 
            _MOI.LessThan(con.set.value)
        ),
    )
end

"""

"""
function _reformulate(
    model::JuMP.Model, 
    method::Hull,
    con::JuMP.ScalarConstraint{JuMP.AffExpr, <: _MOI.LessThan}, 
    lvar::LogicalVariableRef
    )
    #TODO: need to pass _error to build_constraint
    con_func = _disaggregated_constraint(model, con, lvar)
    bvar = gdp_data(model).indicator_variables[Symbol(lvar,"_Bin")]
    con_func.terms[bvar] = -con.set.upper

    JuMP.add_constraint(model,
        JuMP.build_constraint(error,
            con_func,
            _MOI.LessThan(0)
        )
    )
end
function _reformulate(
    model::JuMP.Model, 
    method::Hull,
    con::JuMP.ScalarConstraint{JuMP.AffExpr, <: _MOI.GreaterThan}, 
    lvar::LogicalVariableRef
    )
    #TODO: need to pass _error to build_constraint
    con_func = _disaggregated_constraint(model, con, lvar)
    bvar = gdp_data(model).indicator_variables[Symbol(lvar,"_Bin")]
    con_func.terms[bvar] = -con.set.lower
    
    JuMP.add_constraint(model,
        JuMP.build_constraint(error,
            con_func,
            _MOI.GreaterThan(0)
        )
    )
end
function _reformulate(
    model::JuMP.Model, 
    method::Hull,
    con::JuMP.ScalarConstraint{JuMP.AffExpr, <: _MOI.Interval}, 
    lvar::LogicalVariableRef
    )
    #TODO: need to pass _error to build_constraint
    con_func_GreaterThan = _disaggregated_constraint(model, con, lvar)
    con_func_LessThan = copy(con_func_GreaterThan)
    bvar = gdp_data(model).indicator_variables[Symbol(lvar,"_Bin")]
    con_func_GreaterThan.terms[bvar] = -con.set.lower
    con_func_LessThan.terms[bvar] = -con.set.upper
    
    JuMP.add_constraint(model,
        JuMP.build_constraint(error,
            con_func_GreaterThan,
            _MOI.GreaterThan(0)
        )
    )
    JuMP.add_constraint(model,
        JuMP.build_constraint(error,
            con_func_LessThan,
            _MOI.LessThan(0)
        )
    )
end
function _reformulate(
    model::JuMP.Model, 
    method::Hull,
    con::JuMP.ScalarConstraint{JuMP.AffExpr, <: _MOI.EqualTo}, 
    lvar::LogicalVariableRef
    )
    #TODO: need to pass _error to build_constraint
    con_func = _disaggregated_constraint(model, con, lvar)
    bvar = gdp_data(model).indicator_variables[Symbol(lvar,"_Bin")]
    con_func.terms[bvar] = -con.set.value

    JuMP.add_constraint(model,
        JuMP.build_constraint(error,
            con_func,
            _MOI.EqualTo(0)
        )
    )
end
# define fallbacks for other constraint types
function _reformulate(
    model::JuMP.Model, 
    method::AbstractReformulationMethod, 
    con::JuMP.AbstractConstraint, 
    lvar::LogicalVariableRef
)
    error("$method reformulation for constraint $con is not supported yet.")
end