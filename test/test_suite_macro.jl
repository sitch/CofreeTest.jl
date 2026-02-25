using Test
using CofreeTest
using CofreeTest: extract, Cofree

@testset "Suite Macro" begin
    @testset "basic @suite with @testcase children" begin
        tree = @suite "my suite" begin
            @testcase "first" begin
                @check 1 == 1
            end
            @testcase "second" begin
                @check true
            end
        end

        @test tree isa Cofree
        @test extract(tree).name == "my suite"
        @test length(tree.tail) == 2
        @test extract(tree.tail[1]).name == "first"
        @test extract(tree.tail[2]).name == "second"
        @test extract(tree.tail[1]).body isa Expr
    end

    @testset "@suite with tags" begin
        tree = @suite "tagged" tags=[:slow, :integration] begin
            @testcase "t1" begin end
        end

        @test :slow in extract(tree).tags
        @test :integration in extract(tree).tags
    end

    @testset "nested @suite" begin
        tree = @suite "outer" begin
            @suite "inner" begin
                @testcase "deep" begin
                    @check true
                end
            end
        end

        @test extract(tree).name == "outer"
        @test extract(tree.tail[1]).name == "inner"
        @test extract(tree.tail[1].tail[1]).name == "deep"
    end
end
