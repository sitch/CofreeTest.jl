using Test
using CofreeTest
using CofreeTest: JSONFormatter, handle!, finalize!

function make_test_finished(; name="test", outcome=Pass(true), time_s=0.1, bytes=1024, timestamp=1.0)
    metrics = Metrics(time_s, bytes, 0.0, 0.0, 0.0)
    TestFinished(name, outcome, metrics, CapturedIO("", ""), timestamp)
end

@testset "JSONFormatter" begin
    @testset "handle! — records Pass as 'pass'" begin
        io = IOBuffer()
        fmt = JSONFormatter(io)
        handle!(fmt, make_test_finished(outcome=Pass(true)))
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "\"pass\"")
    end

    @testset "handle! — records Fail as 'fail'" begin
        io = IOBuffer()
        fmt = JSONFormatter(io)
        handle!(fmt, make_test_finished(outcome=Fail(:expr, 1, 2, LineNumberNode(1, :f))))
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "\"fail\"")
    end

    @testset "handle! — records Error as 'error'" begin
        io = IOBuffer()
        fmt = JSONFormatter(io)
        handle!(fmt, make_test_finished(outcome=Error(ErrorException("x"), nothing)))
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "\"error\"")
    end

    @testset "handle! — records Skip as 'skip'" begin
        io = IOBuffer()
        fmt = JSONFormatter(io)
        handle!(fmt, make_test_finished(outcome=Skip("reason")))
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "\"skip\"")
    end

    @testset "finalize! — empty results produces []" begin
        io = IOBuffer()
        fmt = JSONFormatter(io)
        finalize!(fmt)
        output = String(take!(io))
        @test output == "[]"
    end

    @testset "finalize! — includes name, duration, bytes, timestamp" begin
        io = IOBuffer()
        fmt = JSONFormatter(io)
        handle!(fmt, make_test_finished(name="my_test", time_s=0.5, bytes=2048, timestamp=99.0))
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "\"name\":\"my_test\"")
        @test contains(output, "\"duration\":0.5")
        @test contains(output, "\"bytes\":2048")
        @test contains(output, "\"timestamp\":99.0")
    end

    @testset "finalize! — valid JSON structure" begin
        io = IOBuffer()
        fmt = JSONFormatter(io)
        handle!(fmt, make_test_finished(name="t1"))
        handle!(fmt, make_test_finished(name="t2"))
        finalize!(fmt)
        output = String(take!(io))
        @test startswith(output, "[")
        @test endswith(output, "]")
        @test contains(output, "},{")  # two objects separated by comma
    end

    @testset "finalize! — multiple results are comma-separated" begin
        io = IOBuffer()
        fmt = JSONFormatter(io)
        for i in 1:3
            handle!(fmt, make_test_finished(name="test_$i"))
        end
        finalize!(fmt)
        output = String(take!(io))
        # Count objects — should have 3
        @test count('{', output) == 3
        @test count('}', output) == 3
    end

    @testset "handle! — string with quotes is properly escaped" begin
        io = IOBuffer()
        fmt = JSONFormatter(io)
        handle!(fmt, make_test_finished(name="test with \"quotes\""))
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "test with \\\"quotes\\\"")
    end

    @testset "handle! — string with special characters escaped" begin
        io = IOBuffer()
        fmt = JSONFormatter(io)
        handle!(fmt, make_test_finished(name="line1\nline2\ttab\\back"))
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "line1\\nline2\\ttab\\\\back")
    end
end
