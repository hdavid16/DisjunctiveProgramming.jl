function add_disjunction(m::Model,disj...;reformulation=:BMR,M=missing,kw_args...)
    @assert m isa Model "A valid JuMP Model must be provided."
    @assert reformulation in [:BMR, :CHR] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."

    #create binary indicator variables for each disjunction
    bin_var = Symbol("disj_binary_",gensym())
    eval(:(@variable($m, $bin_var[i = 1:length($disj)], Bin)))
    #enforce exclussive OR
    eval(:(@constraint($m,sum($bin_var[i] for i = 1:length($disj)) == 1)))
    #apply reformulation
    eval(:($reformulation($M, $m, $disj, $bin_var)))
end
