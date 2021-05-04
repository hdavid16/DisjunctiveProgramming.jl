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
    name = pos_args[2]
    disjunct = pos_args[3]

    for (k, d) in enumerate(disjunct.args)
        dname = Symbol(name,"_$k")
        c = [i for i in d.args if isa(i,Expr)]
        if length(c) == 1
            eval(:(@constraint($model, $dname, $(c[1]))))
        elseif length(c) > 1
            for (j, ci) in enumerate(c)
                dnamej = Symbol(dname,"_$j")
                eval(:(@constraint($model, $dnamej, $ci)))
            end
        end
    end
end

@disjunction(m, disj1,
                [begin
                    0<=x[1]<=3
                    0<=x[2]<=4
                 end,
                 begin
                    5<=x[1]<=9
                    4<=x[2]<=6
                 end
                ])

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
