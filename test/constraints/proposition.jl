function test_proposition_add_fail()
    m = GDPModel()
    @variable(m, y[1:3], LogicalVariable)
    @test_throws ErrorException @constraint(Model(), logical_or(y...) in IsTrue())
    @test_throws ErrorException @constraint(m, logical_or(y...) == 2)
    @test_throws ErrorException @constraint(m, logical_or(y...) <= 1)
    @test_throws ErrorException @constraint(m, sum(y) in IsTrue())
    @test_throws ErrorException @constraint(m, prod(y) in IsTrue())
    @test_throws ErrorException @constraint(m, sin(y[1]) in IsTrue())
    @test_throws MethodError @constraint(m, logical_or(y...) == IsTrue())
    @test_throws AssertionError @constraint(GDPModel(), logical_or(y...) in IsTrue())
end

function test_negation_add_success()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    c1 = @constraint(model, logical_not(y) in IsTrue())
    @constraint(model, c2, ¬y in IsTrue())
    @test is_valid(model, c1)
    @test is_valid(model, c2)
    @test owner_model(c1) == model
    @test owner_model(c2) == model
    @test name(c1) == ""
    @test name(c2) == "c2"
    @test index(c1) == LogicalConstraintIndex(1)
    @test index(c2) == LogicalConstraintIndex(2)
    @test haskey(DP._logical_constraints(model), index(c1))
    @test haskey(DP._logical_constraints(model), index(c2))
    @test DP._logical_constraints(model)[index(c1)] == DP._constraint_data(c1)
    @test constraint_object(c1).func isa DP._LogicalExpr
    @test constraint_object(c2).func isa DP._LogicalExpr
    @test constraint_object(c1).func.head == 
            constraint_object(c2).func.head == :¬
    @test constraint_object(c1).func.args ==
            constraint_object(c2).func.args == Any[y]
    @test constraint_object(c1).set == 
            constraint_object(c2).set == IsTrue()
    @test c1 == copy(c1)
end

function test_implication_add_success()
    model = GDPModel()
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, c1, implies(y...) in IsTrue())
    @constraint(model, c2, (y[1] ⟹ y[2]) in IsTrue())
    @test_macro_throws ErrorException @constraint(model, y[1] ⟹ y[2] in IsTrue())
    @test constraint_object(c1).func.head == 
            constraint_object(c2).func.head == :⟹
    @test constraint_object(c1).func.args ==
            constraint_object(c2).func.args == Vector{Any}(y)
    @test constraint_object(c1).set == 
            constraint_object(c2).set == IsTrue()
end

function test_equivalence_add_success()
    model = GDPModel()
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, c1, iff(y...) in IsTrue())
    @constraint(model, c2, (y[1] ⇔ y[2]) in IsTrue())
    @test_macro_throws ErrorException @constraint(model, y[1] ⇔ y[2] in IsTrue())
    @test constraint_object(c1).func.head == 
            constraint_object(c2).func.head == :⇔
    @test constraint_object(c1).func.args ==
            constraint_object(c2).func.args == Vector{Any}(y)
    @test constraint_object(c1).set == 
            constraint_object(c2).set == IsTrue()
end

function test_intersection_and_flatten_add_success()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    @constraint(model, c1, logical_and(y...) in IsTrue())
    @constraint(model, c2, ∧(y...) in IsTrue())
    @constraint(model, c3, y[1] ∧ y[2] ∧ y[3] in IsTrue())
    @test is_valid(model, c1)
    @test is_valid(model, c2)
    @test is_valid(model, c3)
    @test constraint_object(c1).func.head == 
            constraint_object(c2).func.head == 
            constraint_object(c3).func.head == :∧
    @test Set(constraint_object(c1).func.args) ==
            Set(constraint_object(c2).func.args) ==
            Set(DP._flatten(constraint_object(c3).func).args)
    @test constraint_object(c1).set == 
            constraint_object(c2).set == 
            constraint_object(c3).set == IsTrue()
end

function test_union_and_flatten_add_success()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    @constraint(model, c1, logical_or(y...) in IsTrue())
    @constraint(model, c2, ∨(y...) in IsTrue())
    @constraint(model, c3, y[1] ∨ y[2] ∨ y[3] in IsTrue())
    @test is_valid(model, c1)
    @test is_valid(model, c2)
    @test is_valid(model, c3)
    @test constraint_object(c1).func.head == 
            constraint_object(c2).func.head == 
            constraint_object(c3).func.head == :∨
    @test Set(constraint_object(c1).func.args) ==
            Set(constraint_object(c2).func.args) ==
            Set(DP._flatten(constraint_object(c3).func).args)
    @test constraint_object(c1).set == 
            constraint_object(c2).set == 
            constraint_object(c3).set == IsTrue()
end

function test_proposition_add_array()
    model = GDPModel()
    @variable(model, y[1:2, 1:3, 1:4], LogicalVariable)
    @constraint(model, con[i=1:2,j=1:3], ∨(y[i,j,:]...) in IsTrue())
    @test con isa Matrix{LogicalConstraintRef}
    @test length(con) == 6
end

function test_proposition_add_dense_axis()
    model = GDPModel()
    I = ["a", "b", "c"]
    J = [1, 2]
    @variable(model, y[I, J, 1:4], LogicalVariable)
    @constraint(model, con[i=I,j=J], ∨(y[i,j,:]...) in IsTrue())
    @test con isa Containers.DenseAxisArray
    @test con.axes[1] == ["a","b","c"]
    @test con.axes[2] == [1,2]
    @test con.data isa Matrix{LogicalConstraintRef}
end

function test_proposition_add_sparse_axis()
    model = GDPModel()
    @variable(model, y[1:3, 1:3, 1:4], LogicalVariable)
    @constraint(model, con[i=1:3,j=1:3; j > i], ∨(y[i,j,:]...) in IsTrue())
    @test con isa Containers.SparseAxisArray
    @test length(con) == 3
    @test con.names == (:i, :j)
    @test Set(keys(con.data)) == Set([(1,2),(1,3),(2,3)])
end

function test_proposition_set_name()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    c1 = @constraint(model, logical_not(y...) in IsTrue())
    set_name(c1, "proposition")
    @test name(c1) == "proposition"
end

function test_proposition_delete()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    c1 = @constraint(model, logical_not(y...) in IsTrue())

    @test_throws AssertionError delete(GDPModel(), c1)
    delete(model, c1)
    @test !haskey(gdp_data(model).logical_constraints, index(c1))
    @test !DP._ready_to_optimize(model)
end

function test_negation_reformulation()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    @constraint(model, ¬y in IsTrue()) 
    reformulate_model(model, DummyReformulation())
    ref_con = DP._reformulation_constraints(model)[1]
    @test is_valid(model, ref_con)
    ref_con_obj = constraint_object(ref_con)
    @test ref_con_obj.set == MOI.GreaterThan(0.0)
    @test ref_con_obj.func == -DP._indicator_to_binary(model)[y]
end

function test_implication_reformulation()
    model = GDPModel()
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, implies(y[1], y[2]) in IsTrue())
    reformulate_model(model, DummyReformulation())
    ref_con = DP._reformulation_constraints(model)[1]
    @test is_valid(model, ref_con)
    ref_con_obj = constraint_object(ref_con)
    @test ref_con_obj.set == MOI.GreaterThan(0.0)
    @test ref_con_obj.func == 
        -DP._indicator_to_binary(model)[y[1]] +
        DP._indicator_to_binary(model)[y[2]]
end

function test_implication_reformulation_fail()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    @constraint(model, implies(y...) in IsTrue())
    @test_throws ErrorException reformulate_model(model, DummyReformulation())
end

function test_equivalence_reformulation()
    model = GDPModel()
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, iff(y[1], y[2]) in IsTrue())
    reformulate_model(model, DummyReformulation())
    ref_cons = DP._reformulation_constraints(model)
    @test all(is_valid.(model, ref_cons))
    ref_con_objs = constraint_object.(ref_cons)
    @test ref_con_objs[1].set == 
            ref_con_objs[2].set == MOI.GreaterThan(0.0)
    @test ref_con_objs[1].func == -ref_con_objs[2].func
    bvars = DP._indicator_to_binary(model)
    for con in ref_cons
        @test normalized_coefficient(con, bvars[y[1]]) ==
                -normalized_coefficient(con, bvars[y[2]])
    end
end

function test_intersection_reformulation()
    model = GDPModel()
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, ∧(y[1], y[2]) in IsTrue())
    reformulate_model(model, DummyReformulation())
    ref_cons = DP._reformulation_constraints(model)
    @test all(is_valid.(model, ref_cons))
    ref_con_objs = constraint_object.(ref_cons)
    @test ref_con_objs[1].set == 
            ref_con_objs[2].set == MOI.GreaterThan(1.0)
    bvars = DP._indicator_to_binary(model)
    funcs = [ref_con_objs[1].func, ref_con_objs[2].func]
    @test 1bvars[y[1]] in funcs
    @test 1bvars[y[2]] in funcs
end

function test_implication_reformulation()
    model = GDPModel()
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, ∨(y[1], y[2]) in IsTrue())
    reformulate_model(model, DummyReformulation())
    ref_con = DP._reformulation_constraints(model)[1]
    @test is_valid(model, ref_con)
    ref_con_obj = constraint_object(ref_con)
    @test ref_con_obj.set == MOI.GreaterThan(1.0)
    @test ref_con_obj.func == 
        DP._indicator_to_binary(model)[y[1]] +
        DP._indicator_to_binary(model)[y[2]]
end

function test_lvar_cnf_functions()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    @test DP._eliminate_equivalence(y) == y
    @test DP._eliminate_implication(y) == y
    @test DP._move_negations_inward(y) == y
    neg_y = DP._negate(y)
    @test neg_y.head == :¬
    @test neg_y.args[1] == y
    @test DP._distribute_and_over_or(y) == y
    @test DP._flatten(y) == y
end

function test_eliminate_equivalence()
    model = GDPModel()
    @variable(model, y[1:2], LogicalVariable)
    ex = y[1] ⇔ y[2]
    new_ex = DP._eliminate_equivalence(ex)
    @test new_ex.head == :∧
    @test length(new_ex.args) == 2
    @test new_ex.args[1].head == :⟹
    @test new_ex.args[2].head == :⟹
    @test Set(new_ex.args[1].args) == Set{Any}(y)
    @test Set(new_ex.args[2].args) == Set{Any}(y)
end

function test_eliminate_equivalence_flat()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    ex = iff(y...)
    new_ex = DP._eliminate_equivalence(ex)
    @test new_ex.head == :∧
    @test new_ex.args[1].head == :⟹
    @test new_ex.args[1].args[1] == y[1]
    @test new_ex.args[1].args[2].head == :∧
    @test y[2] in new_ex.args[1].args[2].args[1].args
    @test y[3] in new_ex.args[1].args[2].args[1].args
    @test y[2] in new_ex.args[1].args[2].args[2].args
    @test y[3] in new_ex.args[1].args[2].args[2].args
    @test new_ex.args[1].args[1] == new_ex.args[2].args[2]
    @test new_ex.args[1].args[2] == new_ex.args[2].args[1]
end

function test_eliminate_equivalence_nested()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    ex = iff(y[1], iff(y[2],y[3]))
    new_ex = DP._eliminate_equivalence(ex)
    @test new_ex.head == :∧
    @test new_ex.args[1].head == :⟹
    @test new_ex.args[1].args[1] == y[1]
    @test new_ex.args[1].args[2].head == :∧
    @test y[2] in new_ex.args[1].args[2].args[1].args
    @test y[3] in new_ex.args[1].args[2].args[1].args
    @test y[2] in new_ex.args[1].args[2].args[2].args
    @test y[3] in new_ex.args[1].args[2].args[2].args
    @test new_ex.args[1].args[1] == new_ex.args[2].args[2]
    @test new_ex.args[1].args[2] == new_ex.args[2].args[1]
end

function test_eliminate_implication()
    model = GDPModel()
    @variable(model, y[1:2], LogicalVariable)
    ex = y[1] ⟹ y[2]
    new_ex = DP._eliminate_implication(ex)
    @test new_ex.head == :∨
    @test new_ex.args[1].head == :¬
    @test new_ex.args[1].args[1] == y[1]
    @test new_ex.args[2] == y[2]
end

function test_eliminate_implication_error()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    ex = implies(y...)
    @test_throws ErrorException DP._eliminate_implication(ex)
end

function test_eliminate_implication_nested()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    ex = (y[1] ⟹ y[2]) ⟹ y[3]
    new_ex = DP._eliminate_implication(ex)
    @test new_ex.head == :∨
    @test new_ex.args[1].head == :¬
    @test new_ex.args[1].args[1].head == :∨
    @test new_ex.args[1].args[1].args[1].head == :¬
    @test new_ex.args[1].args[1].args[1].args[1] == y[1]
    @test new_ex.args[1].args[1].args[2] == y[2]
    @test new_ex.args[2] == y[3]
end

function test_move_negation_inward_error()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    ex = ¬(y, y)
    @test_throws ErrorException DP._move_negations_inward(ex)
end

function test_move_negation_inward()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    ex = ¬y
    new_ex = DP._move_negations_inward(ex)
    @test new_ex.head == :¬
    @test new_ex.args[1] == y
end

function test_move_negation_inward_nested()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    ex = ¬¬y
    @test DP._move_negations_inward(ex) == y
end

function test_negate_error()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    @test_throws ErrorException DP._negate(iff(y,y))
end

function test_negate_or()
    model = GDPModel()
    @variable(model, y[1:2], LogicalVariable)
    ex = ∨(y...)
    new_ex = DP._negate_or(ex)
    @test new_ex.head == :∧
    @test new_ex.args[1].head == :¬
    @test new_ex.args[1].args[1] == y[1]
    @test new_ex.args[2].head == :¬
    @test new_ex.args[2].args[1] == y[2]
end

function test_negate_or_error()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    @test_throws ErrorException DP._negate_or(∨(y))
end

function test_negate_and()
    model = GDPModel()
    @variable(model, y[1:2], LogicalVariable)
    ex = ∧(y...)
    new_ex = DP._negate_and(ex)
    @test new_ex.head == :∨
    @test new_ex.args[1].head == :¬
    @test new_ex.args[1].args[1] == y[1]
    @test new_ex.args[2].head == :¬
    @test new_ex.args[2].args[1] == y[2]    
end

function test_negate_and_error()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    @test_throws ErrorException DP._negate_or(∧(y))
end

function test_negate_negation()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    @test DP._negate_negation(¬y) == y
end

function test_negate_negation_error()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    @test_throws ErrorException DP._negate_negation(¬(y,y))
end

function test_distribute_and_over_or()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    ex = y[1] ∨ (y[2] ∧ y[3])
    new_ex = DP._distribute_and_over_or(ex)
    @test new_ex.head == :∧
    @test new_ex.args[1].head == 
            new_ex.args[2].head == :∨
    @test y[1] in new_ex.args[1].args
    @test y[1] in new_ex.args[2].args
    @test y[2] in new_ex.args[1].args || y[2] in new_ex.args[2].args
    @test y[3] in new_ex.args[1].args || y[3] in new_ex.args[2].args
end

function test_distribute_and_over_or_nested()
    model = GDPModel()
    @variable(model, y[1:4], LogicalVariable)
    ex = (y[1] ∧ y[2]) ∨ (y[3] ∧ y[4])
    new_ex = DP._flatten(DP._distribute_and_over_or(ex))
    for arg in new_ex.args
        @test arg.head == :∨
    end
    @test (y[1] in new_ex.args[1].args && y[3] in new_ex.args[1].args) ||
        (y[1] in new_ex.args[2].args && y[3] in new_ex.args[2].args) ||
        (y[1] in new_ex.args[3].args && y[3] in new_ex.args[3].args) ||
        (y[1] in new_ex.args[4].args && y[3] in new_ex.args[4].args)

    @test (y[1] in new_ex.args[1].args && y[4] in new_ex.args[1].args) ||
        (y[1] in new_ex.args[2].args && y[4] in new_ex.args[2].args) ||
        (y[1] in new_ex.args[3].args && y[4] in new_ex.args[3].args) ||
        (y[1] in new_ex.args[4].args && y[4] in new_ex.args[4].args)

    @test (y[2] in new_ex.args[1].args && y[3] in new_ex.args[1].args) ||
        (y[2] in new_ex.args[2].args && y[3] in new_ex.args[2].args) ||
        (y[2] in new_ex.args[3].args && y[3] in new_ex.args[3].args) ||
        (y[2] in new_ex.args[4].args && y[3] in new_ex.args[4].args)

    @test (y[2] in new_ex.args[1].args && y[4] in new_ex.args[1].args) ||
        (y[2] in new_ex.args[2].args && y[4] in new_ex.args[2].args) ||
        (y[2] in new_ex.args[3].args && y[4] in new_ex.args[3].args) ||
        (y[2] in new_ex.args[4].args && y[4] in new_ex.args[4].args)
end

function test_to_cnf()
    model = GDPModel()
    @variable(model, y[1:3], LogicalVariable)
    ex = iff(y...)
    new_ex = DP._to_cnf(ex)
    @test new_ex.head == :∧
    for arg in new_ex.args
        @test arg.head == :∨
    end
    @test (y[1] in new_ex.args[1].args && y[2] in new_ex.args[1].args && y[3] in new_ex.args[1].args) ||
        (y[1] in new_ex.args[2].args && y[2] in new_ex.args[2].args && y[3] in new_ex.args[2].args) ||
        (y[1] in new_ex.args[3].args && y[2] in new_ex.args[3].args && y[3] in new_ex.args[3].args) ||
        (y[1] in new_ex.args[4].args && y[2] in new_ex.args[4].args && y[3] in new_ex.args[4].args) ||
        (y[1] in new_ex.args[5].args && y[2] in new_ex.args[5].args && y[3] in new_ex.args[5].args) ||
        (y[1] in new_ex.args[6].args && y[2] in new_ex.args[6].args && y[3] in new_ex.args[6].args)

    @test (y[1] in new_ex.args[1].args && !(y[2] in new_ex.args[1].args) && !(y[3] in new_ex.args[1].args)) ||
        (y[1] in new_ex.args[2].args && !(y[2] in new_ex.args[2].args) && !(y[3] in new_ex.args[2].args)) ||
        (y[1] in new_ex.args[3].args && !(y[2] in new_ex.args[3].args) && !(y[3] in new_ex.args[3].args)) ||
        (y[1] in new_ex.args[4].args && !(y[2] in new_ex.args[4].args) && !(y[3] in new_ex.args[4].args)) ||
        (y[1] in new_ex.args[5].args && !(y[2] in new_ex.args[5].args) && !(y[3] in new_ex.args[5].args)) ||
        (y[1] in new_ex.args[6].args && !(y[2] in new_ex.args[6].args) && !(y[3] in new_ex.args[6].args))

    @test (!(y[1] in new_ex.args[1].args) && y[2] in new_ex.args[1].args && !(y[3] in new_ex.args[1].args)) ||
        (!(y[1] in new_ex.args[2].args) && y[2] in new_ex.args[2].args && !(y[3] in new_ex.args[2].args)) ||
        (!(y[1] in new_ex.args[3].args) && y[2] in new_ex.args[3].args && !(y[3] in new_ex.args[3].args)) ||
        (!(y[1] in new_ex.args[4].args) && y[2] in new_ex.args[4].args && !(y[3] in new_ex.args[4].args)) ||
        (!(y[1] in new_ex.args[5].args) && y[2] in new_ex.args[5].args && !(y[3] in new_ex.args[5].args)) ||
        (!(y[1] in new_ex.args[6].args) && y[2] in new_ex.args[6].args && !(y[3] in new_ex.args[6].args))

    @test (!(y[1] in new_ex.args[1].args) && !(y[2] in new_ex.args[1].args) && y[3] in new_ex.args[1].args) ||
        (!(y[1] in new_ex.args[2].args) && !(y[2] in new_ex.args[2].args) && y[3] in new_ex.args[2].args) ||
        (!(y[1] in new_ex.args[3].args) && !(y[2] in new_ex.args[3].args) && y[3] in new_ex.args[3].args) ||
        (!(y[1] in new_ex.args[4].args) && !(y[2] in new_ex.args[4].args) && y[3] in new_ex.args[4].args) ||
        (!(y[1] in new_ex.args[5].args) && !(y[2] in new_ex.args[5].args) && y[3] in new_ex.args[5].args) ||
        (!(y[1] in new_ex.args[6].args) && !(y[2] in new_ex.args[6].args) && y[3] in new_ex.args[6].args)
end

@testset "Logical Proposition Constraints" begin
    @testset "Add Proposition" begin
        test_proposition_add_fail()
        test_negation_add_success()
        test_implication_add_success()
        test_equivalence_add_success()
        test_intersection_and_flatten_add_success()
        test_union_and_flatten_add_success()
        test_proposition_add_array()
        test_proposition_add_dense_axis()
        test_proposition_add_sparse_axis()
    end
    @testset "Reformulate Proposition" begin
        test_negation_reformulation()
        test_implication_reformulation()
        test_implication_reformulation_fail()
        test_equivalence_reformulation()
        test_intersection_reformulation()
        test_implication_reformulation()
    end
    @testset "Conjunctive Normal Form" begin
        test_lvar_cnf_functions()
        test_eliminate_equivalence()
        test_eliminate_equivalence_flat()
        test_eliminate_equivalence_nested()
        test_eliminate_implication()
        test_eliminate_implication_error()
        test_eliminate_implication_nested()
        test_move_negation_inward_error()
        test_move_negation_inward()
        test_move_negation_inward_nested()
        test_negate_error()
        test_negate_or()
        test_negate_or_error()
        test_negate_and()
        test_negate_and_error()
        test_negate_negation()
        test_negate_negation_error()
        test_distribute_and_over_or()
        test_distribute_and_over_or_nested()
        test_to_cnf()
    end
end