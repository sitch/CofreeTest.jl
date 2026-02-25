using Test
using CofreeTest
using CofreeTest: TerminalFormatter, handle!, finalize!, start!

function tf_event(; name="test", outcome=Pass(true), time_s=0.1, bytes=1024)
    metrics = Metrics(time_s, bytes, 0.0, 0.0, 0.0)
    TestFinished(name, outcome, metrics, CapturedIO("", ""), time())
end

@testset "TerminalFormatter" begin
    @testset "construction — defaults" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        @test fmt.total == 0
        @test fmt.completed == 0
        @test fmt.passed == 0
        @test fmt.failed == 0
        @test fmt.errored == 0
        @test fmt.skipped == 0
        @test fmt.color == false
        @test fmt.verbose == false
    end

    @testset "start! — sets total and renders header" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        start!(fmt, 10)
        @test fmt.total == 10
        output = String(take!(io))
        @test contains(output, "CofreeTest")
        @test contains(output, "╭")
        @test contains(output, "╮")
        @test contains(output, "╰")
        @test contains(output, "╯")
    end

    @testset "handle!(TestStarted) — tracks running workers" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        event = TestStarted("my_test", LineNumberNode(1, :f), 42, time())
        handle!(fmt, event)
        @test haskey(fmt.running, 42)
        @test fmt.running[42][1] == "my_test"
    end

    @testset "handle!(TestFinished) — Pass increments counters" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        handle!(fmt, tf_event(name="passing_test", outcome=Pass(true)))
        @test fmt.passed == 1
        @test fmt.completed == 1
        output = String(take!(io))
        @test contains(output, "✔")
        @test contains(output, "passing_test")
    end

    @testset "handle!(TestFinished) — Fail increments counters and renders box" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        fail = Fail(:expr, "expected_val", "got_val", LineNumberNode(10, Symbol("myfile.jl")))
        handle!(fmt, tf_event(name="failing_test", outcome=fail))
        @test fmt.failed == 1
        @test fmt.completed == 1
        output = String(take!(io))
        @test contains(output, "✘")
        @test contains(output, "failing_test")
        @test contains(output, "Failure")
        @test contains(output, "Expected")
        @test contains(output, "Got")
        @test contains(output, "myfile.jl")
    end

    @testset "handle!(TestFinished) — Error increments counters and renders error box" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        err = Error(ErrorException("something broke"), nothing)
        handle!(fmt, tf_event(name="error_test", outcome=err))
        @test fmt.errored == 1
        @test fmt.completed == 1
        output = String(take!(io))
        @test contains(output, "✘")
        @test contains(output, "error_test")
        @test contains(output, "Error")
        @test contains(output, "something broke")
    end

    @testset "handle!(TestFinished) — Skip increments counters and renders reason" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        skip = Skip("not implemented yet")
        handle!(fmt, tf_event(name="skip_test", outcome=skip))
        @test fmt.skipped == 1
        @test fmt.completed == 1
        output = String(take!(io))
        @test contains(output, "○")
        @test contains(output, "skip_test")
        @test contains(output, "not implemented yet")
    end

    @testset "finalize! — summary includes all non-zero counters" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        handle!(fmt, tf_event(outcome=Pass(true)))
        handle!(fmt, tf_event(outcome=Fail(:e, 1, 2, LineNumberNode(1, :f))))
        handle!(fmt, tf_event(outcome=Error(ErrorException("x"), nothing)))
        handle!(fmt, tf_event(outcome=Skip("r")))
        take!(io)  # discard rendering output
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "1 passed")
        @test contains(output, "1 failed")
        @test contains(output, "1 errored")
        @test contains(output, "1 skipped")
        @test contains(output, "total")
    end

    @testset "color=false — no ANSI escape codes" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        handle!(fmt, tf_event(outcome=Pass(true)))
        finalize!(fmt)
        output = String(take!(io))
        @test !contains(output, "\e[")  # no ANSI escape sequences
    end

    @testset "durations are tracked" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        handle!(fmt, tf_event(time_s=0.5))
        handle!(fmt, tf_event(time_s=1.0))
        @test length(fmt.durations) == 2
        @test fmt.durations[1] == 0.5
        @test fmt.durations[2] == 1.0
    end
end
