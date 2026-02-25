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
end
