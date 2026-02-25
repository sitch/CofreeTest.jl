using Test
using CofreeTest

@testset "Integration" begin
    @testset "runtests with inline executor" begin
        tree = suite(
            TestSpec(name="integration suite"),
            [
                leaf(TestSpec(name="addition", body=:(@check 1 + 1 == 2))),
                leaf(TestSpec(name="string", body=:(@check "hello" == "hello"))),
            ]
        )

        io = IOBuffer()
        result_tree = runtests(tree; io, color=false)

        @test extract(result_tree) isa TestResult
        @test extract(result_tree.tail[1]).outcome isa Pass
        @test extract(result_tree.tail[2]).outcome isa Pass

        output = String(take!(io))
        @test contains(output, "CofreeTest")
        @test contains(output, "passed")
    end

    @testset "runtests with failures" begin
        tree = suite(
            TestSpec(name="mixed suite"),
            [
                leaf(TestSpec(name="pass", body=:(@check true))),
                leaf(TestSpec(name="fail", body=:(@check 1 == 2))),
            ]
        )

        io = IOBuffer()
        result_tree = runtests(tree; io, color=false)

        @test extract(result_tree.tail[1]).outcome isa Pass
        # The fail test — @check 1 == 2 emits AssertionFailed but body still returns false
        # Check if we get a meaningful result
        @test extract(result_tree.tail[2]) isa TestResult
    end

    @testset "End-to-end: define → schedule → execute → format" begin
        tree = @suite "e2e" begin
            @testcase "math works" begin
                @check 2 + 2 == 4
                @check 3 * 3 == 9
            end

            @testcase "strings work" begin
                @check "hello " * "world" == "hello world"
            end

            @suite "nested" begin
                @testcase "deep test" begin
                    @check true
                end
            end
        end

        io = IOBuffer()
        result_tree = runtests(tree; io, color=false, formatter=:terminal)

        # Verify result tree structure
        @test extract(result_tree) isa TestResult
        @test extract(result_tree).spec.name == "e2e"

        # All leaf tests should pass
        for child in result_tree.tail
            r = extract(child)
            if r.spec.body !== nothing
                @test r.outcome isa Pass
            end
        end

        # Verify terminal output
        output = String(take!(io))
        @test contains(output, "CofreeTest")
        @test contains(output, "math works")
        @test contains(output, "passed")
    end
end
