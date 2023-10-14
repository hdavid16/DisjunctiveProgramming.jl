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

# Define what should happen to solve a GDPModel
# See https://github.com/jump-dev/JuMP.jl/blob/9ea1df38fd320f864ab4c93c78631d0f15939c0b/src/JuMP.jl#L718-L745
function _optimize_hook(
    model::JuMP.Model; 
    method::AbstractSolutionMethod
    ) # can add more kwargs if wanted
    if !_ready_to_optimize(model) || _solution_method(model) != method
        reformulate_model(model, method)
    end
    return JuMP.optimize!(model; ignore_optimize_hook = true)
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

# Create accessors for GDP data fields
_logical_variables(model::JuMP.Model) = gdp_data(model).logical_variables
_logical_constraints(model::JuMP.Model) = gdp_data(model).logical_constraints
_disjunct_constraints(model::JuMP.Model) = gdp_data(model).disjunct_constraints
_disjunctions(model::JuMP.Model) = gdp_data(model).disjunctions
_indicator_to_binary(model::JuMP.Model) = gdp_data(model).indicator_to_binary
_indicator_to_constraints(model::JuMP.Model) = gdp_data(model).indicator_to_constraints
_reformulation_variables(model::JuMP.Model) = gdp_data(model).reformulation_variables
_reformulation_constraints(model::JuMP.Model) = gdp_data(model).reformulation_constraints
_ready_to_optimize(model::JuMP.Model) = gdp_data(model).ready_to_optimize # Determine if the model is ready to call `optimize!` without a optimize hook
_solution_method(model::JuMP.Model) = gdp_data(model).solution_method # Get the current solution method

# Update the ready_to_optimize field
function _set_ready_to_optimize(model::JuMP.Model, is_ready::Bool)
    gdp_data(model).ready_to_optimize = is_ready
    return
end

# Set the solution method
function _set_solution_method(model::JuMP.Model, method::AbstractSolutionMethod)
    gdp_data(model).solution_method = method
    return
end
