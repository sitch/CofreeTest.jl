using Test
using CofreeTest
using CofreeTest: schedule_tree, run_tree, EventBus, CollectorSubscriber, subscribe!,
    _make_executor, _make_formatter, _aggregate_metrics, _aggregate_outcome, _count_leaves

@testset "Runner" begin
    @testset "schedule assigns inline executor" begin
        tree = suite(
            TestSpec(name="root"),
            [
                leaf(TestSpec(name="t1", body=:(@check true))),
                leaf(TestSpec(name="t2", body=:(@check 1 == 1))),
            ]
        )

        scheduled = schedule_tree(tree)
        @test extract(scheduled) isa Scheduled
        @test extract(scheduled).executor == :inline
        @test extract(scheduled).priority == Inf  # default with no history
        @test extract(scheduled.tail[1]).priority == Inf
        @test length(scheduled.tail) == 2
    end

    @testset "run_tree produces TestResult tree" begin
        tree = suite(
            TestSpec(name="root"),
            [
                leaf(TestSpec(name="t1", body=:(@check true))),
                leaf(TestSpec(name="t2", body=:(@check 1 + 1 == 2))),
            ]
        )

        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        scheduled = schedule_tree(tree)
        results = run_tree(scheduled, bus)

        @test extract(results) isa TestResult
        @test extract(results).spec.name == "root"

        # Children should have results
        @test extract(results.tail[1]) isa TestResult
        @test extract(results.tail[1]).outcome isa Pass
        @test extract(results.tail[2]) isa TestResult
        @test extract(results.tail[2]).outcome isa Pass

        # Events should have been emitted
        @test any(e -> e isa TestStarted, collector.events)
        @test any(e -> e isa TestFinished, collector.events)
    end

    @testset "run_tree handles errors" begin
        tree = leaf(TestSpec(name="boom", body=:(error("kaboom"))))

        bus = EventBus()
        scheduled = schedule_tree(tree)
        results = run_tree(scheduled, bus)

        @test extract(results).outcome isa Error
    end

    @testset "schedule_tree with history — finite priority" begin
        tree = suite(
            TestSpec(name="root"),
            [
                leaf(TestSpec(name="t1", body=:(@check true))),
                leaf(TestSpec(name="t2", body=:(@check 1 == 1))),
            ]
        )

        history = Dict("t1" => 0.5, "t2" => 1.2)
        scheduled = schedule_tree(tree; history)
        @test extract(scheduled.tail[1]).priority == 0.5
        @test extract(scheduled.tail[2]).priority == 1.2
    end

    @testset "schedule_tree with deep nesting" begin
        tree = suite(
            TestSpec(name="root"),
            [
                suite(
                    TestSpec(name="mid"),
                    [leaf(TestSpec(name="deep", body=:(@check true)))]
                )
            ]
        )

        scheduled = schedule_tree(tree)
        @test extract(scheduled.tail[1].tail[1]) isa Scheduled
        @test extract(scheduled.tail[1].tail[1]).spec.name == "deep"
    end

    @testset "_make_executor unknown kind" begin
        @test_throws ErrorException _make_executor(:nonexistent)
    end

    @testset "_make_formatter unknown kind" begin
        @test_throws ErrorException _make_formatter(:nonexistent, IOBuffer(); color=false, verbose=false)
    end

    @testset "_aggregate_metrics — empty children" begin
        m = _aggregate_metrics(Cofree[])
        @test m.time_s == 0.0
        @test m.bytes_allocated == 0
    end

    @testset "_aggregate_outcome — Error takes precedence" begin
        spec = TestSpec(name="t")
        m = Metrics(0.0, 0, 0.0, 0.0, 0.0)
        children = [
            leaf(TestResult(spec, Error(ErrorException("e"), nothing), 0.0, m, TestEvent[], CapturedIO("", ""))),
            leaf(TestResult(spec, Fail(:x, :a, :b, LineNumberNode(0, :f)), 0.0, m, TestEvent[], CapturedIO("", ""))),
        ]
        result = _aggregate_outcome(children)
        @test result isa Error
    end

    @testset "_aggregate_outcome — all Pass" begin
        spec = TestSpec(name="t")
        m = Metrics(0.0, 0, 0.0, 0.0, 0.0)
        children = [
            leaf(TestResult(spec, Pass(true), 0.0, m, TestEvent[], CapturedIO("", ""))),
            leaf(TestResult(spec, Pass(true), 0.0, m, TestEvent[], CapturedIO("", ""))),
        ]
        result = _aggregate_outcome(children)
        @test result isa Pass
    end

    @testset "_count_leaves" begin
        tree = suite(
            TestSpec(name="root"),
            [
                leaf(TestSpec(name="t1", body=:(@check true))),
                suite(
                    TestSpec(name="mid"),
                    [leaf(TestSpec(name="t2", body=:(1+1)))]
                ),
            ]
        )
        @test _count_leaves(tree) == 2
    end

    @testset "runtests with formatter=:dot" begin
        tree = suite(
            TestSpec(name="root"),
            [leaf(TestSpec(name="t1", body=:(1 + 1)))]
        )
        io = IOBuffer()
        runtests(tree; io, formatter=:dot, color=false)
        output = String(take!(io))
        @test contains(output, ".")
    end

    @testset "runtests with formatter=:json" begin
        tree = suite(
            TestSpec(name="root"),
            [leaf(TestSpec(name="t1", body=:(1 + 1)))]
        )
        io = IOBuffer()
        runtests(tree; io, formatter=:json, color=false)
        output = String(take!(io))
        @test startswith(strip(output), "[")
    end

    @testset "_aggregate_outcome — Fail with Pass (no Error)" begin
        spec = TestSpec(name="t")
        m = Metrics(0.0, 0, 0.0, 0.0, 0.0)
        children = [
            leaf(TestResult(spec, Pass(true), 0.0, m, TestEvent[], CapturedIO("", ""))),
            leaf(TestResult(spec, Fail(:x, :a, :b, LineNumberNode(0, :f)), 0.0, m, TestEvent[], CapturedIO("", ""))),
        ]
        result = _aggregate_outcome(children)
        @test result isa Fail
    end

    @testset "runtests with verbose=true" begin
        tree = suite(
            TestSpec(name="root"),
            [leaf(TestSpec(name="t1", body=:(1 + 1)))]
        )
        io = IOBuffer()
        runtests(tree; io, color=false, verbose=true)
        output = String(take!(io))
        @test contains(output, "t1")
    end
end
