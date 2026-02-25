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

    @testset "is_test_file rejects non-.jl files" begin
        @test is_test_file("test_auth.py") == false
        @test is_test_file("test_auth.txt") == false
        @test is_test_file("test_auth") == false
        @test is_test_file("") == false
    end

    @testset "discover_test_files on empty directory" begin
        mktempdir() do dir
            files = discover_test_files(dir)
            @test files == String[]
        end
    end

    @testset "discover_test_files with only non-matching .jl files" begin
        mktempdir() do dir
            write(joinpath(dir, "helpers.jl"), "# not a test")
            write(joinpath(dir, "utils.jl"), "# also not a test")
            files = discover_test_files(dir)
            @test files == String[]
        end
    end
end
