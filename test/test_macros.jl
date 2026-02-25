using Test
using CofreeTest
using CofreeTest: EventBus, CollectorSubscriber, subscribe!

# We test macros by setting up a bus, running @check, and inspecting events

@testset "Macros" begin
    @testset "@check passing" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        # Simulate what happens inside a test execution context
        CofreeTest.with_bus(bus) do
            @check 1 + 1 == 2
        end

        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionPassed
    end

    @testset "@check failing" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check 1 == 2
        end

        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionFailed
        @test collector.events[1].expected == 2
        @test collector.events[1].got == 1
    end

    @testset "@check_throws passing" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check_throws ErrorException error("boom")
        end

        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionPassed
    end

    @testset "@check_throws failing — no exception" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check_throws ErrorException 1 + 1
        end

        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionFailed
    end

    @testset "@check_throws failing — wrong exception" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check_throws ArgumentError error("boom")
        end

        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionFailed
    end

    @testset "@check_skip" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check_skip "not ready"
        end

        # check_skip emits a LogEvent
        @test length(collector.events) == 1
        @test collector.events[1] isa LogEvent
    end
end
