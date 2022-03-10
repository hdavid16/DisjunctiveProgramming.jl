function add_disjunction(m::Model,disj...;reformulation,M=missing,eps=1e-6,name=missing)
    @assert m isa Model "A valid JuMP Model must be provided."
    @assert reformulation in [:BMR, :CHR] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."
    @assert length(disj) > 1 "At least 2 disjuncts must be included."
    #create binary indicator variables for each disjunction
    disj_name = ismissing(name) ? Symbol("disj",gensym()) : name
    #check if indicator variable with that name already exists
    if disj_name in keys(object_dictionary(m))
        #check that the existing name is for a valid binary variable that can be used for the disjunction
        type_check = m[disj_name] isa Vector{VariableRef} #check it is a variable
        type_check2 = all([is_binary(disj_var_i) for disj_var_i in m[disj_name]]) #check it is binary
        dim_check = length(m[disj_name]) >= length(disj) #check the number of indices is at least the number of disjuncts
        @assert type_check && dim_check && type_check2 "An object of name $name is already attached to this model, but is not valid for use in the disjunction. $name must be a Vector of binary variables with dimension greater than or equal to that of the disjunction."
    else #create variable if it doesn't exist
        eval(:(@variable($m, $disj_name[i = 1:length($disj)], Bin)))
    end
    
    #enforce exclussive OR
    disj_var = m[disj_name]
    eval(:(@constraint($m,sum($disj_var[i] for i = 1:length($disj)) == 1)))
    #apply reformulation
    param = reformulation == :BMR ? M : eps
    reformulate(m, disj, disj_name, reformulation, param)
end
