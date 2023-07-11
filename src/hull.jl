"""

"""
function _get_variables(disj::DisjunctiveConstraintData)
    union([
        _get_variables(d)
        for d in disj.constraint.disjuncts
    ]...)
end
function _get_variables(d::Disjunct)
    union([
        _get_variables(con)
        for con in d.constraints
    ]...)
end
function _get_variables(con::JuMP.AbstractArray{<:JuMP.AbstractConstraint})
    union(_get_variables.(con)...)
end
function _get_variables(con::JuMP.ScalarConstraint)
    _get_variables(con.func)
end
function _get_variables(expr::JuMP.AffExpr)
    collect(keys(expr.terms))
end
function _get_variables(expr::JuMP.QuadExpr)
    vars = collect(keys(expr.aff.terms))
    for (pair, _) in expr.terms
        push!(vars, pair.a, pair.b)
    end
    return union(vars)
end

"""

"""
function _disaggregate_variables(model::JuMP.Model, disj::DisjunctiveConstraintData)
    disj_vars = _get_variables(disj)
    disag_var_dict = gdp_data(model).disaggregated_variables
    ind_var_dict = gdp_data(model).indicator_variables
    for d in disj.constraint.disjuncts
        #create binary variable for logic variable (indicator)
        bvar = JuMP.@variable(model, 
            base_name = string(d.indicator), 
            binary = true, 
        )
        ind_var_dict[Symbol(d.indicator,"_Bin")] = bvar
    end
    for var in disj_vars
        JuMP.is_binary(var) && continue #skip binary variables
        if !JuMP.has_lower_bound(var) | !JuMP.has_upper_bound(var)
            error("Variable $var must have a lower and upper bound defined when using the Hull reformulation.")
        end
        sum_disag_vars = JuMP.AffExpr(0) #sum of disaggregated variables
        for d in disj.constraint.disjuncts
            #create disaggregated var
            lb = min(0, JuMP.lower_bound(var))
            ub = max(0, JuMP.upper_bound(var))
            disag_var_name = string(var,"_",d.indicator)
            disag_var = JuMP.@variable(model, 
                base_name = disag_var_name,
                lower_bound = lb,
                upper_bound = ub,
            )
            disag_var_dict[Symbol(disag_var_name)] = disag_var
            #create bounding constraints
            bvar = ind_var_dict[Symbol(d.indicator,"_Bin")]
            JuMP.@constraint(model, lb*bvar - disag_var ≤ 0)
            JuMP.@constraint(model, disag_var - ub*bvar ≤ 0)
            #update aggregation constraint
            JuMP.add_to_expression!(sum_disag_vars, 1, disag_var)
        end
        JuMP.@constraint(model, var == sum_disag_vars)
    end

end

"""

"""
function _disaggregated_constraint(model::JuMP.Model, con::JuMP.ScalarConstraint{JuMP.AffExpr,T}, lvar::LogicalVariableRef) where {T}
    new_con_func = JuMP.AffExpr()
    disag_var_dict = gdp_data(model).disaggregated_variables
    for (var, coeff) in con.func.terms
        JuMP.is_binary(var) && continue #skip binary variables
        disag_var = disag_var_dict[Symbol(var,"_",lvar)]
        new_con_func.terms[disag_var] = coeff
    end

    return new_con_func
end