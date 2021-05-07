function add_disjunction(m::Model,disj...;reformulation=:BMR,M=missing,kw_args...)
    @assert m isa Model "A valid JuMP Model must be provided."
    @assert reformulation in [:BMR, :CHR] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."

    #create binary indicator variables for each disjunction
    bin_var = Symbol("disj_binary_",gensym())
    eval(:(@variable($m, $bin_var[i = 1:length($disj)], Bin)))
    #enforce exclussive OR
    eval(:(@constraint($m,sum($bin_var[i] for i = 1:length($disj)) == 1)))
    #apply reformulation
    for (i,constr) in enumerate(disj)
        if constr isa Vector || constr isa Tuple
            for (j,constr_j) in enumerate(constr)
                if reformulation == :BMR
                    BMR(M, m, constr_j, bin_var, i, j)
                elseif reformulation == :CHR

                end
            end
        elseif constr isa ConstraintRef || typeof(constr) <: Array || constr isa JuMP.Containers.DenseAxisArray
            if reformulation == :BMR
                BMR(M, m, constr, bin_var, i)
            elseif reformulation == :(:CHR)

            end
        end
    end
end
