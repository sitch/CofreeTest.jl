using Test

@testset "CofreeTest.jl" begin
    include("test_cofree.jl")
    include("test_types.jl")
    include("test_events.jl")
end
