using Test
using CofreeTest
using CofreeTest: schedule_tree, run_tree, EventBus, CollectorSubscriber, subscribe!

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
end
