"""

"""
function _get_variables(disj::DisjunctiveConstraintData)
    vars = Set{JuMP.VariableRef}()
    for d in disj.constraint.disjuncts
        union!(vars, _get_variables(d))
    end
    return vars
end
function _get_variables(d::Disjunct)
    vars = Set{JuMP.VariableRef}()
    for con in d.constraints
        union!(vars, _get_variables(con))
    end
    return vars
end
function _get_variables(con::JuMP.AbstractArray{<:JuMP.AbstractConstraint})
    vars = Set{JuMP.VariableRef}()
    for c in con
        union!(vars, _get_variables(c))
    end
    return vars
end
function _get_variables(con::JuMP.ScalarConstraint)
    _get_variables(con.func)
end
function _get_variables(expr::JuMP.AffExpr)
    Set(keys(expr.terms))
end
function _get_variables(expr::JuMP.QuadExpr)
    vars = Set(keys(expr.aff.terms))
    for (pair, _) in expr.terms
        push!(vars, pair.a, pair.b)
    end
    return vars
end

"""

"""
function _update_variable_bounds!(var_bounds_dict::Dict{JuMP.VariableRef, Tuple{Float64, Float64}}, var_set::Set{JuMP.VariableRef})
    for var in var_set
        if (var in keys(var_bounds_dict)) | JuMP.is_binary(var) #skip if binary or if bounds already stored
            continue
        elseif !JuMP.has_lower_bound(var) | !JuMP.has_upper_bound(var)
            error("Variable $var must have a lower and upper bound defined when using the Hull reformulation.")
        else
            lb = min(0, JuMP.lower_bound(var))
            ub = max(0, JuMP.upper_bound(var))
            var_bounds_dict[var] = (lb, ub)
        end
    end
end

"""

"""
function _disaggregate_variable(model::JuMP.Model, d::Disjunct, var::JuMP.VariableRef, bvar::JuMP.VariableRef)
    #create disaggregated var
    lb, ub = gdp_data(model).variable_bounds[var]
    disag_var_name = string(var, "_", d.indicator)
    disag_var = JuMP.@variable(model, 
        base_name = disag_var_name,
        lower_bound = lb,
        upper_bound = ub,
    )
    #store ref to disaggregated variable
    gdp_data(model).disaggregated_variables[Symbol(disag_var_name)] = disag_var
    #create bounding constraints
    JuMP.@constraint(model, lb*bvar - disag_var ≤ 0)
    JuMP.@constraint(model, disag_var - ub*bvar ≤ 0)

    return disag_var
end

"""

"""
function _disaggregated_constraint(model::JuMP.Model, con::JuMP.ScalarConstraint{JuMP.AffExpr,T}, bvar::JuMP.VariableRef) where {T}
    new_con_func = JuMP.AffExpr()
    disag_var_dict = gdp_data(model).disaggregated_variables
    for (var, coeff) in con.func.terms
        JuMP.is_binary(var) && continue #skip binary variables
        disag_var = disag_var_dict[Symbol(var,"_",bvar)]
        new_con_func.terms[disag_var] = coeff
    end

    return new_con_func
end