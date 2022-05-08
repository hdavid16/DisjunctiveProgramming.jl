function convex_hull_reformulation!(constr, bin_var, i, k, eps)
    ref = ismissing(k) ? constr : constr[k...] #get constraint
    #create convex hull constraint
    if ref isa NonlinearConstraintRef || constraint_object(ref).func isa QuadExpr
        nonlinear_perspective_function(ref, bin_var, i, eps)
    elseif ref isa ConstraintRef
        linear_perspective_function(ref, bin_var, i)
    end
end

function disaggregate_variables(m, disj, bin_var)
    #check that variables are bounded
    var_refs = m[:gdp_variable_refs]
    @assert all((has_upper_bound.(var_refs) .&& has_lower_bound.(var_refs)) .|| is_binary.(var_refs)) "All variables must be bounded to perform the Convex-Hull reformulation."
    #reformulate variables
    obj_dict = object_dictionary(m)
    bounds_dict = :variable_bounds_dict in keys(obj_dict) ? obj_dict[:variable_bounds_dict] : Dict() #NOTE: should pass as an keyword argument
    for var_name in m[:gdp_variable_names]
        var = m[var_name]
        #define UB and LB
        if var isa VariableRef
            if string(var) in keys(bounds_dict)
                LB, UB = bounds_dict[string(var)]
            else
                LB, UB = get_bounds(var)
            end
        elseif var isa Array{VariableRef} || var isa Containers.DenseAxisArray || var isa Containers.SparseAxisArray
            #initialize UB and LB with same container type as variable
            if var isa Array{VariableRef} || var isa Containers.DenseAxisArray
                idxs = Iterators.product(axes(var)...)
                LB, UB = zeros(size(var)), zeros(size(var))
                if var isa Containers.DenseAxisArray
                    LB = Containers.DenseAxisArray(LB, axes(var)...)
                    UB = Containers.DenseAxisArray(UB, axes(var)...)
                end
            elseif var isa Containers.SparseAxisArray
                idxs = keys(var.data)
                LB = Containers.SparseAxisArray(Dict(idx => 0. for idx in idxs))
                UB = Containers.SparseAxisArray(Dict(idx => 0. for idx in idxs))
            end
            #populate UB and LB
            for idx in eachindex(var)
                if string(var[idx]) in keys(bounds_dict)
                    LB[idx], UB[idx] = bounds_dict[string(var[idx])]
                else
                    LB[idx], UB[idx] = get_bounds(var[idx])
                end
            end
        end
        #disaggregate variable and add bounding constraints
        for i in eachindex(disj)
            var_name_i = Symbol("$(var_name)_$bin_var$i")
            if var isa VariableRef
                #create and register anonymous variable
                m[var_name_i] = add_disaggregated_variable(m, LB, UB, var, "$var_name_i")
            elseif var isa Array{VariableRef} || var isa Containers.DenseAxisArray
                #create array of anonymous variables
                var_i_array = [
                    add_disaggregated_variable(m, LB[idx...], UB[idx...], var[idx...], "$var_name_i[$(join(idx,","))]")
                    for idx in idxs
                ]
                #containerize if DenseAxisArray
                if var isa Containers.DenseAxisArray
                    var_i_array = Containers.DenseAxisArray(var_i_array, axes(var)...)
                end
                #register disaggregated variable
                m[var_name_i] = var_i_array
            elseif var isa Containers.SparseAxisArray
                #create dictionary of anonymous variables
                var_i_dict = Dict(
                    idx => add_disaggregated_variable(m, LB[idx], UB[idx], var[idx], "$var_name_i[$(join(idx,","))]")
                    for idx in idxs
                )
                #register disaggregated variable
                m[var_name_i] = Containers.SparseAxisArray(var_i_dict)
            end
            #apply bounding constraints on disaggregated variable
            var_i_lb = "$(var_name_i)_lb" 
            var_i_ub = "$(var_name_i)_ub" 
            m[Symbol(var_i_lb)] = @constraint(m, LB * m[bin_var][i] .- m[var_name_i] .<= 0, base_name = var_i_lb)
            m[Symbol(var_i_ub)] = @constraint(m, m[var_name_i] .- UB * m[bin_var][i] .<= 0, base_name = var_i_ub)
        end
    end
end

function sum_disaggregated_variables(m, disj, bin_var)
    for var in m[:gdp_variable_refs]
        dis_vars = []
        for i in eachindex(disj)
            var_name_i = name_disaggregated_variable(var, bin_var, i)
            var_i = variable_by_name(m, var_name_i)
            push!(dis_vars, var_i)
        end
        aggr_con = "$(var)_$(bin_var)_aggregation"
        m[Symbol(aggr_con)] = @constraint(m, var == sum(dis_vars), base_name = aggr_con)
    end
    # for var_name in m[:gdp_variable_names]
    #     var = m[var_name]
    #     dis_vars = []
    #     for i in eachindex(disj)
    #         var_name_i = Symbol("$(var_name)_$bin_var$i")
    #         push!(dis_vars, m[var_name_i])
    #     end
    #     aggr_con = "$(var_name)_$(bin_var)_aggregation"
    #     m[Symbol(aggr_con)] = @constraint(m, var .== sum(dis_vars), base_name = aggr_con)
    # end
end

function add_disaggregated_variable(m, LB, UB, var, base_name)
    @variable(
        m, 
        lower_bound = min(LB,0), 
        upper_bound = max(UB,0), 
        binary = is_binary(var), 
        integer = is_integer(var),
        base_name = base_name
    )
end

function linear_perspective_function(ref, bin_var, i)
    #check constraint type
    bin_var_ref = ref.model[bin_var][i]
    #replace each variable with its disaggregated version
    for var_ref in ref.model[:gdp_variable_refs]
        #get disaggregated variable reference
        var_name_i = name_disaggregated_variable(var_ref, bin_var, i)
        var_i_ref = variable_by_name(ref.model, var_name_i)
        #check var_ref is present in the constraint
        coeff = normalized_coefficient(ref, var_ref)
        iszero(coeff) && continue #if not present, skip
        #swap variable for disaggregated variable
        set_normalized_coefficient(ref, var_ref, 0) #remove original variable
        set_normalized_coefficient(ref, var_i_ref, coeff) #add disaggregated variable
    end
    #multiply RHS constant by binary variable
    rhs = normalized_rhs(ref) #get rhs
    set_normalized_rhs(ref, 0) #set rhs to 0
    set_normalized_coefficient(ref, bin_var_ref, -rhs) #add binary variable (same as multiplying rhs constant by binary variable)
end

function nonlinear_perspective_function(ref, bin_var, i, eps)
    #create symbolic variables (using Symbolics.jl)
    sym_vars = Dict(
        symbolic_variable(var_ref) => symbolic_variable(name_disaggregated_variable(var_ref, bin_var, i))
        for var_ref in ref.model[:gdp_variable_refs]
    )
    ϵ = eps #epsilon parameter for perspective function (See Furman, Sawaya, Grossmann [2020] perspecive function)
    bin_var_sym = Symbol("$bin_var[$i]")
    λ = Num(Symbolics.Sym{Float64}(bin_var_sym))
    FSG1 = Num(Symbolics.Sym{Float64}(gensym())) #this will become: [(1-ϵ)⋅λ + ϵ] (See Furman, Sawaya, Grossmann [2020] perspecive function)
    FSG2 = Num(Symbolics.Sym{Float64}(gensym())) #this will become: ϵ⋅(1-λ) (See Furman, Sawaya, Grossmann [2020] perspecive function)

    #parse ref
    op, lhs, rhs = parse_NLconstraint(ref)
    replace_Symvars!(lhs, ref.model) #convert JuMP variables into Symbolic variables
    gx = eval(lhs) #convert the LHS of the constraint into a Symbolic expression
    #use symbolic substitution to obtain the following expression:
    #[(1-ϵ)⋅λ + ϵ]⋅g(v/[(1-ϵ)⋅λ + ϵ]) - ϵ⋅g(0)⋅(1-λ) <= 0
    #first term
    g1 = FSG1*substitute(gx, Dict(var => var_i/FSG1 for (var,var_i) in sym_vars))
    #second term
    g0 = substitute(gx, Dict(var => 0 for var in keys(sym_vars)))
    @assert !isinf(g0.val) "Convex-hull reformulation has failed for non-linear constraint $ref: $gx is not defined at 0. Perspective function is undetermined."
    g2 = FSG2*g0
    #create perspective function and simplify
    pers_func = simplify(g1 - g2, expand = true)
    #replace FSG expressions & simplify
    pers_func = substitute(pers_func, Dict(FSG1 => (1-ϵ)*λ+ϵ,
                                           FSG2 => ϵ*(1-λ)))
    pers_func = simplify(pers_func)
    replace_NLconstraint(ref, pers_func, op, rhs)
end