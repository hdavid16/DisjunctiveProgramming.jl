is_interval_constraint(con_ref::ConstraintRef) = constraint_object(con_ref).set isa MOI.Interval
is_interval_constraint(con_ref::NonlinearConstraintRef) = count(i -> i == :(<=), Meta.parse(string(con_ref)).args) == 2
is_equality_constraint(con_ref::ConstraintRef) = constraint_object(con_ref).set isa MOI.EqualTo
is_equality_constraint(con_ref::NonlinearConstraintRef) = Meta.parse(string(con_ref)).args[1] == :(==)
JuMP.name(con_ref::NonlinearConstraintRef) = ""

"""
    check_constraint!(m::Model, constr::Tuple)

Check constraints in a disjunction Tuple.

    check_constraint!(m::Model, constr_j, constr_list::Vector)

Check nested constraint and update `constr_list`.

    check_constraint!(m::Model, constr)

Check constraint in a Model.

    check_constraint!(m::Model, constr::Nothing)

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
function check_constraint!(m::Model, constr_j::AbstractArray{<:ConstraintRef}, constr_list::Vector)
    push!(constr_list, check_constraint!(m, constr_j))
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
        # constr_str = split(string(constr),"}")[end]
        # @warn "$constr_str uses the `MOI.Interval` or `MOI.EqualTo` set. Each instance of the interval set has been split into two constraints, one for each bound."
        delete_original_constraint!(m, constr)
    end
    return new_constr
end
function check_constraint!(m::Model, constr::AbstractArray{<:ConstraintRef})
    @assert all(is_valid.(m, constr)) "$constr is not a valid constraint."
    if !any(is_interval_constraint.(constr)) && !any(is_equality_constraint.(constr))
        new_constr = constr
    else
        idxs = get_indices(constr)
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
        # constr_str = split(string(constr),"}")[end]
        # @warn "$constr_str uses the `MOI.Interval` or `MOI.EqualTo` set. Each instance of the interval set has been split into two constraints, one for each bound."
        delete_original_constraint!(m, constr)
    end
    return new_constr
end
check_constraint!(m::Model, constr::Nothing) = nothing

"""
    split_constraint(m::Model, constr::NonlinearConstraintRef)

Split a nonlinear constraint that is an Interval or EqualTo constraint.

    split_constraint(m::Model, constr::ConstraintRef, constr_name::String = name(constr))

Split a linear or quadratic constraint.

    split_constraint(m::Model, constr_obj::ScalarConstraint, lb_name::String, ub_name::String)

Split a constraint that is a MOI.EqualTo or MOI.Interval.

    split_constraint(m::Model, func::Union{AffExpr,QuadExpr}, lb::Float64, ub::Float64, lb_name::String, ub_name::String)

Create split constraint for linear or quadratic constraint.

    split_constraint(m::Model, constr::ConstraintRef, constr_func_expr::Expr, lb::Float64, ub::Float64)

Split a nonlinear constraint.

    split_constraint(args...)

Return nothing for an empty disjunct.
"""
function split_constraint(m::Model, constr::NonlinearConstraintRef)
    constr_expr = Meta.parse(string(constr))
    if constr_expr.args[1] == :(==) #replace == for lb <= expr <= ub and split
        lb, ub = 0, 0#rhs is always 0, but could get obtained from: constr_expr.args[3]
        constr_func_expr = copy(constr_expr.args[2])
        new_constraints = split_constraint(m, constr, constr_func_expr, lb, ub)
        return new_constraints
    elseif count(x -> x == :(<=), constr_expr.args) == 2 #split lb <= expr <= ub
        lb = constr_expr.args[1]
        ub = constr_expr.args[5]
        constr_func_expr = copy(constr_expr.args[3]) #get func part of constraint
        new_constraints = split_constraint(m, constr, constr_func_expr, lb, ub)
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
    new_constraints = split_constraint(m, constr_obj, lb_name, ub_name)

    return new_constraints
end
function split_constraint(m::Model, func::Union{AffExpr,QuadExpr}, lb::Float64, ub::Float64, lb_name::String, ub_name::String)
    return [
        @constraint(m, lb <= func, base_name = lb_name),
        @constraint(m, func <= ub, base_name = ub_name)
    ]
end
function split_constraint(m::Model, constr_obj::ScalarConstraint{T,<:MOI.EqualTo}, lb_name::String, ub_name::String) where T
    split_constraint(m, constr_obj.func, constr_obj.set.value, constr_obj.set.value, lb_name, ub_name)
end
function split_constraint(m::Model, constr_obj::ScalarConstraint{T,<:MOI.Interval}, lb_name::String, ub_name::String) where T
    split_constraint(m, constr_obj.func, constr_obj.set.lower, constr_obj.set.upper, lb_name, ub_name)
end
function split_constraint(m::Model, constr::ConstraintRef, constr_func_expr::Expr, lb::Float64, ub::Float64)
    replace_JuMPvars!(constr_func_expr, m) #replace Expr with JuMP vars
    #replace original constraint with lb <= func
    lb_constr = JuMP._NonlinearConstraint(
        JuMP._NonlinearExprData(m, constr_func_expr), 
        lb, 
        Inf
    )
    m.nlp_data.nlconstr[constr.index.value] = lb_constr
    #create new constraint for func <= ub
    constr_expr_ub = Expr(:call, :(<=), constr_func_expr, ub)
    ub_constr = add_nonlinear_constraint(m, constr_expr_ub)

    return [constr, ub_constr]
end
split_constraint(args...) = nothing

delete_original_constraint!(m::Model, constr::ConstraintRef) = delete(m,constr)
delete_original_constraint!(m::Model, constr::NonlinearConstraintRef) = nothing
delete_original_constraint!(m::Model, constr::AbstractArray{<:ConstraintRef}) = map(c -> delete_original_constraint!(m,c), constr)

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

"""
function replace_constraint(constr::NonlinearConstraintRef, sym_expr, op, rhs)
    #convert symbolic function to expression
    expr = Base.remove_linenums!(build_function(sym_expr)).args[2].args[1]
    #replace symbolic variables by their JuMP variables and math operators with their symbols
    m = constr.model
    replace_JuMPvars!(expr, m)
    replace_operators!(expr)
    # determine bounds of original constraint (if op is ==, both bounds are set to rhs)
    upper_b = (op == :(>=)) ? Inf : rhs
    lower_b = (op == :(<=)) ? -Inf : rhs
    # replace NL constraint currently in the model with the reformulated one
    m.nlp_data.nlconstr[constr.index.value] = JuMP._NonlinearConstraint(JuMP._NonlinearExprData(m, expr), lower_b, upper_b)
end
function replace_constraint(constr::ConstraintRef, sym_expr, op, rhs)
    #convert symbolic function to expression
    op = eval(op)
    expr = Base.remove_linenums!(build_function(op(sym_expr,rhs))).args[2].args[1]
    #replace symbolic variables by their JuMP variables and math operators with their symbols
    m = constr.model
    replace_JuMPvars!(expr, m)
    replace_operators!(expr)
    #add a nonlinear constraint with the perspective function and delete old constraint
    add_nonlinear_constraint(m, expr)
    delete(m, constr)
end