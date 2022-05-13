# Define what should happen to solve a GDPModel
# See https://github.com/jump-dev/JuMP.jl/blob/9ea1df38fd320f864ab4c93c78631d0f15939c0b/src/JuMP.jl#L718-L745
function _optimize_hook(
    model::JuMP.Model; 
    method::AbstractSolutionMethod = BigM()
    ) # can add more kwargs if wanted
    if !_ready_to_optimize(model) && _solution_method(model) != method
        _set_ready_to_optimize(model, false) # maybe not needed

        # TODO do what is needed to solve the model (e.g., add reformulations)

        _set_ready_to_optimize(model, true)
        _set_solution_method(model, method)
    end
    return optimize!(model; ignore_optimize_hook = true)
end
