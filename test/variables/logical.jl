# test creating, modifying, and reformulating logical variables

function test_base()
    model = GDPModel()
    @variable(model, y, Logical)
    @test Base.broadcastable(y) isa Base.RefValue{LogicalVariableRef}
    @test length(y) == 1
end

function test_lvar_add_fail()
   model = Model()
   @test_throws ErrorException @variable(model, y, Logical)
   @test_throws ErrorException @variable(model, y, Logical; kwarg=true)
   @test_throws ErrorException @variable(model, 0 <= y, Logical)
   @test_throws ErrorException @variable(model, y <= 1, Logical)
   @test_throws ErrorException @variable(model, y, Logical, integer=true)
   @test_throws ErrorException @variable(model, y, Logical, start=2)
   @test_throws ErrorException @variable(model, y == 2, Logical)
end

function test_lvar_add_success()
    model = GDPModel()
    @variable(model, y, Logical)
    @test typeof(y) == LogicalVariableRef
    @test owner_model(y) == model
    @test is_valid(model, y)
    @test name(y) == "y"
    @test index(y) == LogicalVariableIndex(1)
    @test isnothing(start_value(y))
    @test isnothing(fix_value(y))
    @test isequal_canonical(y, copy(y))
    @test haskey(DP._logical_variables(model), index(y))
    @test DP._logical_variables(model)[index(y)].variable == LogicalVariable(nothing, nothing)
    @test DP._logical_variables(model)[index(y)].name == "y"
    #reformulate the variable
    test_lvar_reformulation(model, y)
end

function test_lvar_add_array()
    model = GDPModel()
    @variable(model, y[1:3, 1:2], Logical)
    @test y isa Array{LogicalVariableRef, 2}
    @test length(y) == 6
end

function test_lvar_add_dense_axis()
    model = GDPModel()
    @variable(model, y[["a","b","c"],[1,2]], Logical)
    @test y isa Containers.DenseAxisArray
    @test length(y) == 6
    @test y.axes[1] == ["a","b","c"]
    @test y.axes[2] == [1,2]
    @test y.data isa Array{LogicalVariableRef, 2}
end

function test_lvar_add_sparse_axis()
    model = GDPModel()
    @variable(model, y[i = 1:3, j = 1:3; j > i], Logical)
    @test y isa Containers.SparseAxisArray
    @test length(y) == 3
    @test y.names == (:i, :j)
    @test Set(keys(y.data)) == Set([(1,2),(1,3),(2,3)])
end

function test_lvar_set_name()
    model = GDPModel()
    @variable(model, y, Logical)
    set_name(y, "z")
    @test name(y) == "z"
    #reformulate the variable
    test_lvar_reformulation(model, y)
end

function test_lvar_creation_start_value()
    model = GDPModel()
    @variable(model, y, Logical, start = true)
    @test start_value(y)
    #reformulate the variable
    test_lvar_reformulation(model, y)
end

function test_lvar_set_start_value()
    model = GDPModel()
    @variable(model, y, Logical)
    @test isnothing(start_value(y))
    set_start_value(y, false)
    @test !start_value(y)
    #reformulate the variable
    test_lvar_reformulation(model, y)
end

function test_lvar_creation_fix_value()
    model = GDPModel()
    @variable(model, y == true, Logical)
    @test fix_value(y)
end

function test_lvar_fix_value()
    model = GDPModel()
    @variable(model, y, Logical)
    @test isnothing(fix_value(y))
    fix(y, true)
    @test fix_value(y)
    #reformulate the variable
    test_lvar_reformulation(model, y)
    #unfix the value
    unfix(y)
    @test isnothing(fix_value(y))
end

function test_lvar_delete()
    model = GDPModel()
    @variable(model, y, Logical)
    @variable(model, z, Logical)
    @variable(model, x)
    @constraint(model, con, x <= 10, DisjunctConstraint(y))
    @constraint(model, con2, x >= 50, DisjunctConstraint(z))
    @disjunction(model, disj, [y, z])
    @constraint(model, lcon, y ∨ z in IsTrue())
    DP._reformulate_logical_variables(model)

    @test_throws AssertionError delete(GDPModel(), y)
    
    delete(model, y)
    @test !haskey(gdp_data(model).logical_variables, index(y))
    @test haskey(gdp_data(model).logical_variables, index(z))
    @test !haskey(gdp_data(model).disjunct_constraints, index(con))
    @test !haskey(gdp_data(model).disjunctions, index(disj))
    @test !haskey(gdp_data(model).logical_constraints, index(lcon))
    @test !haskey(gdp_data(model).indicator_to_constraints, y)
    @test !haskey(gdp_data(model).indicator_to_binary, y)
    @test haskey(gdp_data(model).indicator_to_binary, z)
    @test !DP._ready_to_optimize(model)
end

function test_lvar_reformulation()
    model = GDPModel()
    @variable(model, y, Logical, start = false)
    fix(y, true)
    test_lvar_reformulation(model, y)
end

function test_lvar_reformulation(model::Model, lvref::LogicalVariableRef)
    model = owner_model(lvref)
    DP._reformulate_logical_variables(model)
    @test haskey(DP._indicator_to_binary(model), lvref)
    bvref = DP._indicator_to_binary(model)[lvref]
    @test bvref in DP._reformulation_variables(model)
    @test name(bvref) == name(lvref)
    @test is_valid(model, bvref)
    @test is_binary(bvref)
    if isnothing(start_value(lvref))
        @test isnothing(start_value(bvref))
    elseif start_value(lvref)
        @test isone(start_value(bvref))
    else
        @test iszero(start_value(bvref))
    end
    if isnothing(fix_value(lvref))
        @test_throws Exception fix_value(bvref)
    elseif fix_value(lvref)
        @test isone(fix_value(bvref))
    else
        @test iszero(fix_value(bvref))
    end
end

@testset "Logical Variables" begin
    @testset "Base Methods" begin
        test_base()
    end
    @testset "Add Logical Variables" begin
        test_lvar_add_fail()
        test_lvar_add_success()
        test_lvar_add_array()
        test_lvar_add_dense_axis()
        test_lvar_add_sparse_axis()
    end
    @testset "Logical Variable Properties" begin
        test_lvar_set_name()
        test_lvar_creation_start_value()
        test_lvar_set_start_value()
        test_lvar_creation_fix_value()
        test_lvar_fix_value()
    end
    @testset "Delete Logical Variables" begin
        test_lvar_delete()
    end
    @testset "Reformulate Logical Variables" begin
        test_lvar_reformulation()
    end
end