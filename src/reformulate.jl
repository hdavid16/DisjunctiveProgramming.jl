"""
    reformulate_disjunction(m::Model, disj...; bin_var, reformulation, param)

Reformulate disjunction on a JuMP model.

    reformulate_disjunction(disj, bin_var, reformulation, param)

Reformulate disjunction.
"""
function reformulate_disjunction(m::Model, disj...; bin_var, reformulation, param)
    #placeholder to store new constraints (reformulated)
    @assert !in(bin_var, keys(m.ext)) "$bin_var cannot be used as the indicator variable for the disjunction because it has already been used on another disjunction."
    m.ext[bin_var] = [] #store constraints associated with indicator variable
    #check disj
    disj = [check_constraint!(m, constr) for constr in disj]#check_disjunction!(m, disj)
    #run reformulation
    if reformulation == :hull
        if !in(:disaggregated_variables, keys(m.ext))
            m.ext[:disaggregated_variables] = Set([]) #record disaggregated variables to avoid duplicating disaggregation (nested disjunctions)
        end
        disaggregate_variables(m, disj, bin_var)
    end
    reformulate_disjunction(m, disj, bin_var, reformulation, param)
end
function reformulate_disjunction(m::Model, disj, bin_var, reformulation, param)
    for (i,constr) in enumerate(disj)
        reformulate_constraint(constr, bin_var, reformulation, param, i)
    end
    update_constraint_list!(disj, m.ext[bin_var])
    # NOTE: Next line files when a disjunct has a single ConstraintRef since iterate is not defined for this type
    # push!(m.ext[bin_var], Iterators.flatten(filter(is_constraint, disj))...)
end

"""
    reformulate_constraint(constr::Tuple, bin_var, reformulation, param, i)

Reformulate a Tuple of constraints.

    reformulate_constraint(constr::AbstractArray{<:ConstraintRef}, bin_var, reformulation, param, i, j = missing)

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
reformulate_constraint(args...) = nothing
