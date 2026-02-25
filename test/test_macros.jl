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

        # check_skip emits a LogEvent with level and message
        @test length(collector.events) == 1
        @test collector.events[1] isa LogEvent
        @test collector.events[1].level == :skip
        @test collector.events[1].message == "not ready"
    end

    @testset "@check_broken — expected failure passes" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        result = CofreeTest.with_bus(bus) do
            @check_broken 1 == 2
        end

        @test result == true
        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionPassed
        @test collector.events[1].value == :broken
    end

    @testset "@check_broken — unexpected pass fails" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        result = CofreeTest.with_bus(bus) do
            @check_broken 1 == 1
        end

        @test result == false
        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionFailed
        @test collector.events[1].expected == :broken
        @test collector.events[1].got == :passed
    end

    @testset "@check_broken — exception counts as expected failure" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        result = CofreeTest.with_bus(bus) do
            @check_broken error("boom")
        end

        @test result == true
        @test collector.events[1] isa AssertionPassed
        @test collector.events[1].value == :broken
    end

    @testset "@check with comparison operators" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check 1 != 2
            @check 1 < 2
            @check 2 > 1
            @check 1 <= 1
            @check 2 >= 2
            @check 1 === 1
        end

        @test length(collector.events) == 6
        @test all(e -> e isa AssertionPassed, collector.events)
    end

    @testset "@check operator failure captures both sides" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check 10 < 5
        end

        @test length(collector.events) == 1
        evt = collector.events[1]
        @test evt isa AssertionFailed
        @test evt.got == 10
        @test evt.expected == 5
    end

    @testset "current_bus outside context throws" begin
        @test_throws ErrorException CofreeTest.current_bus()
    end
end
