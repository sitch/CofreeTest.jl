using Test
using CofreeTest
using CofreeTest: InlineExecutor, ProcessExecutor, TaskExecutor, execute!, EventBus, CollectorSubscriber, subscribe!, ExecutorPool, create_pool, teardown!, setup!, default_njobs, recycle!

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
        collector = CollectorSubscriber()
        subscribe!(bus, collector)
        exec = InlineExecutor()
        outcome, metrics, io = execute!(exec, spec, bus)

        # The executor detects assertion failures and returns Fail
        @test outcome isa Fail
        @test any(e -> e isa AssertionFailed, collector.events)
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

    @testset "ProcessExecutor — executes in separate process" begin
        spec = TestSpec(
            name="process test",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=quote
                1 + 1
            end,
        )
        bus = EventBus()
        exec = ProcessExecutor(1)
        try
            outcome, metrics, io = execute!(exec, spec, bus)
            @test outcome isa Pass
            @test metrics.time_s >= 0.0
        finally
            teardown!(exec)
        end
    end

    @testset "ExecutorPool — creates pool of workers" begin
        pool = create_pool(ProcessExecutor; njobs=2)
        try
            @test length(pool.executors) == 2
        finally
            teardown!(pool)
        end
    end

    @testset "TaskExecutor — executes as green thread" begin
        spec = TestSpec(
            name="task test",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=:(1 + 1),
        )
        bus = EventBus()
        exec = TaskExecutor(1)
        outcome, metrics, io = execute!(exec, spec, bus)
        @test outcome isa Pass
    end

    @testset "ProcessExecutor — error in test body" begin
        spec = TestSpec(
            name="process error",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=:(error("kaboom")),
        )
        bus = EventBus()
        exec = ProcessExecutor(1)
        try
            outcome, metrics, io = execute!(exec, spec, bus)
            @test outcome isa Error
        finally
            teardown!(exec)
        end
    end

    @testset "ProcessExecutor — setup!/teardown! lifecycle" begin
        exec = ProcessExecutor(1)
        teardown!(exec)
        @test exec.worker === nothing
        setup!(exec)
        @test exec.worker !== nothing
        teardown!(exec)
        @test exec.worker === nothing
    end

    @testset "TaskExecutor — error in test body" begin
        spec = TestSpec(
            name="task error",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=:(error("kaboom")),
        )
        bus = EventBus()
        exec = TaskExecutor(1)
        outcome, metrics, io = execute!(exec, spec, bus)
        @test outcome isa Error
    end

    @testset "default_njobs returns >= 1" begin
        @test default_njobs() >= 1
    end

    @testset "ProcessExecutor — recycle! respawns worker" begin
        exec = ProcessExecutor(1)
        try
            @test exec.worker !== nothing
            recycle!(exec)
            @test exec.worker !== nothing  # worker alive after recycle
        finally
            teardown!(exec)
        end
    end
end
