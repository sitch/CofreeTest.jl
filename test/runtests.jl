using Test

@testset "CofreeTest.jl" begin
    include("test_cofree.jl")
    include("test_types.jl")
    include("test_events.jl")
    include("test_discovery.jl")
    include("test_filter.jl")
    include("test_macros.jl")
    include("test_executor.jl")
    include("test_runner.jl")
    include("test_formatter.jl")
    include("test_terminal_components.jl")
    include("test_json_formatter.jl")
    include("test_multi_formatter.jl")
    include("test_terminal_formatter.jl")
    include("test_history.jl")
    include("test_suite_macro.jl")
    include("test_compat.jl")
    include("test_integration.jl")
end
