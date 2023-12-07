function test_disjunct_constraint_printing()
    # Set up the model
    model = GDPModel()
    @variable(model, x[1:2])
    @variable(model, Y[1:2], Logical)
    @constraint(model, c1, x[1]^2 >= 3.2, Disjunct(Y[1]))
    c2 = @constraint(model, x[2] <= 2, Disjunct(Y[2]))

    # Test plain printing
    if Sys.iswindows()
        show_test(MIME("text/plain"), c1, "c1 : x[1]² >= 3.2, if Y[1] = True")
        show_test(MIME("text/plain"), c2, "x[2] <= 2, if Y[2] = True") 
    else
        show_test(MIME("text/plain"), c1, "c1 : x[1]² ≥ 3.2, if Y[1] = True")
        show_test(MIME("text/plain"), c2, "x[2] ≤ 2, if Y[2] = True") 
    end

    # Test math mode string
    c1_str = "x_{1}^2 \\geq 3.2, \\; \\text{if } Y_{1} = \\text{True}"
    @test constraint_string(MIME("text/latex"), c1, in_math_mode = true) == c1_str
    c2_str = "x_{2} \\leq 2, \\; \\text{if } Y_{2} = \\text{True}"
    @test constraint_string(MIME("text/latex"), c2, in_math_mode = true) == c2_str

    # Test LaTeX printing
    show_test(MIME("text/latex"), c1, "\$\$ $(c1_str) \$\$")
    show_test(MIME("text/latex"), c2, "\$\$ $(c2_str) \$\$") 
end

function test_disjunction_printing()
    # Set up the model
    model = GDPModel()
    @variable(model, x[1:2])
    @variable(model, Y[1:2], Logical)
    @constraint(model, 2x[1]^2 >= 1, Disjunct(Y[1]))
    @constraint(model, x[2] - 1 == 2.1, Disjunct(Y[2]))
    @constraint(model, 0 <= x[1] <= 1, Disjunct(Y[2]))
    @disjunction(model, d1, Y)
    d2 = disjunction(model, Y)

    # Test plain printing
    if Sys.iswindows()
        str = "[Y[1] --> {2 x[1]² >= 1}] or [Y[2] --> {x[2] == 3.1; x[1] in [0, 1]}]"
        show_test(MIME("text/plain"), d1, "d1 : " * str)
        show_test(MIME("text/plain"), d2, str) 
    else
        str = "[Y[1] ⟹ {2 x[1]² ≥ 1}] ⋁ [Y[2] ⟹ {x[2] = 3.1; x[1] ∈ [0, 1]}]"
        show_test(MIME("text/plain"), d1, "d1 : " * str)
        show_test(MIME("text/plain"), d2, str) 
    end

    # Test math mode string
    str = "\\begin{bmatrix}\n Y_{1}\\\\\n 2 x_{1}^2 \\geq 1\\end{bmatrix} \\bigvee \\begin{bmatrix}\n Y_{2}\\\\\n x_{2} = 3.1\\\\\n x_{1} \\in [0, 1]\\end{bmatrix}"
    @test constraint_string(MIME("text/latex"), d1, in_math_mode = true) == str
    @test constraint_string(MIME("text/latex"), d2, in_math_mode = true) == str

    # Test LaTeX printing
    show_test(MIME("text/latex"), d1, "\$\$ $(str) \$\$")
    show_test(MIME("text/latex"), d2, "\$\$ $(str) \$\$") 
end

function test_nested_disjunction_printing()
    # Set up the model
    m = GDPModel()
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

    # Test plain printing
    if Sys.iswindows()
        inner = "[W[1] --> {x[1] in [1, 2]; x[2] in [5, 6]}] or [W[2] --> {x[1] in [2, 3]; x[2] in [4, 5]}]"
        str = "outer : [Y[1] --> {x[1] in [1, 3]; x[2] in [4, 6]; $(inner)}] or [Y[2] --> {x[1] in [8, 9]; x[2] in [1, 2]}]"
        show_test(MIME("text/plain"), outer, str)
    else
        inner = "[W[1] ⟹ {x[1] ∈ [1, 2]; x[2] ∈ [5, 6]}] ⋁ [W[2] ⟹ {x[1] ∈ [2, 3]; x[2] ∈ [4, 5]}]"
        str = "outer : [Y[1] ⟹ {x[1] ∈ [1, 3]; x[2] ∈ [4, 6]; $(inner)}] ⋁ [Y[2] ⟹ {x[1] ∈ [8, 9]; x[2] ∈ [1, 2]}]"
        show_test(MIME("text/plain"), outer, str)
    end
    inner = "\\begin{bmatrix}\n W_{1}\\\\\n x_{1} \\in [1, 2]\\\\\n x_{2} \\in [5, 6]\\end{bmatrix} \\bigvee \\begin{bmatrix}\n W_{2}\\\\\n x_{1} \\in [2, 3]\\\\\n x_{2} \\in [4, 5]\\end{bmatrix}"
    str = "\$\$ \\begin{bmatrix}\n Y_{1}\\\\\n x_{1} \\in [1, 3]\\\\\n x_{2} \\in [4, 6]\\\\\n $(inner)\\end{bmatrix} \\bigvee \\begin{bmatrix}\n Y_{2}\\\\\n x_{1} \\in [8, 9]\\\\\n x_{2} \\in [1, 2]\\end{bmatrix} \$\$"
    show_test(MIME("text/latex"), outer, str)
end

function test_logic_constraint_printing()
    # Set up the model
    model = GDPModel()
    @variable(model, x[1:2])
    @variable(model, Y[1:2], Logical)
    @constraint(model, c1, ¬(Y[1] && Y[2]) == (Y[1] || Y[2]) := true)
    c2 = @constraint(model, ¬(Y[1] && Y[2]) == (Y[1] || Y[2]) := true)
    
    # Test plain printing
    if Sys.iswindows()
        show_test(MIME("text/plain"), c1, "c1 : !(Y[1] and Y[2]) <--> (Y[1] or Y[2]) = True")
        show_test(MIME("text/plain"), c2, "!(Y[1] and Y[2]) <--> (Y[1] or Y[2]) = True") 
    else
        show_test(MIME("text/plain"), c1, "c1 : ¬(Y[1] ∧ Y[2]) ⟺ (Y[1] ∨ Y[2]) = True")
        show_test(MIME("text/plain"), c2, "¬(Y[1] ∧ Y[2]) ⟺ (Y[1] ∨ Y[2]) = True") 
    end

    # Test LaTeX printing
    str = "\$\$ {\\neg\\left({{Y[1]} \\wedge {Y[2]}}\\right)} \\iff {\\left({Y[1]} \\vee {Y[2]}\\right)} = \\text{True} \$\$"
    show_test(MIME("text/latex"), c1, str)
    show_test(MIME("text/latex"), c2, str)

    # Test cardinality constraints
    for (Set, s) in ((Exactly, "exactly"), (AtMost, "atmost"), (AtLeast, "atleast"))
       c3 = @constraint(model, Y in Set(1), base_name = "c3")
       c4 = @constraint(model, Y in Set(1))
       str = "$s(1, Y[1], Y[2])"
       show_test(MIME("text/plain"), c3, "c3 : $(str)")
       show_test(MIME("text/plain"), c4, str)
       str = "\$\$ \\text{$s}\\left(1, Y_{1}, Y_{2}\\right) \$\$"
       show_test(MIME("text/latex"), c3, str)
       show_test(MIME("text/latex"), c4, str)
    end
end

@testset "Printing" begin
    @testset "Disjunct Constraints" begin
        test_disjunct_constraint_printing()
    end
    @testset "Disjunctions" begin
        test_disjunction_printing()
        test_nested_disjunction_printing()
    end
    @testset "Logical Constraints" begin
        test_logic_constraint_printing()
    end
end
