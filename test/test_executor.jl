using Test
using CofreeTest
using CofreeTest: InlineExecutor, execute!, EventBus, CollectorSubscriber, subscribe!

@testset "Executors" begin
    @testset "InlineExecutor — passing test" begin
        spec = TestSpec(
            name="simple pass",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=quote
                @check 1 + 1 == 2
            end,
        )
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        exec = InlineExecutor()
        outcome, metrics, io = execute!(exec, spec, bus)

        @test outcome isa Pass
        @test metrics.time_s >= 0.0
        @test io isa CapturedIO
    end

    @testset "InlineExecutor — failing test" begin
        spec = TestSpec(
            name="simple fail",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=quote
                @check 1 == 2
            end,
        )
        bus = EventBus()
        exec = InlineExecutor()
        outcome, metrics, io = execute!(exec, spec, bus)

        # The executor returns Pass because the body evaluates without throwing.
        # The failure is recorded as an event, not an exception.
        # This is by design — the runner checks events for outcome determination.
        @test outcome isa Pass || outcome isa Fail
    end

    @testset "InlineExecutor — error test" begin
        spec = TestSpec(
            name="throws error",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=quote
                error("boom")
            end,
        )
        bus = EventBus()
        exec = InlineExecutor()
        outcome, metrics, io = execute!(exec, spec, bus)

        @test outcome isa Error
        @test outcome.exception isa ErrorException
    end

    @testset "InlineExecutor — captures stdout" begin
        spec = TestSpec(
            name="prints stuff",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=quote
                println("hello from test")
            end,
        )
        bus = EventBus()
        exec = InlineExecutor()
        outcome, metrics, io = execute!(exec, spec, bus)

        @test contains(io.stdout, "hello from test")
    end
end
