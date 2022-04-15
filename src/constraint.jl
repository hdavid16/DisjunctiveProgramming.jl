is_interval_constraint(con_ref::ConstraintRef{<:AbstractModel}) = constraint_object(con_ref).set isa MOI.Interval
is_interval_constraint(con_ref::NonlinearConstraintRef) = count(i -> i == :(<=), Meta.parse(string(con_ref)).args) == 2
JuMP.name(con_ref::NonlinearConstraintRef) = ""

function check_constraint!(m, constr)
    @assert all(is_valid.(m, constr)) "$constr is not a valid constraint."
    split_flag = false
    constr_name = gen_constraint_name(constr)
    if constr isa ConstraintRef
        new_constr = split_interval_constraint(m, constr)
        if isnothing(new_constr)
            new_constr = constr
        else
            split_flag = true
            m[constr_name] = new_constr
        end
    elseif constr isa Union{Array, Containers.DenseAxisArray, Containers.SparseAxisArray}
        if !any(is_interval_constraint.(constr))
            new_constr = constr
        else
            split_flag = true
            if constr isa Union{Array, Containers.DenseAxisArray}
                idxs = Iterators.product(axes(constr)...)
            elseif constr isa Containers.SparseAxisArray
                idxs = keys(constr.data)
            end
            constr_dict = Dict(union(
                [
                    split_interval_constraint(m, constr[idx...]) |>
                        i -> isnothing(i) ? 
                            (idx...,"") => constr[idx...] : 
                            [(idx...,"lb") => i[1], (idx...,"ub") => i[2]]
                    for idx in idxs
                ]...
            ))
            new_constr = Containers.SparseAxisArray(constr_dict)
            m[constr_name] = new_constr
        end
    end

    if split_flag
        @warn "$(split(string(constr),"}")[end]) uses the `MOI.Interval` set. Each instance of the interval set has been split into two constraints, one for each bound."
        delete_original_constraint!(m, constr)
    end

    return new_constr
end

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

function split_interval_constraint(m, constr, constr_name = name(constr))
    if isempty(constr_name)
        constr_name = "[$constr]"
    end
    if constr isa NonlinearConstraintRef
        constr_expr = Meta.parse(string(constr))
        if count(x -> x == :(<=), constr_expr.args) == 2
            lb = constr_expr.args[1]
            ub = constr_expr.args[5]
            constr_expr_func = copy(constr_expr.args[3]) #get func part of constraint
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
            #return split constraint
            return [constr, ub_constr]
        end
    elseif constr isa ConstraintRef
        constr_obj = constraint_object(constr)
        if constr_obj.set isa MOI.Interval
            lb = constr_obj.set.lower
            ub = constr_obj.set.upper
            ex = constr_obj.func
            lb_name = name_split_constraint(constr_name, :lb)
            ub_name = name_split_constraint(constr_name, :ub)
            return [
                @constraint(m, lb <= ex, base_name = lb_name),
                @constraint(m, ex <= ub, base_name = ub_name)
            ]
        end
    end
    return nothing
end

function delete_original_constraint!(m, constr)
    if constr isa ConstraintRef
        if !isa(constr, NonlinearConstraintRef)
            delete(m, constr)
            # unregister(m, constr)
        end
    elseif constr isa Union{Array, Containers.DenseAxisArray, Containers.SparseAxisArray}
        if !isa(first(constr), NonlinearConstraintRef)
            delete.(m, constr)
            # unregister(m, constr)
        end
    end
end