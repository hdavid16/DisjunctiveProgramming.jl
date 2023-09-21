function test_empty_model()
    model = GDPModel()
    @test gdp_data(model) isa GDPData
    @test isempty(DP._logical_variables(model))
    @test isempty(DP._logical_constraints(model))
    @test isempty(DP._disjunct_constraints(model))
    @test isempty(DP._disjunctions(model))
    @test isempty(DP._indicator_to_binary(model))
    @test isempty(DP._indicator_to_constraints(model))
    @test isempty(DP._reformulation_variables(model))
    @test isempty(DP._reformulation_constraints(model))
    @test isnothing(DP._solution_method(model))
    @test !DP._ready_to_optimize(model)
end

function test_non_gdp_model()
    model = JuMP.Model()
    @test_throws ErrorException gdp_dta(model)
end

function test_creation_optimizer()
    model = GDPModel(HiGHS.Optimizer)
    @test solver_name(model) == "HiGHS"
end

function test_set_optimizer()
    model = GDPModel()
    set_optimizer(model, HiGHS.Optimizer)
    @test solver_name(model) == "HiGHS"
end

@testset "GDP Model" begin
    test_empty_model()
    test_non_gdp_model()
    test_optimizer_set()
    test_set_optimizer()
end