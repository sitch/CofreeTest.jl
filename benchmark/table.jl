# table.jl — Format benchmark results into comparison tables

using BenchmarkTools: Trial, median, memory, allocs
using Statistics: quantile, std, mean, median as stats_median

# --- Data types ---

struct BenchRow
    scenario::String
    cofree_time_ns::Float64
    stdlib_time_ns::Float64
    cofree_allocs::Int
    stdlib_allocs::Int
    cofree_memory::Int
    stdlib_memory::Int
    cofree_p25::Float64
    cofree_p75::Float64
    cofree_cv::Float64
    n_tests::Int
    cofree_ci_lo::Float64
    cofree_ci_hi::Float64
    outlier_count::Int
end

struct ScalingPoint
    n::Int
    cofree_ns::Float64
    stdlib_ns::Float64
    cofree_per_test_ns::Float64
    stdlib_per_test_ns::Float64
    cofree_allocs_per_test::Float64
    cofree_mem_per_test::Float64
end

# --- Statistical functions ---

function bootstrap_median_ci(times::Vector{Float64}; n::Int=1000, alpha::Float64=0.05)
    length(times) < 2 && return (times[1], times[1])
    k = length(times)
    medians = Vector{Float64}(undef, n)
    for i in 1:n
        resample = [times[rand(1:k)] for _ in 1:k]
        medians[i] = stats_median(resample)
    end
    sort!(medians)
    lo_idx = max(1, round(Int, alpha / 2 * n))
    hi_idx = min(n, round(Int, (1 - alpha / 2) * n))
    (medians[lo_idx], medians[hi_idx])
end

function tukey_outlier_count(times::Vector{Float64})
    length(times) < 4 && return 0
    q1 = quantile(times, 0.25)
    q3 = quantile(times, 0.75)
    iqr = q3 - q1
    lo = q1 - 1.5 * iqr
    hi = q3 + 1.5 * iqr
    count(t -> t < lo || t > hi, times)
end

# --- Formatting helpers ---

function ratio_str(a, b)
    b == 0 && return "N/A"
    r = a / b
    r >= 1.0 ? "$(round(r; digits=1))x" : "1/$(round(1/r; digits=1))x"
end

function format_time(ns::Float64)
    if ns < 1_000
        "$(round(ns; digits=0)) ns"
    elseif ns < 1_000_000
        "$(round(ns / 1_000; digits=1)) μs"
    elseif ns < 1_000_000_000
        "$(round(ns / 1_000_000; digits=1)) ms"
    else
        "$(round(ns / 1_000_000_000; digits=2)) s"
    end
end

function format_mem(bytes)
    bytes = Int(round(bytes))
    if bytes < 1024
        "$bytes B"
    elseif bytes < 1024^2
        "$(round(bytes / 1024; digits=1)) KiB"
    elseif bytes < 1024^3
        "$(round(bytes / 1024^2; digits=1)) MiB"
    else
        "$(round(bytes / 1024^3; digits=1)) GiB"
    end
end

function format_number(n)
    s = string(round(Int, n))
    # Add comma separators
    parts = String[]
    while length(s) > 3
        push!(parts, s[end-2:end])
        s = s[1:end-3]
    end
    push!(parts, s)
    join(reverse(parts), ",")
end

# --- Table constructors ---

function make_row(scenario::String, cofree_trial::Trial, stdlib_trial::Trial; n_tests::Int=0)
    ct = median(cofree_trial).time
    st = median(stdlib_trial).time
    ca = Int(median(cofree_trial).allocs)
    sa = Int(median(stdlib_trial).allocs)
    cm = Int(memory(cofree_trial))
    sm = Int(memory(stdlib_trial))
    times = cofree_trial.times
    p25 = length(times) > 1 ? quantile(times, 0.25) : ct
    p75 = length(times) > 1 ? quantile(times, 0.75) : ct
    m = mean(times)
    cv = m > 0 && length(times) > 1 ? std(times) / m * 100 : 0.0
    ci_lo, ci_hi = bootstrap_median_ci(times)
    outliers = tukey_outlier_count(times)
    BenchRow(scenario, ct, st, ca, sa, cm, sm, p25, p75, cv, n_tests, ci_lo, ci_hi, outliers)
end

function make_scaling_point(n::Int, cofree_trial::Trial, stdlib_trial::Trial)
    ct = median(cofree_trial).time
    st = median(stdlib_trial).time
    ca = Int(median(cofree_trial).allocs)
    cm = Int(memory(cofree_trial))
    ScalingPoint(n, ct, st, ct / n, st / n, ca / n, cm / n)
end

# --- Terminal output ---

function print_comparison_table(rows::Vector{BenchRow})
    println()
    w = 145
    println("=" ^ w)
    println(rpad("Scenario", 26), " | ",
            rpad("CofreeTest", 12), " | ",
            rpad("Test stdlib", 12), " | ",
            rpad("Ratio", 8), " | ",
            rpad("95% CI", 28), " | ",
            rpad("CV", 6), " | ",
            "Memory")
    println("-" ^ w)

    for row in rows
        ct = format_time(row.cofree_time_ns)
        st = format_time(row.stdlib_time_ns)
        ratio = ratio_str(row.cofree_time_ns, row.stdlib_time_ns)
        ci = row.cofree_ci_lo > 0 ?
            "[$(format_time(row.cofree_ci_lo)), $(format_time(row.cofree_ci_hi))]" :
            "N/A"
        cv = "$(round(row.cofree_cv; digits=1))%"
        mem = "$(format_mem(row.cofree_memory)) / $(format_mem(row.stdlib_memory))"
        outlier_flag = row.outlier_count > 0 ? " [$(row.outlier_count) outliers]" : ""
        println(rpad(row.scenario, 26), " | ",
                rpad(ct, 12), " | ",
                rpad(st, 12), " | ",
                rpad(ratio, 8), " | ",
                rpad(ci, 28), " | ",
                rpad(cv, 6), " | ",
                mem, outlier_flag)
    end

    println("=" ^ w)
    println()
end

function print_scaling_table(points::Vector{ScalingPoint})
    println()
    println("Scaling Analysis (flat suites, per-test cost)")
    w = 100
    println("=" ^ w)
    println(rpad("N tests", 10), " | ",
            rpad("CofreeTest", 12), " | ",
            rpad("per test", 12), " | ",
            rpad("Test stdlib", 12), " | ",
            rpad("per test", 12), " | ",
            rpad("Ratio", 8), " | ",
            "Allocs/test")
    println("-" ^ w)

    for p in points
        println(rpad(string(p.n), 10), " | ",
                rpad(format_time(p.cofree_ns), 12), " | ",
                rpad(format_time(p.cofree_per_test_ns), 12), " | ",
                rpad(format_time(p.stdlib_ns), 12), " | ",
                rpad(format_time(p.stdlib_per_test_ns), 12), " | ",
                rpad(ratio_str(p.cofree_per_test_ns, p.stdlib_per_test_ns), 8), " | ",
                format_number(p.cofree_allocs_per_test))
    end

    println("=" ^ w)
    println()
end

function print_executor_table(rows::Vector{Tuple{String, Float64, Int, Int}})
    println()
    println("Executor Comparison (100 flat tests)")
    w = 65
    println("=" ^ w)
    println(rpad("Executor", 22), " | ",
            rpad("Time", 14), " | ",
            rpad("Allocs", 10), " | ",
            "Memory")
    println("-" ^ w)

    for (name, time_ns, alloc, mem) in rows
        println(rpad(name, 22), " | ",
                rpad(format_time(time_ns), 14), " | ",
                rpad(format_number(alloc), 10), " | ",
                format_mem(mem))
    end

    println("=" ^ w)
    println()
end

function print_formatter_table(rows::Vector{Tuple{String, Float64, Int, Int}})
    println()
    println("Formatter Overhead (100 flat tests)")
    w = 65
    println("=" ^ w)
    println(rpad("Formatter", 22), " | ",
            rpad("Time", 14), " | ",
            rpad("Allocs", 10), " | ",
            "Memory")
    println("-" ^ w)

    for (name, time_ns, alloc, mem) in rows
        println(rpad(name, 22), " | ",
                rpad(format_time(time_ns), 14), " | ",
                rpad(format_number(alloc), 10), " | ",
                format_mem(mem))
    end

    println("=" ^ w)
    println()
end

function print_phase_table(phases::Vector{Tuple{String, Float64}})
    println()
    println("Per-Phase Bottleneck Analysis (100 iterations each)")
    w = 45
    println("=" ^ w)
    println(rpad("Phase", 28), " | ", "Time")
    println("-" ^ w)

    for (name, time_ns) in phases
        println(rpad(name, 28), " | ", format_time(time_ns))
    end

    println("=" ^ w)
    println()
end

# --- Markdown output ---

function print_markdown_comparison(rows::Vector{BenchRow})
    println()
    println("## CofreeTest vs Test stdlib")
    println()
    println("| Scenario | CofreeTest | Test stdlib | Ratio | 95% CI | CV | Memory (C/T) |")
    println("|----------|-----------|-------------|-------|--------|----|-------------|")
    for row in rows
        ct = format_time(row.cofree_time_ns)
        st = format_time(row.stdlib_time_ns)
        ratio = ratio_str(row.cofree_time_ns, row.stdlib_time_ns)
        ci = row.cofree_ci_lo > 0 ?
            "[$(format_time(row.cofree_ci_lo)), $(format_time(row.cofree_ci_hi))]" :
            "N/A"
        cv = "$(round(row.cofree_cv; digits=1))%"
        mem = "$(format_mem(row.cofree_memory)) / $(format_mem(row.stdlib_memory))"
        println("| $(row.scenario) | $ct | $st | $ratio | $ci | $cv | $mem |")
    end
    println()
end

function print_doctest_table(rows::Vector{Tuple{String, Float64, Int, Int}})
    println()
    println("Doctest Overhead Analysis (100 iterations each)")
    w = 75
    println("=" ^ w)
    println(rpad("Stage", 28), " | ",
            rpad("Time", 14), " | ",
            rpad("Allocs", 10), " | ",
            "Memory")
    println("-" ^ w)

    for (name, time_ns, alloc, mem) in rows
        println(rpad(name, 28), " | ",
                rpad(format_time(time_ns), 14), " | ",
                rpad(format_number(alloc), 10), " | ",
                format_mem(mem))
    end

    println("=" ^ w)
    println()
end

function print_markdown_scaling(points::Vector{ScalingPoint})
    println("## Scaling Analysis")
    println()
    println("| N | CofreeTest | per test | Test stdlib | per test | Ratio |")
    println("|---|-----------|----------|-------------|----------|-------|")
    for p in points
        println("| $(p.n) | $(format_time(p.cofree_ns)) | $(format_time(p.cofree_per_test_ns)) | $(format_time(p.stdlib_ns)) | $(format_time(p.stdlib_per_test_ns)) | $(ratio_str(p.cofree_per_test_ns, p.stdlib_per_test_ns)) |")
    end
    println()
end
