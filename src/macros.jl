macro disjunction(args...)
    pos_args, kw_args, requestedcontainer = Containers._extract_kw_args(args)
    m = pos_args[1]
    println(m)
    @assert eval(:($m isa Model)) "$m must be a JuMP Model."
    disj = pos_args[2:end]
    #get reformulation method
    method = filter(i -> i.args[1] == :reformulation, kw_args)
    if !isempty(method)
        reformulation_method = method[1].args[2]
        @assert reformulation_method in [:(:BMR), :(:CHR)] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."
    else
        throw(UndefKeywordError(:reformulation))
    end
    #Big-M
    if reformulation_method == :(:BMR)
        M = filter(i -> i.args[1] == :BigM, kw_args)
        if isempty(M)
            M = nothing #initialize Big-M
            @warn "No BigM value passed for use in Big-M Reformulation. BigM values will be inferred from variable bounds."
        else
            M = eval(:($M.args[2]))
        end
    end
    #get all variable names
    vars = eval(:(all_variables($m)))
    #apply reformulation
    for (i,arg) in enumerate(disj)
        var_name = Symbol("disj_ind_$i") #create disjunction indicator binary
        eval(:(@variable($m,$var_name,Bin)))
        if Meta.isexpr(arg, :tuple) || Meta.isexpr(arg,:vect)
            for (j,a) in enumerate(arg.args)
                @assert eval(:($a in keys(($m).obj_dict))) "$a is not a constraint in the model."
                @assert eval(:(is_valid($m,$m[$a]))) "$a is not a valid constraint in the model."
                arg_set = eval(:(constraint_object($m[$a]))).set
                set_fields = fieldnames(typeof(arg_set))
                @assert length(set_fields) == 1 "A reformulation cannot be done on constraint $a because it is not one of the following GreaterThan, LessThan, or EqualTo."

                if reformulation_method == :(:BMR)
                    apply_BigM(M, m, a, arg_set, set_fields, vars, var_name)
                elseif reformulation_method == :(:CHR)

                end
            end
        else
            @assert eval(:($arg in keys(($m).obj_dict))) "$arg is not a constraint in the model."
            @assert eval(:(is_valid($m,$m[$arg]))) "$arg is not a valid constraint in the model."
            arg_set = eval(:(constraint_object($m[$arg]))).set
            set_fields = fieldnames(typeof(arg_set))
            @assert length(set_fields) == 1 "A reformulation cannot be done on constraint $arg because it is not one of the following GreaterThan, LessThan, or EqualTo."

            if reformulation_method == :(:BMR)
                apply_BigM(M, m, arg, arg_set, set_fields, vars, var_name)
            elseif reformulation_method == :(:CHR)

            end
        end
    end
end

function infer_BigM(m, arg, arg_set, set_fields, vars)
    @assert :value in set_fields || :lower in set_fields || :upper in set_fields "$arg must be one the following: GreaterThan, LessThan, or EqualTo."
    BigM = 0 #initialize BigM
    for var in vars
        coeff = eval(:(normalized_coefficient($m[$arg],$var)))
        iszero(coeff) && continue
        has_bounds = (eval(:(has_lower_bound($var))), eval(:(has_upper_bound($var))))
        if coeff > 0
            if :lower in set_fields && has_bounds[1]
                bound = eval(:(lower_bound($var)))
            elseif :upper in set_fields || :value in set_fields && has_bounds[2]
                bound = eval(:(upper_bound($var)))
            else
                error("BigM parameter cannot be infered due to lack of variable bounds for variable $var.")
            end
            BigM += coeff*bound
        elseif coeff < 0
            if :lower in set_fields && has_bounds[2]
                bound = eval(:(upper_bound($var)))
            elseif :upper in set_fields || :value in set_fields && has_bounds[1]
                bound = eval(:(lower_bound($var)))
            else
                error("BigM parameter cannot be infered due to lack of variable bounds for variable $var.")
            end
            BigM += coeff*bound
        end
    end
    if :lower in set_fields
        BigM -= arg_set.lower
    elseif :upper in set_fields
        BigM -= arg_set.upper
    elseif :value in set_fields
        BigM -= arg_set.value
    end

    return BigM
end

function apply_BigM(M, m, arg, arg_set, set_fields, vars, var_name)
    if M isa Number
        BigM = M
    elseif M isa Vector || M isa Tuple
        @assert M[i] isa Number "$arg was passed more than 1 BigM value"
        BigM = M[i]
    else
        BigM = infer_BigM(m, arg, arg_set, set_fields, vars)
    end
    eval(:(add_to_function_constant($m[$arg], -$BigM)))
    eval(:(set_normalized_coefficient($m[$arg], $var_name , $BigM)))
end
