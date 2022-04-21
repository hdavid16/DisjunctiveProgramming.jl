using Test
using JuMP
using DisjunctiveProgramming

@testset "linear constraints" begin

    function minimal()
        m = Model()
        @variable(m, -1<=x<=10)
        
        @constraint(m, con1, x<=3)
        @constraint(m, con2, 0<=x)
        @constraint(m, con3, x<=9)
        @constraint(m, con4, 5<=x)
        
        @disjunction(m,(con1,con2),con3,con4,reformulation=:CHR,name=:y)

        @test true
    end
    
    function simple_example(reform)
        m = Model()
        @variable(m, -10<=x<=10)
        @constraint(m, con1, x<=-1)
        @constraint(m, con2, 1<=x)
        
        if (reform == :BMR)
            @disjunction(m, con1, con2, reformulation=:BMR, name=:y)
        elseif (reform == :CHR)
            @disjunction(m, con1, con2, reformulation=:CHR, name=:y)
        end
        return m
    end

    function robustness()
        unreg = m -> unregister(m, :original_model_variables)

        function fresh_model()
            m = Model()
            @variable(m, -10<=x<=10)
            @constraint(m, con1, x<=-1)
            @constraint(m, con2, 1<=x)
            return m, con1, con2
        end
        
        # not enough constraints
        m = fresh_model()[1]
        # @test_throws DomainError @disjunction(m, (con1, con2), reformulation=:BMR, name=:y)
        unreg(m)
        # @test_throws DomainError @disjunction(m, con1, reformulation=:BMR, name=:y)

        # Big-M reformulation without variable bounds defined 
        # should only work if user specifies M value
        m = Model()
        @variable(m, x)
        @constraint(m, con1, x<=-1)
        @constraint(m, con2, 1<=x)
        @test @disjunction(m, con1, con2, reformulation=:BMR, name=:y, M=11) == nothing
        unreg(m)
        @test_throws ErrorException @disjunction(m, con1, con2, reformulation=:BMR, name=:y)

        # CHR reformulation without variable bounds defined should fail
        m = Model()
        @variable(m, x)
        @constraint(m, con1, x<=-1)
        @constraint(m, con2, 1<=x)
        @test_throws AssertionError @disjunction(m, con1, con2, reformulation=:CHR, name=:y)

        # empty constraints on one side of disjunction
        m, con1, con2 = fresh_model()
        @test @disjunction(m, con1, nothing, reformulation=:BMR, name=:y) == nothing
        m, con1, con2 = fresh_model()
        @test @disjunction(m, nothing, con2, reformulation=:CHR, name=:z) == nothing
        m, con1, con2 = fresh_model()
        @test @disjunction(m, (con1, con2), nothing, reformulation=:BMR, name=:y) == nothing

    end

    function model_BMR_valid(m)
        # Expecting to see following constraints:
        # x <= -1 + 11 * (1 - y1)
        # -x <= -1 + 11 * (1 - y2)
        # y1 + y2 = 1
        # -10<=x<=10
        cons = (L -> all_constraints(m, L...)).(list_of_constraint_types(m))
        @test sum(length.(cons)) == 5 + 2 # add 2 for y1/y2 binary statements
 
        con_strings = replace.(constraints_string(REPLMode, m), "[" => "", 
            "]" => "", "+ y" => "+y", " y" => "* y", 
            "con1 :" => "", "con2 :" => "")
        cons_actual = Meta.parse.(con_strings[1:5])
        cons_expected = [:(y1 + y2 == 1), :(x + 11 * y1 <= 10),
                         :(-x + 11 * y2 <= 10), :(x >= -10), :(x <= 10)]
        matches = sum(map(i->isequal(i[1], i[2]), 
            Base.product(cons_expected, cons_actual)))
        @test matches == length(cons_actual)
    end

    function model_CHR_valid(m)
        # Expecting to see following constraints:
        # x_y1 <= -1 * y1
        # -x_y2 <= -1 * y2
        # y1 + y2 = 1
        # x = x_y1 + x_y2
        # -10 * y1 <= x_y1 <= 10 * y1
        # -10 * y2 <= x_y2 <= 10 * y2
        # -10 <= x <= 10
        # -10 <= x_y1 <= 10
        # -10 <= x_y2 <= 10
        cons = (L -> all_constraints(m, L...)).(list_of_constraint_types(m))
        @test sum(length.(cons)) == 14 + 2 # add 2 for y1/y2 binary statements
        
        con_strings = replace.(constraints_string(REPLMode, m), "[" => "", 
            "]" => "", "+ y" => "+y", " y" => "* y", 
            "con1 :" => "", "con2 :" => "")
        println.(con_strings)
        cons_expected = [:(y1 + y2 == 1), :(x - x_1 - x_2 == 0), :(x >= -10),
                     :(x_1 + y1 <= 0), :(-x_2 + y2 <= 0), :(x <= 10),
                     :(x_1 >= -10), :(x_1 <= 10), :(x_2 >= -10), :(x_2 <= 10),
                     :(-10 * y1 - x_1 <= 0), :(-10 * y1 + x_1 <= 0),
                     :(-10 * y2 - x_2 <= 0), :(-10 * y2 + x_2 <= 0)]
        cons_actual = Meta.parse.(con_strings[1:14])
        matches = sum(map(i->isequal(i[1], i[2]), 
            Base.product(cons_expected, cons_actual)))
        @test matches == length(cons_actual)
    end

    robustness()

    m1 = simple_example(:BMR)
    model_BMR_valid(m1)

    m2 = simple_example(:CHR)
    model_CHR_valid(m2)

end