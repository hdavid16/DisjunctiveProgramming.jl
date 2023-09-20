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