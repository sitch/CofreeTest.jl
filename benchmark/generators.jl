# generators.jl — Generate equivalent test workloads for CofreeTest and Test stdlib

using CofreeTest
using CofreeTest: schedule_tree, EventBus, subscribe!, run_tree
using Test

# --- CofreeTest generators ---

function generate_flat_suite(n::Int)
    children = [leaf(TestSpec(name="test_$i", body=:(@check true))) for i in 1:n]
    suite(TestSpec(name="flat_$n"), children)
end

function generate_nested_suite(depth::Int, breadth::Int)
    if depth <= 1
        children = [leaf(TestSpec(name="leaf_$i", body=:(@check true))) for i in 1:breadth]
        return suite(TestSpec(name="level_1"), children)
    end
    children = [generate_nested_suite(depth - 1, breadth) for _ in 1:breadth]
    suite(TestSpec(name="level_$depth"), children)
end

function generate_multi_assertion_suite(n_tests::Int, n_assertions::Int)
    body = Expr(:block, [:(CofreeTest.@check($(i) == $(i))) for i in 1:n_assertions]...)
    children = [leaf(TestSpec(name="multi_$j", body=body)) for j in 1:n_tests]
    suite(TestSpec(name="multi_assert"), children)
end

const SCALING_POINTS = [10, 50, 100, 500, 1000, 5000]

function generate_scaling_points()
    [(n=n, cofree=generate_flat_suite(n), stdlib=stdlib_flat_suite(n)) for n in SCALING_POINTS]
end

# --- Test stdlib generators ---

function stdlib_flat_suite(n::Int)
    function ()
        redirect_stdout(devnull) do
            redirect_stderr(devnull) do
                Test.@testset "flat_$n" begin
                    for i in 1:n
                        Test.@test true
                    end
                end
            end
        end
        nothing
    end
end

function stdlib_nested_suite(depth::Int, breadth::Int)
    function ()
        redirect_stdout(devnull) do
            redirect_stderr(devnull) do
                _run_stdlib_nested(depth, breadth)
            end
        end
        nothing
    end
end

function _run_stdlib_nested(depth::Int, breadth::Int)
    if depth <= 1
        Test.@testset "level_1" begin
            for i in 1:breadth
                Test.@test true
            end
        end
    else
        Test.@testset "level_$depth" begin
            for _ in 1:breadth
                _run_stdlib_nested(depth - 1, breadth)
            end
        end
    end
end

function stdlib_multi_assertion(n_tests::Int, n_assertions::Int)
    function ()
        redirect_stdout(devnull) do
            redirect_stderr(devnull) do
                Test.@testset "multi" begin
                    for j in 1:n_tests
                        Test.@testset "test_$j" begin
                            for i in 1:n_assertions
                                Test.@test i == i
                            end
                        end
                    end
                end
            end
        end
        nothing
    end
end
