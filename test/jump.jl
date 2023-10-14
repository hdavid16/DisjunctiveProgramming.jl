function test_moi_set()
    for (jumpset, moisettype) in [(AtLeast(1), DP._MOIAtLeast),
                           (AtMost(1), DP._MOIAtMost),
                           (Exactly(1), DP._MOIExactly)]
        moiset = moi_set(jumpset, 10)
        @test moiset isa moisettype
        @test moiset.dimension == 10
    end
end

@testset "JuMP" begin
    test_moi_set()
end