"""
    hull_reformulation!(constr::ConstraintRef{<:AbstractModel, MOI.ConstraintIndex{MOI.ScalarAffineFunction{T},V}}, bin_var, args...) where {T,V}

Apply the hull reformulation to a linear constraint.

    hull_reformulation!(constr::ConstraintRef, bin_var, eps, i, j, k)

Apply the hull reformulation to a nonlinear constraint (includes quadratic) at index k of constraint j in disjunct i.

    hull_reformulation!(constr::AbstractArray{<:ConstraintRef}, bin_var, eps, i, j, k)

Call the hull reformulation on a constraint at index k of constraint j in disjunct i.
"""
function hull_reformulation!(constr::ConstraintRef{<:AbstractModel, MOI.ConstraintIndex{MOI.ScalarAffineFunction{T},V}}, bin_var, args...) where {T,V}
    #check constraint type
    m = constr.model
    i = args[2] #get disjunct index
    bin_var_ref = m[bin_var][i]
    #replace each variable with its disaggregated version
    for var_ref in get_constraint_variables(constr)
        is_binary(var_ref) && continue #NOTE: binaries from nested disjunctions are not disaggregated and don't need to be swapped out
        var_ref in m.ext[:disaggregated_variables] && continue #disaggregated variables are not touched
        #get disaggregated variable reference
        var_name_i = name_disaggregated_variable(var_ref, bin_var, i)
        var_i_ref = variable_by_name(m, var_name_i)
        #check var_ref is present in the constraint
        coeff = normalized_coefficient(constr, var_ref)
        iszero(coeff) && continue #if not present, skip
        #swap variable for disaggregated variable
        set_normalized_coefficient(constr, var_ref, 0) #remove original variable
        set_normalized_coefficient(constr, var_i_ref, coeff) #add disaggregated variable
    end
    #multiply RHS constant by binary variable
    rhs = normalized_rhs(constr) #get rhs
    set_normalized_rhs(constr, 0) #set rhs to 0
    set_normalized_coefficient(constr, bin_var_ref, -rhs) #add binary variable (same as multiplying rhs constant by binary variable)
end
function hull_reformulation!(constr::ConstraintRef, bin_var, eps, i, j, k)
    eps = get_reform_param(eps, i, j, k)
    #create symbolic variables (using Symbolics.jl)
    sym_vars = Dict(
        symbolic_variable(var_ref) => symbolic_variable(name_disaggregated_variable(var_ref, bin_var, i))
        for var_ref in get_constraint_variables(constr)
    )
    ϵ = eps #epsilon parameter for perspective function (See Furman, Sawaya, Grossmann [2020] perspecive function)
    bin_var_sym = Symbol("$bin_var[$i]")
    λ = Num(Symbolics.Sym{Float64}(bin_var_sym))
    FSG1 = Num(Symbolics.Sym{Float64}(gensym())) #this will become: [(1-ϵ)⋅λ + ϵ] (See Furman, Sawaya, Grossmann [2020] perspecive function)
    FSG2 = Num(Symbolics.Sym{Float64}(gensym())) #this will become: ϵ⋅(1-λ) (See Furman, Sawaya, Grossmann [2020] perspecive function)

    #parse constr
    op, lhs, rhs = parse_constraint(constr)
    replace_Symvars!(lhs, constr.model) #convert JuMP variables into Symbolic variables
    gx = eval(lhs) #convert the LHS of the constraint into a Symbolic expression
    #use symbolic substitution to obtain the following expression:
    #[(1-ϵ)⋅λ + ϵ]⋅g(v/[(1-ϵ)⋅λ + ϵ]) - ϵ⋅g(0)⋅(1-λ) <= 0
    #first term
    g1 = FSG1*substitute(gx, Dict(var => var_i/FSG1 for (var,var_i) in sym_vars))
    #second term
    g0 = substitute(gx, Dict(var => 0 for var in keys(sym_vars)))
    @assert !isinf(g0.val) "Hull reformulation has failed for non-linear constraint $constr: $gx is not defined at 0. Perspective function is undetermined."
    g2 = FSG2*g0
    #create perspective function and simplify
    pers_func = simplify(g1 - g2, expand = true)
    #replace FSG expressions & simplify
    pers_func = substitute(pers_func, Dict(FSG1 => (1-ϵ)*λ+ϵ,
                                           FSG2 => ϵ*(1-λ)))
    pers_func = simplify(pers_func)
    replace_constraint(constr, bin_var, pers_func, op, rhs)
end
hull_reformulation!(constr::AbstractArray{<:ConstraintRef}, bin_var, eps, i, j, k) = 
    hull_reformulation!(constr[k], bin_var, eps, i, j, k)

"""
    disaggregate_variables(m::Model, disj, bin_var)

Disaggregate all variables in the model and tag them with the disjunction name.
"""
function disaggregate_variables(m::Model, disj, bin_var)
    #check that variables are bounded
    var_refs = get_constraint_variables(disj)
    @assert all((has_upper_bound.(var_refs) .&& has_lower_bound.(var_refs)) .|| is_binary.(var_refs)) "All variables must be bounded to perform the Hull reformulation."
    #reformulate variables
    obj_dict = object_dictionary(m)
    bounds_dict = :variable_bounds_dict in keys(obj_dict) ? obj_dict[:variable_bounds_dict] : Dict() #NOTE: should pass as an keyword argument
    for var in var_refs
        is_binary(var) && continue #NOTE: don't disaggregate binary variables from nested disjunctions
        var in m.ext[:disaggregated_variables] && continue #skip already disaggregated variables
        #define UB and LB
        LB, UB = get_bounds(var, bounds_dict)
        #disaggregate variable and add bounding constraints
        sum_vars = AffExpr(0) #initialize sum of disaggregated variables
        for i in eachindex(disj)
            var_name_i_str = name_disaggregated_variable(var,bin_var,i)
            var_name_i = Symbol(var_name_i_str)
            #create disaggregated variable
            var_i = add_disaggregated_variable(m, var, LB, UB, var_name_i_str)
            push!(
                m.ext[:disaggregated_variables],
                var_i
            )
            #apply bounding constraints on disaggregated variable
            var_i_lb = "$(var_name_i)_lb" 
            var_i_ub = "$(var_name_i)_ub" 
            push!(
                m.ext[bin_var], 
                @constraint(m, LB * m[bin_var][i] .- var_i .<= 0, base_name = var_i_lb),
                @constraint(m, var_i .- UB * m[bin_var][i] .<= 0, base_name = var_i_ub)
            )
            #update disaggregated sum expression
            add_to_expression!(sum_vars, 1, var_i)
        end
        #sum disaggregated variables
        aggr_con = "$(var)_$(bin_var)_aggregation"
        push!(
            m.ext[bin_var],
            @constraint(m, var == sum_vars, base_name = aggr_con)
        )
    end
end

"""
    add_disaggregated_variable(m::Model, var::VariableRef, LB, UB, base_name)

Disaggreagate a variable with lower bound `LB`, upper bound `UB`, and name `base_name`.

    add_disaggregated_variable(m::Model, var::AbstractArray{VariableRef}, LB, UB, base_name)

Disaggregate a variable block stored in an Array or DenseAxisArray.

    add_disaggregated_variable(m::Model, var::Containers.SparseAxisArray, LB, UB, base_name)

Disaggregate a variable block stored in a SparseAxisArray.
"""
function add_disaggregated_variable(m::Model, var::VariableRef, LB, UB, base_name)
    @variable(
        m, 
        lower_bound = min(LB,0), 
        upper_bound = max(UB,0), 
        binary = is_binary(var), 
        integer = is_integer(var),
        base_name = base_name
    )
end
function add_disaggregated_variable(m::Model, var::AbstractArray{VariableRef}, LB, UB, base_name)
    idxs = Iterators.product(axes(var)...)
    var_i_array = [
        add_disaggregated_variable(m, var[idx...], LB[idx...], UB[idx...], "$base_name[$(join(idx,","))]")
        for idx in idxs
    ]
    return containerize(var, var_i_array)
end
function add_disaggregated_variable(m::Model, var::Containers.SparseAxisArray, LB, UB, base_name)
    idxs = keys(var.data)
    var_i_dict = Dict(
        idx => add_disaggregated_variable(m, var[idx], LB[idx], UB[idx], "$base_name[$(join(idx,","))]")
        for idx in idxs
    )
    return Containers.SparseAxisArray(var_i_dict)
end
containerize(var::Array, arr) = arr
containerize(var::Containers.DenseAxisArray, arr) = Containers.DenseAxisArray(arr, axes(var)...)