is_interval_constraint(con_ref::ConstraintRef) = constraint_object(con_ref).set isa MOI.Interval
is_interval_constraint(con_ref::NonlinearConstraintRef) = count(i -> i == :(<=), Meta.parse(string(con_ref)).args) == 2
is_equality_constraint(con_ref::ConstraintRef) = constraint_object(con_ref).set isa MOI.EqualTo
is_equality_constraint(con_ref::NonlinearConstraintRef) = Meta.parse(string(con_ref)).args[1] == :(==)
JuMP.name(con_ref::NonlinearConstraintRef) = ""

check_constraint!(m::Model, constr::Nothing) = nothing
function check_constraint!(m::Model, constr::Tuple)
    constr_list = []
    map(constr_j -> check_constraint!(m, constr_j, constr_list), constr)

    return Tuple(constr_list)
end
function check_constraint!(m::Model, constr_j::Union{Tuple,Array}, constr_list::Vector)
    map(constr_jk -> check_constraint!(m, constr_jk, constr_list), constr_j)
end
function check_constraint!(m::Model, constr_j::ConstraintRef, constr_list::Vector)
    push!(constr_list, check_constraint!(m, constr_j))
end
function check_constraint!(m::Model, constr::ConstraintRef)
    @assert all(is_valid(m, constr)) "$constr is not a valid constraint."
    new_constr = split_constraint(m, constr)
    if isnothing(new_constr)
        new_constr = constr
    else
        constr_name = gen_constraint_name(constr)
        m[constr_name] = new_constr
        constr_str = split(string(constr),"}")[end]
        @warn "$constr_str uses the `MOI.Interval` or `MOI.EqualTo` set. Each instance of the interval set has been split into two constraints, one for each bound."
        delete_original_constraint!(m, constr)
    end

    return new_constr
end
function check_constraint!(m::Model, constr::AbstractArray)
    @assert all(is_valid.(m, constr)) "$constr is not a valid constraint."
    if !any(is_interval_constraint.(constr)) && !any(is_equality_constraint.(constr))
        new_constr = constr
    else
        idxs = get_keys(constr)
        constr_dict = Dict(union(
            [
                split_constraint(m, constr[idx...]) |>
                    i -> isnothing(i) ? 
                        (idx...,"") => constr[idx...] : 
                        [(idx...,"lb") => i[1], (idx...,"ub") => i[2]]
                for idx in idxs
            ]...
        ))
        new_constr = Containers.SparseAxisArray(constr_dict)
        constr_name = gen_constraint_name(constr)
        m[constr_name] = new_constr
        constr_str = split(string(constr),"}")[end]
        @warn "$constr_str uses the `MOI.Interval` or `MOI.EqualTo` set. Each instance of the interval set has been split into two constraints, one for each bound."
        delete_original_constraint!(m, constr)
    end

    return new_constr
end

# function check_constraint!(m, constr)
#     @assert all(is_valid.(m, constr)) "$constr is not a valid constraint."
#     split_flag = false
#     constr_name = gen_constraint_name(constr)
#     constr_str = split(string(constr),"}")[end]
#     if constr isa ConstraintRef
#         new_constr = split_constraint(m, constr)
#         if isnothing(new_constr)
#             new_constr = constr
#         else
#             split_flag = true
#             m[constr_name] = new_constr
#         end
#     elseif constr isa Union{Array, Containers.DenseAxisArray, Containers.SparseAxisArray}
#         if !any(is_interval_constraint.(constr)) && !any(is_equality_constraint.(constr))
#             new_constr = constr
#         else
#             split_flag = true
#             if constr isa Union{Array, Containers.DenseAxisArray}
#                 idxs = Iterators.product(axes(constr)...)
#             elseif constr isa Containers.SparseAxisArray
#                 idxs = keys(constr.data)
#             end
#             constr_dict = Dict(union(
#                 [
#                     split_constraint(m, constr[idx...]) |>
#                         i -> isnothing(i) ? 
#                             (idx...,"") => constr[idx...] : 
#                             [(idx...,"lb") => i[1], (idx...,"ub") => i[2]]
#                     for idx in idxs
#                 ]...
#             ))
#             new_constr = Containers.SparseAxisArray(constr_dict)
#             m[constr_name] = new_constr
#         end
#     end

#     if split_flag
#         @warn "$constr_str uses the `MOI.Interval` or `MOI.EqualTo` set. Each instance of the interval set has been split into two constraints, one for each bound."
#         delete_original_constraint!(m, constr)
#     end

#     return new_constr
# end

function gen_constraint_name(constr)
    constr_name = name.(constr)
    if any(isempty.(constr_name))
        constr_name = gensym("constraint")
    elseif !isa(constr_name, String)
        c_names = union(first.(split.(constr_name,"[")))
        if length(c_names) == 1
            constr_name = c_names[1]
        else
            constr_name = gensym("constraint")
        end
    end

    return Symbol("$(constr_name)_split")
end

function split_constraint(m::Model, constr::NonlinearConstraintRef, constr_name::String = name(constr))
    if isempty(constr_name)
        constr_name = "[$constr]"
    end
    constr_expr = Meta.parse(string(constr))
    if constr_expr.args[1] == :(==) #replace == for lb <= expr <= ub and split
        lb, ub = 0, 0#rhs is always 0, but could get obtained from: constr_expr.args[3]
        constr_expr_func = copy(constr_expr.args[2])
        new_constraints = split_nonlinear_constraint(m, constr, constr_expr_func, lb, ub)
        return new_constraints
    elseif count(x -> x == :(<=), constr_expr.args) == 2 #split lb <= expr <= ub
        lb = constr_expr.args[1]
        ub = constr_expr.args[5]
        constr_expr_func = copy(constr_expr.args[3]) #get func part of constraint
        new_constraints = split_nonlinear_constraint(m, constr, constr_expr_func, lb, ub)
        return new_constraints
    else
        return nothing
    end
end
function split_constraint(m::Model, constr::ConstraintRef, constr_name::String = name(constr))
    if isempty(constr_name)
        constr_name = "[$constr]"
    end
    lb_name = name_split_constraint(constr_name, :lb)
    ub_name = name_split_constraint(constr_name, :ub)
    constr_obj = constraint_object(constr)
    new_constraints = split_linear_constraint(m, constr_obj, lb_name, ub_name)

    return new_constraints
end

# function split_constraint(m::Model, constr::ConstraintRef, constr_name::String = name(constr))
#     constr_obj = constraint_object(constr)
#     if constr_obj.set isa MOI.EqualTo
#         lb = constr_obj.set.value
#         ub = lb
#         new_constraints = split_linear_constraint(m, constr_obj, constr_name, lb, ub)
#         return new_constraints
#     elseif constr_obj.set isa MOI.Interval
#         lb = constr_obj.set.lower
#         ub = constr_obj.set.upper
#         new_constraints = split_linear_constraint(m, constr_obj, constr_name, lb, ub)
#         return new_constraints
#     else
#         return nothing
#     end
# end

# function split_constraint(m, constr, constr_name = name(constr))
#     if isempty(constr_name)
#         constr_name = "[$constr]"
#     end
#     if constr isa NonlinearConstraintRef
#         constr_expr = Meta.parse(string(constr))
#         if constr_expr.args[1] == :(==) #replace == for lb <= expr <= ub and split
#             lb, ub = 0, 0#rhs is always 0, but could get obtained from: constr_expr.args[3]
#             constr_expr_func = copy(constr_expr.args[2])
#             new_constraints = split_nonlinear_constraint(m, constr, constr_expr_func, lb, ub)
#             return new_constraints
#         elseif count(x -> x == :(<=), constr_expr.args) == 2 #split lb <= expr <= ub
#             lb = constr_expr.args[1]
#             ub = constr_expr.args[5]
#             constr_expr_func = copy(constr_expr.args[3]) #get func part of constraint
#             new_constraints = split_nonlinear_constraint(m, constr, constr_expr_func, lb, ub)
#             return new_constraints
#         end
#     elseif constr isa ConstraintRef
#         constr_obj = constraint_object(constr)
#         if constr_obj.set isa MOI.EqualTo
#             lb = constr_obj.set.value
#             ub = lb
#             new_constraints = split_linear_constraint(m, constr_obj, constr_name, lb, ub)
#             return new_constraints
#         elseif constr_obj.set isa MOI.Interval
#             lb = constr_obj.set.lower
#             ub = constr_obj.set.upper
#             new_constraints = split_linear_constraint(m, constr_obj, constr_name, lb, ub)
#             return new_constraints
#         end
#     end
#     return nothing
# end

# function split_linear_constraint(m, constr_obj, constr_name, lb, ub)
#     ex = constr_obj.func
#     lb_name = name_split_constraint(constr_name, :lb)
#     ub_name = name_split_constraint(constr_name, :ub)
#     return [
#         @constraint(m, lb <= ex, base_name = lb_name),
#         @constraint(m, ex <= ub, base_name = ub_name)
#     ]
# end

# function split_linear_constraint(m::Model, func::AffExpr, lb::Float64, ub::Float64, lb_name::String, ub_name::String) where T
#     return [
#         add_constraint(
#             m, 
#             ScalarConstraint(func, MOI.GreaterThan{Float64}(lb)), 
#             lb_name
#         ),
#         add_constraint(
#             m, 
#             ScalarConstraint(func, MOI.LessThan{Float64}(ub)), 
#             ub_name
#         ),
#     ]
# end
function split_linear_constraint(m::Model, func::AffExpr, lb::Float64, ub::Float64, lb_name::String, ub_name::String) where T
    return [
        @constraint(m, lb <= func, base_name = lb_name),
        @constraint(m, func <= ub, base_name = ub_name)
    ]
end
function split_linear_constraint(m::Model, constr_obj::ScalarConstraint{T,<:MOI.EqualTo}, lb_name::String, ub_name::String) where T
    split_linear_constraint(m, constr_obj.func, constr_obj.set.value, constr_obj.set.value, lb_name, ub_name)
end
function split_linear_constraint(m::Model, constr_obj::ScalarConstraint{T,<:MOI.Interval}, lb_name::String, ub_name::String) where T
    split_linear_constraint(m, constr_obj.func, constr_obj.set.lower, constr_obj.set.upper, lb_name, ub_name)
end
split_linear_constraint(args...) = nothing

function split_nonlinear_constraint(m, constr, constr_expr_func, lb, ub)
    replace_JuMPvars!(constr_expr_func, m) #replace Expr with JuMP vars
    #replace original constraint with lb <= func
    lb_constr = JuMP._NonlinearConstraint(
        JuMP._NonlinearExprData(m, constr_expr_func), 
        lb, 
        Inf
    )
    m.nlp_data.nlconstr[constr.index.value] = lb_constr
    #create new constraint for func <= ub
    constr_expr_ub = Expr(:call, :(<=), constr_expr_func, ub)
    ub_constr = add_nonlinear_constraint(m, constr_expr_ub)

    return [constr, ub_constr]
end

delete_original_constraint!(m::Model, constr::ConstraintRef) = delete(m,constr)
delete_original_constraint!(m::Model, constr::NonlinearConstraintRef) = nothing
delete_original_constraint!(m::Model, constr::AbstractArray) = map(c -> delete_original_constraint!(m,c), constr)

# function delete_original_constraint!(m, constr)
#     if constr isa ConstraintRef
#         if !isa(constr, NonlinearConstraintRef)
#             delete(m, constr)
#             # unregister(m, constr)
#         end
#     elseif constr isa Union{Array, Containers.DenseAxisArray, Containers.SparseAxisArray}
#         if !isa(first(constr), NonlinearConstraintRef)
#             delete.(m, constr)
#             # unregister(m, constr)
#         end
#     end
# end