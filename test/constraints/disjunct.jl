function test_disjunct_add_fail()
    model = GDPModel()
    @variable(model, x)
    @variable(GDPModel(), y, Logical)
    @test_macro_throws UndefVarError @constraint(model, x == 1, Disjunct(y)) # logical variable from another model
    
    @variable(model, w, Logical)
    @variable(model, z, Bin)
    @test_macro_throws UndefVarError @constraint(model, z == 1, Disjunct(w)) # binary variable
    @test_throws ErrorException build_constraint(error, 1z, MOI.EqualTo(1), Disjunct(w)) # binary variable
end

function test_disjunct_add_success()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, Logical)
    c1 = @constraint(model, x == 1, Disjunct(y))
    @constraint(model, c2, x == 1, Disjunct(y))
    @test owner_model(c1) == model
    @test is_valid(model, c1)
    @test index(c1) == DisjunctConstraintIndex(1)
    @test name(c1) == ""
    @test name(c2) == "c2"
    @test haskey(DP._disjunct_constraints(model), index(c1))
    @test haskey(DP._disjunct_constraints(model), index(c2))
    @test haskey(DP._indicator_to_constraints(model), y)
    @test DP._indicator_to_constraints(model)[y] == [c1, c2]
    @test DP._disjunct_constraints(model)[index(c1)] == DP._constraint_data(c1)
    @test constraint_object(c1).set == MOI.EqualTo(1.0)
    @test constraint_object(c1).func == constraint_object(c2).func == 1x
    @test constraint_object(c1).set == constraint_object(c2).set
    @test c1 == copy(c1)
end

function test_disjunct_add_array()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2, 1:3], Logical)
    @constraint(model, con[i=1:2, j=1:3], x == 1, Disjunct(y[i,j]))
    @test con isa Matrix{DisjunctConstraintRef}
    @test length(con) == 6
end

function test_disjunct_add_dense_axis()
    model = GDPModel()
    @variable(model, x)
    I = ["a", "b", "c"]
    J = [1, 2]
    @variable(model, y[I, J], Logical)
    @constraint(model, con[i=I, j=J], x == 1, Disjunct(y[i,j]))
    
    @test con isa Containers.DenseAxisArray
    @test con.axes[1] == ["a","b","c"]
    @test con.axes[2] == [1,2]
    @test con.data isa Matrix{DisjunctConstraintRef}
end

function test_disjunct_add_sparse_axis()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:3, 1:3], Logical)
    @constraint(model, con[i=1:3, j=1:3; j > i], x==i+j, Disjunct(y[i,j]))

    @test con isa Containers.SparseAxisArray
    @test length(con) == 3
    @test con.names == (:i, :j)
    @test Set(keys(con.data)) == Set([(1,2),(1,3),(2,3)])
end

function test_disjunct_set_name()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, Logical)
    c1 = @constraint(model, x == 1, Disjunct(y))
    set_name(c1, "new name")
    @test name(c1) == "new name"
end

function test_disjunct_delete()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, Logical)
    @constraint(model, c1, x == 1, Disjunct(y))

    @test_throws AssertionError delete(GDPModel(), c1)
    delete(model, c1)
    @test !haskey(gdp_data(model).disjunct_constraints, index(c1))
    @test !DP._ready_to_optimize(model)
end

@testset "Disjunct Constraints" begin
    test_disjunct_add_fail()
    test_disjunct_add_success()
    test_disjunct_add_array()
    test_disjunct_add_dense_axis()
    test_disjunct_add_sparse_axis()
    test_disjunct_set_name()
    test_disjunct_delete()
end