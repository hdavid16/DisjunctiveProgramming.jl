using HiGHS

function test_linear_gdp_example(m)
    set_attribute(m, MOI.Silent(), true)
    @variable(m, 1 ≤ x[1:2] ≤ 9)
    @variable(m, Y[1:2], Logical)
    @variable(m, W[1:2], Logical)
    @objective(m, Max, sum(x))
    @constraint(m, y1[i=1:2], [1,4][i] ≤ x[i] ≤ [3,6][i], Disjunct(Y[1]))
    @constraint(m, w1[i=1:2], [1,5][i] ≤ x[i] ≤ [2,6][i], Disjunct(W[1]))
    @constraint(m, w2[i=1:2], [2,4][i] ≤ x[i] ≤ [3,5][i], Disjunct(W[2]))
    @constraint(m, y2[i=1:2], [8,1][i] ≤ x[i] ≤ [9,2][i], Disjunct(Y[2]))
    @disjunction(m, inner, [W[1], W[2]], Disjunct(Y[1]))
    @disjunction(m, outer, [Y[1], Y[2]])

    optimize!(m, method = BigM())
    @test termination_status(m) == MOI.OPTIMAL
    @test objective_value(m) ≈ 11
    @test value.(x) ≈ [9,2]
    bins = gdp_data(m).indicator_to_binary
    @test value(bins[Y[1]]) ≈ 0
    @test value(bins[Y[2]]) ≈ 1
    @test value(bins[W[1]]) ≈ 0
    @test value(bins[W[2]]) ≈ 0

    optimize!(m, method = Hull())
    @test termination_status(m) == MOI.OPTIMAL
    @test objective_value(m) ≈ 11
    @test value.(x) ≈ [9,2]
    bins = gdp_data(m).indicator_to_binary
    @test value(bins[Y[1]]) ≈ 0
    @test value(bins[Y[2]]) ≈ 1
    @test value(bins[W[1]]) ≈ 0
    @test value(bins[W[2]]) ≈ 0
    @test value(variable_by_name(m, "x[1]_Y[1]")) ≈ 0
    @test value(variable_by_name(m, "x[1]_Y[2]")) ≈ 9
    @test value(variable_by_name(m, "x[1]_W[1]")) ≈ 0
    @test value(variable_by_name(m, "x[1]_W[2]")) ≈ 0
    @test value(variable_by_name(m, "x[2]_Y[1]")) ≈ 0
    @test value(variable_by_name(m, "x[2]_Y[2]")) ≈ 2
    @test value(variable_by_name(m, "x[2]_W[1]")) ≈ 0
    @test value(variable_by_name(m, "x[2]_W[2]")) ≈ 0
end

function test_generic_model(m)
    set_attribute(m, MOI.Silent(), true)
    @variable(m, 1 ≤ x[1:2] ≤ 9)
    @variable(m, Y[1:2], Logical)
    @variable(m, W[1:2], Logical)
    @objective(m, Max, sum(x))
    @constraint(m, y1[i=1:2], [1,4][i] ≤ x[i] ≤ [3,6][i], Disjunct(Y[1]))
    @constraint(m, w1[i=1:2], [1,5][i] ≤ x[i] ≤ [2,6][i], Disjunct(W[1]))
    @constraint(m, w2[i=1:2], [2,4][i] ≤ x[i] ≤ [3,5][i], Disjunct(W[2]))
    @constraint(m, y2[i=1:2], [8,1][i] ≤ x[i] ≤ [9,2][i], Disjunct(Y[2]))
    @disjunction(m, inner, [W[1], W[2]], Disjunct(Y[1]))
    @disjunction(m, outer, [Y[1], Y[2]])

    optimize!(m, method = BigM())
    optimize!(m, method = Hull())

    # TODO add meaningful tests once we find an appropriate solver
end

@testset "Solve Linear GDP" begin
    test_linear_gdp_example(GDPModel(HiGHS.Optimizer))
    mockoptimizer = () -> MOI.Utilities.MockOptimizer(
        MOI.Utilities.UniversalFallback(MOIU.Model{Float32}()),
        eval_objective_value = false
        )
    test_generic_model(GDPModel{Float32}(mockoptimizer))
end