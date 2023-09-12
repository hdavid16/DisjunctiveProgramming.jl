# Define what should happen to solve a GDPModel
# See https://github.com/jump-dev/JuMP.jl/blob/9ea1df38fd320f864ab4c93c78631d0f15939c0b/src/JuMP.jl#L718-L745
function _optimize_hook(
    model::JuMP.Model; 
    method::AbstractSolutionMethod = BigM(1_000_000)
    ) # can add more kwargs if wanted
    if !_ready_to_optimize(model) && _solution_method(model) != method
        _set_ready_to_optimize(model, false)
        #reformulate
        _reformulate_logical_variables(model)
        _reformulate_disjunctive_constraints(model, method)
        _reformulate_logical_constraints(model)
        #ready to optimize
        _set_ready_to_optimize(model, true)
        _set_solution_method(model, method)
    end
    return optimize!(model; ignore_optimize_hook = true)
end
