function test_default_hull()
    method = Hull()
    @test method.value == 1e-6
end

function test_set_hull()
    method = Hull(0.001)
    @test method.value == 0.001
end

function test_query_variable_bounds()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, -100 <= y <= -10)
    method = Hull()
    DP._query_variable_bounds(model, method)
    @test haskey(method.variable_bounds, x)
    @test haskey(method.variable_bounds, y)
    @test method.variable_bounds[x] == (0, 100)
    @test method.variable_bounds[y] == (-100, 0)
end

function test_query_variable_bounds_error1()
    model = GDPModel()
    @variable(model, x <= 100)
    method = Hull()
    @test_throws ErrorException DP._query_variable_bounds(model, method)
end

function test_query_variable_bounds_error2()
    model = GDPModel()
    @variable(model, -100 <= x)
    method = Hull()
    @test_throws ErrorException DP._query_variable_bounds(model, method)
end

function test_disaggregate_variables()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, y, Bin)
    @variable(model, z, Logical)
    vrefs = Set{VariableRef}() #initialize empty set to check if method.disjunct_variables has variables added to it in _disaggregate_variable call
    DP._reformulate_logical_variables(model)
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), vrefs)
    vrefs = Set([x,y])
    DP._disaggregate_variables(model, z, vrefs, method)

    refvars = DP._reformulation_variables(model)
    @test length(refvars) == 2
    zbin = variable_by_name(model, "z")
    @test zbin in refvars
    x_z = variable_by_name(model, "x_z")
    @test x_z in refvars
    @test has_lower_bound(x_z) && lower_bound(x_z) == 0
    @test has_upper_bound(x_z) && upper_bound(x_z) == 100
    @test name(x_z) == "x_z"
    x_z_lb = constraint_by_name(model, "x_z_lower_bound") |> constraint_object
    @test x_z_lb.func == -x_z
    @test x_z_lb.set == MOI.LessThan(0.)
    x_z_ub = constraint_by_name(model, "x_z_upper_bound") |> constraint_object
    @test x_z_ub.func == -100zbin + x_z
    @test x_z_ub.set == MOI.LessThan(0.)
end

function test_aggregate_variable()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    vrefs = Set([x])
    DP._reformulate_logical_variables(model)
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    refcons = Vector{JuMP.AbstractConstraint}() 
    DP._aggregate_variable(model, refcons, x, method)
    @test length(refcons) == 1
    @test refcons[1].func == -x + sum(method.disjunction_variables[x])
    @test refcons[1].set == MOI.EqualTo(0.)
end

function test_disaggregate_expression_var_binary()
    model = GDPModel()
    @variable(model, x, Bin)
    @variable(model, z, Logical)
    DP._reformulate_logical_variables(model)
    bvrefs = DP._indicator_to_binary(model)

    vrefs = Set([x])
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 1.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    @test isnothing(variable_by_name(model, "x_z"))
    
    refexpr = DP._disaggregate_expression(model, x, bvrefs[z], method)
    @test refexpr == x
end

function test_disaggregate_expression_var()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    DP._reformulate_logical_variables(model)
    bvrefs = DP._indicator_to_binary(model)

    vrefs = Set([x])
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    
    refexpr = DP._disaggregate_expression(model, x, bvrefs[z], method)
    x_z = variable_by_name(model, "x_z")
    @test refexpr == x_z
end

function test_disaggregate_expression_affine()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    DP._reformulate_logical_variables(model)
    bvrefs = DP._indicator_to_binary(model)

    vrefs = Set([x])
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    
    refexpr = DP._disaggregate_expression(model, 2x + 1, bvrefs[z], method)
    x_z = variable_by_name(model, "x_z")
    zbin = variable_by_name(model, "z")
    @test refexpr == 2x_z + 1zbin
end

function test_disaggregate_expression_quadratic()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    DP._reformulate_logical_variables(model)
    bvrefs = DP._indicator_to_binary(model)

    vrefs = Set([x])
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    
    refexpr = DP._disaggregate_expression(model, 2x^2 + 1, bvrefs[z], method)
    x_z = variable_by_name(model, "x_z")
    zbin = variable_by_name(model, "z")
    ϵ = method.value
    @test refexpr.head == :+
    @test 1zbin in refexpr.args
    arg2 = setdiff(refexpr.args, [1zbin])[1]
    @test arg2.head == :/
    @test 2x_z^2 in arg2.args
    @test (1-ϵ)*zbin+ϵ in arg2.args
end

function test_disaggregate_nl_expression_c()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    DP._reformulate_logical_variables(model)
    bvrefs = DP._indicator_to_binary(model)

    vrefs = Set([x])
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    
    refexpr = DP._disaggregate_nl_expression(model, 1, bvrefs[z], method)
    @test refexpr == 1
end

function test_disaggregate_nl_expression_var_binary()
    model = GDPModel()
    @variable(model, x, Bin)
    @variable(model, z, Logical)
    DP._reformulate_logical_variables(model)
    bvrefs = DP._indicator_to_binary(model)

    vrefs = Set([x])
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 1.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    
    refexpr = DP._disaggregate_nl_expression(model, x, bvrefs[z], method)
    @test refexpr == x
end

function test_disaggregate_nl_expression_var()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    DP._reformulate_logical_variables(model)
    bvrefs = DP._indicator_to_binary(model)

    vrefs = Set([x])
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    
    refexpr = DP._disaggregate_nl_expression(model, x, bvrefs[z], method)
    x_z = variable_by_name(model, "x_z")
    zbin = variable_by_name(model, "z")
    ϵ = method.value
    @test refexpr.head == :/
    @test x_z in refexpr.args
    @test (1-ϵ)*zbin+ϵ in refexpr.args
end

function test_disaggregate_nl_expression_aff()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    DP._reformulate_logical_variables(model)
    bvrefs = DP._indicator_to_binary(model)

    vrefs = Set([x])
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    
    refexpr = DP._disaggregate_nl_expression(model, 2x + 1, bvrefs[z], method)
    x_z = variable_by_name(model, "x_z")
    zbin = variable_by_name(model, "z")
    ϵ = method.value
    @test refexpr.head == :+
    @test 1 in refexpr.args
    arg2 = setdiff(refexpr.args, [1])[1]
    @test arg2.head == :/
    @test 2x_z in arg2.args
    @test (1-ϵ)*zbin+ϵ in arg2.args
end

function test_disaggregate_nl_expression_quad()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    DP._reformulate_logical_variables(model)
    bvrefs = DP._indicator_to_binary(model)

    vrefs = Set([x])
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    
    refexpr = DP._disaggregate_nl_expression(model, 2x^2 + 1, bvrefs[z], method)
    x_z = variable_by_name(model, "x_z")
    zbin = variable_by_name(model, "z")
    ϵ = method.value
    @test refexpr.head == :+
    @test 1 in refexpr.args
    arg2 = setdiff(refexpr.args, [1])[1]
    @test arg2.head == :/
    @test 2x_z^2 in arg2.args
    @test ((1-ϵ)*zbin+ϵ)^2 in arg2.args
end

function test_disaggregate_nl_expession()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    DP._reformulate_logical_variables(model)
    bvrefs = DP._indicator_to_binary(model)

    vrefs = Set([x])
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), vrefs)
    DP._disaggregate_variables(model, z, vrefs, method)
    
    refexpr = DP._disaggregate_nl_expression(model, 2x^3 + 1, bvrefs[z], method)
    x_z = variable_by_name(model, "x_z")
    zbin = variable_by_name(model, "z")
    ϵ = method.value
    @test refexpr.head == :+
    @test 1 in refexpr.args
    arg2 = setdiff(refexpr.args, [1zbin])[1]
    @test arg2.head == :*
    @test 2 in arg2.args
    arg3 = setdiff(arg2.args, [2])[1]
    @test arg3.head == :^
    @test arg3.args[2] == 3
    @test arg3.args[1].head == :/
    @test x_z in arg3.args[1].args
    @test (1-ϵ)*zbin+ϵ in arg3.args[1].args
end
#less than, greater than, equalto
function test_scalar_var_hull_1sided(moiset)
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, x in moiset(5), DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 1
    @test ref[1].func == x_z - 5*zbin
    @test ref[1].set isa moiset
    @test DP._set_value(ref[1].set) == 0
end
#less than, greater than, equalto
function test_scalar_affine_hull_1sided(moiset)
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, 1x in moiset(5), DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 1
    @test ref[1].func == x_z - 5*zbin
    @test ref[1].set isa moiset
    @test DP._set_value(ref[1].set) == 0
end
#nonpositives, nonnegatives, zeros
function test_vector_var_hull_1sided(moiset)
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, [x; x] in moiset(2), DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 1
    @test ref[1].func == [x_z; x_z]
    @test ref[1].set == moiset(2)
end
#nonpositives, nonnegatives, zeros
function test_vector_affine_hull_1sided(moiset)
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, [x - 5; x - 5] in moiset(2), DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    method = DP._Hull(Hull(1e-3, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 1
    @test ref[1].func == [x_z - 5*zbin; x_z - 5*zbin]
    @test ref[1].set == moiset(2)
end
#less than, greater than, equalto
function test_scalar_quadratic_hull_1sided(moiset)
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, x^2 in moiset(5), DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 1
    @test ref[1].func.head == :-
    @test 5zbin in ref[1].func.args
    arg2 = setdiff(ref[1].func.args, [5zbin])[1]
    @test 0*zbin in arg2.args
    arg3 = setdiff(arg2.args, [0*zbin])[1]
    @test arg3.head == :/
    @test x_z^2 in arg3.args
    @test (1-ϵ)*zbin+ϵ in arg3.args
    @test ref[1].set isa moiset
    @test DP._set_value(ref[1].set) == 0
end
#nonpositives, nonnegatives, zeros
function test_vector_quadratic_hull_1sided(moiset)
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, [x^2 - 5; x^2 - 5] in moiset(2), DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 1
    @test length(ref[1].func) == 2
    for i in 1:2
        @test ref[1].func[i].head == :+
        @test -5zbin in ref[1].func[i].args
        arg2 = setdiff(ref[1].func[i].args, [-5zbin])[1]
        @test arg2.head == :/
        @test x_z^2 in arg2.args
        @test (1-ϵ)*zbin+ϵ in arg2.args
    end
    @test ref[1].set == moiset(2)
end
#less than, greater than, equalto
function test_scalar_nonlinear_hull_1sided_error()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, log(x) <= 10, DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    @test_throws ErrorException reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
end
function test_scalar_nonlinear_hull_1sided(moiset)
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, x^3 in moiset(5), DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 1
    @test ref[1].func.head == :-
    @test 5zbin in ref[1].func.args
    arg2 = setdiff(ref[1].func.args, [5zbin])[1]
    @test 0*zbin in arg2.args
    arg3 = setdiff(arg2.args, [0*zbin])[1]
    @test arg3.head == :*
    @test (1-ϵ)*zbin+ϵ in arg3.args
    arg4 = setdiff(arg3.args, [(1-ϵ)*zbin+ϵ])[1]
    @test arg4.head == :^
    @test arg4.args[2] == 3
    @test arg4.args[1].head == :/
    @test x_z in arg4.args[1].args
    @test (1-ϵ)*zbin+ϵ in arg4.args[1].args
    @test ref[1].set isa moiset
    @test DP._set_value(ref[1].set) == 0
end
#nonpositives, nonnegatives, zeros
function test_vector_nonlinear_hull_1sided_error()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, [log(x),log(x)] <= [10,10], DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    @test_throws ErrorException reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
end
function test_vector_nonlinear_hull_1sided(moiset)
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, [x^3 - 5; x^3 - 5] in moiset(2), DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 1
    @test length(ref[1].func) == 2
    for i in 1:2
        @test ref[1].func[i].head == :-
        @test -5*ϵ*(1-zbin) in ref[1].func[i].args
        arg2 = setdiff(ref[1].func[i].args, [-5*ϵ*(1-zbin)])[1]
        @test arg2.head == :*
        @test (1-ϵ)*zbin+ϵ in arg2.args
        arg3 = setdiff(arg2.args, [(1-ϵ)*zbin+ϵ])[1]
        @test arg3.head == :-
        @test 5 in arg3.args
        arg4 = setdiff(arg3.args, [5])[1]
        @test arg4.head == :^
        @test arg4.args[2] == 3
        @test arg4.args[1].head == :/
        @test x_z in arg4.args[1].args
        @test (1-ϵ)*zbin+ϵ in arg4.args[1].args
    end
    @test ref[1].set == moiset(2)
end
#interval
function test_scalar_var_hull_2sided()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, x in MOI.Interval(5,5), DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 2
    sets = (MOI.GreaterThan, MOI.LessThan)
    for i in 1:2
        @test ref[i].func == x_z - 5*zbin
        @test ref[i].set isa sets[i]
        @test DP._set_value(ref[1].set) == 0
    end
end
function test_scalar_affine_hull_2sided()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, 5 <= x <= 5, DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 2
    sets = (MOI.GreaterThan, MOI.LessThan)
    for i in 1:2
        @test ref[i].func == x_z - 5*zbin
        @test ref[i].set isa sets[i]
        @test DP._set_value(ref[1].set) == 0
    end
end
function test_scalar_quadratic_hull_2sided()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, 5 <= x^2 <= 5, DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 2
    sets = (MOI.GreaterThan, MOI.LessThan)
    for i in 1:2
        @test ref[i].func.head == :-
        @test 5zbin in ref[i].func.args
        arg2 = setdiff(ref[i].func.args, [5zbin])[1]
        @test 0*zbin in arg2.args
        arg3 = setdiff(arg2.args, [0*zbin])[1]
        @test arg3.head == :/
        @test x_z^2 in arg3.args
        @test (1-ϵ)*zbin+ϵ in arg3.args
        @test ref[i].set isa sets[i]
        @test DP._set_value(ref[i].set) == 0
    end
end
function test_scalar_nonlinear_hull_2sided_error()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, 0 <= log(x) <= 10, DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    @test_throws ErrorException reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
end
function test_scalar_nonlinear_hull_2sided()
    model = GDPModel()
    @variable(model, 10 <= x <= 100)
    @variable(model, z, Logical)
    @constraint(model, con, 5 <= x^3 <= 5, DisjunctConstraint(z))
    DP._reformulate_logical_variables(model)
    zbin = variable_by_name(model, "z")
    ϵ = 1e-3
    method = DP._Hull(Hull(ϵ, Dict(x => (0., 100.))), Set([x]))
    DP._disaggregate_variables(model, z, Set([x]), method)
    x_z = variable_by_name(model, "x_z")
    ref = reformulate_disjunct_constraint(model, constraint_object(con), zbin, method)
    @test length(ref) == 2
    sets = (MOI.GreaterThan, MOI.LessThan)
    for i in 1:2
        @test ref[i].func.head == :-
        @test 5zbin in ref[i].func.args
        arg2 = setdiff(ref[i].func.args, [5zbin])[1]
        @test 0*zbin in arg2.args
        arg3 = setdiff(arg2.args, [0*zbin])[1]
        @test arg3.head == :*
        @test (1-ϵ)*zbin+ϵ in arg3.args
        arg4 = setdiff(arg3.args, [(1-ϵ)*zbin+ϵ])[1]
        @test arg4.head == :^
        @test arg4.args[2] == 3
        @test arg4.args[1].head == :/
        @test x_z in arg4.args[1].args
        @test (1-ϵ)*zbin+ϵ in arg4.args[1].args
        @test ref[i].set isa sets[i]
        @test DP._set_value(ref[i].set) == 0
    end
end

@testset "Hull Reformulation" begin
    test_default_hull()
    test_set_hull()
    test_query_variable_bounds()
    test_query_variable_bounds_error1()
    test_query_variable_bounds_error2()
    test_disaggregate_variables()
    test_aggregate_variable()
    test_disaggregate_expression_var_binary()
    test_disaggregate_expression_var()
    test_disaggregate_expression_affine()
    test_disaggregate_expression_quadratic()
    test_disaggregate_nl_expression_c()
    test_disaggregate_nl_expression_var_binary()
    test_disaggregate_nl_expression_var()
    test_disaggregate_nl_expression_aff()
    test_disaggregate_nl_expression_quad()
    test_disaggregate_nl_expession()
    for s in (MOI.LessThan, MOI.GreaterThan, MOI.EqualTo)
        test_scalar_var_hull_1sided(s)
        test_scalar_affine_hull_1sided(s)
        test_scalar_quadratic_hull_1sided(s)        
        test_scalar_nonlinear_hull_1sided(s)
    end
    test_scalar_nonlinear_hull_1sided_error()
    for s in (MOI.Nonpositives, MOI.Nonnegatives, MOI.Zeros)
        test_vector_var_hull_1sided(s)
        test_vector_affine_hull_1sided(s)
        test_vector_quadratic_hull_1sided(s)        
        test_vector_nonlinear_hull_1sided(s)
    end
    test_vector_nonlinear_hull_1sided_error()
    test_scalar_var_hull_2sided()
    test_scalar_affine_hull_2sided()
    test_scalar_quadratic_hull_2sided()
    test_scalar_nonlinear_hull_2sided()
    test_scalar_nonlinear_hull_2sided_error()
end