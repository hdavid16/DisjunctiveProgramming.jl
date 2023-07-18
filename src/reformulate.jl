"""

"""
function _reformulate(model::JuMP.Model, method::AbstractReformulationMethod)
    for (_, disj) in disjunctions(model)
        _reformulate(model, method, disj)
    end
end

"""

"""
function _reformulate(model::JuMP.Model, method::Union{BigM,Indicator}, disj::DisjunctiveConstraintData)
    ind_var_dict = gdp_data(model).indicator_variables
    for d in disj.constraint.disjuncts
        #create binary variable for logic variable (indicator)
        bvar = JuMP.@variable(model, 
            base_name = string(d.indicator), 
            binary = true,
        )
        ind_var_dict[Symbol(d.indicator, "_Bin")] = bvar
        #reformualte disjunct
        _reformulate(model, method, d, bvar)
    end
end

"""

"""
function _reformulate(model::JuMP.Model, method::Hull, disj::DisjunctiveConstraintData)
    ind_var_dict = gdp_data(model).indicator_variables
    var_bounds_dict = gdp_data(model).variable_bounds
    disj_vars = _get_disjunction_variables(disj)
    sum_disag_vars = Dict(var => JuMP.AffExpr() for var in disj_vars) #initialize sum constraint for disaggregated variables
    _update_variable_bounds!(var_bounds_dict, disj_vars) #update variable bounds dict
    #reformulate each disjunct
    for d in disj.constraint.disjuncts
        #create binary variable for logic variable (indicator)
        bvar = JuMP.@variable(model, 
            base_name = string(d.indicator), 
            binary = true,
        )
        ind_var_dict[Symbol(d.indicator,"_Bin")] = bvar
        #create disaggregated variables for that disjunct
        for var in disj_vars
            JuMP.is_binary(var) && continue #skip binary variables
            #create disaggregated var
            disag_var = _disaggregate_variable(model, d, var, bvar)
            #update aggregation constraint
            JuMP.add_to_expression!(sum_disag_vars[var], 1, disag_var)
        end
        #reformulate disjunct
        _reformulate(model, method, d, bvar)
    end
    #create sum constraint for disaggregated variables
    for var in disj_vars
        JuMP.is_binary(var) && continue #skip binary variables
        JuMP.@constraint(model, var == sum_disag_vars[var])
    end
end

"""

"""
function _reformulate(model::JuMP.Model, method::AbstractReformulationMethod, d::Disjunct, bvar::JuMP.VariableRef)
    #reformulate each constraint and add to the model
    for con in d.constraints
        _reformulate(model, method, con, bvar)
    end
end

"""

"""
function _reformulate(model::JuMP.Model, method::AbstractReformulationMethod, con::JuMP.AbstractArray{T}, args...) where {T <: JuMP.AbstractConstraint}
    for c in con
        _reformulate(model, method, c, args...)
    end
end

"""

"""
function _reformulate(
    model::JuMP.Model, 
    method::BigM,
    con::JuMP.ScalarConstraint{T, S}, 
    bvar::JuMP.VariableRef
) where {T, S <: _MOI.LessThan}
    #TODO: need to pass _error to build_constraint
    M = method.tighten ? _calculate_tight_M(con) : method.value
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
    con::JuMP.ScalarConstraint{T, S}, 
    bvar::JuMP.VariableRef
) where {T, S <: _MOI.GreaterThan}
    #TODO: need to pass _error to build_constraint
    M = method.tighten ? _calculate_tight_M(con) : method.value
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
    con::JuMP.ScalarConstraint{T, S}, 
    bvar::JuMP.VariableRef
) where {T, S <: _MOI.Interval}
    #TODO: need to pass _error to build_constraint
    M = method.tighten ? _calculate_tight_M(con) : (method.value, method.value)
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
    con::JuMP.ScalarConstraint{T, S}, 
    bvar::JuMP.VariableRef
) where {T, S <: _MOI.EqualTo}
    #TODO: need to pass _error to build_constraint
    M = method.tighten ? _calculate_tight_M(con) : (method.value, method.value)
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
    ::Hull,
    con::JuMP.ScalarConstraint{JuMP.AffExpr, S}, 
    bvar::JuMP.VariableRef
) where {S <: _MOI.LessThan}
    #TODO: need to pass _error to build_constraint
    con_func = _disaggregated_constraint(model, con, bvar)
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
    ::Hull,
    con::JuMP.ScalarConstraint{JuMP.AffExpr, S}, 
    bvar::JuMP.VariableRef
) where {S <: _MOI.GreaterThan}
    #TODO: need to pass _error to build_constraint
    con_func = _disaggregated_constraint(model, con, bvar)
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
    ::Hull,
    con::JuMP.ScalarConstraint{JuMP.AffExpr, S}, 
    bvar::JuMP.VariableRef
) where {S <: _MOI.Interval}
    #TODO: need to pass _error to build_constraint
    con_func_GreaterThan = _disaggregated_constraint(model, con, bvar)
    con_func_LessThan = copy(con_func_GreaterThan)
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
    ::Hull,
    con::JuMP.ScalarConstraint{JuMP.AffExpr, S}, 
    bvar::JuMP.VariableRef
    ) where {S <: _MOI.EqualTo}
    #TODO: need to pass _error to build_constraint
    con_func = _disaggregated_constraint(model, con, bvar)
    con_func.terms[bvar] = -con.set.value

    JuMP.add_constraint(model,
        JuMP.build_constraint(error,
            con_func,
            _MOI.EqualTo(0)
        )
    )
end

"""

"""
function _reformulate(
    model::JuMP.Model,
    ::Indicator,
    con::JuMP.ScalarConstraint{JuMP.AffExpr, S},
    bvar::JuMP.VariableRef
) where {S}
    JuMP.add_constraint(model,
        JuMP.build_constraint(error,
            [bvar, con.func],
            _MOI.Indicator{_MOI.ACTIVATE_ON_ONE}(con.set)
        )
    )
end

# define fallbacks for other constraint types
function _reformulate(
    ::JuMP.Model, 
    method::AbstractReformulationMethod, 
    con::JuMP.AbstractConstraint, 
    ::JuMP.VariableRef
)
    error("$method reformulation for constraint $con is not supported yet.")
end