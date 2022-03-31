function CHR!(m, constr, bin_var, i, k, eps)
    ref = ismissing(k) ? constr : constr[k...] #get constraint
    @assert is_valid(m,ref) "$constr is not a valid constraint in the model."
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
    for var_name in m[:gdp_variable_names]
        var = m[var_name]
        #define UB and LB
        if var isa VariableRef
            LB, UB = get_bounds(var)
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
                LB[idx], UB[idx] = get_bounds(var[idx])
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
            lb_constr = LB * m[bin_var][i] .- m[var_name_i]
            m[Symbol(var_name_i,"_lb")] = @constraint(m, lb_constr .<= 0)
            ub_constr = m[var_name_i] .- UB * m[bin_var][i]
            m[Symbol(var_name_i,"_ub")] = @constraint(m, ub_constr .<= 0)
        end
    end
end

function sum_disaggregated_variables(m, disj, bin_var)
    for var_name in m[:gdp_variable_names]
        var = m[var_name]
        dis_vars = []
        for i in eachindex(disj)
            var_name_i = Symbol("$(var_name)_$bin_var$i")
            push!(dis_vars, m[var_name_i])
        end
        m[Symbol(var_name,"_aggregation")] = @constraint(m, var .== sum.(dis_vars))
    end
end

function add_disaggregated_variable(m, LB, UB, var, base_name)
    @variable(
        m, 
        lower_bound = LB, 
        upper_bound = UB, 
        binary = is_binary(var), 
        integer = is_integer(var),
        base_name = base_name
    )
end

function linear_perspective_function(ref, bin_var, i)
    #check constraint type
    ref_obj = constraint_object(ref)
    @assert ref_obj.set isa MOI.LessThan || ref_obj.set isa MOI.GreaterThan || ref_obj.set isa MOI.EqualTo "$ref must be one the following: GreaterThan, LessThan, or EqualTo."
    bin_var_ref = ref.model[bin_var][i]
    #replace each variable with its disaggregated version
    for var_ref in ref.model[:gdp_variable_refs]
        #get disaggregated variable reference
        var_name_i = replace(string(var_ref), "[" => "_$bin_var$i[")
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
    sym_vars = Dict()
    for var_ref in ref.model[:gdp_variable_refs]
        #get disaggregated variable reference
        var_name_i = replace(string(var_ref), "[" => "_$bin_var$i[")
        var_sym = Symbol(var_ref)
        var_i_sym = Symbol(var_name_i)
        sym_vars[eval(:(Symbolics.@variables($var_sym)[1]))] = eval(:(Symbolics.@variables($var_i_sym)[1]))
    end
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
    g2 = FSG2*substitute(gx, Dict(var => 0 for var in keys(sym_vars)))
    #create perspective function and simplify
    pers_func = simplify(g1 - g2, expand = true)
    #replace FSG expressions & simplify
    pers_func = substitute(pers_func, Dict(FSG1 => (1-ϵ)*λ+ϵ,
                                           FSG2 => ϵ*(1-λ)))
    pers_func = simplify(pers_func)
    replace_NLconstraint(ref, pers_func, op, rhs)
end