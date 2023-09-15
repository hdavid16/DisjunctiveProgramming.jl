################################################################################
#                              LOGICAL VARIABLES
################################################################################
# helper function to create the variable info used when creating reformulation variables
function _variable_info(;
    binary::Bool=false, 
    lower_bound::Float64=-Inf, upper_bound::Float64=Inf, 
    start_value::Union{Nothing, Bool}=nothing, 
    fix_value::Union{Nothing, Bool}=nothing
)
    JuMP.VariableInfo(
        !isinf(lower_bound), lower_bound, 
        !isinf(upper_bound), upper_bound, 
        !isnothing(fix_value), fix_value, #fix value
        !isnothing(start_value), start_value, #start value
        binary, false #integrality
    )
end

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
function Base.getindex(map::JuMP.ReferenceMap, vref::LogicalVariableRef)
    return LogicalVariableRef(map.model, JuMP.index(vref))
end

# JuMP extensions
JuMP.owner_model(vref::LogicalVariableRef) = vref.model

JuMP.index(vref::LogicalVariableRef) = vref.index

JuMP.isequal_canonical(v::LogicalVariableRef, w::LogicalVariableRef) = v == w

function JuMP.is_valid(model::JuMP.Model, vref::LogicalVariableRef)
    return model === JuMP.owner_model(vref)
end

function JuMP.name(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    return data.logical_variables[JuMP.index(vref)].name
end

function JuMP.set_name(vref::LogicalVariableRef, name::String)
    data = gdp_data(JuMP.owner_model(vref))
    data.logical_variables[JuMP.index(vref)].name = name
    return
end

function JuMP.start_value(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    return data.logical_variables[JuMP.index(vref)].variable.start
end

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

function JuMP.fix_value(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    return data.logical_variables[JuMP.index(vref)].variable.fix_value
end

function JuMP.fix(vref::LogicalVariableRef, value::Bool)
    data = gdp_data(JuMP.owner_model(vref))
    var = data.logical_variables[JuMP.index(vref)].variable
    new_var = LogicalVariable(value, var.start_value)
    data.logical_variables[JuMP.index(vref)].variable = new_var
    return
end

function JuMP.unfix(vref::LogicalVariableRef)
    data = gdp_data(JuMP.owner_model(vref))
    var = data.logical_variables[JuMP.index(vref)].variable
    new_var = LogicalVariable(nothing, var.start_value)
    data.logical_variables[JuMP.index(vref)].variable = new_var
    return
end

function JuMP.delete(model::JuMP.Model, vref::LogicalVariableRef)
    @assert JuMP.is_valid(model, vref) "Variable does not belong to model."
    vidx = JuMP.index(vref)
    dict = _logical_variables(model)
    #delete any disjunct constraints associated with the logical variables in the disjunction
    dcidxs = _indicator_to_constraints(model)[vidx]
    for cidx in dcidxs
        JuMP.delete(model, DisjunctConstraintRef(model, cidx))
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
function _get_disjunction_variables(model::JuMP.Model, disj::ConstraintData{Disjunction})
    vars = Set{JuMP.VariableRef}()
    for ind_idx in disj.constraint.disjuncts
        for cidx in _indicator_to_constraints(model)[ind_idx]
            cdata = _disjunct_constraints(model)[cidx]
            _interrogate_variables(v -> push!(vars, v), cdata.constraint)
        end
    end
    return vars
end

function _get_constraint_variables(model::JuMP.Model, con::Union{JuMP.ScalarConstraint, JuMP.VectorConstraint})
    vars = Set{LogicalVariableRef}()
    _interrogate_variables(v -> push!(vars, v), con) 
    return vars   
end

# Constant
function _interrogate_variables(interrogator::Function, c::Number)
    return
end

# VariableRef
function _interrogate_variables(interrogator::Function, var::JuMP.VariableRef)
    interrogator(var)
    return
end

# LogicalVariableRef
function _interrogate_variables(interrogator::Function, var::LogicalVariableRef)
    interrogator(var)
    return
end

# AffExpr
function _interrogate_variables(interrogator::Function, aff::JuMP.AffExpr)
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
function _interrogate_variables(interrogator::Function, con::JuMP.ScalarConstraint)
    _interrogate_variables(interrogator, con.func)
end
function _interrogate_variables(interrogator::Function, con::JuMP.VectorConstraint)
    for func in con.func
        _interrogate_variables(interrogator, func)
    end
end

# AbstractArray
function _interrogate_variables(interrogator::Function, arr::AbstractArray)
    _interrogate_variables.(interrogator, arr)
    return
end

# Fallback
function _interrogate_variables(interrogator::Function, other)
    error("Cannot extract variables from object of type $(typeof(other)) inside of a disjunctive constraint.")
end