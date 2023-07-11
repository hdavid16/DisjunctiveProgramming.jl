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
    elseif info.has_start && !isone(info.fix) && !iszero(info.fix)
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
    idx = _MOIUC.add_item(gdp_data(model).logical_variables, data)
    return LogicalVariableRef(model, idx)
end

# Basic base extensions
Base.copy(v::LogicalVariableRef) = v
Base.broadcastable(v::LogicalVariableRef) = Ref(v)
Base.length(v::LogicalVariableRef) = 1

"""

"""
JuMP.owner_model(vref::LogicalVariableRef) = vref.model

"""

"""
JuMP.index(vref::LogicalVariableRef) = vref.index

function Base.:(==)(v::LogicalVariableRef, w::LogicalVariableRef)
    return v.model === w.model && v.index == w.index
end
JuMP.isequal_canonical(v::LogicalVariableRef, w::LogicalVariableRef) = v == w

function Base.getindex(map::JuMP.ReferenceMap, vref::LogicalVariableRef)
    return LogicalVariableRef(map.model, JuMP.index(vref))
end

"""

"""
function JuMP.is_valid(model::JuMP.Model, vref::LogicalVariableRef)
    return model === JuMP.owner_model(vref)
end

"""

"""
function JuMP.name(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    return data.logical_variables[JuMP.index(vref)].name
end

"""

"""
function JuMP.set_name(vref::LogicalVariableRef, name::String)
    data = gdp_data(JuMP.owner_model(vref))
    data.logical_variables[JuMP.index(vref)].name = name
    return
end

"""

"""
function JuMP.start_value(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    return data.logical_variables[JuMP.index(vref)].variable.start
end

"""

"""
function JuMP.set_start_value(
    vref::LogicalVariableRef, 
    value::Union{Nothing, Bool}
    )
    data = gdp_data(JuMP.owner_model(vref))
    var = data.logical_variables[JuMP.index(vref)].variable
    new_var = LogicalVariable(var.fix_value, value)
    data.logical_variables[JuMP.index(vref)].variable = new_var
    return
end

"""

"""
function JuMP.fix_value(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    return data.logical_variables[JuMP.index(vref)].variable.fix_value
end

"""

"""
function JuMP.fix(vref::LogicalVariableRef, value::Bool)
    data = gdp_data(JuMP.owner_model(vref))
    var = data.logical_variables[JuMP.index(vref)].variable
    new_var = LogicalVariable(value, var.start_value)
    data.logical_variables[JuMP.index(vref)].variable = new_var
    return
end

"""

"""
function JuMP.unfix(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    var = data.logical_variables[JuMP.index(vref)].variable
    new_var = LogicalVariable(nothing, var.start_value)
    data.logical_variables[JuMP.index(vref)].variable = new_var
    return
end

"""

"""
function JuMP.delete(model::JuMP.Model, vref::LogicalVariableRef)
    @assert JuMP.is_valid(model, vref) "Variable does not belong to model."
    data = gdp_data(JuMP.owner_model(vref))
    dict = data.logical_variables[JuMP.index(vref)]
    # TODO check if used by a disjunction and/or a proposition
    delete!(dict, index(vref))
    return 
end