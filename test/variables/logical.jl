# test creating, modifying, and reformulating logical variables
function test_lvar_add_fail()
   model = Model()
   @test_throws ErrorException @variable(model, y, LogicalVariable)
end

function test_lvar_add_success()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    @test typeof(y) == LogicalVariableRef
    @test JuMP.owner_model(y) == model
    @test JuMP.is_valid(model, y)
    @test JuMP.name(y) == "y"
    @test JuMP.index(y) == LogicalVariableIndex(1)
    @test isnothing(JuMP.start_value(y))
    @test isnothing(JuMP.fix_value(y))
    @test JuMP.isequal_canonical(y, copy(y))
    @test haskey(DP._logical_variables(model), JuMP.index(y))
    @test DP._logical_variables(model)[JuMP.index(y)] isa LogicalVariableData
    @test DP._logical_variables(model)[JuMP.index(y)].variable == LogicalVariable(nothing, nothing)
    @test DP._logical_variables(model)[JuMP.index(y)].name == "y"
    #reformulate the variable
    test_reformulating_lvar(model, y)
end

function test_lvar_add_array()
    model = GDPModel()
    @variable(model, y[1:3, 1:2], LogicalVariable)
    @test typeof(y) == Array{LogicalVariableRef, 2}
    @test length(y) == 6
end

function test_lvar_add_dense_axis()
    model = GDPModel()
    @variable(model, y[["a","b","c"],[1,2]], LogicalVariable)
    @test y isa JuMP.Containers.DenseAxisArray
    @test length(y) == 6
    @test y.axes[1] == ["a","b","c"]
    @test y.axes[2] == [1,2]
    @test y.data isa Array{LogicalVariableRef, 2}
end

function test_lvar_add_sparse_axis()
    model = GDPModel()
    @variable(model, y[i = 1:3, j = 1:3; j > i], LogicalVariable)
    @test y isa JuMP.Containers.SparseAxisArray
    @test length(y) == 3
    @test y.names == (:i, :j)
    @test Set(keys(y.data)) == Set([(1,2),(1,3),(2,3)])
end

function test_lvar_set_name()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    JuMP.set_name(y, "z")
    @test JuMP.name(y) == "z"
    #reformulate the variable
    test_reformulating_lvar(model, y)
end

function test_lvar_creation_start_value()
    model = GDPModel()
    @variable(model, y, LogicalVariable, start = true)
    @test JuMP.start_value(y)
    #reformulate the variable
    test_reformulating_lvar(model, y)
end

function test_lvar_set_start_value()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    @test isnothing(JuMP.start_value(y))
    JuMP.set_start_value(y, false)
    @test !JuMP.start_value(y)
    #reformulate the variable
    test_reformulating_lvar(model, y)
end

function test_lvar_fix_value()
    model = GDPModel()
    @variable(model, y, LogicalVariable)
    @test isnothing(JuMP.fix_value(y))
    JuMP.fix(y, true)
    @test JuMP.fix_value(y)
    #reformulate the variable
    test_reformulating_lvar(model, y)
    #unfix the value
    JuMP.unfix(y)
    @test isnothing(JuMP.fix_value(y))
end

function test_lvar_delete()
    m1 = GDPModel()
    m2 = GDPModel()
    @variable(m1, y, LogicalVariable)
    @variable(m1, z, LogicalVariable)
    @variable(m1, x)
    @constraint(m1, con, x <= 10, DisjunctConstraint(y))
    @constraint(m1, con2, x >= 50, DisjunctConstraint(z))
    @disjunction(m1, disj, [y, z])
    @constraint(m1, lcon, y == true)

    @test_throws AssertionError JuMP.delete(m2, y)
    
    JuMP.delete(m1, y)
    @test !haskey(gdp_data(m1).logical_variables, y)
    @test !haskey(gdp_data(m1).logical_variables, z)
    @test !haskey(gdp_data(m1).disjunct_constraints, con)
    @test !haskey(gdp_data(m1).disjunctions, disj)
    @test !haskey(gdp_data(m1).logical_constraints, lcon)
    @test !haskey(gdp_data(m1).indicator_to_constraints, y)
    @test !haskey(gdp_data(m1).indicator_to_binary, y)
    @test !DP._ready_to_optimize(m1)
end

function test_lvar_reformulation()
    model = GDPModel()
    @variable(model, y, LogicalVariable, start = false)
    JuMP.fix(y, true)
    test_reformulating_lvar(model, y)
end

function test_reformulating_lvar(model::JuMP.Model, lvref::LogicalVariableRef)
    model = JuMP.owner_model(lvref)
    DP._reformulate_logical_variables(model)
    @test haskey(DP._indicator_to_binary(model), lvref)
    bvref = DP._indicator_to_binary(model)[lvref]
    @test bvref in DP._reformulation_variables(model)
    @test JuMP.name(bvref) == JuMP.name(lvref)
    @test JuMP.is_valid(model, bvref)
    @test JuMP.is_binary(bvref)
    if isnothing(JuMP.start_value(lvref))
        @test isnothing(JuMP.start_value(bvref))
    elseif JuMP.start_value(lvref)
        @test isone(JuMP.start_value(bvref))
    else
        @test iszero(JuMP.start_value(bvref))
    end
    if isnothing(JuMP.fix_value(lvref))
        @test_throws Exception JuMP.fix_value(bvref)
    elseif JuMP.fix_value(lvref)
        @test isone(JuMP.fix_value(bvref))
    else
        @test iszero(JuMP.fix_value(bvref))
    end
end

@testset "Logical Variables" begin
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
        test_lvar_fix_value()
    end
    @testset "Delete Logical Variables" begin
        test_lvar_delete()
    end
    @testset "Reformulate Logical Variables" begin
        test_lvar_reformulation()
    end
end