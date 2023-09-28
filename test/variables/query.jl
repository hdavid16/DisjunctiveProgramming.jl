function test_interrogate_non_variables()
    vars = Set()
    f = Base.Fix1(push!, vars) #interrogator
    #numbers
    DP._interrogate_variables(f, 1)
    @test isempty(vars)
    empty!(vars)
    DP._interrogate_variables(f, 1.0)
    @test isempty(vars)
    empty!(vars)
    #strings/symbols
    @test_throws ErrorException DP._interrogate_variables(f, "a")
    @test_throws ErrorException DP._interrogate_variables(f, :a)
end

function test_interrogate_variables()
    vars = Set()
    f = Base.Fix1(push!, vars) #interrogator
    m = GDPModel()
    @variable(m, x)
    @variable(m, y, LogicalVariable)
    DP._interrogate_variables(f, [x, y])
    @test x in vars
    @test y in vars
    @test length(vars) == 2
end

function test_interrogate_affexpr()
    vars = Set()
    f = Base.Fix1(push!, vars) #interrogator
    m = GDPModel()
    @variable(m, x)
    @variable(m, y, LogicalVariable)
    @variable(m, z)
    DP._interrogate_variables(f, x + y + z)
    @test x in vars
    @test y in vars
    @test z in vars
    @test length(vars) == 3
end

function test_interrogate_quadexpr()
    vars = Set()
    f = Base.Fix1(push!, vars) #interrogator
    m = GDPModel()
    @variable(m, x)
    @variable(m, y, LogicalVariable)
    @variable(m, z)
    DP._interrogate_variables(f, x^2 + x*y + z + 1)
    @test x in vars
    @test y in vars
    @test z in vars
    @test length(vars) == 3
    empty!(vars)
end

function test_interrogate_nonlinear_expr()
    vars = Set()
    f = Base.Fix1(push!, vars) #interrogator
    m = GDPModel()
    @variable(m, x)
    @variable(m, y, LogicalVariable)
    @variable(m, z)
    DP._interrogate_variables(f, sin(exp(x^2 + 1)) + cos(x) + y + 2)
    @test x in vars
    @test y in vars
    @test !(z in vars)
    @test length(vars) == 2
end

function test_interrogate_logical_expr()
    vars = Set()
    f = Base.Fix1(push!, vars) #interrogator
    m = GDPModel()
    @variable(m, y, LogicalVariable)
    @variable(m, w[1:5], LogicalVariable)
    ex = (implies(w[1], w[2]) ∧ w[3]) ⇔ (¬w[4] ∨ y)
    DP._interrogate_variables(f, ex)
    @test w[1] in vars
    @test w[2] in vars
    @test w[3] in vars
    @test w[4] in vars
    @test !(w[5] in vars)
    @test y in vars
    @test length(vars) == 5
end

function test_interrogate_proposition_constraint()
    m = GDPModel()
    @variable(m, y, LogicalVariable)
    @variable(m, w[1:5], LogicalVariable)
    ex = (implies(w[1], w[2]) ∧ w[3]) ⇔ (¬w[4] ∨ y)
    @constraint(m, con, ex in IsTrue())
    obj = JuMP.constraint_object(con)
    vars = DP._get_constraint_variables(m, obj)
    @test w[1] in vars
    @test w[2] in vars
    @test w[3] in vars
    @test w[4] in vars
    @test !(w[5] in vars)
    @test y in vars
    @test length(vars) == 5
end

function test_interrogate_selector_constraint()
    m = GDPModel()
    @variable(m, y, LogicalVariable)
    @variable(m, w[1:5], LogicalVariable)
    @constraint(m, con, w[1:4] in AtMost(y))
    obj = JuMP.constraint_object(con)
    vars = DP._get_constraint_variables(m, obj)
    @test w[1] in vars
    @test w[2] in vars
    @test w[3] in vars
    @test w[4] in vars
    @test !(w[5] in vars)
    @test y in vars
    @test length(vars) == 5
end

function test_interrogate_disjunction()
    m = GDPModel()
    @variable(m, -5 ≤ x[1:2] ≤ 10)
    @variable(m, Y[1:2], LogicalVariable)
    @constraint(m, [i = 1:2], 0 ≤ x[i] ≤ [3,4][i], DisjunctConstraint(Y[1]))
    @constraint(m, [i = 1:2], [5,4][i] ≤ x[i] ≤ [9,6][i], DisjunctConstraint(Y[2]))
    @disjunction(m, Y)
    disj = DP._disjunctions(m)[DisjunctionIndex(1)].constraint
    vars = DP._get_disjunction_variables(m, disj)
    @test Set(x) == vars
end

function test_interrogate_nested_disjunction()
    m = GDPModel()
    @variable(m, -5 <= x[1:3] <= 5)

    @variable(m, y[1:2], LogicalVariable)
    @constraint(m, x[1] <= -2, DisjunctConstraint(y[1]))
    @constraint(m, x[1] >= 2, DisjunctConstraint(y[2]))
    @disjunction(m, y)

    @variable(m, w[1:2], LogicalVariable)
    @constraint(m, x[2] <= -3, DisjunctConstraint(w[1]))
    @constraint(m, x[2] >= 3, DisjunctConstraint(w[2]))
    @disjunction(m, w, DisjunctConstraint(y[1]))

    @variable(m, z[1:2], LogicalVariable)
    @constraint(m, x[3] <= -4, DisjunctConstraint(z[1]))
    @constraint(m, x[3] >= 4, DisjunctConstraint(z[2]))
    @disjunction(m, z, DisjunctConstraint(w[1]))

    disj = DP._disjunctions(m)[DisjunctionIndex(1)].constraint
    vars = DP._get_disjunction_variables(m, disj)
    @test Set(x) == vars
end

@testset "Variable Interrogation" begin
    test_interrogate_non_variables()
    test_interrogate_variables()
    test_interrogate_affexpr()
    test_interrogate_quadexpr()
    test_interrogate_nonlinear_expr()
    test_interrogate_logical_expr()
    test_interrogate_proposition_constraint()
    test_interrogate_selector_constraint()
    test_interrogate_disjunction()
    test_interrogate_nested_disjunction()
end