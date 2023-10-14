function test_reformulate_disjunct_constraint_fallback()
    model = GDPModel()
    @variable(model, x)
    c = build_constraint(error, 1x, MOI.LessThan(1))
    @test_throws ErrorException reformulate_disjunct_constraint(model, c, x, DummyReformulation())
end

@testset "Fallbacks" begin
    test_reformulate_disjunct_constraint_fallback()
end