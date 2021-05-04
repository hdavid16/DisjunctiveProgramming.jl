using JuMP, GLPK

m = Model(GLPK.Optimizer)
@variable(m, y)
@variable(m, x[1:2])

macro disjunction(args...)
    return _disjunction_macro(args)
end

function _disjunction_macro(args)
    pos_args, kw_args, requestedcontainer = Containers._extract_kw_args(args)
    model = pos_args[1]
    y = pos_args[2]
    if isa(y, Symbol)
        c = y
        x = pos_args[3:end]
    else
        c = gensym()
        x = pos_args[2:end]
    end

    method = filter(i -> i.args[1] == :reformulation, kw_args)
    if !isempty(method)
        reformulation_method = method[1].args[2]
        @assert eval(reformulation_method) in [:BMR, :CHR] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."
    else
        error(UndefKeywordError,": keyword argument reformulation not assigned. Valid options are `:BMR` (Big-M Reformulation) and `:CHR` (Convex-Hull Reormulation).")
    end

    if eval(reformulation_method) == :BMR
        M = filter(i -> i.args[1] == :BigM, kw_args)
        if isempty(M)
            M = :(0) #initialize Big-M
            @warn "No BigM value passed for use in Big-M Reformulation. A value will be inferred."
        else
            M = M[1]
        end
    end

    for (k, disjunct) in enumerate(x)
        name_k = Symbol(c,"_$k") #name for the constraint
        varname_k = Symbol(c,"_$(k)_var") #name for the binary indicator variable
        eval(:(@variable($model, $varname_k, Bin))) #create binary indicator variable

        #extract constraints for the disjunct
        xk = [i for i in disjunct.args if Meta.isexpr(i,:comparison) || Meta.isexpr(i,:call)]
        if !isempty(xk) #add constraints
            for (j, xkj) in enumerate(xk)
                #create constraint
                name_k_j = Symbol(name_k,"_$j")
                eval(:(@constraint($model, $name_k_j, $xkj)))
                #add big-M
                if eval(reformulation_method) == :BMR
                    if eval(M) == 0
                        vars = filter(i -> Meta.isexpr(i,:ref), xkj.args)
                        for var in vars
                            coeff = eval(:(normalized_coefficient($name_k_j,$var)))
                            lb, ub = :(nothing), :(nothing)
                            if eval(:(has_lower_bound($var)))
                                lb = eval(:(lower_bound($var)))
                            end
                            if eval(:(has_upper_bound($var)))
                                ub = eval(:(upper_bound($var)))
                            end
                        end
                    end
                    eval(:(add_to_function_constant($name_k_j, -$M)))
                    eval(:(set_normalized_coefficient($name_k_j, $varname_k, $M)))
                #convex-hull reformulation
                elseif eval(reformulation_method) == :CHR

                end
            end
        end
    end
end

@disjunction(m, disj,
                 begin
                    0<=x[1]<=3
                    0<=x[2]<=4
                 end,
                 begin
                    5<=x[1]<=9
                    4<=x[2]<=6
                 end
                , reformulation = :BMR, BigM = 100)


#=
macro disjunction(args...)
    return _disjunction_macro(args)
end

function _disjunction_macro(args)
    pos_args, kw_args, requestedcontainer = Containers._extract_kw_args(args)
    model = pos_args[1]#esc(pos_args[1])
    disj = pos_args[2]

    for d in disj.args
        for i in d.args
            if isa(i,Expr)
                eval(:(@constraint($model,$i)))
            end
        end
    end
end

@disjunction(m,  [begin
                    0<=x[1]<=3
                    0<=x[2]<=4
                 end,
                 begin
                    5<=x[1]<=9
                    4<=x[2]<=6
                 end
                ])
=#
