using Test
using CofreeTest
using CofreeTest: HISTORY_DIR, _history_path, load_history, save_history!, _collect_durations!

@testset "History" begin
    @testset "_history_path — builds versioned path from module" begin
        mktempdir() do dir
            old = HISTORY_DIR[]
            try
                HISTORY_DIR[] = dir
                path = _history_path(Main)
                @test contains(path, "Main")
                @test contains(path, "$(VERSION.major).$(VERSION.minor)")
                @test endswith(path, ".jls")
                @test startswith(path, dir)
            finally
                HISTORY_DIR[] = old
            end
        end
    end

    @testset "load_history — returns empty dict when no file exists" begin
        mktempdir() do dir
            old = HISTORY_DIR[]
            try
                HISTORY_DIR[] = dir
                result = load_history(Main)
                @test result == Dict{String, Float64}()
                @test result isa Dict{String, Float64}
            finally
                HISTORY_DIR[] = old
            end
        end
    end

    @testset "load_history — returns empty dict on corrupt file" begin
        mktempdir() do dir
            old = HISTORY_DIR[]
            try
                HISTORY_DIR[] = dir
                path = _history_path(Main)
                mkpath(dirname(path))
                write(path, "this is garbage data not valid serialization")
                result = load_history(Main)
                @test result == Dict{String, Float64}()
            finally
                HISTORY_DIR[] = old
            end
        end
    end

    @testset "save_history! and load_history — round-trip" begin
        mktempdir() do dir
            old = HISTORY_DIR[]
            try
                HISTORY_DIR[] = dir

                # Build a result tree with known durations
                m1 = Metrics(1.5, 100, 0.0, 0.0, 0.0)
                m2 = Metrics(2.5, 200, 0.0, 0.0, 0.0)
                spec1 = TestSpec(name="test_a", body=:(@check true))
                spec2 = TestSpec(name="test_b", body=:(@check true))
                r1 = TestResult(spec1, Pass(true), 1.5, m1, TestEvent[], CapturedIO("", ""))
                r2 = TestResult(spec2, Pass(true), 2.5, m2, TestEvent[], CapturedIO("", ""))
                result_tree = suite(
                    TestResult(TestSpec(name="root"), Pass(nothing), 4.0, Metrics(4.0, 300, 0.0, 0.0, 0.0), TestEvent[], CapturedIO("", "")),
                    [leaf(r1), leaf(r2)]
                )

                save_history!(Main, result_tree)
                durations = load_history(Main)

                @test durations["test_a"] == 1.5
                @test durations["test_b"] == 2.5
                @test length(durations) == 2
            finally
                HISTORY_DIR[] = old
            end
        end
    end

    @testset "save_history! — creates directory if missing" begin
        mktempdir() do dir
            old = HISTORY_DIR[]
            nested = joinpath(dir, "deep", "nested", "path")
            try
                HISTORY_DIR[] = nested

                spec = TestSpec(name="t1", body=:(@check true))
                m = Metrics(0.5, 0, 0.0, 0.0, 0.0)
                r = TestResult(spec, Pass(true), 0.5, m, TestEvent[], CapturedIO("", ""))
                tree = suite(
                    TestResult(TestSpec(name="root"), Pass(nothing), 0.5, m, TestEvent[], CapturedIO("", "")),
                    [leaf(r)]
                )

                save_history!(Main, tree)
                @test isfile(_history_path(Main))
            finally
                HISTORY_DIR[] = old
            end
        end
    end

    @testset "_collect_durations! — skips suite nodes (body === nothing)" begin
        durations = Dict{String, Float64}()
        spec_suite = TestSpec(name="suite_node")  # body === nothing
        spec_leaf = TestSpec(name="leaf_node", body=:(@check true))
        m = Metrics(1.0, 0, 0.0, 0.0, 0.0)
        r_suite = TestResult(spec_suite, Pass(nothing), 2.0, m, TestEvent[], CapturedIO("", ""))
        r_leaf = TestResult(spec_leaf, Pass(true), 1.0, m, TestEvent[], CapturedIO("", ""))

        tree = suite(r_suite, [leaf(r_leaf)])
        _collect_durations!(durations, tree)

        @test haskey(durations, "leaf_node")
        @test !haskey(durations, "suite_node")
        @test durations["leaf_node"] == 1.0
    end

    @testset "_collect_durations! — recurses into nested children" begin
        durations = Dict{String, Float64}()
        m = Metrics(0.5, 0, 0.0, 0.0, 0.0)

        deep_leaf = TestResult(TestSpec(name="deep", body=:(@check true)), Pass(true), 0.3, m, TestEvent[], CapturedIO("", ""))
        inner_suite = TestResult(TestSpec(name="inner"), Pass(nothing), 0.3, m, TestEvent[], CapturedIO("", ""))
        outer_suite = TestResult(TestSpec(name="outer"), Pass(nothing), 0.3, m, TestEvent[], CapturedIO("", ""))

        tree = suite(outer_suite, [suite(inner_suite, [leaf(deep_leaf)])])
        _collect_durations!(durations, tree)

        @test haskey(durations, "deep")
        @test durations["deep"] == 0.3
        @test length(durations) == 1
    end
end
