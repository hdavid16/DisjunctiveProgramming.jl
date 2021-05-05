using JuMP, GLPK

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
        @assert reformulation_method in [:(:BMR), :(:CHR)] "Invalid reformulation method passed to keyword argument `:reformulation`. Valid options are :BMR (Big-M Reformulation) and :CHR (Convex-Hull Reormulation)."
    else
        throw(UndefKeywordError(:reformulation))
    end

    if reformulation_method == :(:BMR)
        M = filter(i -> i.args[1] == :BigM, kw_args)
        if isempty(M)
            M = 0 #initialize Big-M
            @warn "No BigM value passed for use in Big-M Reformulation. A value will be inferred."
        else
            M = eval(M[1])
        end
    end

    for (k, disjunct) in enumerate(x)
       name_k = Symbol(c,"_$k") #name for the constraint
       varname_k = Symbol(c,"_$(k)_var") #name for the binary indicator variable
       eval(:(@variable($model, $varname_k, Bin))) #create binary indicator variable

       #extract constraints for the disjunct
       xk = filter(i -> Meta.isexpr(i,:comparison) || Meta.isexpr(i,:call), disjunct.args)
       if !isempty(xk) #add constraints
           for (j, xkj) in enumerate(xk)
               #get variables and associated bounds for the constraint
               vars = filter(i -> Meta.isexpr(i,:ref), xkj.args)
               has_bounds = Dict(var => (eval(:(has_lower_bound($var))), eval(:(has_upper_bound($var)))) for var in vars)
               bounds = Dict(var => (eval(:(lower_bound($var))), eval(:(upper_bound($var)))) for var in vars)
               #create constraint
               name_k_j = Symbol(name_k,"_$j")
               eval(:(@constraint($model, $name_k_j, $xkj)))
               coeff = Dict(var => eval(:(normalized_coefficient($name_k_j,$var))) for var in vars)
               xkj_set = eval(:(constraint_object($name_k_j))).set
               xkj_set_fields = fieldnames(typeof(xkj_set))
               #add big-M
               if eval(reformulation_method) == :BMR
                   if M == 0
                       LB, UB = 0., 0.
                       for var in vars
                           if coeff[var] > 0
                               if :upper in xkj_set_fields && has_bounds[var][2]
                                   UB += coeff[var]*bounds[var][2]
                               elseif :lower in xkj_set_fields && has_bounds[var][1]
                                   LB += coeff[var]*bounds[var][1]
                               else
                                   error("BigM parameter cannot be infered due to lack of variable bounds.")
                               end
                           elseif coeff[var] < 0
                               if :lower in xkj_set_fields && has_bounds[var][2]
                                   LB += coeff[var]*bounds[var][2]
                               elseif :upper in xkj_set_fields && has_bounds[var][1]
                                   UB += coeff[var]*bounds[var][1]
                               else
                                   error("BigM parameter cannot be infered due to lack of variable bounds.")
                               end
                           end
                       end
                       if :lower in xkj_set_fields && :upper in xkj_set_fields #NOTE: THIS TYPE OF CONSTRAINT NEEDS TO BE SPLIT INTO TWO!!!
                           M = max(abs(LB - xkj_set.lower), abs(UB - xkj_set.upper))
                       elseif :lower in xkj_set_fields
                           M = LB - xkj_set.lower
                       elseif :upper in xkj_set_fields
                           M = UB - xkj_set.upper
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

m = Model(GLPK.Optimizer)
@variable(m, y)
@variable(m, 0<=x[1:2]<=10)


@disjunction(m, disj,
                 begin
                    x[1]<=3
                    0<=x[1]
                    x[2]<=4
                    0<=x[2]
                 end,
                 begin
                    x[1]<=9
                    5<=x[1]
                    x[2]<=6
                    4<=x[2]
                 end
                , reformulation = :BMR)#, BigM = 100)


#=
macro disjunction(args...)
    return _disjunction_macro(args)
end

function _disjunction_macro(args)
    pos_args, kw_args, requestedcontainer = Containers._extract_kw_args(args)
    model = pos_args[1]#eval(pos_args[1])
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
