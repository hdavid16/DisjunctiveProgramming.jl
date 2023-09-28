function test_selector_constraint_add_fail()
    m = GDPModel()
    @variable(m, y[1:3], LogicalVariable)
    @test_throws ErrorException @constraint(JuMP.Model(), y in AtMost(2))
    @test_throws ErrorException @constraint(m, logical_or(y...) in Exactly(1))
    @test_throws ErrorException @constraint(m, sin.(y) in Exactly(1))
    @test_throws AssertionError @constraint(GDPModel(), y in AtMost(2))
    @test_throws MethodError @constraint(m, y in AtMost(1.0))
    @test_throws MethodError @constraint(m, y[1:2] in AtMost(1y[3]))
end

function test_selector_constraint_add_success()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    c1 = @constraint(model, y in Exactly(1))
    @constraint(model, c2, y in Exactly(1))
    @test JuMP.owner_model(c1) == model
    @test JuMP.is_valid(model, c1)
    @test JuMP.index(c1) == LogicalConstraintIndex(1)
    @test JuMP.name(c1) == ""
    @test JuMP.name(c2) == "c2"
    @test haskey(DP._logical_constraints(model), JuMP.index(c1))
    @test haskey(DP._logical_constraints(model), JuMP.index(c2))
    @test DP._logical_constraints(model)[JuMP.index(c1)] == DP._constraint_data(c1)
    @test 1 in JuMP.constraint_object(c1).func
    @test y[1] in JuMP.constraint_object(c1).func
    @test y[2] in JuMP.constraint_object(c1).func
    @test y[3] in JuMP.constraint_object(c1).func
    @test JuMP.constraint_object(c1).set == DP._MOIExactly(4)
    @test JuMP.constraint_object(c1).func == JuMP.constraint_object(c2).func
    @test JuMP.constraint_object(c1).set == JuMP.constraint_object(c2).set
    @test c1 == copy(c1)
end

function test_logical_constraint_set_name()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    c1 = @constraint(model, y in Exactly(1))
    JuMP.set_name(c1, "proposition")
    @test JuMP.name(c1) == "proposition"
end

function test_proposition_add_fail()
    m = GDPModel()
    @variable(m, y[1:3], LogicalVariable)
    @test_throws ErrorException @constraint(JuMP.Model(), logical_or(y...) in IsTrue())
    @test_throws ErrorException @constraint(m, logical_or(y...) == 2)
    @test_throws ErrorException @constraint(m, logical_or(y...) <= 1)
    @test_throws ErrorException @constraint(m, sum(y) in IsTrue())
    @test_throws ErrorException @constraint(m, prod(y) in IsTrue())
    @test_throws ErrorException @constraint(m, sin(y[1]) in IsTrue())
    @test_throws MethodError @constraint(m, logical_or(y...) == IsTrue())
    @test_throws AssertionError @constraint(GDPModel(), logical_or(y...) in IsTrue())
end

@testset "Logical Constraints" begin
    test_selector_constraint_add_fail()
    test_selector_constraint_add_success()
    test_logical_constraint_set_name()
    test_proposition_add_fail()
end