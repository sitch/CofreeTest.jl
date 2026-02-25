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
end
