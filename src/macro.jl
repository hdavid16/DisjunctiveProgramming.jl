macro disjunction(args...)
    pos_args, kw_args, _ = Containers._extract_kw_args(args)

    #get kw_args
    reformulation = filter(i -> i.args[1] == :reformulation, kw_args)
    if !isempty(reformulation)
        reformulation = reformulation[1].args[2]
    else
        throw(UndefKeywordError(:reformulation))
    end
    M = filter(i -> i.args[1] == :M, kw_args)
    M = !isempty(M) ? esc(M[1].args[2]) : :(missing)
    eps = filter(i -> i.args[1] == :eps, kw_args)
    eps = !isempty(eps) ? esc(eps[1].args[2]) : :(1e-6)
    name = filter(i -> i.args[1] == :name, kw_args)
    name = !isempty(name) ? esc(name[1].args[2]) : :(missing)

    #get args
    m = esc(pos_args[1])
    disj = [esc(a) for a in pos_args[2:end]]
    
    #build disjunction
    :(add_disjunction($m, $(disj...), reformulation = $reformulation, M = $M, eps = $eps, name = $name))
end

function add_disjunction(m::Model,disj...;reformulation,M=missing,eps=1e-6,name=missing)
    @assert m isa Model "A valid JuMP Model must be provided."
    @assert reformulation in [:BMR, :CHR] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."
    @assert length(disj) > 1 "At least 2 disjuncts must be included."
    #create binary indicator variables for each disjunction
    disj_name = ismissing(name) ? Symbol("disj",gensym()) : name
    @assert !in(disj_name, keys(object_dictionary(m))) "The disjunction name $disj_name already exists as a model object. Specify a name that is not present in the model's object_dictionary."
    #create variable if it doesn't exist
    m[disj_name] = @variable(m, [eachindex(disj)], Bin, base_name = string(disj_name))
    #add xor constraint on binary variable
    m[Symbol("XOR(",disj_name,")")] = @constraint(m, sum(m[disj_name][i] for i in eachindex(disj)) == 1)
    #apply reformulation
    param = reformulation == :BMR ? M : eps
    reformulate_disjunction(m, disj, disj_name, reformulation, param)
end

macro proposition(m, expr)
    #get args
    m = esc(m)
    expr = Expr(:quote, expr)
    :(add_logical_proposition($m, $expr))
end

function add_logical_proposition(m::Model, expr::Expr)
    @assert m isa Model "A valid JuMP Model must be provided."
    to_cnf!(m, expr)
end