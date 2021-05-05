macro disjunction(args...)
    pos_args, kw_args, _ = Containers._extract_kw_args(args)
    m = esc(pos_args[1])
    disj = [esc(a) for a in pos_args[2:end]]
    reformulation = filter(i -> i.args[1] == :reformulation, kw_args)
    if !isempty(reformulation)
        reformulation = reformulation[1].args[2]
    else
        throw(UndefKeywordError(:reformulation))
    end
    BigM = filter(i -> i.args[1] == :BigM, kw_args)
    if !isempty(BigM)
        BigM = BigM[1].args[2]
    else
        BigM = :(missing)
    end
    :(add_disjunction($m,$(disj...); reformulation = $reformulation, BigM = $BigM))
end
