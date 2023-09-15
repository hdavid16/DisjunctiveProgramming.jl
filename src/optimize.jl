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

"""
    reformulate_model(model::JuMP.Model, method::AbstractSolutionMethod)

Reformulate a `GDPModel` using the specified `method`. Prior to reformulation,
all previous reformulation variables and constraints are deleted.
"""
function reformulate_model(model::JuMP.Model, method::AbstractSolutionMethod)
    #clear all previous reformulations
    for (cidx, cshape) in _reformulation_constraints(model)
        JuMP.delete(model, JuMP.ConstraintRef(model, cidx, cshape))
    end
    gdp_data(model).reformulation_constraints = Vector{Tuple{_MOI.ConstraintIndex, JuMP.AbstractShape}}()        
    for vidx in _reformulation_variables(model)
        JuMP.delete(model, JuMP.VariableRef(model, vidx))
    end
    gdp_data(model).reformulation_variables = Vector{_MOI.VariableIndex}()
    #reformulate
    _reformulate_logical_variables(model)
    _reformulate_disjunctions(model, method)
    _reformulate_logical_constraints(model)
    #set solution method
    _set_solution_method(model, method)
    _set_ready_to_optimize(model, true)
end
