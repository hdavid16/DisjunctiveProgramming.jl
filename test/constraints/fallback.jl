function test_reformulate_disjunct_constraint_fallback()
    model = GDPModel()
    @variable(model, x)
    c = build_constraint(error, 1x, MOI.LessThan(1))
    @test_throws ErrorException reformulate_disjunct_constraint(model, c, x, DummyReformulation())
end

function test_exactly1_fallback()
    @test requires_exactly1(BigM()) == false
end

@testset "Fallbacks" begin
    test_reformulate_disjunct_constraint_fallback()
    test_exactly1_fallback()
end