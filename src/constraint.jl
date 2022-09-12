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
        delete(m, constr)
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
        delete(m, constr)
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
function split_constraint(m::Model, constr::ConstraintRef, constr_func_expr::Expr, lb::Real, ub::Real)
    replace_JuMPvars!(constr_func_expr, m) #replace Expr with JuMP vars
    #create split constraints
    constr_expr_lb = Expr(:call, :(>=), constr_func_expr, lb)
    constr_expr_ub = Expr(:call, :(<=), constr_func_expr, ub)
    lb_constr = add_nonlinear_constraint(m, constr_expr_lb)
    ub_constr = add_nonlinear_constraint(m, constr_expr_ub)

    return [lb_constr, ub_constr]
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
    replace_constraint(constr::ConstraintRef, bin_var::Symbol, sym_expr, op, rhs)

Replace nonlinear or quadratic constraint with its hull reformulation.
"""
function replace_constraint(constr::ConstraintRef, bin_var::Symbol, sym_expr, op, rhs)
    #convert symbolic function to expression
    op = eval(op)
    expr = Base.remove_linenums!(build_function(op(sym_expr,rhs))).args[2].args[1]
    #replace symbolic variables by their JuMP variables and math operators with their symbols
    m = constr.model
    replace_JuMPvars!(expr, m)
    replace_operators!(expr)
    #replace constraint with prespective function
    push!(m.ext[bin_var], add_nonlinear_constraint(m, expr))
    delete(m, constr)
end