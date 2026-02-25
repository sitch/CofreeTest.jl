using Test
using CofreeTest
using CofreeTest: is_test_file, discover_test_files

@testset "Discovery" begin
    @testset "is_test_file" begin
        @test is_test_file("test_auth.jl") == true
        @test is_test_file("auth_test.jl") == true
        @test is_test_file("helpers.jl") == false
        @test is_test_file("runtests.jl") == false
        @test is_test_file("test_auth.jl") == true
        @test is_test_file("my_test.jl") == true
        @test is_test_file("testing.jl") == false
        @test is_test_file("test_.jl") == true
    end

    @testset "discover_test_files" begin
        fixture_dir = joinpath(@__DIR__, "fixtures", "discovery")
        files = discover_test_files(fixture_dir)

        basenames = Set(basename.(files))
        @test "test_auth.jl" in basenames
        @test "models_test.jl" in basenames
        @test "test_users.jl" in basenames
        @test "posts_test.jl" in basenames
        @test !("helpers.jl" in basenames)
        @test length(files) == 4
    end

    @testset "discover_test_files returns sorted paths" begin
        fixture_dir = joinpath(@__DIR__, "fixtures", "discovery")
        files = discover_test_files(fixture_dir)
        @test issorted(files)
    end
end
