using HiGHS

function test_linear_gdp_example()
    m = GDPModel(HiGHS.Optimizer)
    set_attribute(m, MOI.Silent(), true)
    @variable(m, 1 ≤ x[1:2] ≤ 9)
    @variable(m, Y[1:2], LogicalVariable)
    @variable(m, W[1:2], LogicalVariable)
    @objective(m, Max, sum(x))
    @constraint(m, y1[i=1:2], [1,4][i] ≤ x[i] ≤ [3,6][i], DisjunctConstraint(Y[1]))
    @constraint(m, w1[i=1:2], [1,5][i] ≤ x[i] ≤ [2,6][i], DisjunctConstraint(W[1]))
    @constraint(m, w2[i=1:2], [2,4][i] ≤ x[i] ≤ [3,5][i], DisjunctConstraint(W[2]))
    @constraint(m, y2[i=1:2], [8,1][i] ≤ x[i] ≤ [9,2][i], DisjunctConstraint(Y[2]))
    @disjunction(m, inner, [W[1], W[2]], DisjunctConstraint(Y[1]))
    @disjunction(m, outer, [Y[1], Y[2]])
    @constraint(m, Y in Exactly(1))
    @constraint(m, W in Exactly(Y[1]))

    optimize!(m, method = BigM())
    @test JuMP.termination_status(m) == MOI.OPTIMAL
    @test JuMP.objective_value(m) ≈ 11
    @test JuMP.value.(x) ≈ [9,2]
    bins = gdp_data(m).indicator_to_binary
    @test JuMP.value(bins[Y[1]]) ≈ 0
    @test JuMP.value(bins[Y[2]]) ≈ 1
    @test JuMP.value(bins[W[1]]) ≈ 0
    @test JuMP.value(bins[W[2]]) ≈ 0

    optimize!(m, method = Hull())
    @test JuMP.termination_status(m) == MOI.OPTIMAL
    @test JuMP.objective_value(m) ≈ 11
    @test JuMP.value.(x) ≈ [9,2]
    bins = gdp_data(m).indicator_to_binary
    @test JuMP.value(bins[Y[1]]) ≈ 0
    @test JuMP.value(bins[Y[2]]) ≈ 1
    @test JuMP.value(bins[W[1]]) ≈ 0
    @test JuMP.value(bins[W[2]]) ≈ 0
    @test JuMP.value(JuMP.variable_by_name(m, "x[1]_Y[1]")) ≈ 0
    @test JuMP.value(JuMP.variable_by_name(m, "x[1]_Y[2]")) ≈ 9
    @test JuMP.value(JuMP.variable_by_name(m, "x[1]_W[1]")) ≈ 0
    @test JuMP.value(JuMP.variable_by_name(m, "x[1]_W[2]")) ≈ 0
    @test JuMP.value(JuMP.variable_by_name(m, "x[2]_Y[1]")) ≈ 0
    @test JuMP.value(JuMP.variable_by_name(m, "x[2]_Y[2]")) ≈ 2
    @test JuMP.value(JuMP.variable_by_name(m, "x[2]_W[1]")) ≈ 0
    @test JuMP.value(JuMP.variable_by_name(m, "x[2]_W[2]")) ≈ 0
end

@testset "Solve Linear GDP" begin
    test_linear_gdp_example()
end