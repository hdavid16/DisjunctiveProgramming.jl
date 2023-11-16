using HiGHS

function test_GDPData()
    @test GDPData{Model, VariableRef, ConstraintRef}() isa GDPData{Model, VariableRef, ConstraintRef, Float64}
end

function test_empty_model()
    @test GDPModel{GenericModel{Float16}, GenericVariableRef{Float16}, ConstraintRef}() isa GenericModel{Float16}
    @test GDPModel{Int}() isa GenericModel{Int}
    @test GDPModel{MyModel, MyVarRef, MyConRef}() isa MyModel
    model = GDPModel()
    @test gdp_data(model) isa GDPData
    @test isempty(DP._logical_variables(model))
    @test isempty(DP._logical_constraints(model))
    @test isempty(DP._disjunct_constraints(model))
    @test isempty(DP._disjunctions(model))
    @test isempty(DP._exactly1_constraints(model))
    @test isempty(DP._indicator_to_binary(model))
    @test isempty(DP._indicator_to_constraints(model))
    @test isempty(DP._constraint_to_indicator(model))
    @test isempty(DP._reformulation_variables(model))
    @test isempty(DP._reformulation_constraints(model))
    @test isempty(DP._variable_bounds(model))
    @test isnothing(DP._solution_method(model))
    @test !DP._ready_to_optimize(model)
end

function test_non_gdp_model()
    model = Model()
    @test_throws ErrorException gdp_data(model)
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
    test_GDPData()
    test_empty_model()
    test_non_gdp_model()
    test_creation_optimizer()
    test_set_optimizer()
end