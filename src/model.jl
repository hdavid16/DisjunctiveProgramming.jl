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
    haskey(model.ext, :GDP) || error("Cannot access GDP data from a regular `JuMP.Model`.")
    return model.ext[:GDP]
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
