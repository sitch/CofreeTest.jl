using Test
using CofreeTest
using CofreeTest: box, progress_bar, spinner_frame, bar_chart,
                  sparkline, dot_leader, format_duration, format_bytes,
                  color_for_duration

@testset "Terminal Components" begin
    @testset "box" begin
        result = box("Title", ["line 1", "line 2"]; width=40)
        @test startswith(result, " ╭")
        @test contains(result, "Title")
        @test contains(result, "line 1")
        @test contains(result, "╰")
    end

    @testset "progress_bar" begin
        result = progress_bar(5, 10; width=20)
        @test contains(result, "━")
        @test contains(result, "5/10")
    end

    @testset "spinner_frame" begin
        frames = [spinner_frame(i) for i in 0:7]
        @test length(unique(frames)) == 8  # 8 distinct braille frames
        @test spinner_frame(0) == spinner_frame(8)  # wraps around
    end

    @testset "bar_chart" begin
        result = bar_chart(7, 10; width=10)
        @test contains(result, "█")
        @test length(replace(result, r"[^█▏▎▍▌▋▊▉]" => "")) > 0
    end

    @testset "sparkline" begin
        result = sparkline([1.0, 3.0, 2.0, 5.0, 4.0])
        @test length(result) == 5
        @test all(c -> c in "▁▂▃▄▅▆▇█", result)
    end

    @testset "dot_leader" begin
        result = dot_leader("test name", "0.5s"; width=40)
        @test startswith(result, "test name")
        @test endswith(result, "0.5s")
        @test contains(result, "·")
    end

    @testset "format_duration" begin
        @test format_duration(0.001) == "1ms"
        @test format_duration(0.5) == "0.5s"
        @test format_duration(65.0) == "1m 05s"
    end

    @testset "format_bytes" begin
        @test format_bytes(512) == "512 B"
        @test format_bytes(1536) == "1.5 KB"
        @test format_bytes(2_500_000) == "2.4 MB"
        @test format_bytes(3_000_000_000) == "2.8 GB"
    end

    @testset "color_for_duration" begin
        @test color_for_duration(0.05) == :green
        @test color_for_duration(0.5) == :yellow
        @test color_for_duration(2.0) == :red
    end

    @testset "sparkline — empty vector" begin
        @test sparkline(Float64[]) == ""
    end

    @testset "sparkline — all same value" begin
        result = sparkline([5.0, 5.0, 5.0])
        @test length(result) == 3
        # When all values are same, uses middle char (index 4)
        @test all(c -> c == '▄', result)
    end

    @testset "progress_bar — zero total" begin
        result = progress_bar(0, 0; width=20)
        @test contains(result, "0/0")
        @test contains(result, "0%")
    end

    @testset "dot_leader — overflow (left + right > width)" begin
        result = dot_leader("very long left name here", "very long right"; width=20)
        # Should still have at least 1 dot
        @test contains(result, "·")
    end

    @testset "box — empty lines" begin
        result = box("Empty", String[]; width=40)
        @test startswith(result, " ╭")
        @test contains(result, "╰")
    end

    @testset "box — oversized line truncation" begin
        long_line = repeat("x", 200)
        result = box("Test", [long_line]; width=40)
        @test contains(result, "╭")
        @test contains(result, "╯")
    end

    @testset "format_bytes — boundary values" begin
        @test format_bytes(0) == "0 B"
        @test format_bytes(1024) == "1.0 KB"
    end

    @testset "format_duration — boundary values" begin
        @test format_duration(0.0) == "0ms"
        @test format_duration(60.0) == "1m 00s"
    end

    @testset "bar_chart — max_value zero" begin
        result = bar_chart(5, 0; width=10)
        @test length(result) == 10
        @test result == " " ^ 10
    end

    @testset "bar_chart — value exceeds max (clamp)" begin
        result = bar_chart(15, 10; width=10)
        @test contains(result, "█")
    end
end
