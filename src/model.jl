################################################################################
#                              GDP MODEL
################################################################################

"""
    GDPModel([optimizer]; [kwargs...])::JuMP.Model

The core model object for building general disjunction programming models.
"""
function GDPModel(args...; kwargs...)
    model = JuMP.Model(args...; kwargs...)
    model.ext[:GDP] = GDPData()
    JuMP.set_optimize_hook(model, _optimize_hook)
    return model
end

# Determine if the model is ready to call `optimize!` without a optimize hook
_ready_to_optimize(model::JuMP.Model) = gdp_data(model).ready_to_optimize

# Update the ready_to_optimize field
function _set_ready_to_optimize(model::JuMP.Model, is_ready::Bool)
    gdp_data(model).ready_to_optimize = is_ready
    return
end

# Get the current solution method
_solution_method(model::JuMP.Model) = gdp_data(model).solution_method

# Set the solution method
function _set_solution_method(model::JuMP.Model, method::AbstractSolutionMethod)
    gdp_data(model).solution_method = method
    return
end

################################################################################
#                              GDP DATA
################################################################################

"""
    gdp_data(model::JuMP.Model)::GDPData

Extract the [`GDPData`](@ref) from a `GDPModel`.
"""
function gdp_data(model::JuMP.Model)
    is_gdp_model(model) || error("Cannot access GDP data from a regular `JuMP.Model`.")
    return model.ext[:GDP]
end

"""
    is_gdp_model(model::JuMP.Model)::Bool

Return if `model` was created via the [`GDPModel`](@ref) constructor.
"""
function is_gdp_model(model::JuMP.Model)
    return haskey(model.ext, :GDP)
end

"""

"""
function disjunction_indicators(disjunction::DisjunctionRef) 
    model, idx = disjunction.model, disjunction.index
    ind_idxs = _disjunction_to_indicators(model)[idx]
    return LogicalVariableRef.(model, ind_idxs) # TODO account for nested disjunctions
end

# Create accessors for GDP data fields
function _logical_variables(model::JuMP.Model)
    return model.ext[:GDP].logical_variables
end

function _logical_constraints(model::JuMP.Model)
    return model.ext[:GDP].logical_constraints
end

function _disjunct_constraints(model::JuMP.Model)
    return model.ext[:GDP].disjunct_constraints
end

function _disjunctions(model::JuMP.Model)
    return model.ext[:GDP].disjunctions
end

function _disjunction_to_indicators(model::JuMP.Model)
    return model.ext[:GDP].disjunction_to_indicators
end

function _indicator_to_disjunction(model::JuMP.Model)
    return model.ext[:GDP].indicator_to_disjunction
end

function _indicator_to_constraints(model::JuMP.Model)
    return model.ext[:GDP].indicator_to_constraints
end

function _constraint_to_indicator(model::JuMP.Model)
    return model.ext[:GDP].constraint_to_indicator
end

function _indicator_to_binary(model::JuMP.Model)
    return model.ext[:GDP].indicator_to_binary
end

function _global_to_disjunct_variable(model::JuMP.Model)
    return model.ext[:GDP].global_to_disjunct_variable
end

function _global_to_disjunction_variables(model::JuMP.Model)
    return model.ext[:GDP].global_to_disjunction_variables
end

function _variable_bounds(model::JuMP.Model)
    return model.ext[:GDP].variable_bounds
end

"""

"""
function _indicator_to_binary_ref(lvref::LogicalVariableRef)
    model, idx = lvref.model, lvref.index
    return JuMP.VariableRef(model, _indicator_to_binary(model)[idx])
end

################################################################################
#                              COPY EXT
################################################################################

function JuMP.copy_extension_data(data::GDPData, new_model::JuMP.AbstractModel, model::JuMP.AbstractModel)
    new_model.ext[:GDP] = GDPData(
        data.logical_variables, 
        _copy(data.logical_constraints, new_model), 
        _copy(data.disjunct_constraints, new_model),
        _copy(data.disjunctions, new_model), 
        data.disjunction_to_indicators,
        data.indicator_to_disjunction,
        data.indicator_to_binary,
        data.indicator_to_constraints,
        data.constraint_to_indicator,
        data.global_to_disjunct_variable,
        data.global_to_disjunction_variables,
        data.variable_bounds,
        data.solution_method, 
        data.ready_to_optimize,
    )
end

