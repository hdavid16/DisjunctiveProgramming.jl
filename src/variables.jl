################################################################################
#                              LOGICAL VARIABLES
################################################################################
"""
    JuMP.build_variable(_error::Function, info::VariableInfo, 
                        ::Union{Type{Logical}, Logical})

Extend `JuMP.build_variable` to work with logical variables. This in 
combination with `JuMP.add_variable` enables the use of 
`@variable(model, [var_expr], Logical)`.
"""
function JuMP.build_variable(
    _error::Function, 
    info::VariableInfo, 
    tag::Type{Logical};
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
    elseif info.has_fix && !isone(info.fixed_value) && !iszero(info.fixed_value)
        _error("Invalid fix value, must be false or true.")
    elseif info.has_start && !isone(info.start) && !iszero(info.start)
        _error("Invalid start value, must be false or true.")
    end

    # create the variable
    fix = info.has_fix ? Bool(info.fixed_value) : nothing
    start = info.has_start ? Bool(info.start) : nothing
    return LogicalVariable(fix, start)
end

# Logical variable with tag data
function JuMP.build_variable(
    _error::Function, 
    info::VariableInfo, 
    tag::Logical;
    kwargs...
    )
    lvar = JuMP.build_variable(_error, info, Logical; kwargs...)
    return _TaggedLogicalVariable(lvar, tag.tag_data) 
end

# Helper functions to extract the core variable object
_get_variable(v::_TaggedLogicalVariable) = v.variable
_get_variable(v) = v

# Helper function to add start value and fix value
function _add_logical_info(bvref, var::LogicalVariable)
    if !isnothing(var.fix_value)
        JuMP.fix(bvref, var.fix_value)
    end
    if !isnothing(var.start_value)
        JuMP.set_start_value(bvref, var.start_value)
    end
    return
end
function _add_logical_info(bvref, var::_TaggedLogicalVariable)
    return _add_logical_info(bvref, var.variable)
end

# Dispatch on logical variable type to create a binary variable
function _make_binary_variable(model, ::LogicalVariable, name)
    return JuMP.@variable(model, base_name = name, binary = true)
end
function _make_binary_variable(model, var::_TaggedLogicalVariable, name)
    return JuMP.@variable(
        model, 
        base_name = name, 
        binary = true, 
        variable_type = var.tag_data
        )
end

"""
    JuMP.add_variable(model::Model, v::LogicalVariable, 
                      name::String = "")::LogicalVariableRef
                
Extend `JuMP.add_variable` for [`LogicalVariable`](@ref)s. This 
helps enable `@variable(model, [var_expr], Logical)`.
"""
function JuMP.add_variable(
    model::JuMP.AbstractModel, 
    v::Union{LogicalVariable, _TaggedLogicalVariable}, 
    name::String = ""
    )
    is_gdp_model(model) || error("Can only add logical variables to `GDPModel`s.")
    # add the logical variable
    data = LogicalVariableData(_get_variable(v), name)
    idx = _MOIUC.add_item(_logical_variables(model), data)
    lvref = LogicalVariableRef(model, idx)
    _set_ready_to_optimize(model, false)
    # add the associated binary variables
    bvref = _make_binary_variable(model, v, name)
    _add_logical_info(bvref, v)
    _indicator_to_binary(model)[lvref] = bvref
    return lvref
end

# Base extensions
Base.copy(v::LogicalVariableRef) = v
Base.broadcastable(v::LogicalVariableRef) = Ref(v)
Base.length(v::LogicalVariableRef) = 1
function Base.:(==)(v::LogicalVariableRef, w::LogicalVariableRef)
    return v.model === w.model && v.index == w.index
end
# function Base.getindex(map::ReferenceMap, vref::LogicalVariableRef)
#     return LogicalVariableRef(map.model, index(vref))
# end

# Define helpful getting functions
function _variable_object(lvref::LogicalVariableRef)
    dict = _logical_variables(JuMP.owner_model(lvref))
    return dict[JuMP.index(lvref)].variable
end

# Define helpful setting functions
function _set_variable_object(lvref::LogicalVariableRef, var::LogicalVariable)
    model = JuMP.owner_model(lvref)
    _logical_variables(model)[JuMP.index(lvref)].variable = var
    _set_ready_to_optimize(model, false)
    return
end

# JuMP extensions
"""
    JuMP.owner_model(vref::LogicalVariableRef)::JuMP.AbstractModel

Return the `GDP model` to which `vref` belongs.
"""
JuMP.owner_model(vref::LogicalVariableRef) = vref.model

"""
    JuMP.index(vref::LogicalVariableRef)::LogicalVariableIndex

Return the index of logical variable that associated with `vref`.
"""
JuMP.index(vref::LogicalVariableRef) = vref.index

"""
    JuMP.isequal_canonical(v::LogicalVariableRef, w::LogicalVariableRef)::Bool

Return `true` if `v` and `w` refer to the same logical variable in the same
`GDP model`.
"""
JuMP.isequal_canonical(v::LogicalVariableRef, w::LogicalVariableRef) = v == w

"""
    JuMP.is_valid(model::JuMP.AbstractModel, vref::LogicalVariableRef)::Bool

Return `true` if `vref` refers to a valid logical variable in `GDP model`.
"""
function JuMP.is_valid(model::JuMP.AbstractModel, vref::LogicalVariableRef)
    return model === owner_model(vref) && haskey(_logical_variables(model), JuMP.index(vref))
end

"""
    JuMP.name(vref::LogicalVariableRef)::String

Get a logical variable's name attribute.
"""
function JuMP.name(vref::LogicalVariableRef)
    data = gdp_data(owner_model(vref))
    return data.logical_variables[index(vref)].name
end

"""
    JuMP.set_name(vref::LogicalVariableRef, name::String)::Nothing

Set a logical variable's name attribute.
"""
function JuMP.set_name(vref::LogicalVariableRef, name::String)
    model = owner_model(vref)
    data = gdp_data(model)
    data.logical_variables[index(vref)].name = name
    _set_ready_to_optimize(model, false)
    JuMP.set_name(binary_variable(vref), name)
    return
end

"""
    JuMP.start_value(vref::LogicalVariableRef)::Bool

Return the start value of the logical variable `vref`.
"""
function JuMP.start_value(vref::LogicalVariableRef)
    return _variable_object(vref).start_value
end

"""
    JuMP.set_start_value(vref::LogicalVariableRef, value::Union{Nothing, Bool})::Nothing

Set the start value of the logical variable `vref`.

Pass `nothing` to unset the start value.
"""
function JuMP.set_start_value(
    vref::LogicalVariableRef, 
    value::Union{Nothing, Bool}
    )
    new_var = LogicalVariable(JuMP.fix_value(vref), value)
    _set_variable_object(vref, new_var)
    JuMP.set_start_value(binary_variable(vref), value)
    return
end
"""
    JuMP.is_fixed(vref::LogicalVariableRef)::Bool

Return `true` if `vref` is a fixed variable. If
    `true`, the fixed value can be queried with
    fix_value.
"""
function JuMP.is_fixed(vref::LogicalVariableRef)
    return !isnothing(_variable_object(vref).fix_value)
end

"""
    JuMP.fix_value(vref::LogicalVariableRef)::Bool

Return the value to which a logical variable is fixed.
"""
function JuMP.fix_value(vref::LogicalVariableRef)
    return _variable_object(vref).fix_value
end

"""
    JuMP.fix(vref::LogicalVariableRef, value::Bool)::Nothing

Fix a logical variable to a value. Update the fixing
constraint if one exists, otherwise create a
new one.
"""
function JuMP.fix(vref::LogicalVariableRef, value::Bool)
    new_var = LogicalVariable(value, JuMP.start_value(vref))
    _set_variable_object(vref, new_var)
    JuMP.fix(binary_variable(vref), value)
    return
end

"""
    JuMP.unfix(vref::LogicalVariableRef)::Nothing

Delete the fixed value of a logical variable.
"""
function JuMP.unfix(vref::LogicalVariableRef)
    new_var = LogicalVariable(nothing, JuMP.start_value(vref))
    _set_variable_object(vref, new_var)
    JuMP.unfix(binary_variable(vref))
    return
end

"""
    binary_variable(vref::LogicalVariableRef)::JuMP.AbstractVariableRef

Returns the underlying binary variable for the logical variable `vref` which 
is used in the reformulated model. This is helpful to embed logical variables 
in algebraic constraints.
"""
function binary_variable(vref::LogicalVariableRef)
    model = JuMP.owner_model(vref)
    return _indicator_to_binary(model)[vref]
end

"""
    JuMP.value(vref::LogicalVariableRef)::Bool

Returns the optimized value of `vref`. This dispatches on 
`value(binary_variable(vref))` and then rounds to the closest 
`Bool` value.
"""
function JuMP.value(vref::LogicalVariableRef)
    return JuMP.value(binary_variable(vref)) >= 0.5
end

"""
    JuMP.delete(model::JuMP.AbstractModel, vref::LogicalVariableRef)::Nothing

Delete the logical variable associated with `vref` from the `GDP model`.
"""
function JuMP.delete(model::JuMP.AbstractModel, vref::LogicalVariableRef)
    @assert is_valid(model, vref) "Variable does not belong to model."
    vidx = index(vref)
    dict = _logical_variables(model)
    #delete any disjunct constraints associated with the logical variables in the disjunction
    if haskey(_indicator_to_constraints(model), vref)
        crefs = _indicator_to_constraints(model)[vref]
        JuMP.delete.(model, crefs)
        delete!(_indicator_to_constraints(model), vref)
    end
    #delete any disjunctions that have the logical variable
    for (didx, ddata) in _disjunctions(model)
        if vref in ddata.constraint.indicators
            JuMP.delete(model, DisjunctionRef(model, didx))
        end
    end
    #delete any logical constraints involving the logical variables
    for (cidx, cdata) in _logical_constraints(model)
        lvars = _get_logical_constraint_variables(model, cdata.constraint)
        if vref in lvars
            JuMP.delete(model, LogicalConstraintRef(model, cidx))
        end
    end
    #delete the logical variable
    delete!(dict, vidx)
    JuMP.delete(model, binary_variable(vref))
    delete!(_indicator_to_binary(model), vref)
    #not ready to optimize
    _set_ready_to_optimize(model, false)
    return 
end

################################################################################
#                              VARIABLE INTERROGATION
################################################################################
function _get_disjunction_variables(model::M, disj::Disjunction) where {M <: JuMP.AbstractModel}
    vars = Set{JuMP.variable_ref_type(M)}()
    for vidx in disj.indicators
        !haskey(_indicator_to_constraints(model), vidx) && continue #skip if disjunct is empty
        for cref in _indicator_to_constraints(model)[vidx]
            con = constraint_object(cref)
            _interrogate_variables(Base.Fix1(push!, vars), con)
        end
    end
    return vars
end

function _get_logical_constraint_variables(
    ::M, 
    con::Union{JuMP.ScalarConstraint, JuMP.VectorConstraint}
    ) where {M <: JuMP.AbstractModel}
    vars = Set{LogicalVariableRef{M}}()
    _interrogate_variables(Base.Fix1(push!, vars), con)
    return vars   
end

# Constant
function _interrogate_variables(interrogator::Function, c::Number)
    return
end

# VariableRef/LogicalVariableRef
function _interrogate_variables(interrogator::Function, var::JuMP.AbstractVariableRef)
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
function _interrogate_variables(interrogator::Function, quad::JuMP.GenericQuadExpr)
    for (pair, _) in quad.terms
        interrogator(pair.a)
        interrogator(pair.b)
    end
    _interrogate_variables(interrogator, quad.aff)
    return
end

# NonlinearExpr
function _interrogate_variables(interrogator::Function, nlp::JuMP.GenericNonlinearExpr)
    for arg in nlp.args
        _interrogate_variables(interrogator, arg)
    end
    # TODO avoid recursion. See InfiniteOpt.jl for alternate method that avoids stackoverflow errors with deeply nested expressions:
    # https://github.com/infiniteopt/InfiniteOpt.jl/blob/cb6dd6ae40fe0144b1dd75da0739ea6e305d5357/src/expressions.jl#L520-L534
    return
end

# Constraint
function _interrogate_variables(interrogator::Function, con::JuMP.AbstractConstraint)
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
    model = owner_model(first(disj.indicators))
    dvars = _get_disjunction_variables(model, disj)
    _interrogate_variables(interrogator, dvars)
    return
end

# Fallback
function _interrogate_variables(interrogator::Function, other)
    error("Cannot extract variables from object of type $(typeof(other)).")
end
