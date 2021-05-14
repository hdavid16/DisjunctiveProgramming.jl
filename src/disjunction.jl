function add_disjunction(m::Model,args...;reformulation=:BMR,M=missing,eps=1e-6)
    @assert m isa Model "A valid JuMP Model must be provided."
    @assert reformulation in [:BMR, :CHR] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."

    #create binary indicator variables for each disjunction
    if args[1] isa Symbol #name for disjunction can be the first argument
        @assert isnothing(variable_by_name(m,string(args[1]))) "Name for disjunction binary cannot be the same as an existing variable."
        disj_name = args[1]
        disj = args[2:end]
    else #if name is not passed, then generate it
        disj_name = Symbol("disj",gensym())
        disj = args
    end
    eval(:(@variable($m, $disj_name[i = 1:length($disj)], Bin)))
    #enforce exclussive OR
    eval(:(@constraint($m,sum($disj_name[i] for i = 1:length($disj)) == 1)))
    #apply reformulation
    if reformulation == :BMR
        reformulate(m, disj, disj_name, reformulation, M)
    elseif reformulation == :CHR
        reformulate(m, disj, disj_name, reformulation, eps)
    end
end
