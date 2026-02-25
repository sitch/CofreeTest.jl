using Test
using CofreeTest
using CofreeTest: Cofree, extract, duplicate, extend, fmap, hoist, leaf, suite

@testset "Cofree" begin
    @testset "construction and extract" begin
        c = Cofree(1, Cofree{Vector{Cofree{Vector{Nothing}, Int}}, Int}[])
        @test extract(c) == 1
        @test c.tail == []

        c2 = Cofree("hello", [Cofree("world", Cofree{Vector{Cofree{Vector{Nothing}, String}}, String}[])])
        @test extract(c2) == "hello"
        @test length(c2.tail) == 1
        @test extract(c2.tail[1]) == "world"
    end

    @testset "leaf and suite constructors" begin
        l = leaf(42)
        @test extract(l) == 42
        @test isempty(l.tail)

        s = suite(0, [leaf(1), leaf(2), leaf(3)])
        @test extract(s) == 0
        @test length(s.tail) == 3
        @test extract(s.tail[2]) == 2
    end

    @testset "fmap" begin
        children = [leaf(1), leaf(2), leaf(3)]
        result = fmap(c -> Cofree(extract(c) * 10, c.tail), children)
        @test extract(result[1]) == 10
        @test extract(result[2]) == 20
        @test extract(result[3]) == 30
    end

    @testset "hoist" begin
        tree = suite("root", [leaf("a"), suite("mid", [leaf("b")])])
        upper = hoist(uppercase, tree)
        @test extract(upper) == "ROOT"
        @test extract(upper.tail[1]) == "A"
        @test extract(upper.tail[2]) == "MID"
        @test extract(upper.tail[2].tail[1]) == "B"
    end

    @testset "duplicate" begin
        tree = suite(1, [leaf(2), leaf(3)])
        d = duplicate(tree)
        # extract(duplicate(x)) == x  (comonad law 1)
        @test extract(d) === tree
        # each child is the original subtree
        @test extract(d.tail[1]) === tree.tail[1]
        @test extract(d.tail[2]) === tree.tail[2]
    end

    @testset "extend" begin
        tree = suite(1, [leaf(2), leaf(3)])
        # extend extract == id  (comonad law 2)
        result = extend(extract, tree)
        @test extract(result) == extract(tree)
        @test extract(result.tail[1]) == extract(tree.tail[1])
        @test extract(result.tail[2]) == extract(tree.tail[2])
    end

    @testset "comonad law: extract ∘ duplicate == id" begin
        tree = suite("a", [leaf("b"), suite("c", [leaf("d")])])
        @test extract(duplicate(tree)) === tree
    end

    @testset "comonad law: fmap extract ∘ duplicate == id" begin
        tree = suite(1, [leaf(2), leaf(3)])
        d = duplicate(tree)
        unwrapped = Cofree(extract(extract(d)), fmap(c -> Cofree(extract(extract(c)), extract(c).tail), d.tail))
        @test extract(unwrapped) == extract(tree)
        @test extract(unwrapped.tail[1]) == extract(tree.tail[1])
    end

    @testset "extend composes" begin
        tree = suite(1, [leaf(2), leaf(3)])
        f = c -> extract(c) + 1
        g = c -> extract(c) * 2
        # extend f ∘ extend g == extend (f ∘ extend g)
        left = extend(f, extend(g, tree))
        right = extend(c -> f(extend(g, c)), tree)
        @test extract(left) == extract(right)
        @test extract(left.tail[1]) == extract(right.tail[1])
    end

    @testset "fmap over Tuple" begin
        children = (leaf(1), leaf(2))
        result = fmap(c -> Cofree(extract(c) * 10, c.tail), children)
        @test result isa Tuple
        @test extract(result[1]) == 10
        @test extract(result[2]) == 20
    end

    @testset "leaf(nothing)" begin
        l = leaf(nothing)
        @test extract(l) === nothing
        @test isempty(l.tail)
    end

    @testset "suite with empty children" begin
        s = suite("root", Cofree[])
        @test extract(s) == "root"
        @test isempty(s.tail)
    end

    @testset "duplicate on leaf" begin
        l = leaf(42)
        d = duplicate(l)
        @test extract(d) === l
        @test isempty(d.tail)
    end

    @testset "extend on leaf" begin
        l = leaf(10)
        result = extend(c -> extract(c) * 2, l)
        @test extract(result) == 20
        @test isempty(result.tail)
    end
end
