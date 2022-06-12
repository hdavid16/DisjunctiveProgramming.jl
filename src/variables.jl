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
    if is_gdp_model(model) 
        error("Can only add logical variables to `GDPModel`s.")
    end
    data = LogicalVariableData(v, name)
    idx = _MOIUC.add_item(gdp_data(model), data)
    return LogicalVariableRef(model, idx)
end

# Basic base extensions
Base.copy(v::LogicalVariableRef) = v
Base.broadcastable(v::LogicalVariableRef) = Ref(v)
Base.length(v::LogicalVariableRef) = 1
