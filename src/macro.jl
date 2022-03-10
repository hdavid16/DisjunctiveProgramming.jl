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
