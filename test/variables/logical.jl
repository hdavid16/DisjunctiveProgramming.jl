# test creating, modifying, and reformulating logical variables

function test_base()
    model = GDPModel()
    @variable(model, y, Logical)
    @test Base.broadcastable(y) isa Base.RefValue{LogicalVariableRef{Model}}
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
    y = LogicalVariableRef(model, LogicalVariableIndex(1))
    @test @variable(model, y, Logical) == y
    @test owner_model(y) == model
    @test is_valid(model, y)
    @test name(y) == "y"
    @test index(y) == LogicalVariableIndex(1)
    @test isnothing(start_value(y))
    @test isnothing(fix_value(y))
    @test isequal_canonical(y, copy(y))
    @test haskey(DP._logical_variables(model), index(y))
    @test DP._logical_variables(model)[index(y)].variable == LogicalVariable(nothing, nothing, nothing)
    @test DP._logical_variables(model)[index(y)].name == "y"
    @test binary_variable(y) isa VariableRef
    @test is_binary(binary_variable(y))
end

function test_lvar_add_array()
    model = GDPModel()
    @variable(model, y[1:3, 1:2], Logical)
    @test y isa Array{LogicalVariableRef{Model}, 2}
    @test length(y) == 6
end

function test_lvar_add_dense_axis()
    model = GDPModel()
    @variable(model, y[["a","b","c"],[1,2]], Logical)
    @test y isa Containers.DenseAxisArray
    @test length(y) == 6
    @test y.axes[1] == ["a","b","c"]
    @test y.axes[2] == [1,2]
    @test y.data isa Array{LogicalVariableRef{Model}, 2}
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
    @test set_name(y, "z") isa Nothing
    @test name(y) == "z"
end

function test_lvar_creation_start_value()
    model = GDPModel()
    @variable(model, y, Logical, start = true)
    @test start_value(y)
    @test start_value(binary_variable(y)) == 1
end

function test_lvar_set_start_value()
    model = GDPModel()
    @variable(model, y, Logical)
    @test isnothing(start_value(y))
    set_start_value(y, false)
    @test !start_value(y)
    @test start_value(binary_variable(y)) == 0
end

function test_lvar_creation_fix_value()
    model = GDPModel()
    @variable(model, y == true, Logical)
    @test fix_value(y)
    @test fix_value(binary_variable(y)) == 1
end

function test_lvar_fix_value()
    model = GDPModel()
    @variable(model, y, Logical)
    @test isnothing(fix_value(y))
    fix(y, true)
    @test fix_value(y)
    @test fix_value(binary_variable(y)) == 1
    #unfix the value
    unfix(y)
    @test isnothing(fix_value(y))
    @test !is_fixed(binary_variable(y))
end

function test_lvar_delete()
    model = GDPModel()
    @variable(model, y, Logical)
    @variable(model, z, Logical)
    @variable(model, x)
    @constraint(model, con, x <= 10, Disjunct(y))
    @constraint(model, con2, x >= 50, Disjunct(z))
    @disjunction(model, disj, [y, z])
    @constraint(model, lcon, y ∨ z := true)

    @test_throws AssertionError delete(GDPModel(), y)
    
    bvar = binary_variable(y)
    @test delete(model, y) isa Nothing
    @test !haskey(gdp_data(model).logical_variables, index(y))
    @test haskey(gdp_data(model).logical_variables, index(z))
    @test !haskey(gdp_data(model).disjunct_constraints, index(con))
    @test !haskey(gdp_data(model).disjunctions, index(disj))
    @test !haskey(gdp_data(model).logical_constraints, index(lcon))
    @test !haskey(gdp_data(model).indicator_to_constraints, y)
    @test !haskey(gdp_data(model).indicator_to_binary, y)
    @test haskey(gdp_data(model).indicator_to_binary, z)
    @test !DP._ready_to_optimize(model)
    @test !is_valid(model, bvar)
end

function test_lvar_logical_compliment()
    model = GDPModel()
    @variable(model, y1, Logical)
    # test addition
    @test_throws ErrorException @variable(model, y2 == true, Logical, logical_compliment = y1)
    @test_throws ErrorException @variable(model, y2, Logical, logical_compliment = y1, start = false)
    @variable(model, y2, Logical, logical_compliment = y1)
    # test queries
    @test binary_variable(y2) == 1 - binary_variable(y1)
    @test name(y2) == "y2"
    @test set_name(y2, "new_name") isa Nothing
    @test name(y2) == "new_name"
    @test_throws ErrorException set_start_value(y2, false)
    @test_throws ErrorException fix(y2, false)
    @test unfix(y2) isa Nothing
    @test has_logical_compliment(y2)
    @test !has_logical_compliment(y1)
    # test error for logical of logical
    @test_throws ErrorException @variable(model, y3, Logical, logical_compliment = y2)
    # test deletion
    @test delete(model, y2) isa Nothing
    @test !is_valid(model, y2)
end

function test_tagged_variables()
    model = GDPModel{MyModel, MyVarRef, MyConRef}()
    y = [LogicalVariableRef(model, LogicalVariableIndex(i)) for i in 1:2]
    @test @variable(model, y[1:2], Logical(MyVar), start = true) == y
    bvars = binary_variable.(y)
    @test name(y[1]) == "y[1]"
    @test start_value(y[1])
    @test set_start_value(y[2], false) isa Nothing
    @test !start_value(y[2])
    @test start_value(bvars[2]) == 0
    @test !is_fixed(y[1])
    @test fix(y[1], false) isa Nothing
    @test is_fixed(y[1])
    @test fix_value(bvars[1]) == 0
    @test unfix(y[1]) isa Nothing
    @test !is_fixed(y[1])
    @test !is_fixed(bvars[1])
    @test set_name(y[2], "test") isa Nothing
    @test name(y[2]) == "test"
    @test name(bvars[2]) == "test"
    @test delete(model, y[1]) isa Nothing
    @test !is_valid(model, y[1])
    @test !is_valid(model, bvars[1])
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
    @testset "Logical Compliment Variables" begin
        test_lvar_logical_compliment()
    end
    @testset "Tagged Logical Variables" begin
        test_tagged_variables()
    end
end