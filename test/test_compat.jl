using Test
using CofreeTest
using CofreeTest: CofreeTestSet, EventBus, CollectorSubscriber, subscribe!

@testset "Compat" begin
    @testset "@test pass intercepted" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        ts = CofreeTestSet(bus, "compat test")
        Test.push_testset(ts)
        try
            @test 1 + 1 == 2
        finally
            Test.pop_testset()
        end

        @test any(e -> e isa AssertionPassed, collector.events)
    end

    @testset "@test fail intercepted" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        ts = CofreeTestSet(bus, "compat test")
        Test.push_testset(ts)
        try
            @test 1 == 2
        finally
            Test.pop_testset()
        end

        @test any(e -> e isa AssertionFailed, collector.events)
    end

    @testset "Test.Broken intercepted as AssertionPassed" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        ts = CofreeTestSet(bus, "broken test")
        result = Test.Broken(:test_broken, :(1 == 2))
        Test.record(ts, result)

        @test any(e -> e isa AssertionPassed, collector.events)
        evt = first(e for e in collector.events if e isa AssertionPassed)
        @test evt.value == :broken
    end

    @testset "Test.Error intercepted as AssertionFailed" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        ts = CofreeTestSet(bus, "error test")
        Test.push_testset(ts)
        try
            # @test with an expression that throws triggers a Test.Error record
            @test error("test error")
        finally
            Test.pop_testset()
        end

        @test any(e -> e isa AssertionFailed, collector.events)
        evt = first(e for e in collector.events if e isa AssertionFailed)
        @test evt.expr == :error
        @test evt.expected == :no_error
    end

    @testset "Test.finish is a no-op" begin
        bus = EventBus()
        ts = CofreeTestSet(bus, "test")
        @test Test.finish(ts) === nothing
    end
end
