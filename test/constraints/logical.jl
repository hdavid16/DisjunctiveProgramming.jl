function test_add_selector_fail_1()
    @variable(GDPModel(), y[1:3], LogicalVariable)
    @test_throws ErrorException @constraint(JuMP.Model(), y in AtMost(2))
    @test_throws AssertionError @constraint(GDPModel(), y in AtMost(2))
end
function test_add_selector_fail_2()
    m = GDPModel()
    @variable(m, y[1:3], LogicalVariable)
    @test_throws MethodError @constraint(m, y in AtMost(1.0))
    @test_throws MethodError @constraint(m, y[1:2] in AtMost(1y[3]))
end

function test_add_proposition_fail_1()
    @variable(GDPModel(), y[1:3], LogicalVariable)
    @test_throws ErrorException @constraint(JuMP.Model(), logical_or(y...) == true)
    @test_throws AssertionError @constraint(GDPModel(), logical_or(y...) == true)
end
function test_add_proposition_fail_2()
    m = GDPModel()
    @variable(m, y[1:3], LogicalVariable)
    @constraint(m, logical_or(y...) == 2)
end