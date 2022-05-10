"""
    reformulate_disjunction(m::Model, disj...; bin_var, reformulation, param)

Reformulate disjunction on a JuMP model.

    reformulate_disjunction(disj, bin_var, reformulation, param)

Reformulate disjunction.
"""
function reformulate_disjunction(m::Model, disj...; bin_var, reformulation, param)
    #check disj
    disj = [check_constraint!(m, constr) for constr in disj]#check_disjunction!(m, disj)
    #get original variable refs and variable names
    vars = setdiff(all_variables(m), m[bin_var])
    var_names = unique(Symbol.([split("$var","[")[1] for var in vars]))
    if !in(:gdp_variable_refs, keys(object_dictionary(m)))
        @expression(m, gdp_variable_refs, vars)
    end
    if !in(:gdp_variable_names, keys(object_dictionary(m)))
        @expression(m, gdp_variable_names, var_names)
    end
    #run reformulation
    if reformulation == :hull
        disaggregate_variables(m, disj, bin_var)
        sum_disaggregated_variables(m, disj, bin_var)
    end
    reformulate_disjunction(disj, bin_var, reformulation, param)

    #show new constraints as a Dict
    new_constraints = Dict{Symbol,Any}(
        Symbol(bin_var,"[$i]") => disj[i] for i in eachindex(disj)
    )
    new_constraints[Symbol(bin_var,"_XOR")] = constraint_by_name(m, "XOR(disj_$bin_var)")
    if reformulation == :hull
        for var in m[:gdp_variable_refs]
            agg_con_name = "$(var)_$(bin_var)_aggregation"
            new_constraints[Symbol(agg_con_name)] = constraint_by_name(m, agg_con_name)
        end
    end
    return new_constraints

    #remove model.optimize_hook ?

    # return m[bin_var]
end
function reformulate_disjunction(disj, bin_var, reformulation, param)
    for (i,constr) in enumerate(disj)
        reformulate_constraint(constr, bin_var, reformulation, param, i)
    end
end

"""
    reformulate_constraint(constr::Tuple, bin_var, reformulation, param, i)

Reformulate a Tuple of constraints.

    reformulate_constraint(constr::AbstractArray, bin_var, reformulation, param, i, j = missing)

Reformulate a block of constraints.

    reformulate_constraint(constr::ConstraintRef, bin_var, reformulation, param, i, j = missing, k = missing)

Reformulate a constraint.
"""
function reformulate_constraint(constr::Tuple, bin_var, reformulation, param, i)
    for (j,constr_j) in enumerate(constr)
        reformulate_constraint(constr_j, bin_var, reformulation, param, i, j)
    end
end
function reformulate_constraint(constr::AbstractArray, bin_var, reformulation, param, i, j = missing)
    for k in eachindex(constr)
        reformulate_constraint(constr[k], bin_var, reformulation, param, i, j, k)
    end
end
function reformulate_constraint(constr::ConstraintRef, bin_var, reformulation, param, i, j = missing, k = missing)
    if reformulation == :big_m
        big_m_reformulation!(constr, bin_var, param, i, j, k)
    elseif reformulation == :hull
        hull_reformulation!(constr, bin_var, param, i, j, k)
    end
end
