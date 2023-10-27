function test_selector_add_fail()
    m = GDPModel()
    @variable(m, y[1:3], Logical)
    @test_throws ErrorException @constraint(Model(), y in AtMost(2))
    @test_throws ErrorException @constraint(m, logical_or(y...) in Exactly(1))
    @test_throws ErrorException @constraint(m, sin.(y) in Exactly(1))
    @test_throws VariableNotOwned @constraint(GDPModel(), y in AtMost(2))
    # @test_throws MethodError @constraint(m, y in AtMost(1.0)) --> MethodErrors are not a good thing to want
    # @test_throws MethodError @constraint(m, y[1:2] in AtMost(1y[3]))
end

function test_selector_add_success()
    model = GDPModel()
    @variable(model, y[1:3], Logical)
    c1 = @constraint(model, y in Exactly(1))
    @constraint(model, c2, y in Exactly(1))
    @test owner_model(c1) == model
    @test is_valid(model, c1)
    @test index(c1) == LogicalConstraintIndex(1)
    @test name(c1) == ""
    @test name(c2) == "c2"
    @test haskey(DP._logical_constraints(model), index(c1))
    @test haskey(DP._logical_constraints(model), index(c2))
    @test DP._logical_constraints(model)[index(c1)] == DP._constraint_data(c1)
    @test 1 in constraint_object(c1).func
    @test y[1] in constraint_object(c1).func
    @test y[2] in constraint_object(c1).func
    @test y[3] in constraint_object(c1).func
    @test constraint_object(c1).set == DP._MOIExactly(4)
    @test constraint_object(c1).func == constraint_object(c2).func
    @test constraint_object(c1).set == constraint_object(c2).set
    @test c1 == copy(c1)
end

function test_nested_selector_add_success()
    model = GDPModel()
    @variable(model, y[1:3], Logical)
    c1 = @constraint(model, y[1:2] in Exactly(y[3]))
    @test is_valid(model, c1)
    @test length(constraint_object(c1).func) == 3
    @test y[1] in constraint_object(c1).func
    @test y[2] in constraint_object(c1).func
    @test y[3] in constraint_object(c1).func
end

function test_selector_add_array()
    model = GDPModel()
    @variable(model, y[1:2, 1:3, 1:4], Logical)
    @constraint(model, con[i=1:2, j=1:3], y[i,j,:] in Exactly(1))
    @test con isa Matrix{LogicalConstraintRef}
    @test length(con) == 6
end

function test_selector_add_dense_axis()
    model = GDPModel()
    I = ["a", "b", "c"]
    J = [1, 2]
    @variable(model, y[I, J, 1:4], Logical)
    @constraint(model, con[i=I, j=J], y[i,j,:] in Exactly(1))
    @test con isa Containers.DenseAxisArray
    @test con.axes[1] == ["a","b","c"]
    @test con.axes[2] == [1,2]
    @test con.data isa Matrix{LogicalConstraintRef}
end

function test_selector_add_sparse_axis()
    model = GDPModel()
    @variable(model, y[1:3, 1:3, 1:4], Logical)
    @constraint(model, con[i=1:3, j=1:3; j > i], y[i,j,:] in Exactly(1))
    @test con isa Containers.SparseAxisArray
    @test length(con) == 3
    @test con.names == (:i, :j)
    @test Set(keys(con.data)) == Set([(1,2),(1,3),(2,3)])
end

function test_selector_set_name()
    model = GDPModel()
    @variable(model, y[1:3], Logical)
    c1 = @constraint(model, y in Exactly(1))
    set_name(c1, "selector")
    @test name(c1) == "selector"
end

function test_selector_delete()
    model = GDPModel()
    @variable(model, y[1:3], Logical)
    c1 = @constraint(model, y in Exactly(1))

    @test_throws AssertionError delete(GDPModel(), c1)

    delete(model, c1)
    @test !haskey(gdp_data(model).logical_constraints, index(c1))
    @test !DP._ready_to_optimize(model)
end

function test_exactly_reformulation()
    model = GDPModel()
    @variable(model, y[1:3], Logical)
    @constraint(model, y in Exactly(1))
    reformulate_model(model, DummyReformulation())
    ref_con = DP._reformulation_constraints(model)[1]
    @test is_valid(model, ref_con)
    ref_con_obj = constraint_object(ref_con)
    @test ref_con_obj.set == MOI.EqualTo(1.0)
    @test ref_con_obj.func == sum(DP._reformulation_variables(model))
end

function test_atleast_reformulation()
    model = GDPModel()
    @variable(model, y[1:3], Logical)
    @constraint(model, y in AtLeast(1))
    reformulate_model(model, DummyReformulation())
    ref_con = DP._reformulation_constraints(model)[1]
    @test is_valid(model, ref_con)
    ref_con_obj = constraint_object(ref_con)
    @test ref_con_obj.set == MOI.GreaterThan(1.0)
    @test ref_con_obj.func == sum(DP._reformulation_variables(model))
end

function test_atmost_reformulation()
    model = GDPModel()
    @variable(model, y[1:3], Logical)
    @constraint(model, y in AtMost(1))
    reformulate_model(model, DummyReformulation())
    ref_con = DP._reformulation_constraints(model)[1]
    @test is_valid(model, ref_con)
    ref_con_obj = constraint_object(ref_con)
    @test ref_con_obj.set == MOI.LessThan(1.0)
    @test ref_con_obj.func == sum(DP._reformulation_variables(model))
end

function test_nested_exactly_reformulation()
    model = GDPModel()
    @variable(model, y[1:3], Logical)
    @constraint(model, y[1:2] in Exactly(y[3]))
    reformulate_model(model, DummyReformulation())
    ref_con = DP._reformulation_constraints(model)[1]
    @test is_valid(model, ref_con)
    ref_con_obj = constraint_object(ref_con)
    @test ref_con_obj.set == MOI.EqualTo(0.0)
    @test ref_con_obj.func == 
        DP._indicator_to_binary(model)[y[1]] +
        DP._indicator_to_binary(model)[y[2]] -
        DP._indicator_to_binary(model)[y[3]]
end

function test_nested_atleast_reformulation()
    model = GDPModel()
    @variable(model, y[1:3], Logical)
    @constraint(model, y[1:2] in AtLeast(y[3]))
    reformulate_model(model, DummyReformulation())
    ref_con = DP._reformulation_constraints(model)[1]
    @test is_valid(model, ref_con)
    ref_con_obj = constraint_object(ref_con)
    @test ref_con_obj.set == MOI.GreaterThan(0.0)
    @test ref_con_obj.func == 
        DP._indicator_to_binary(model)[y[1]] +
        DP._indicator_to_binary(model)[y[2]] -
        DP._indicator_to_binary(model)[y[3]]
end

function test_nested_atmost_reformulation()
    model = GDPModel()
    @variable(model, y[1:3], Logical)
    @constraint(model, y[1:2] in AtMost(y[3]))
    reformulate_model(model, DummyReformulation())
    ref_con = DP._reformulation_constraints(model)[1]
    @test is_valid(model, ref_con)
    ref_con_obj = constraint_object(ref_con)
    @test ref_con_obj.set == MOI.LessThan(0.0)
    @test ref_con_obj.func == 
        DP._indicator_to_binary(model)[y[1]] +
        DP._indicator_to_binary(model)[y[2]] -
        DP._indicator_to_binary(model)[y[3]]
end

@testset "Logical Selector Constraints" begin
    @testset "Add Selector" begin
        test_selector_add_fail()
        test_selector_add_success()
        test_nested_selector_add_success()
        test_selector_add_array()
        test_selector_add_dense_axis()
        test_selector_add_sparse_axis()
    end
    @testset "Selector Properties" begin
        test_selector_set_name()
    end
    @testset "Delete Selector" begin
        test_selector_delete()
    end
    @testset "Reformulate Selector" begin
        test_exactly_reformulation()
        test_atleast_reformulation()
        test_atmost_reformulation()
        test_nested_exactly_reformulation()
        test_nested_atleast_reformulation()
        test_nested_atmost_reformulation()
    end
end