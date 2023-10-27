function test_reformulate_disjunct_constraint_fallback()
    model = GDPModel()
    @variable(model, x)
    c = build_constraint(error, 1x, MOI.LessThan(1))
    @test_throws ErrorException reformulate_disjunct_constraint(model, c, x, DummyReformulation())
end

function test_exclusive_fallback()
    @test requires_exclusive(BigM()) == false
end

@testset "Fallbacks" begin
    test_reformulate_disjunct_constraint_fallback()
    test_exclusive_fallback()
end