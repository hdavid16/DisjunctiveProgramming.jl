function test_indicator_scalar_constraints()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, x == 5, DisjunctConstraint(y[1]))
    @constraint(model, x <= 5, DisjunctConstraint(y[1]))
    @constraint(model, x >= 5, DisjunctConstraint(y[1]))
    @constraint(model, x == 10, DisjunctConstraint(y[2]))
    @constraint(model, x <= 10, DisjunctConstraint(y[2]))
    @constraint(model, x >= 10, DisjunctConstraint(y[2]))
    @disjunction(model, y)
    reformulate_model(model, Indicator())
    
    ref_cons = DP._reformulation_constraints(model)
    ref_cons_obj = constraint_object.(ref_cons)
    @test length(ref_cons) == 6
    @test all(is_valid.(model, ref_cons))
    @test all(isa.(ref_cons_obj, VectorConstraint))
    @test all([cobj.set isa MOI.Indicator for cobj in ref_cons_obj])
end

function test_indicator_vector_constraints()
    model = GDPModel()
    A = [1 0; 0 1]
    @variable(model, x)
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, A*[x,x] == [5,5], DisjunctConstraint(y[1]))
    @constraint(model, A*[x,x] == [10,10], DisjunctConstraint(y[2]))
    @disjunction(model, y)
    reformulate_model(model, Indicator())
    
    ref_cons = DP._reformulation_constraints(model)
    ref_cons_obj = constraint_object.(ref_cons)
    @test length(ref_cons) == 4
    @test all(is_valid.(model, ref_cons))
    @test all(isa.(ref_cons_obj, VectorConstraint))
    @test all([cobj.set isa MOI.Indicator for cobj in ref_cons_obj])
end

function test_indicator_array()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, [1:3, 1:2], x <= 6, DisjunctConstraint(y[1]))
    @constraint(model, [1:3, 1:2], x >= 6, DisjunctConstraint(y[2]))
    @disjunction(model, y)
    reformulate_model(model, Indicator())

    ref_cons = DP._reformulation_constraints(model)
    ref_cons_obj = constraint_object.(ref_cons)
    @test length(ref_cons) == 12
    @test all(is_valid.(model, ref_cons))
    @test all(isa.(ref_cons_obj, VectorConstraint))
    @test all([cobj.set isa MOI.Indicator for cobj in ref_cons_obj])
end

function test_indicator_dense_axis()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, [["a","b","c"],[1,2]], x <= 7, DisjunctConstraint(y[1]))
    @constraint(model, [["a","b","c"],[1,2]], x >= 7, DisjunctConstraint(y[2]))
    @disjunction(model, y)
    reformulate_model(model, Indicator())    

    ref_cons = DP._reformulation_constraints(model)
    ref_cons_obj = constraint_object.(ref_cons)
    @test length(ref_cons) == 12
    @test all(is_valid.(model, ref_cons))
    @test all(isa.(ref_cons_obj, VectorConstraint))
    @test all([cobj.set isa MOI.Indicator for cobj in ref_cons_obj])
end

function test_indicator_sparse_axis()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], LogicalVariable)
    @constraint(model, [i = 1:3, j = 1:3; j > i], x <= 7, DisjunctConstraint(y[1]))
    @constraint(model, [i = 1:3, j = 1:3; j > i], x >= 7, DisjunctConstraint(y[2]))
    @disjunction(model, y)
    reformulate_model(model, Indicator()) 

    ref_cons = DP._reformulation_constraints(model)
    ref_cons_obj = constraint_object.(ref_cons)
    @test length(ref_cons) == 6
    @test all(is_valid.(model, ref_cons))
    @test all(isa.(ref_cons_obj, VectorConstraint))
    @test all([cobj.set isa MOI.Indicator for cobj in ref_cons_obj])
end

function test_indicator_nested()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], LogicalVariable)
    @variable(model, z[1:2], LogicalVariable)
    @constraint(model, x <= 5, DisjunctConstraint(y[1]))
    @constraint(model, x >= 5, DisjunctConstraint(y[2]))
    @disjunction(model, y, DisjunctConstraint(z[1]))
    @constraint(model, x <= 10, DisjunctConstraint(z[1]))
    @constraint(model, x >= 10, DisjunctConstraint(z[2]))
    @disjunction(model, z)
    reformulate_model(model, Indicator())

    ref_cons = DP._reformulation_constraints(model)
    ref_cons_obj = constraint_object.(ref_cons)
    @test length(ref_cons) == 4
    @test all(is_valid.(model, ref_cons))
    @test all(isa.(ref_cons_obj, VectorConstraint))
    @test all([cobj.set isa MOI.Indicator for cobj in ref_cons_obj])
end

@testset "Indicator" begin
    test_indicator_scalar_constraints()
    test_indicator_vector_constraints()
    test_indicator_array()
    test_indicator_dense_axis()
    test_indicator_sparse_axis()
    test_indicator_nested()
end