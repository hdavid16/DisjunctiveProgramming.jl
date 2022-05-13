"""
    disjunction(m, args...)

Add disjunction macro.
"""
macro disjunction(m, args...)
    #get disjunction (pos_args) and keyword arguments
    pos_args, kw_args, _ = Containers._extract_kw_args(args)
    @assert length(pos_args) > 1 "At least 2 disjuncts must be included. If there is an empty disjunct, use `nothing`."

    #get kw_args and set defaults if missing
    reformulation = filter(i -> i.args[1] == :reformulation, kw_args)
    if !isempty(reformulation)
        reformulation = reformulation[1].args[2]
        reformulation_kind = eval(reformulation)
        @assert reformulation_kind in [:big_m, :hull] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :big_m (Big-M Reformulation) and :hull (Hull Reformulation)."
        if reformulation_kind == :big_m
            M = filter(i -> i.args[1] == :M, kw_args)
            param = !isempty(M) ? M[1].args[2] : :(missing)
        elseif reformulation_kind == :hull
            ϵ = filter(i -> i.args[1] == :ϵ, kw_args)
            param = !isempty(ϵ) ? ϵ[1].args[2] : :(1e-6)
        else
        end
    else
        throw(UndefKeywordError(:reformulation))
    end
    name = filter(i -> i.args[1] == :name, kw_args)
    if !isempty(name)
        name = name[1].args[2]
        disj_name = Symbol("disj_",eval(name))
    else
        name = :(Symbol("disj",gensym()))
        disj_name = eval(name)
    end
    
    #create constraints for each disjunction
    disj_names = [Symbol("$(disj_name)[$i]") for i in eachindex(pos_args)]
    disjunction = []
    for (d,dname) in zip(pos_args,disj_names)
        if Meta.isexpr(d, :tuple)
            for (j,di) in enumerate(d.args)
                i = findfirst(x -> x == d, pos_args)
                dname_j = Symbol("$(disj_name)[$i,$j]")
                d.args[j] = add_disjunction_constraint(m, di, dname_j)
            end
            push!(disjunction, d)
        else
            push!(disjunction, add_disjunction_constraint(m, d, dname))
        end
    end

    #XOR constraint name
    xor_con = Symbol("XOR($disj_name)")
    
    #build disjunction
    code = quote
        @assert !in($name, keys(object_dictionary($m))) "The disjunction name $name is already registered in the model. Specify new name."
        $m[$name] = @variable($m, [eachindex($disjunction)], Bin, base_name = string($name), lower_bound = 0, upper_bound = 1)
        @constraint($m, $xor_con, sum($m[$name]) == 1)
        reformulate_disjunction($m, $(disjunction...); bin_var = $name, reformulation = $reformulation, param = $param)
    end

    return esc(code)
end

"""
    add_disjunction_constraint(m, d, dname)

Add disjunction constraint with name dname.
"""
function add_disjunction_constraint(m, d, dname)
    if Meta.isexpr(d, :block)
        d = quote
            try
                @constraints($m,$d)
            catch e
                if e isa ErrorException
                    @NLconstraints($m,$d)
                else
                    throw(e)
                end
            end
        end
    elseif Meta.isexpr(d, (:call, :comparison))
        d = quote
            try
                @constraint($m,$dname,$d)
            catch e
                if e isa ErrorException
                    @NLconstraint($m,$d)
                else
                    throw(e)
                end
            end
        end
    end
    
    return d
end

"""
    add_disjunction!(m::Model,disj...;reformulation::Symbol,M=missing,ϵ=1e-6,name=missing)

Add disjunction and reformulate.
"""
function add_disjunction!(m::Model,disj...;reformulation::Symbol,M=missing,ϵ=1e-6,name=missing)
    #run checks
    @assert reformulation in [:big_m, :hull] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :big_m (Big-M Reformulation) and :hull (Hull Reformulation)."
    @assert length(disj) > 1 "At least 2 disjuncts must be included. If there is an empty disjunct, use `nothing`."

    #get kw_args and set defaults if missing
    param = reformulation == :big_m ? M : ϵ
    bin_var = ismissing(name) ? Symbol("disj",gensym()) : name
    disj_name = ismissing(name) ? bin_var : Symbol("disj_",name)
    
    #XOR constraint name
    xor_con = "XOR($disj_name)"
    
    #apply reformulation
    @assert !in(bin_var, keys(object_dictionary(m))) "The disjunction name $bin_var is already registered in the model. Specify new name."
    #create indicator variable
    m[bin_var] = @variable(m, [eachindex(disj)], Bin, base_name = string(bin_var), lower_bound = 0, upper_bound = 1)
    #add xor constraint on binary variable
    m[Symbol(xor_con)] = @constraint(m, sum(m[bin_var]) == 1, base_name = xor_con)
    #reformulate disjunction
    reformulate_disjunction(m, disj...; bin_var, reformulation, param)
end

"""
    proposition(m, expr)

Add logical proposition macro.
"""
macro proposition(m, expr)
    #get args
    expr = QuoteNode(expr)
    code = :(DisjunctiveProgramming.to_cnf!($m, $expr))
    
    return esc(code)
end
