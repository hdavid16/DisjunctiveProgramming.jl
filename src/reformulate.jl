function reformulate_disjunction(m, disj, bin_var, reformulation, param)
    #check disj
    disj = check_disjunction(m, disj)
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
    if reformulation == :CHR
        disaggregate_variables(m, disj, bin_var)
        sum_disaggregated_variables(m, disj, bin_var)
    end
    reformulate(m, disj, bin_var, reformulation, param)

    # return m[bin_var]
end

function reformulate(m, disj, bin_var, reformulation, param)
    for (i,constr) in enumerate(disj)
        if constr isa Tuple #NOTE: Make it so that it must be bundled in a Tuple (not Array), to avoid confusing it with a Variable Array
            for (j,constr_j) in enumerate(constr)
                apply_reformulation(m, constr_j, bin_var, reformulation, param, i, j)
            end
        elseif constr isa Union{ConstraintRef, Array, Containers.DenseAxisArray, Containers.SparseAxisArray}
            apply_reformulation(m, constr, bin_var, reformulation, param, i)
        end
    end
end

function apply_reformulation(m, constr, bin_var, reformulation, param, i, j = missing)
    param = get_reform_param(param, i, j) #M or eps
    if constr isa ConstraintRef
        call_reformulation(reformulation, m, constr, bin_var, i, missing, param)
    elseif constr isa Union{Array, Containers.DenseAxisArray, Containers.SparseAxisArray}
        for k in eachindex(constr)
            call_reformulation(reformulation, m, constr, bin_var, i, k, param)
        end
    end
end

function call_reformulation(reformulation, m, constr, bin_var, i, k, param)
    if reformulation == :BMR
        BMR!(m, constr, bin_var, i, k, param)
    elseif reformulation == :CHR
        CHR!(m, constr, bin_var, i, k, param)
    end
end

function get_reform_param(param, i, j)
    if param isa Number || ismissing(param)
        param = param
    elseif param isa Vector || param isa Tuple
        if param[i] isa Number
            param = param[i]
        elseif param[i] isa Vector || param[i] isa Tuple
            @assert !ismissing(j) "If constraint specific param values are provided, there must be more than one constraint in disjunct $i."
            @assert j <= length(param[i]) "If constraint specific param values are provided, a value must be provided for each constraint in disjunct $i."
            param = param[i][j]
        else
            error("Invalid param parameter provided for disjunct $i.")
        end
    else
        error("Invalid param parameter provided for disjunct $i.")
    end
end
