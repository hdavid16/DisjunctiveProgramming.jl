function add_disjunction(m::Model,disj...;reformulation,M=missing,eps=1e-6,name=missing)
    @assert m isa Model "A valid JuMP Model must be provided."
    @assert reformulation in [:BMR, :CHR] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."
    @assert length(disj) > 1 "At least 2 disjuncts must be included."
    #create binary indicator variables for each disjunction
    disj_name = ismissing(name) ? Symbol("disj",gensym()) : name
    #check indicator variable doesn't exist and create it
    if disj_name in keys(object_dictionary(m))
        error("The disjunction name $disj_name already exists as a model object. Specify a name that is not present in the model's object_dictionary.")
    else #create variable if it doesn't exist
        eval(:(@variable($m, $disj_name[i = 1:length($disj)], Bin)))
    end
    
    #enforce exclussive OR
    #NOTE: This needs to be enforced with a logical proposition!
    # disj_var = m[disj_name]
    # @constraint(m,sum(disj_var[i] for i = 1:length(disj)) == 1)
    #apply reformulation
    param = reformulation == :BMR ? M : eps
    reformulate_disjunction(m, disj, disj_name, reformulation, param)
end
