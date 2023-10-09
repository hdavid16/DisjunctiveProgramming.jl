function test_default_bigm()
    method = BigM()
    @test method.value == 1e9
    @test method.tighten
end

function test_default_tighten_bigm()
    method = BigM(100)
    @test method.value == 100
    @test method.tighten
end

function test_set_bigm()
    method = BigM(1e6, false)
    @test method.value == 1e6
    @test !method.tighten
end

function test_get_M_1sided()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, 3*x <= 1, DisjunctConstraint(y))
    cobj = constraint_object(con)
    M = DP._get_M(cobj.func, cobj.set, BigM(100, false))
    @test M == 100
    @test_throws ErrorException DP._get_M(cobj.func, cobj.set, BigM(Inf, false))
end

function test_get_tight_M_1sided()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, 3*x <= 1, DisjunctConstraint(y))
    cobj = constraint_object(con)

    method = BigM(100)
    DP._query_variable_bounds(model, method)
    M = DP._get_tight_M(cobj.func, cobj.set, method)
    @test M == 100

    method = BigM(Inf)
    DP._query_variable_bounds(model, method)
    @test_throws ErrorException DP._get_tight_M(cobj.func, cobj.set, method)

    set_upper_bound(x, 10)
    method = BigM()
    DP._query_variable_bounds(model, method)
    M = DP._get_tight_M(cobj.func, cobj.set, method)
    @test M == 29
end

function test_get_M_2sided()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, 3*x == 1, DisjunctConstraint(y))
    cobj = constraint_object(con)

    method = BigM(100)
    M = DP._get_M(cobj.func, cobj.set, method)
    @test M[1] == 100
    @test M[2] == 100

    method = BigM(Inf)
    @test_throws ErrorException DP._get_M(cobj.func, cobj.set, method)
end

function test_get_tight_M_2sided()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, 3*x == 1, DisjunctConstraint(y))
    cobj = constraint_object(con)
    
    method = BigM(100)
    DP._query_variable_bounds(model, method)
    M = DP._get_tight_M(cobj.func, cobj.set, method)
    @test M[1] == 100
    @test M[2] == 100

    method = BigM(Inf)
    DP._query_variable_bounds(model, method)
    @test_throws ErrorException DP._get_tight_M(cobj.func, cobj.set, method)

    set_lower_bound(x, -10)
    set_upper_bound(x, 10)
    method = BigM()
    DP._query_variable_bounds(model, method)
    M = DP._get_tight_M(cobj.func, cobj.set, method)
    @test M[1] == 31
    @test M[2] == 29
end

function test_interval_arithmetic_LessThan()
    model = Model()
    @variable(model, x[1:3])
    @variable(model, y, Bin)
    @expression(model, func, -x[1] + 2*x[2] - 3*x[3] + 4*y + 5)

    method = BigM()
    DP._query_variable_bounds(model, method)
    M = DP._interval_arithmetic_LessThan(func, 0.0, method)
    @test isinf(M)

    set_upper_bound.(x, 10)
    method = BigM()
    DP._query_variable_bounds(model, method)
    M = DP._interval_arithmetic_LessThan(func, 0.0, method)
    @test isinf(M)

    set_lower_bound.(x, -10)
    method = BigM()
    DP._query_variable_bounds(model, method)
    M = DP._interval_arithmetic_LessThan(func, 0.0, method)
    @test M == -(-10) + 2*10 - 3*(-10) + 5 
end

function test_interval_arithmetic_GreaterThan()
    model = Model()
    @variable(model, x[1:3])
    @variable(model, y, Bin)
    @expression(model, func, -x[1] + 2*x[2] - 3*x[3] + 4*y + 5)

    method = BigM()
    DP._query_variable_bounds(model, method)
    M = DP._interval_arithmetic_GreaterThan(func, 0.0, method)
    @test isinf(M)

    set_upper_bound.(x, 10)
    method = BigM()
    DP._query_variable_bounds(model, method)
    M = DP._interval_arithmetic_GreaterThan(func, 0.0, method)
    @test isinf(M)

    set_lower_bound.(x, -10)
    method = BigM()
    DP._query_variable_bounds(model, method)
    M = DP._interval_arithmetic_GreaterThan(func, 0.0, method)
    @test -M == -(10) + 2*(-10) - 3*(10) + 5 
end

function test_calculate_tight_M()
    model = Model()
    @variable(model, -1 <= x <= 1)
    method = BigM()
    DP._query_variable_bounds(model, method)
    M = DP._calculate_tight_M(1*x, MOI.LessThan(5.0), method)
    @test M == -4
    M = DP._calculate_tight_M(1*x, MOI.GreaterThan(5.0), method)
    @test -M == -6
    M = DP._calculate_tight_M(1*x, MOI.Nonpositives(3), method)
    @test M == 1
    M = DP._calculate_tight_M(1*x, MOI.Nonnegatives(3), method)
    @test -M == -1
    M = DP._calculate_tight_M(1*x, MOI.Interval(5.0, 5.0), method)
    @test -M[1] == -6
    @test M[2] == -4
    M = DP._calculate_tight_M(1*x, MOI.EqualTo(5.0), method)
    @test -M[1] == -6
    @test M[2] == -4
    M = DP._calculate_tight_M(1*x, MOI.Zeros(3), method)
    @test -M[1] == -1
    @test M[2] == 1
    for ex in (x^2, exp(x)), set in (MOI.LessThan(5.0), MOI.GreaterThan(5.0), MOI.Nonpositives(4), MOI.Nonnegatives(4))
        M = DP._calculate_tight_M(ex, set, method)
        @test isinf(M)
    end
    for ex in (x^2, exp(x)), set in (MOI.Interval(5.0,5.0), MOI.EqualTo(5.0), MOI.Zeros(4))
        M = DP._calculate_tight_M(ex, set, method)
        @test all(isinf.(M))
    end
    @test_throws ErrorException DP._calculate_tight_M(1*x, MOI.SOS1([1.0,3.0,2.5]), method)
end

function test_lessthan_bigm()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, x <= 5, DisjunctConstraint(y))

    DP._reformulate_logical_variables(model)
    bvref = DP._indicator_to_binary(model)[y]
    ref = reformulate_disjunct_constraint(model, constraint_object(con), bvref, BigM(100, false))
    @test length(ref) == 1
    @test ref[1].func == x - 100*(-bvref)
    @test ref[1].set == MOI.LessThan(5.0 + 100)
end

function test_nonpositives_bigm()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, [x; x] <= [5; 5], DisjunctConstraint(y))

    DP._reformulate_logical_variables(model)
    bvref = DP._indicator_to_binary(model)[y]
    ref = reformulate_disjunct_constraint(model, constraint_object(con), bvref, BigM(100, false))
    @test length(ref) == 1
    @test ref[1].func[1] == x - 5 - 100*(1-bvref)
    @test ref[1].func[2] == x - 5 - 100*(1-bvref)
    @test ref[1].set == MOI.Nonpositives(2)
end

function test_greaterhan_bigm()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, x >= 5, DisjunctConstraint(y))

    DP._reformulate_logical_variables(model)
    bvref = DP._indicator_to_binary(model)[y]
    ref = reformulate_disjunct_constraint(model, constraint_object(con), bvref, BigM(100, false))
    @test length(ref) == 1
    @test ref[1].func == x + 100*(-bvref)
    @test ref[1].set == MOI.GreaterThan(5.0 - 100)
end

function test_nonnegatives_bigm()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, [x; x] >= [5; 5], DisjunctConstraint(y))

    DP._reformulate_logical_variables(model)
    bvref = DP._indicator_to_binary(model)[y]
    ref = reformulate_disjunct_constraint(model, constraint_object(con), bvref, BigM(100, false))
    @test length(ref) == 1
    @test ref[1].func[1] == x - 5 + 100*(1-bvref)
    @test ref[1].func[2] == x - 5 + 100*(1-bvref)
    @test ref[1].set == MOI.Nonnegatives(2)
end

function test_greaterhan_bigm()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, x == 5, DisjunctConstraint(y))

    DP._reformulate_logical_variables(model)
    bvref = DP._indicator_to_binary(model)[y]
    ref = reformulate_disjunct_constraint(model, constraint_object(con), bvref, BigM(100, false))
    @test length(ref) == 2
    @test ref[1].func == x + 100*(-bvref)
    @test ref[1].set == MOI.GreaterThan(5.0 - 100)
    @test ref[2].func == x - 100*(-bvref)
    @test ref[2].set == MOI.LessThan(5.0 + 100)
end

function test_greaterhan_bigm()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, 5 <= x <= 5, DisjunctConstraint(y))

    DP._reformulate_logical_variables(model)
    bvref = DP._indicator_to_binary(model)[y]
    ref = reformulate_disjunct_constraint(model, constraint_object(con), bvref, BigM(100, false))
    @test length(ref) == 2
    @test ref[1].func == x + 100*(-bvref)
    @test ref[1].set == MOI.GreaterThan(5.0 - 100)
    @test ref[2].func == x - 100*(-bvref)
    @test ref[2].set == MOI.LessThan(5.0 + 100)
end

function test_zeros_bigm()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, [x; x] == [5; 5], DisjunctConstraint(y))

    DP._reformulate_logical_variables(model)
    bvref = DP._indicator_to_binary(model)[y]
    ref = reformulate_disjunct_constraint(model, constraint_object(con), bvref, BigM(100, false))
    @test length(ref) == 2
    @test ref[1].func[1] == x - 5 + 100*(1-bvref)
    @test ref[1].func[2] == x - 5 + 100*(1-bvref)
    @test ref[1].set == MOI.Nonnegatives(2)
    @test ref[2].func[1] == x - 5 - 100*(1-bvref)
    @test ref[2].func[2] == x - 5 - 100*(1-bvref)
    @test ref[2].set == MOI.Nonpositives(2)
end

function test_nested_bigm()
    model = GDPModel()
    @variable(model, -100 <= x <= 100)
    @variable(model, y[1:2], LogicalVariable)
    @variable(model, z[1:2], LogicalVariable)
    @constraint(model, x <= 5, DisjunctConstraint(y[1]))
    @constraint(model, x >= 5, DisjunctConstraint(y[2]))
    @disjunction(model, inner, y, DisjunctConstraint(z[1]))
    @constraint(model, x <= 10, DisjunctConstraint(z[1]))
    @constraint(model, x >= 10, DisjunctConstraint(z[2]))
    @disjunction(model, outer, z)

    reformulate_model(model, BigM())
    bvrefs = DP._indicator_to_binary(model)
    refcons = constraint_object.(DP._reformulation_constraints(model))
    @test length(refcons) == 4
    @test refcons[1].func == x - 95*(-bvrefs[y[1]])
    @test refcons[1].set == MOI.LessThan(5.0 + 95)
    @test refcons[2].func == x + 105*(-bvrefs[y[2]])
    @test refcons[2].set == MOI.GreaterThan(5.0 - 105)
    @test refcons[3].func == x - 90*(-bvrefs[z[1]])
    @test refcons[3].set == MOI.LessThan(10.0 + 90)
    @test refcons[4].func == x + 110*(-bvrefs[z[2]])
    @test refcons[4].set == MOI.GreaterThan(10.0 - 110)
end

@testset "BigM Reformulation" begin
    test_default_bigm()
    test_default_tighten_bigm()
    test_set_bigm()
    test_get_M_1sided()
    test_get_tight_M_1sided()
    test_get_M_2sided()
    test_get_tight_M_2sided()
    test_interval_arithmetic_LessThan()
    test_interval_arithmetic_GreaterThan()
    test_calculate_tight_M()
    test_lessthan_bigm()
    test_nonpositives_bigm()
    test_greaterhan_bigm()
    test_nonnegatives_bigm()
    test_greaterhan_bigm()
    test_greaterhan_bigm()
    test_zeros_bigm()
    test_nested_bigm()
end