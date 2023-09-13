# Define what should happen to solve a GDPModel
# See https://github.com/jump-dev/JuMP.jl/blob/9ea1df38fd320f864ab4c93c78631d0f15939c0b/src/JuMP.jl#L718-L745
function _optimize_hook(
    model::JuMP.Model; 
    method::AbstractSolutionMethod
    ) # can add more kwargs if wanted
    if !_ready_to_optimize(model) && _solution_method(model) != method
        #clear all previous reformulations
        for (cidx, cshape) in _reformulation_constraints(model)
            JuMP.delete(model, JuMP.ConstraintRef(model, cidx, cshape))
        end
        for vidx in _reformulation_variables(model)
            JuMP.delete(model, JuMP.VariableRef(model, vidx))
        end
        #reformulate
        _reformulate_logical_variables(model)
        _reformulate_disjunctions(model, method)
        _reformulate_logical_constraints(model)
        #ready to optimize
        _set_solution_method(model, method)
    end
    return JuMP.optimize!(model; ignore_optimize_hook = true)
end
