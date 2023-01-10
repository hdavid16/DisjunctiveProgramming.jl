constraint_set(constr::ConstraintRef) = constraint_object(constr).set
constraint_set(constr::NonlinearConstraintRef) = nonlinear_model(constr.model)[index(constr)].set
is_interval(constr::ConstraintRef) = constraint_set(constr) isa MOI.Interval
is_equalto(constr::ConstraintRef) = constraint_set(constr) isa MOI.EqualTo
JuMP.name(constr::NonlinearConstraintRef) = ""

"""
    check_constraint!(m::Model, constr::Tuple)

Check constraints in a disjunction Tuple.

    check_constraint!(m::Model, constr_j, constr_list::Vector)

Check nested constraint and update `constr_list`.

    check_constraint!(m::Model, constr)

Check constraint in a Model.

    check_constraint!(args...)

Return nothing for an empty disjunct.
"""
function check_constraint!(m::Model, constr::Tuple)
    constr_list = []
    map(constr_j -> check_constraint!(m, constr_j, constr_list), constr)
    return Tuple(constr_list)
end
function check_constraint!(m::Model, constr_j::Tuple, constr_list::Vector)
    map(constr_jk -> check_constraint!(m, constr_jk, constr_list), constr_j)
end
function check_constraint!(m::Model, constr_j::AbstractArray, constr_list::Vector)
    map(constr_jk -> check_constraint!(m, constr_jk, constr_list), constr_j)
end
function check_constraint!(m::Model, constr_j::AbstractArray{<:ConstraintRef}, constr_list::Vector)
    push!(constr_list, check_constraint!(m, constr_j))
end
function check_constraint!(m::Model, constr_j::ConstraintRef, constr_list::Vector)
    push!(constr_list, check_constraint!(m, constr_j))
end
function check_constraint!(m::Model, constr::ConstraintRef)
    @assert all(is_valid(m, constr)) "$constr is not a valid constraint."
    new_constr = split_constraint(constr)
    if isnothing(new_constr)
        new_constr = constr
    else
        delete(m, constr)
    end
    return new_constr
end
function check_constraint!(m::Model, constr::AbstractArray{<:ConstraintRef})
    @assert all(is_valid.(m, constr)) "$constr is not a valid constraint."
    if !any(is_interval.(constr)) && !any(is_equalto.(constr))
        new_constr = constr
    else
        idxs = get_indices(constr)
        constr_dict = Dict(union(
            [
                split_constraint(constr[idx...]) |>
                    i -> isnothing(i) ? 
                        (idx...,"") => constr[idx...] : 
                        [(idx...,"lb") => i[1], (idx...,"ub") => i[2]]
                for idx in idxs
            ]...
        ))
        new_constr = Containers.SparseAxisArray(constr_dict)
        delete.(m, constr)
    end
    return new_constr
end
check_constraint!(args...) = nothing

"""
    split_constraint(constr::ConstraintRef)

Split a constraint that is an Interval or EqualTo constraint.

    split_constraint(args...)

Return nothing for an empty disjunct.
"""
function split_constraint(constr::ConstraintRef)
    constr_set = constraint_set(constr)
    if is_equalto(constr)
        lb = ub = constr_set.value
        return _split_constraint(constr.model, constr, lb, ub)
    elseif is_interval(constr)
        lb = constr_set.lower
        ub = constr_set.upper
        return _split_constraint(constr.model, constr, lb, ub)
    else
        return nothing
    end
end
function _split_constraint(m::Model, constr::NonlinearConstraintRef, lb::Float64, ub::Float64)
    nlp = nonlinear_model(m)
    nlconstr = nlp[index(constr)]
    #add lb constraint
    nlp.last_constraint_index += 1
    index1 = MOI.Nonlinear.ConstraintIndex(nlp.last_constraint_index)
    nlp.constraints[index1] =
        MOI.Nonlinear.Constraint(nlconstr.expression, MOI.LessThan(ub))
    #add ub constraint
    nlp.last_constraint_index += 1
    index2 = MOI.Nonlinear.ConstraintIndex(nlp.last_constraint_index)
    nlp.constraints[index2] =
        MOI.Nonlinear.Constraint(nlconstr.expression, MOI.GreaterThan(lb))

    return [
        ConstraintRef(m, index1, constr.shape), 
        ConstraintRef(m, index2, constr.shape)
    ]
end
function _split_constraint(m::Model, constr::ConstraintRef, lb::Float64, ub::Float64)
    constr_name = name(constr)
    if isempty(constr_name)
        constr_name = "[$constr]"
    end
    lb_name = name_split(constr_name; new_index = :lb)
    ub_name = name_split(constr_name; new_index = :ub)
    func = constraint_object(constr).func
    return [
        @constraint(m, lb <= func, base_name = lb_name),
        @constraint(m, func <= ub, base_name = ub_name)
    ]
end
split_constraint(args...) = nothing

"""
    parse_constraint(constr::ConstraintRef)

Extract constraint operator symbol (op), constraint function expression (LHS), and constraint RHS.    
"""
function parse_constraint(constr::ConstraintRef)
    #check function has a single comparrison operator (<=, >=, ==)
    constr_str = replace(split(string(constr),": ")[end], " " => "", "²" => "^2") #remove name, blanks and power notation
    constr_expr = Meta.parse(constr_str).args
    op = constr_expr[1] #comparrison operator
    lhs = constr_expr[2] #LHS of the constraint
    rhs = constr_expr[3] #RHS of constraint
    return op, lhs, rhs
end

"""
    add_reformulated_constraint(constr::ConstraintRef, bin_var::Symbol, sym_expr, op, rhs)

Replace nonlinear or quadratic constraint with its hull reformulation.
"""
function add_reformulated_constraint(constr::ConstraintRef, bin_var::Symbol, sym_expr, op, rhs)
    #convert symbolic function to expression
    op = eval(op)
    expr = Base.remove_linenums!(build_function(op(sym_expr,rhs))).args[2].args[1]
    #replace symbolic variables by their JuMP variables and math operators with their symbols
    m = constr.model
    replace_JuMPvars!(expr, m)
    replace_operators!(expr)
    #add new constraint and delete old one
    new_constr = add_nonlinear_constraint(m, expr)
    push!(m.ext[bin_var], new_constr)
    delete(m, constr)

    return new_constr
end