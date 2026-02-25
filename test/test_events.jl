using Test
using CofreeTest
using CofreeTest: EventBus, emit!, subscribe!, CollectorSubscriber

@testset "Events" begin
    @testset "event construction" begin
        e = SuiteStarted("auth", LineNumberNode(1, :f), 1.0)
        @test e.name == "auth"
        @test e.timestamp == 1.0

        e2 = TestStarted("login", LineNumberNode(2, :f), 1, 2.0)
        @test e2.worker_id == 1

        e3 = TestFinished("login", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 3.0)
        @test e3.outcome isa Pass

        e4 = AssertionPassed(:(@check true), true, LineNumberNode(1, :f), 1.0)
        @test e4.value == true

        e5 = AssertionFailed(:(@check 1==2), 1, 2, LineNumberNode(1, :f), 1.0)
        @test e5.expected == 1
    end

    @testset "EventBus emit and subscribe" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        emit!(bus, SuiteStarted("test", LineNumberNode(1, :f), 1.0))
        emit!(bus, TestStarted("t1", LineNumberNode(2, :f), 1, 2.0))
        emit!(bus, TestFinished("t1", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 3.0))

        @test length(collector.events) == 3
        @test collector.events[1] isa SuiteStarted
        @test collector.events[2] isa TestStarted
        @test collector.events[3] isa TestFinished
    end

    @testset "EventBus multiple subscribers" begin
        bus = EventBus()
        c1 = CollectorSubscriber()
        c2 = CollectorSubscriber()
        subscribe!(bus, c1)
        subscribe!(bus, c2)

        emit!(bus, SuiteStarted("s", LineNumberNode(1, :f), 1.0))

        @test length(c1.events) == 1
        @test length(c2.events) == 1
    end
end
