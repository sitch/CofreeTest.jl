using Test

@testset "CofreeTest.jl" begin
    include("test_cofree.jl")
    include("test_types.jl")
    include("test_events.jl")
    include("test_discovery.jl")
    include("test_filter.jl")
    include("test_macros.jl")
end
