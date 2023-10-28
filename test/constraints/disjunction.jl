function test_macro_helpers()
    @test DP._esc_non_constant(1) == 1
    @test DP._get_name(:x) == :x
    @test DP._get_name("x") == "x"
    @test DP._get_name(nothing) == ()
    @test DP._get_name(Expr(:string,"x")) == Expr(:string,"x")
    @test DP._name_call("",[]) == ""
    @test DP._name_call("name",[]) == "name"
end

function test_disjunction_add_fail()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], Logical)
    @constraint(model, x == 5, Disjunct(y[1]))
    
    @test_macro_throws ErrorException @disjunction(model) #not enough arguments
    @test_macro_throws UndefVarError @disjunction(model, y) #unassociated indicator
    @test_macro_throws UndefVarError @disjunction(GDPModel(), y) #wrong model
    @test_macro_throws ErrorException @disjunction(Model(), y) #not a GDPModel
    @test_macro_throws UndefVarError @disjunction(model, [y[1], y[1]]) #duplicate indicator
    @test_macro_throws UndefVarError @disjunction(model, y[1]) #unrecognized disjunction expression
    @test_throws ErrorException disjunction(model, y[1]) #unrecognized disjunction expression
    @test_throws ErrorException disjunction(model, [1]) #unrecognized disjunction expression
    @test_macro_throws UndefVarError @disjunction(model, y, "random_arg") #unrecognized extra argument
    @test_throws ErrorException DP._disjunction(error, model, y, "y", "random_arg") #unrecognized extra argument
    @test_macro_throws ErrorException @disjunction(model, "ABC") #unrecognized structure
    @test_macro_throws ErrorException @disjunction(model, begin y end) #@disjunctions (plural)
    @test_macro_throws UndefVarError @disjunction(model, x, y) #name x already exists

    @constraint(model, x == 10, Disjunct(y[2]))
    @disjunction(model, disj, y)
    @test_macro_throws UndefVarError @disjunction(model, disj, y) #duplicate name
    @test_throws ErrorException DP._error_if_cannot_register(error, model, :disj) #duplicate name

    @test_macro_throws ErrorException @disjunction(model, "bad"[i=1:2], y) #wrong expression for disjunction name
    @test_macro_throws ErrorException @disjunction(model, [model=1:2], y) #index name can't be same as model name
end

function test_disjunction_add_success()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], Logical)
    @constraint(model, x == 5, Disjunct(y[1]))
    @constraint(model, x == 10, Disjunct(y[2]))
    disj = @disjunction(model, y)
    @disjunction(model, disj2, y)
    @test owner_model(disj) == model
    @test is_valid(model, disj)
    @test index(disj) == DisjunctionIndex(1)
    @test name(disj) == ""
    @test name(disj2) == "disj2"
    @test haskey(DP._disjunctions(model), index(disj))
    @test haskey(DP._disjunctions(model), index(disj2))
    @test DP._disjunctions(model)[index(disj)] == DP._constraint_data(disj)
    @test !constraint_object(disj).nested
    @test constraint_object(disj).indicators == y
    @test disj == copy(disj)
end

function test_disjunction_add_nested()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], Logical)
    @variable(model, z[1:2], Logical)
    @constraint(model, x <= 5, Disjunct(y[1]))
    @constraint(model, x >= 5, Disjunct(y[2]))
    @disjunction(model, inner, y, Disjunct(z[1]))
    @constraint(model, x <= 10, Disjunct(z[1]))
    @constraint(model, x >= 10, Disjunct(z[2]))
    @disjunction(model, outer, z)

    @test is_valid(model, inner)
    @test is_valid(model, outer)
    @test haskey(DP._disjunctions(model), index(inner))
    @test haskey(DP._disjunctions(model), index(outer))
    @test constraint_object(inner).nested
    @test !constraint_object(outer).nested
    @test haskey(DP._indicator_to_constraints(model), z[1])
    @test inner in DP._indicator_to_constraints(model)[z[1]]
end

function test_disjunction_add_array()
    model=GDPModel()
    @variable(model, x)
    @variable(model, y[1:2, 1:3, 1:4], Logical)
    @constraint(model, con[i=1:2, j=1:3, k=1:4], x==i+j+k, Disjunct(y[i,j,k]))
    @disjunction(model, disj[i=1:2, j=1:3], y[i,j,:]; container = Array)

    @test disj isa Matrix{DisjunctionRef}
    @test length(disj) == 6
    @test all(is_valid.(model, disj))
end

function test_disjunciton_add_dense_axis()
    model = GDPModel()
    @variable(model, x)
    I = ["a", "b", "c"]
    J = [1, 2]
    @variable(model, y[I, J, 1:4], Logical)
    @constraint(model, con[i=I, j=J, k=1:4], x==k, Disjunct(y[i,j,k]))
    @disjunction(model, disj[i=I, j=J], y[i,j,:])

    @test disj isa Containers.DenseAxisArray
    @test disj.axes[1] == ["a","b","c"]
    @test disj.axes[2] == [1,2]
    @test disj.data isa Matrix{DisjunctionRef}
end

function test_disjunction_add_sparse_axis()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:3, 1:3, 1:4], Logical)
    @constraint(model, con[i=1:3, j=1:3, k=1:4; j > i], x==i+j+k, Disjunct(y[i,j,k]))
    @disjunction(model, disj[i=1:3, j=1:3; j > i], y[i,j,:])

    @test disj isa Containers.SparseAxisArray
    @test length(disj) == 3
    @test disj.names == (:i, :j)
    @test Set(keys(disj.data)) == Set([(1,2),(1,3),(2,3)])
end

function test_disjunctions_add_fail()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], Logical)
    @variable(model, z[1:2], Logical)
    @constraint(model, x <= 5, Disjunct(y[1]))
    @constraint(model, x >= 5, Disjunct(y[2]))
    @test_macro_throws ErrorException @disjunctions(model, y)
end

function test_disjunctions_add_success()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], Logical)
    @variable(model, z[1:2], Logical)
    @constraint(model, x <= 5, Disjunct(y[1]))
    @constraint(model, x >= 5, Disjunct(y[2]))
    @constraint(model, x <= 10, Disjunct(z[1]))
    @constraint(model, x >= 10, Disjunct(z[2]))
    @disjunctions(model, begin
        disj1, y
        disj2, z
    end)
    @test is_valid(model, disj1)
    @test is_valid(model, disj2)
    @test haskey(DP._disjunctions(model), index(disj1))
    @test haskey(DP._disjunctions(model), index(disj2))

    unamed = @disjunctions(model, begin
        y
        z
    end)
    @test all(is_valid.(model, unamed))
    @test haskey(DP._disjunctions(model), index(unamed[1]))
    @test haskey(DP._disjunctions(model), index(unamed[2]))
end

function test_disjunction_set_name()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], Logical)
    @constraint(model, x == 5, Disjunct(y[1]))
    @constraint(model, x == 10, Disjunct(y[2]))
    @disjunction(model, disj, y)
    set_name(disj, "new_name")
    @test name(disj) == "new_name"
end

function test_disjunction_delete()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], Logical)
    @constraint(model, x == 5, Disjunct(y[1]))
    @constraint(model, x == 10, Disjunct(y[2]))
    @disjunction(model, disj, y)

    @test_throws AssertionError delete(GDPModel(), disj)
    delete(model, disj)
    @test !haskey(gdp_data(model).disjunctions, index(disj))
    @test !DP._ready_to_optimize(model)
end

function test_disjunction_function()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], Logical)
    @constraint(model, x == 5, Disjunct(y[1]))
    @constraint(model, x == 10, Disjunct(y[2]))
    disj = disjunction(model, y, "name")

    @test is_valid(model, disj)
    @test name(disj) == "name"
    set_name(disj, "new_name")
    @test name(disj) == "new_name"
    @test haskey(DP._disjunctions(model), index(disj))
end

function test_disjunction_function_nested()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y[1:2], Logical)
    @variable(model, z[1:2], Logical)
    @constraint(model, x <= 5, Disjunct(y[1]))
    @constraint(model, x >= 5, Disjunct(y[2]))
    @constraint(model, x <= 10, Disjunct(z[1]))
    @constraint(model, x >= 10, Disjunct(z[2]))
    disj1 = disjunction(model, y, Disjunct(z[1]), "inner")
    disj2 = disjunction(model, z, "outer")

    @test is_valid(model, disj1)
    @test is_valid(model, disj2)
    @test haskey(DP._disjunctions(model), index(disj1))
    @test haskey(DP._disjunctions(model), index(disj2))
    @test constraint_object(disj1).nested
    @test !constraint_object(disj2).nested
    @test haskey(DP._indicator_to_constraints(model), z[1])
    @test disj1 in DP._indicator_to_constraints(model)[z[1]]
end

@testset "Disjunction" begin
    @testset "Macro Helpers" begin
        test_macro_helpers()
    end
    @testset "Add Disjunction" begin
        test_disjunction_add_fail()
        test_disjunction_add_success()
        test_disjunction_add_nested()
        test_disjunction_add_array()
        test_disjunciton_add_dense_axis()
        test_disjunction_add_sparse_axis()
        test_disjunctions_add_fail()
        test_disjunctions_add_success()
        test_disjunction_function()
        test_disjunction_function_nested()
    end
    @testset "Disjunction Properties" begin
        test_disjunction_set_name()
    end
    @testset "Delete Disjunction" begin
        test_disjunction_delete()
    end
end