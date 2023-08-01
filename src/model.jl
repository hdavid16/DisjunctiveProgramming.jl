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
    disjuncts = _disjunctions(model)[idx].constraint.disjuncts
    return LogicalVariableRef[disj.indicator for disj in disjuncts]
end

"""

"""
function _disjunct_constraint_map(model::JuMP.Model)
    is_gdp_model(model) || error("Cannot access disjunct constraint map from a regular `JuMP.Model`.")
    return model.ext[:GDP].disjunct_constraint_map
end

"""

"""
function _disjunct_constraints(model::JuMP.Model)
    is_gdp_model(model) || error("Cannot access disjunct constraints from a regular `JuMP.Model`.")
    return model.ext[:GDP].disjunct_constraints
end

"""

"""
function _disjunctions(model::JuMP.Model)
    is_gdp_model(model) || error("Cannot access disjunctions from a regular `JuMP.Model`.")
    return model.ext[:GDP].disjunctions
end

"""

"""
function _logical_constraints(model::JuMP.Model)
    is_gdp_model(model) || error("Cannot access logical constraints from a regular `JuMP.Model`.")
    return model.ext[:GDP].logical_constraints
end

"""

"""
function _logical_variables(model::JuMP.Model)
    is_gdp_model(model) || error("Cannot access logical variables from a regular `JuMP.Model`.")
    return model.ext[:GDP].logical_variables
end

"""

"""


function JuMP.copy_extension_data(data::GDPData, new_model::JuMP.AbstractModel, model::JuMP.AbstractModel)
    new_model.ext[:GDP] = GDPData(
        data.logical_variables, 
        _copy(data.logical_constraints, new_model), 
        _copy(data.disjunct_constraints, new_model),
        data.disjunct_constraint_map,
        _copy(data.disjunctions, new_model), 
        data.solution_method, 
        data.ready_to_optimize,
        _copy(data.disaggregated_variables, new_model), 
        _copy(data.indicator_variables, new_model), 
        _copy(data.variable_bounds, new_model)
    )
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
