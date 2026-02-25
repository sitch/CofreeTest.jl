using Test
using CofreeTest
using CofreeTest: MultiFormatter, DotFormatter, handle!, finalize!

@testset "MultiFormatter" begin
    @testset "handle! — dispatches to all child formatters" begin
        io1 = IOBuffer()
        io2 = IOBuffer()
        fmt = MultiFormatter([DotFormatter(io1), DotFormatter(io2)])
        event = TestFinished("t", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0)
        handle!(fmt, event)

        @test position(io1) > 0  # something written
        @test position(io2) > 0
        @test String(take!(io1)) == "."
        @test String(take!(io2)) == "."
    end

    @testset "finalize! — calls finalize! on all children" begin
        io1 = IOBuffer()
        io2 = IOBuffer()
        fmt = MultiFormatter([DotFormatter(io1), DotFormatter(io2)])
        event = TestFinished("t", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0)
        handle!(fmt, event)
        finalize!(fmt)

        output1 = String(take!(io1))
        output2 = String(take!(io2))
        @test contains(output1, "passed")
        @test contains(output2, "passed")
    end

    @testset "handle! — works with zero formatters" begin
        fmt = MultiFormatter(AbstractFormatter[])
        event = TestFinished("t", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0)
        handle!(fmt, event)  # should not error
        finalize!(fmt)
        @test true
    end

    @testset "handle! — works with single formatter" begin
        io = IOBuffer()
        fmt = MultiFormatter([DotFormatter(io)])
        event = TestFinished("t", Fail(:e, 1, 2, LineNumberNode(1, :f)), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0)
        handle!(fmt, event)
        @test String(take!(io)) == "F"
    end
end
