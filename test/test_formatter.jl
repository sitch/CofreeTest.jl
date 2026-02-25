using Test
using CofreeTest
using CofreeTest: DotFormatter, handle!, finalize!, EventBus, CollectorSubscriber

@testset "Formatters" begin
    @testset "DotFormatter — pass" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, TestFinished("t1", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        @test String(take!(io)) == "."
    end

    @testset "DotFormatter — fail" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, TestFinished("t1", Fail(:e, 1, 2, LineNumberNode(1, :f)), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        @test String(take!(io)) == "F"
    end

    @testset "DotFormatter — error" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, TestFinished("t1", Error(ErrorException("x"), nothing), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        @test String(take!(io)) == "E"
    end

    @testset "DotFormatter — skip" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, TestFinished("t1", Skip("r"), Metrics(0.0, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        @test String(take!(io)) == "S"
    end

    @testset "DotFormatter — ignores non-TestFinished events" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, SuiteStarted("s", LineNumberNode(1, :f), 1.0))
        @test String(take!(io)) == ""
    end

    @testset "DotFormatter — finalize prints newline and summary" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, TestFinished("t1", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        handle!(fmt, TestFinished("t2", Fail(:e, 1, 2, LineNumberNode(1, :f)), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        take!(io)  # clear dots
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "2 tests")
        @test contains(output, "1 passed")
        @test contains(output, "1 failed")
    end
end
