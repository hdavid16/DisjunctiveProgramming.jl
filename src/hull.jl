################################################################################
#                              VARIABLE DISAGGREGATION
################################################################################
function _update_variable_bounds(vref::JuMP.VariableRef)
    model, idx = vref.model, vref.index
    if (vref in keys(_variable_bounds(model))) || JuMP.is_binary(vref) #skip if binary or if bounds already stored
        return
    elseif !JuMP.has_lower_bound(vref) || !JuMP.has_upper_bound(vref)
        error("Variable $vref must have both lower and upper bounds defined when using the Hull reformulation.")
    else
        lb = min(0, JuMP.lower_bound(vref))
        ub = max(0, JuMP.upper_bound(vref))
        _variable_bounds(model)[idx] = (lb, ub)
    end
end
function _disaggregate_variables(model::JuMP.Model, ind_idx::LogicalVariableIndex, vrefs::Set{JuMP.VariableRef}, disag_vars::_Hull)
    #create disaggregated variables for that disjunct
    for vref in vrefs
        JuMP.is_binary(vref) && continue #skip binary variables
        _disaggregate_variable(model, ind_idx, vref, disag_vars) #create disaggregated var for that disjunct
    end
end
function _disaggregate_variable(model::JuMP.Model, ind_idx::LogicalVariableIndex, vref::JuMP.VariableRef, disag_vars::_Hull)
    #create disaggregated (disjunct) vref
    v_idx = JuMP.index(vref) #variable
    lb, ub = _variable_bounds(model)[v_idx]
    dvar = JuMP.ScalarVariable(_variable_info(lower_bound = lb, upper_bound = ub))
    lvref = LogicalVariableRef(model, ind_idx)
    dvref = JuMP.add_variable(model, dvar, "$(vref)_$(lvref)")
    dv_idx = JuMP.index(dvref) #disaggregated (disjunct) variable
    push!(_reformulation_variables(model), dv_idx)
    #get binary indicator variable
    bv_idx = _indicator_to_binary(model)[ind_idx]
    bvref = JuMP.VariableRef(model, bv_idx)
    #temp storage
    push!(disag_vars.disjunction[vref], dvref)
    disag_vars.disjunct[vref, bvref] = dvref
    #create bounding constraints
    dvname = JuMP.name(dvref)
    new_con_lb_ref = JuMP.add_constraint(model,
        JuMP.build_constraint(error, lb*bvref - dvref, _MOI.LessThan(0)),
        "$dvname lower bounding"
    )
    new_con_ub_ref = JuMP.add_constraint(model,
        JuMP.build_constraint(error, dvref - ub*bvref, _MOI.LessThan(0)),
        "$dvname upper bounding"
    )
    push!(_reformulation_constraints(model), 
        (JuMP.index(new_con_lb_ref), JuMP.ScalarShape()), 
        (JuMP.index(new_con_ub_ref), JuMP.ScalarShape())
    )

    return dvref
end

function _aggregate_variable(model::JuMP.Model, vref::JuMP.VariableRef, disag_vars::_Hull)
    JuMP.is_binary(vref) && return #skip binary variables
    con_expr = JuMP.@expression(model, -vref + sum(disag_vars.disjunction[vref]))
    con = JuMP.build_constraint(error, con_expr, _MOI.EqualTo(0))
    con_ref = JuMP.add_constraint(model, con, "$vref aggregation")
    push!(_reformulation_constraints(model), 
        (JuMP.index(con_ref), JuMP.ScalarShape())
    )

    return con_ref
end

################################################################################
#                              DISAGGREGATE CONSTRAINT
################################################################################
# affine expression
function _disaggregate_expression(model::JuMP.Model, aff::JuMP.AffExpr, bvref::JuMP.VariableRef, method::_Hull)
    new_expr = zero(JuMP.AffExpr)
    for (vref, coeff) in aff.terms
        if JuMP.is_binary(vref) #keep any binary terms unchanged
            JuMP.add_to_expression!(new_expr, coeff*vref)
        else #replace other vars with disaggregated form
            dvref = method.disjunct[vref, bvref]
            JuMP.add_to_expression!(new_expr, coeff*dvref)
        end
    end
    JuMP.add_to_expression!(new_expr, aff.constant*bvref) #multiply constant by binary
    return new_expr
end
# quadratic expression
# TODO review what happens when there are bilinear terms with binary variables involved since these are not being disaggregated (e.g., complementarity constraints; though likely irrelevant)...
function _disaggregate_expression(model::JuMP.Model, quad::JuMP.QuadExpr, bvref::JuMP.VariableRef, method::_Hull)
    #get affine part
    new_expr = zero(JuMP.NonlinearExpr)
     # TODO update when JuMP supports add_to_expression! for NonlinearExpr
    JuMP._MA.add_mul!!(new_expr, _disaggregate_expression(model, quad.aff, bvref, method))
    #get nonlinear part
    ϵ = method.value
    for (pair, coeff) in quad.terms
        da_ref = method.disjunct[pair.a, bvref]
        db_ref = method.disjunct[pair.b, bvref]
         # TODO update when JuMP supports add_to_expression! for NonlinearExpr
         JuMP._MA.add_mul!!(new_expr, coeff * da_ref * db_ref / ((1-ϵ)*bvref+ϵ))
    end

    return new_expr
end
# constant in NonlinearExpr
function _disaggregate_nl_expression(model::JuMP.Model, c::Number, ::JuMP.VariableRef, ::_Hull)
    return c
end
# variable in NonlinearExpr
function _disaggregate_nl_expression(model::JuMP.Model, vref::JuMP.VariableRef, bvref::JuMP.VariableRef, method::_Hull)
    ϵ = method.value
    dvref = method.disjunct[vref, bvref]
    new_var = dvref / ((1-ϵ)*bvref+ϵ)
    return new_var
end
# affine expression in NonlinearExpr
function _disaggregate_nl_expression(model::JuMP.Model, aff::JuMP.AffExpr, bvref::JuMP.VariableRef, method::_Hull)
    new_expr = zero(JuMP.NonlinearExpr)
     # TODO update when JuMP supports add_to_expression! for NonlinearExpr
     JuMP._MA.add_mul!!(new_expr, JuMP.AffExpr(aff.constant))
    ϵ = method.value
    for (vref, coeff) in aff.terms
        if JuMP.is_binary(vref) #keep any binary variables undisaggregated
            dvref = vref
        else #replace other vars with disaggregated form
            dvref = method.disjunct[vref, bvref]
        end
         # TODO update when JuMP supports add_to_expression! for NonlinearExpr
         JuMP._MA.add_mul!!(new_expr, coeff * dvref / ((1-ϵ)*bvref+ϵ))
    end
    return new_expr
end
# quadratic expression in NonlinearExpr
function _disaggregate_nl_expression(model::JuMP.Model, quad::JuMP.QuadExpr, bvref::JuMP.VariableRef, method::_Hull)
    #get affine part
    new_expr = _disaggregate_nl_expression(model, quad.aff, bvref, method)
    #get quadratic part
    ϵ = method.value
    for (pair, coeff) in quad.terms
        da_ref = method.disjunct[pair.a, bvref]
        db_ref = method.disjunct[pair.b, bvref]
         # TODO update when JuMP supports add_to_expression! for NonlinearExpr
         JuMP._MA.add_mul!!(new_expr, coeff * da_ref * db_ref / ((1-ϵ)*bvref+ϵ)^2)
    end
    return new_expr
end
# nonlinear expression in NonlinearExpr
function _disaggregate_nl_expression(model::JuMP.Model, nlp::JuMP.NonlinearExpr, bvref::JuMP.VariableRef, method::_Hull)
    new_args = Vector{Any}(undef, length(nlp.args))
    for (i,arg) in enumerate(nlp.args)
        new_args[i] = _disaggregate_nl_expression(model, arg, bvref, method)
    end
    new_expr = JuMP.NonlinearExpr(nlp.head, new_args)
    return new_expr
end