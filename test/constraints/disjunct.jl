function test_disjunct_add_fail()
    model = GDPModel()
    @variable(model, x)
    @variable(GDPModel(), y, LogicalVariable)
    @test_macro_throws ErrorException @constraint(model, x == 1, DisjunctConstraint(y)) # logical variable from another model
    
    @variable(model, w, LogicalVariable)
    @variable(model, z, Bin)
    @test_macro_throws ErrorException @constraint(model, z == 1, DisjunctConstraint(w)) # binary variable
end

function test_disjunct_add_success()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    c1 = @constraint(model, x == 1, DisjunctConstraint(y))
    @constraint(model, c2, x == 1, DisjunctConstraint(y))
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
    @variable(model, y[1:2, 1:3], LogicalVariable)
    @constraint(model, con[i=1:2, j=1:3], x == 1, DisjunctConstraint(y[i,j]))
    @test con isa Matrix{DisjunctConstraintRef}
    @test length(con) == 6
end

function test_disjunct_add_dense_axis()
    
end

function test_disjunct_add_sparse_axis()

end

function test_disjunct_set_name()

end

function test_disjunct_delete()

end