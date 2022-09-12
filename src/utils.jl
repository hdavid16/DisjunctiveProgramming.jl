"""
    get_indices(arr::Containers.SparseAxisArray)

Get indices in SparseAxisArray.

    get_indices(arr)

Get indices in Array or DenseAxisArray.
"""
get_indices(arr::Containers.SparseAxisArray) = keys(arr.data)
get_indices(arr) = Iterators.product(axes(arr)...)

get_reform_param(param::Missing, args...; constr) = 
    apply_interval_arithmetic(constr)
get_reform_param(param::Number, args...; kwargs...) = param
get_reform_param(param::Union{Vector,Tuple}, i::Int, args...; kwargs...) =
    get_reform_param(param[i], args...; kwargs...)
function get_reform_param(param::Dict, args...; kwargs...)
    arg_list = [arg for arg in args if !ismissing(arg)] #remove mising if j or k are missing
    get_reform_param(param[arg_list...]; kwargs...)
end

"""
    get_constraint_variables(m::Model, con)

Get variables that have non-zero coefficients in the passed constraint,
constraint container, or disjunction
"""
function get_constraint_variables(m::Model, con::ConstraintRef{<:AbstractModel, MOI.ConstraintIndex{MOI.ScalarAffineFunction{T},V}}) where {T,V}
    return filter(
        var_ref -> 
            !iszero(normalized_coefficient(con, var_ref)), 
        all_variables(m)
    )
end
function get_constraint_variables(m::Model, con::ConstraintRef)
    var_list = []
    constr_expr = parse_constraint(con)[2]
    constraint_variables!(constr_expr, m, var_list)

    return var_list
end
function get_constraint_variables(m::Model, con::Union{Containers.SparseAxisArray, Containers.DenseAxisArray, Array{<:ConstraintRef}})
    return union(
        [
            get_constraint_variables(m,con[idx]) 
            for idx in eachindex(con)
        ]...
    )
end
function get_constraint_variables(m::Model, disjunction)
    return union(
        [
            get_constraint_variables(m, disj)
            for disj in disjunction if !isnothing(disj)
        ]...
    )
end

function replace_Symvars!(expr, model; logical_proposition = false)
    #replace JuMP variables with symbolic variables
    name = join(split(string(expr)," "))
    var = variable_by_name(model, name)
    if !isnothing(var)
        logical_proposition && @assert is_binary(var) "Only binary variables are allowed in $expr."
        return Symbol(name)
    end
    if expr isa Expr
        for i in eachindex(expr.args)
            expr.args[i] = replace_Symvars!(expr.args[i], model)
        end
    end

    return expr
end

function replace_JuMPvars!(expr, model)
    #replace symbolic variables and any matching expressions with JuMP variables
    var = variable_by_name(model, string(expr))
    !isnothing(var) && return var
    if expr isa Expr #run recursion
        for i in eachindex(expr.args)
            expr.args[i] = replace_JuMPvars!(expr.args[i], model)
        end
    end

    return expr
end

function replace_operators!(expr)
    #replace operators with their symbol. NOTE: Is this still needed for the hull_reformulation! of nl constraints? (check this)
    if expr isa Expr #run recursion
        for i in eachindex(expr.args)
            expr.args[i] = replace_operators!(expr.args[i])
        end
    elseif expr isa Function #replace Function with its symbol
        return Symbol(expr)
    end

    return expr
end

function replace_intevals!(expr, intervals)
    #replace variables with their intervals
    expr_str = replace(string(expr), ", " => ",") #remove any blank space after index commas
    if expr_str in keys(intervals) #check if expression is one of the model variables in the intervals dict
        return intervals[expr_str] #replace expression with interval
    elseif expr isa Expr
        if length(expr.args) == 1 #run recursive relation on the leaf node on expression tree
            expr.args[i] = replace_intevals!(expr.args[i], intervals)
        else #run recursive relation on each internal node of the expression tree, but skip the first element, which will always be the operator (this will avoid issues if the user creates a model variable called exp)
            for i in 2:length(expr.args)
                expr.args[i] = replace_intevals!(expr.args[i], intervals)
            end
        end
    end

    return expr
end

function symbolic_variable(var_ref)
    var_sym = Symbol(var_ref)
    return eval(:(Symbolics.@variables($var_sym)[1]))
end

function name_disaggregated_variable(var_ref, bin_var, i)
    var_name = name(var_ref)
    var_name_i = "$(var_name)_$(bin_var)$i"

    return var_name_i
end

function name_split_constraint(con_name, side)
    #get disaggregated variable reference
    if occursin("[", string(con_name))
        con_name = replace(string(con_name), "]" => ",$side]")
    else
        con_name = "$(con_name)[$side]"
    end

    return con_name
end

function constraint_variables!(expr, model, var_list=[])
    name = join(split(string(expr)," "))
    var = variable_by_name(model, name)
    if !isnothing(var)
        push!(var_list, var)
    elseif expr isa Expr
        for i in eachindex(expr.args)
            constraint_variables!(expr.args[i], model, var_list)
        end
    end
end

is_constraint(m::Model, constr::ConstraintRef) = is_valid(m,constr)
is_constraint(m::Model, constr::AbstractArray{<:ConstraintRef}) = all(is_valid.(m,constr))
is_constraint(m::Model, constr::Tuple) = all([is_constraint(m,i) for i in constr])