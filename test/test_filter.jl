using Test
using CofreeTest
using CofreeTest: TestFilter, filter_tree, parse_test_args

# Helper to collect all names from a Cofree tree
function collect_names(c::Cofree)
    names = String[]
    _collect!(names, c)
    names
end

function _collect!(names, c::Cofree)
    name = extract(c).name
    name != "root" && push!(names, name)
    for child in c.tail
        _collect!(names, child)
    end
end

@testset "Filter" begin
    # Build a test tree
    function make_tree()
        suite(
            TestSpec(name="root", tags=Set{Symbol}()),
            [
                leaf(TestSpec(name="fast test", tags=Set([:unit, :fast]))),
                leaf(TestSpec(name="slow test", tags=Set([:integration, :slow]))),
                suite(
                    TestSpec(name="auth", tags=Set([:unit])),
                    [
                        leaf(TestSpec(name="login", tags=Set([:unit]))),
                        leaf(TestSpec(name="logout", tags=Set([:unit, :slow]))),
                    ]
                ),
            ]
        )
    end

    @testset "filter by name" begin
        tree = make_tree()
        f = TestFilter(names=["login"], tags=Set{Symbol}(), exclude_tags=Set{Symbol}())
        result = filter_tree(tree, f)
        @test !isnothing(result)
        names = collect_names(result)
        @test "login" in names
        @test !("slow test" in names)
        @test !("fast test" in names)
    end

    @testset "filter by tag inclusion" begin
        tree = make_tree()
        f = TestFilter(names=String[], tags=Set([:fast]), exclude_tags=Set{Symbol}())
        result = filter_tree(tree, f)
        @test !isnothing(result)
        names = collect_names(result)
        @test "fast test" in names
        @test !("slow test" in names)
    end

    @testset "filter by tag exclusion" begin
        tree = make_tree()
        f = TestFilter(names=String[], tags=Set{Symbol}(), exclude_tags=Set([:slow]))
        result = filter_tree(tree, f)
        @test !isnothing(result)
        names = collect_names(result)
        @test "fast test" in names
        @test "login" in names
        @test !("slow test" in names)
        @test !("logout" in names)
    end

    @testset "parse CLI args" begin
        args = ["auth", "login", "--tags=unit,fast", "--exclude=slow"]
        f = parse_test_args(args)
        @test f.names == ["auth", "login"]
        @test f.tags == Set([:unit, :fast])
        @test f.exclude_tags == Set([:slow])
    end

    @testset "empty filter returns full tree" begin
        tree = make_tree()
        f = TestFilter(names=String[], tags=Set{Symbol}(), exclude_tags=Set{Symbol}())
        result = filter_tree(tree, f)
        @test !isnothing(result)
        names = collect_names(result)
        @test length(names) == 5  # all 5 named nodes (excl root)
    end
end
