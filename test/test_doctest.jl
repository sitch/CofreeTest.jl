using Test
using CofreeTest
using CofreeTest: EventBus, CollectorSubscriber, subscribe!, emit!

# --- Test module with docstrings for integration tests ---

module DocTestFixture

"""
    double(x)

Double the input value.

```jldoctest
julia> double(3)
6

julia> double(0)
0
```
"""
double(x) = 2x

"""
    greet(name)

Return a greeting string.

```jldoctest
julia> greet("Julia")
"Hello, Julia!"
```
"""
greet(name) = "Hello, $(name)!"

"""
    add(a, b)

No doctest blocks here, just plain docs.
"""
add(a, b) = a + b

"""
    multi_statement()

Tests shared state across statements in a block.

```jldoctest
julia> x = 10
10

julia> x + 5
15
```
"""
multi_statement() = nothing

"""
    print_example()

Tests stdout capture.

```jldoctest
julia> println("hello world")
hello world
```
"""
print_example() = nothing

"""
    setup_example()

Tests setup-only statements (no expected output).

```jldoctest
julia> x = 42

julia> x + 8
50
```
"""
setup_example() = nothing

"""
    multiline_expr()

Tests multi-line expressions with continuation.

```jldoctest
julia> function triple(x)
           3x
       end
triple (generic function with 1 method)

julia> triple(4)
12
```
"""
multiline_expr() = nothing

"""
    two_blocks()

Has two separate doctest blocks.

```jldoctest
julia> 1 + 1
2
```

Some text between blocks.

```jldoctest
julia> 2 * 3
6
```
"""
two_blocks() = nothing

end # module DocTestFixture


@testset "DocTest" begin

    # --- Parsing tests ---

    @testset "extract_doctest_blocks — single block" begin
        docstr = """
            foo(x)

        Does foo.

        ```jldoctest
        julia> foo(2)
        4
        ```
        """
        blocks = CofreeTest._extract_doctest_blocks(docstr)
        @test length(blocks) == 1
        @test length(blocks[1].pairs) == 1
        input, expected = blocks[1].pairs[1]
        @test input == "foo(2)"
        @test expected == "4"
    end

    @testset "extract_doctest_blocks — multiple statements" begin
        docstr = """
        ```jldoctest
        julia> x = 5
        5

        julia> x + 1
        6
        ```
        """
        blocks = CofreeTest._extract_doctest_blocks(docstr)
        @test length(blocks) == 1
        @test length(blocks[1].pairs) == 2
        @test blocks[1].pairs[1] == ("x = 5", "5")
        @test blocks[1].pairs[2] == ("x + 1", "6")
    end

    @testset "extract_doctest_blocks — multiple blocks" begin
        docstr = """
        ```jldoctest
        julia> 1 + 1
        2
        ```

        Text between.

        ```jldoctest
        julia> 2 * 3
        6
        ```
        """
        blocks = CofreeTest._extract_doctest_blocks(docstr)
        @test length(blocks) == 2
        @test blocks[1].pairs[1] == ("1 + 1", "2")
        @test blocks[2].pairs[1] == ("2 * 3", "6")
    end

    @testset "extract_doctest_blocks — no blocks" begin
        docstr = """
        Just plain documentation.

        ```julia
        some_example()
        ```
        """
        blocks = CofreeTest._extract_doctest_blocks(docstr)
        @test isempty(blocks)
    end

    @testset "extract_doctest_blocks — named group" begin
        docstr = """
        ```jldoctest mygroup
        julia> 1 + 1
        2
        ```
        """
        blocks = CofreeTest._extract_doctest_blocks(docstr)
        @test length(blocks) == 1
        @test blocks[1].name == "mygroup"
    end

    @testset "extract_doctest_blocks — setup-only statement" begin
        docstr = """
        ```jldoctest
        julia> x = 42

        julia> x + 8
        50
        ```
        """
        blocks = CofreeTest._extract_doctest_blocks(docstr)
        @test length(blocks) == 1
        @test length(blocks[1].pairs) == 2
        # Setup statement has empty expected output
        @test blocks[1].pairs[1] == ("x = 42", "")
        @test blocks[1].pairs[2] == ("x + 8", "50")
    end

    @testset "extract_doctest_blocks — multi-line expression" begin
        docstr = """
        ```jldoctest
        julia> function triple(x)
                   3x
               end
        triple (generic function with 1 method)
        ```
        """
        blocks = CofreeTest._extract_doctest_blocks(docstr)
        @test length(blocks) == 1
        input, expected = blocks[1].pairs[1]
        @test contains(input, "function triple(x)")
        @test contains(input, "3x")
        @test contains(input, "end")
        @test expected == "triple (generic function with 1 method)"
    end

    @testset "extract_doctest_blocks — stdout capture" begin
        docstr = """
        ```jldoctest
        julia> println("hello world")
        hello world
        ```
        """
        blocks = CofreeTest._extract_doctest_blocks(docstr)
        @test length(blocks) == 1
        @test blocks[1].pairs[1] == ("println(\"hello world\")", "hello world")
    end

    # --- Body generation tests ---

    @testset "doctest_block_to_body produces valid Expr" begin
        block = CofreeTest.DocTestBlock(
            [("1 + 1", "2")],
            nothing,
            LineNumberNode(0, :unknown),
        )
        body = CofreeTest._doctest_block_to_body(block, Main)
        @test body isa Expr
    end

    @testset "doctest_block_to_body — setup-only pair" begin
        block = CofreeTest.DocTestBlock(
            [("x = 42", ""), ("x + 8", "50")],
            nothing,
            LineNumberNode(0, :unknown),
        )
        body = CofreeTest._doctest_block_to_body(block, Main)
        @test body isa Expr
    end

    # --- Tree structure tests ---

    @testset "discover_doctests builds correct tree" begin
        tree = discover_doctests(DocTestFixture)
        spec = extract(tree)

        # Root is a suite named after the module
        @test spec isa TestSpec
        @test contains(spec.name, "DocTestFixture")
        @test spec.body === nothing  # suite, not leaf

        # Has children (one per documented symbol with doctests)
        @test length(tree.tail) > 0

        # All children are suites for symbols
        for child in tree.tail
            child_spec = extract(child)
            @test child_spec isa TestSpec
            @test child_spec.body === nothing  # symbol-level suite
        end
    end

    @testset "discover_doctests skips functions without doctests" begin
        tree = discover_doctests(DocTestFixture)

        # add() has no jldoctest blocks, should not appear
        names = [extract(c).name for c in tree.tail]
        @test !any(n -> contains(n, "add"), names)
    end

    @testset "discover_doctests tags" begin
        tree = discover_doctests(DocTestFixture; tags=Set([:doctest, :custom]))

        # Root and children should have the tags
        @test :doctest in extract(tree).tags
        @test :custom in extract(tree).tags
    end

    @testset "discover_doctests — two blocks become two leaves" begin
        tree = discover_doctests(DocTestFixture)

        # Find the two_blocks symbol
        two_blocks_child = nothing
        for child in tree.tail
            if contains(extract(child).name, "two_blocks")
                two_blocks_child = child
                break
            end
        end

        @test two_blocks_child !== nothing
        @test length(two_blocks_child.tail) == 2
        # Both are leaf TestSpecs with bodies
        for leaf_node in two_blocks_child.tail
            @test extract(leaf_node).body !== nothing
        end
    end

    # --- Runtime execution tests ---

    @testset "_format_doctest_output — value only" begin
        result = CofreeTest._format_doctest_output(42, "")
        @test result == "42"
    end

    @testset "_format_doctest_output — stdout only" begin
        result = CofreeTest._format_doctest_output(nothing, "hello\n")
        @test result == "hello"
    end

    @testset "_format_doctest_output — both value and stdout" begin
        result = CofreeTest._format_doctest_output(42, "debug\n")
        @test contains(result, "debug")
        @test contains(result, "42")
    end

    @testset "_format_doctest_output — nothing and empty" begin
        result = CofreeTest._format_doctest_output(nothing, "")
        @test result == ""
    end

    # --- Integration tests ---

    @testset "discover_doctests + runtests end-to-end" begin
        tree = discover_doctests(DocTestFixture)
        # Run with devnull to suppress output
        result_tree = runtests(tree; io=devnull, formatter=:dot)

        # Root should pass
        root_result = extract(result_tree)
        @test root_result.outcome isa Pass
    end

    @testset "doctest with shared state passes" begin
        tree = discover_doctests(DocTestFixture)
        result_tree = runtests(tree; io=devnull, formatter=:dot)

        # Find multi_statement test result — should pass because x = 10; x + 5 == 15
        found_pass = false
        function check_tree(node)
            r = extract(node)
            if contains(r.spec.name, "multi_statement") && r.spec.body !== nothing
                @test r.outcome isa Pass
                found_pass = true
            end
            for child in node.tail
                check_tree(child)
            end
        end
        check_tree(result_tree)
        @test found_pass
    end

    @testset "doctest with stdout capture passes" begin
        tree = discover_doctests(DocTestFixture)
        result_tree = runtests(tree; io=devnull, formatter=:dot)

        found_pass = false
        function check_print(node)
            r = extract(node)
            if contains(r.spec.name, "print_example") && r.spec.body !== nothing
                @test r.outcome isa Pass
                found_pass = true
            end
            for child in node.tail
                check_print(child)
            end
        end
        check_print(result_tree)
        @test found_pass
    end

    # --- @doctest macro ---

    @testset "@doctest macro returns Cofree tree" begin
        tree = @doctest DocTestFixture
        @test tree isa Cofree
        @test contains(extract(tree).name, "DocTestFixture")
    end
end
