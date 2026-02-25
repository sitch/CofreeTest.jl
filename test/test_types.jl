using Test
using CofreeTest

@testset "Types" begin
    @testset "Outcome types" begin
        p = Pass(42)
        @test p.value == 42

        f = Fail(:(@test 1 == 2), 1, 2, LineNumberNode(1, :file))
        @test f.expected == 1
        @test f.got == 2

        e = Error(ErrorException("boom"), nothing)
        @test e.exception == ErrorException("boom")

        s = Skip("not implemented")
        @test s.reason == "not implemented"

        pd = Pending("todo")
        @test pd.reason == "todo"

        t = Timeout(5.0, 10.0)
        @test t.limit == 5.0
        @test t.actual == 10.0
    end

    @testset "Metrics" begin
        m = Metrics(1.5, 1024, 0.1, 6.7, 128.0)
        @test m.time_s == 1.5
        @test m.bytes_allocated == 1024
        @test m.gc_time_s == 0.1
        @test m.gc_pct == 6.7
        @test m.rss_mb == 128.0
    end

    @testset "CapturedIO" begin
        io = CapturedIO("hello", "warn")
        @test io.stdout == "hello"
        @test io.stderr == "warn"
    end

    @testset "TestSpec" begin
        spec = TestSpec(
            name="my test",
            tags=Set([:unit]),
            source=LineNumberNode(10, Symbol("test.jl")),
            body=:(@check true),
            setup=nothing,
            teardown=nothing,
        )
        @test spec.name == "my test"
        @test :unit in spec.tags
        @test spec.body isa Expr
        @test spec.setup === nothing
        @test spec.teardown === nothing
        @test spec.source.line == 10
        @test spec.source.file == Symbol("test.jl")
    end

    @testset "Scheduled" begin
        spec = TestSpec("t", Set{Symbol}(), LineNumberNode(1, :f), nothing, nothing, nothing)
        sched = Scheduled(spec, :inline, nothing, 0.0)
        @test sched.spec === spec
        @test sched.executor == :inline
    end

    @testset "TestResult" begin
        spec = TestSpec("t", Set{Symbol}(), LineNumberNode(1, :f), nothing, nothing, nothing)
        metrics = Metrics(0.1, 512, 0.0, 0.0, 64.0)
        result = TestResult(spec, Pass(true), 0.1, metrics, TestEvent[], CapturedIO("", ""))
        @test result.outcome isa Pass
        @test result.duration == 0.1
    end

    @testset "Cofree integration" begin
        spec1 = TestSpec("suite", Set{Symbol}(), LineNumberNode(1, :f), nothing, nothing, nothing)
        spec2 = TestSpec("test1", Set([:unit]), LineNumberNode(2, :f), :(1+1), nothing, nothing)
        tree = suite(spec1, [leaf(spec2)])
        @test extract(tree).name == "suite"
        @test extract(tree.tail[1]).name == "test1"
    end

    @testset "TestSpec kwdef defaults" begin
        spec = TestSpec(name="minimal")
        @test spec.name == "minimal"
        @test spec.tags == Set{Symbol}()
        @test spec.source == LineNumberNode(0, :unknown)
        @test spec.body === nothing
        @test spec.setup === nothing
        @test spec.teardown === nothing
    end

    @testset "TestResult with non-empty events" begin
        spec = TestSpec(name="t")
        metrics = Metrics(0.1, 512, 0.0, 0.0, 64.0)
        events = TestEvent[SuiteStarted("s", LineNumberNode(1, :f), 1.0)]
        result = TestResult(spec, Pass(true), 0.1, metrics, events, CapturedIO("", ""))
        @test length(result.events) == 1
        @test result.events[1] isa SuiteStarted
    end
end
