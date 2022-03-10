function add_disjunction(m::Model,disj...;reformulation,M=missing,eps=1e-6,name=missing)
    @assert m isa Model "A valid JuMP Model must be provided."
    @assert reformulation in [:BMR, :CHR] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."
    @assert length(disj) > 1 "At least 2 disjuncts must be included."
    #create binary indicator variables for each disjunction
    disj_name = ismissing(name) ? Symbol("disj",gensym()) : name
    @assert isnothing(variable_by_name(m,string(disj_name))) "Name for disjunction binary cannot be the same as an existing variable."
    eval(:(@variable($m, $disj_name[i = 1:length($disj)], Bin)))
    #enforce exclussive OR
    eval(:(@constraint($m,sum($disj_name[i] for i = 1:length($disj)) == 1)))
    #apply reformulation
    param = reformulation == :BMR ? M : eps
    reformulate(m, disj, disj_name, reformulation, param)
end
