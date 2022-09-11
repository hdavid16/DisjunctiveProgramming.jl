"""
    disjunction(m, args...)

Add disjunction macro.
"""
macro disjunction(m, args...)
    #get disjunction (args) and keyword arguments
    disjuncts, kwargs, _ = Containers._extract_kw_args(args)

    #get kwargs and set defaults if missing
    reformulation_kwarg = filter(i -> i.args[1] == :reformulation, kwargs)
    reformulation = isempty(reformulation_kwarg) ? throw(UndefKeywordError(:reformulation)) : reformulation_kwarg[1].args[2]
    M_kwarg = filter(i -> i.args[1] == :M, kwargs)
    M = isempty(M_kwarg) ? :missing : M_kwarg[1].args[2]
    ϵ_kwarg = filter(i -> i.args[1] == :ϵ, kwargs)
    ϵ = isempty(ϵ_kwarg) ? :(1e-6) : ϵ_kwarg[1].args[2]
    name_kwarg = filter(i -> i.args[1] == :name, kwargs)
    name = isempty(name_kwarg) ? Symbol("disj_",gensym()) : name_kwarg[1].args[2]
    disj_name = isempty(name_kwarg) ? name : Symbol("disj_",eval(name))
    
    #create constraints for each disjunction
    disj_names = [Symbol("$(disj_name)[$i]") for i in eachindex(disjuncts)]
    disjunction = []
    for (d,dname) in zip(disjuncts,disj_names)
        if Meta.isexpr(d, :tuple)
            for (j,di) in enumerate(d.args)
                i = findfirst(x -> x == d, disjuncts)
                dname_j = Symbol("$(disj_name)[$i,$j]")
                d.args[j] = add_disjunction_constraint(m, di, dname_j)
            end
            push!(disjunction, d)
        else
            push!(disjunction, add_disjunction_constraint(m, d, dname))
        end
    end
    
    #build disjunction
    code = quote
        DisjunctiveProgramming.add_disjunction!($m, $(disjunction...); reformulation = $reformulation, M = $M, ϵ = $ϵ, name = $name)
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
                    @NLconstraint($m,$dname,$d)
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

    #get kwargs and set defaults if missing
    param = reformulation == :big_m ? M : ϵ
    bin_var = ismissing(name) ? Symbol("disj",gensym()) : name
    
    #apply reformulation
    if bin_var in keys(object_dictionary(m))
        @assert length(disj) <= length(m[bin_var]) "The disjunction name $bin_var is already registered in the model and its size is smaller than the number of disjunts. Specify new name."
    else
        #create indicator variable
        m[bin_var] = @variable(m, [eachindex(disj)], Bin, base_name = string(bin_var))
    end

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
    code = :(DisjunctiveProgramming.add_proposition!($m, $expr))
    
    return esc(code)
end
