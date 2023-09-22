################################################################################
#                              LOGICAL VARIABLES
################################################################################
"""
    JuMP.build_variable(_error::Function, info::JuMP.VariableInfo, 
                        ::Type{LogicalVariable})::LogicalVariable

Extend `JuMP.build_variable` to work with logical variables. This in 
combination with `JuMP.add_variable` enables the use of 
`@variable(model, [var_expr], LogicalVariable)`.
"""
function JuMP.build_variable(
    _error::Function, 
    info::JuMP.VariableInfo, 
    tag::Type{LogicalVariable};
    kwargs...
    )
    # check for invalid input
    for (k, _) in kwargs
        _error("Unsupported keyword argument `$k`.")
    end
    if info.has_lb || info.has_ub
        _error("Logical variables cannot have bounds.")
    elseif info.integer
        _error("Logical variables cannot be integer valued.")
    elseif info.has_fix && !isone(info.fix) && !iszero(info.fix)
        _error("Invalid fix value, must be 0 or 1.")
    elseif info.has_start && !isone(info.start) && !iszero(info.start)
        _error("Invalid start value, must be 0 or 1.")
    end

    # create the variable
    fix = info.has_fix ? Bool(info.fix) : nothing
    start = info.has_start ? Bool(info.start) : nothing
    return LogicalVariable(fix, start)
end

"""
    JuMP.add_variable(model::JuMP.Model, v::LogicalVariable, 
                      name::String = "")::LogicalVariableRef
                
Extend `JuMP.add_variable` for [`LogicalVariable`](@ref)s. This 
helps enable `@variable(model, [var_expr], LogicalVariable)`.
"""
function JuMP.add_variable(
    model::JuMP.Model, 
    v::LogicalVariable, 
    name::String = ""
    )
    is_gdp_model(model) || error("Can only add logical variables to `GDPModel`s.")
    data = LogicalVariableData(v, name)
    idx = _MOIUC.add_item(_logical_variables(model), data)
    _set_ready_to_optimize(model, false)
    return LogicalVariableRef(model, idx)
end

# Base extensions
Base.copy(v::LogicalVariableRef) = v
Base.broadcastable(v::LogicalVariableRef) = Ref(v)
Base.length(v::LogicalVariableRef) = 1
function Base.:(==)(v::LogicalVariableRef, w::LogicalVariableRef)
    return v.model === w.model && v.index == w.index
end

# JuMP extensions
"""
    JuMP.owner_model(vref::LogicalVariableRef)

Return the `GDP model` to which `vref` belongs.
"""
JuMP.owner_model(vref::LogicalVariableRef) = vref.model

"""
    JuMP.index(vref::LogicalVariableRef)

Return the index of logical variable that associated with `vref`.
"""
JuMP.index(vref::LogicalVariableRef) = vref.index

"""
    JuMP.isequal_canonical(v::LogicalVariableRef, w::LogicalVariableRef)

Return `true` if `v` and `w` refer to the same logical variable in the same
`GDP model`.
"""
JuMP.isequal_canonical(v::LogicalVariableRef, w::LogicalVariableRef) = v == w

"""
    JuMP.is_valid(model::JuMP.Model, vref::LogicalVariableRef)

Return `true` if `vref` refers to a valid logical variable in `GDP model`.
"""
function JuMP.is_valid(model::JuMP.Model, vref::LogicalVariableRef)
    return model === JuMP.owner_model(vref)
end

"""
    JuMP.name(vref::LogicalVariableRef)

Get a logical variable's name attribute.
"""
function JuMP.name(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    return data.logical_variables[JuMP.index(vref)].name
end

"""
    JuMP.set_name(vref::LogicalVariableRef, name::String)

Set a logical variable's name attribute.
"""
function JuMP.set_name(vref::LogicalVariableRef, name::String)
    model = JuMP.owner_model(vref)
    data = gdp_data(model)
    data.logical_variables[JuMP.index(vref)].name = name
    _set_ready_to_optimize(model, false)
    return
end

"""
    JuMP.start_value(vref::LogicalVariableRef)

Return the start value of the logical variable `vref`.
"""
function JuMP.start_value(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    return data.logical_variables[JuMP.index(vref)].variable.start_value
end

"""
    JuMP.set_start_value(vref::LogicalVariableRef, value::Union{Nothing, Bool})

Set the start value of the logical variable `vref`.

Pass `nothing` to unset the start value.
"""
function JuMP.set_start_value(
    vref::LogicalVariableRef, 
    value::Union{Nothing, Bool}
    )
    model = JuMP.owner_model(vref)
    data = gdp_data(model)
    var = data.logical_variables[JuMP.index(vref)].variable
    new_var = LogicalVariable(var.fix_value, value)
    data.logical_variables[JuMP.index(vref)].variable = new_var
    _set_ready_to_optimize(model, false)
    return
end
"""
    JuMP.is_fixed(vref::LogicalVariableRef)

Return `true` if `vref` is a fixed variable. If
    `true`, the fixed value can be queried with
    fix_value.
"""
function JuMP.is_fixed(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    return !isnothing(data.logical_variables[JuMP.index(vref)].variable.fix_value)
end

"""
    JuMP.fix_value(vref::LogicalVariableRef)

Return the value to which a logical variable is fixed.
"""
function JuMP.fix_value(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    return data.logical_variables[JuMP.index(vref)].variable.fix_value
end

"""
    JuMP.fix(vref::LogicalVariableRef, value::Bool)

Fix a logical variable to a value. Update the fixing
constraint if one exists, otherwise create a
new one.
"""
function JuMP.fix(vref::LogicalVariableRef, value::Bool)
    model = JuMP.owner_model(vref)
    data = gdp_data(model)
    var = data.logical_variables[JuMP.index(vref)].variable
    new_var = LogicalVariable(value, var.start_value)
    data.logical_variables[JuMP.index(vref)].variable = new_var
    _set_ready_to_optimize(model, false)
    return
end

"""
    JuMP.unfix(vref::LogicalVariableRef)

Delete the fixed value of a logical variable.
"""
function JuMP.unfix(vref::LogicalVariableRef)
    model = JuMP.owner_model(vref)
    data = gdp_data(model)
    var = data.logical_variables[JuMP.index(vref)].variable
    new_var = LogicalVariable(nothing, var.start_value)
    data.logical_variables[JuMP.index(vref)].variable = new_var
    _set_ready_to_optimize(model, false)
    return
end

"""
    JuMP.delete(model::JuMP.Model, vref::LogicalVariableRef)

Delete the logical variable associated with `vref` from the `GDP model`.
"""
function JuMP.delete(model::JuMP.Model, vref::LogicalVariableRef)
    @assert JuMP.is_valid(model, vref) "Variable does not belong to model."
    vidx = JuMP.index(vref)
    dict = _logical_variables(model)
    #delete any disjunct constraints associated with the logical variables in the disjunction
    crefs = _indicator_to_constraints(model)[vref]
    JuMP.delete.(model, crefs)
    delete!(_indicator_to_constraints(model), vref)
    #delete any disjunctions that have the logical variable
    for (didx, ddata) in _disjunctions(model)
        if vref in ddata.constraint.indicators
            setdiff!(ddata.constraint.indicators, [vref])
            JuMP.delete(model, DisjunctionRef(model, didx))
        end
    end
    #delete any logical constraints involving the logical variables
    for (cidx, cdata) in _logical_constraints(model)
        lvars = _get_constraint_variables(model, cdata.constraint)
        if vref in lvars
            JuMP.delete(model, LogicalConstraintRef(model, cidx))
        end
    end
    #delete the logical variable
    delete!(dict, vidx)
    #not ready to optimize
    _set_ready_to_optimize(model, false)
    return 
end

################################################################################
#                              VARIABLE INTERROGATION
################################################################################
function _get_disjunction_variables(model::JuMP.Model, disj::Disjunction)
    vars = Set{JuMP.VariableRef}()
    for lvref in disj.indicators
        for cref in _indicator_to_constraints(model)[lvref]
            con = JuMP.constraint_object(cref)
            _interrogate_variables(v -> push!(vars, v), con)
        end
    end
    return vars
end

function _get_constraint_variables(model::JuMP.Model, con::Union{JuMP.ScalarConstraint, JuMP.VectorConstraint})
    vars = Set{Union{JuMP.VariableRef, LogicalVariableRef}}()
    _interrogate_variables(v -> push!(vars, v), con.func)
    return vars   
end

# Constant
function _interrogate_variables(interrogator::Function, c::Number)
    return
end

# VariableRef/LogicalVariableRef
function _interrogate_variables(interrogator::Function, var::Union{JuMP.VariableRef, LogicalVariableRef})
    interrogator(var)
    return
end

# AffExpr
function _interrogate_variables(interrogator::Function, aff::JuMP.GenericAffExpr)
    for (var, _) in aff.terms
        interrogator(var)
    end
    return
end

# QuadExpr
function _interrogate_variables(interrogator::Function, quad::JuMP.QuadExpr)
    for (pair, _) in quad.terms
        interrogator(pair.a)
        interrogator(pair.b)
    end
    _interrogate_variables(interrogator, quad.aff)
    return
end

# NonlinearExpr and _LogicalExpr (T <: Union{JuMP.VariableRef, LogicalVariableRef})
function _interrogate_variables(interrogator::Function, nlp::JuMP.GenericNonlinearExpr{T}) where {T}
    for arg in nlp.args
        _interrogate_variables(interrogator, arg)
    end
    # TODO avoid recursion. See InfiniteOpt.jl for alternate method that avoids stackoverflow errors with deeply nested expressions:
    # https://github.com/infiniteopt/InfiniteOpt.jl/blob/cb6dd6ae40fe0144b1dd75da0739ea6e305d5357/src/expressions.jl#L520-L534
    return
end

# Constraint
function _interrogate_variables(interrogator::Function, con::Union{JuMP.ScalarConstraint, JuMP.VectorConstraint})
    _interrogate_variables(interrogator, con.func)
end

# AbstractArray
function _interrogate_variables(interrogator::Function, arr::AbstractArray)
    _interrogate_variables.(interrogator, arr)
    return
end

# Set
function _interrogate_variables(interrogator::Function, set::Set)
    _interrogate_variables.(interrogator, set)
    return
end

# Nested disjunction
function _interrogate_variables(interrogator::Function, disj::Disjunction)
    model = JuMP.owner_model(disj.indicators[1])
    dvars = _get_disjunction_variables(model, disj)
    _interrogate_variables(interrogator, dvars)
    return
end

# Fallback
function _interrogate_variables(interrogator::Function, other)
    error("Cannot extract variables from object of type $(typeof(other)).")
end