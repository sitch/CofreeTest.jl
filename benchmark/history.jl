# history.jl — Save and compare benchmark results over time

using JSON

const RESULTS_DIR = joinpath(@__DIR__, "results")

struct HistoryEntry
    timestamp::String
    scenarios::Dict{String, Dict{String, Any}}
end

# --- Statistical comparison ---

function cohens_d(mu1::Float64, mu2::Float64, cv1::Float64, cv2::Float64)
    sigma1 = cv1 / 100.0 * mu1
    sigma2 = cv2 / 100.0 * mu2
    pooled_sd = sqrt((sigma1^2 + sigma2^2) / 2.0)
    pooled_sd < 1e-9 && return 0.0
    abs(mu1 - mu2) / pooled_sd
end

function regression_verdict(prev_ns::Float64, curr_ns::Float64,
                            prev_cv::Float64, curr_cv::Float64)
    pct = (curr_ns - prev_ns) / prev_ns * 100.0
    mean_cv = (prev_cv + curr_cv) / 2.0
    threshold = max(5.0, 2.0 * mean_cv)
    abs(pct) < threshold && return :invariant
    d = cohens_d(prev_ns, curr_ns, prev_cv, curr_cv)
    d < 0.5 && return :invariant
    pct > 0 ? :regression : :improvement
end

# --- Save / Load ---

function save_results(rows::Vector{BenchRow}, scaling::Vector{ScalingPoint})
    mkpath(RESULTS_DIR)
    ts = Dates.format(Dates.now(), "yyyy-mm-dd_HHMMSS")
    data = Dict(
        "timestamp" => ts,
        "julia_version" => string(VERSION),
        "scenarios" => Dict(
            row.scenario => Dict(
                "cofree_ns" => row.cofree_time_ns,
                "stdlib_ns" => row.stdlib_time_ns,
                "cofree_allocs" => row.cofree_allocs,
                "cofree_memory" => row.cofree_memory,
                "cofree_cv" => row.cofree_cv,
                "cofree_ci_lo" => row.cofree_ci_lo,
                "cofree_ci_hi" => row.cofree_ci_hi,
                "outlier_count" => row.outlier_count,
            ) for row in rows
        ),
        "scaling" => Dict(
            string(p.n) => Dict(
                "cofree_ns" => p.cofree_ns,
                "stdlib_ns" => p.stdlib_ns,
                "cofree_per_test_ns" => p.cofree_per_test_ns,
            ) for p in scaling
        ),
    )
    path = joinpath(RESULTS_DIR, "$ts.json")
    open(path, "w") do io
        JSON.print(io, data, 2)
    end
    println("Results saved to $path")
    path
end

function load_latest()
    isdir(RESULTS_DIR) || return nothing
    files = filter(f -> endswith(f, ".json"), readdir(RESULTS_DIR))
    isempty(files) && return nothing
    sort!(files)
    path = joinpath(RESULTS_DIR, files[end])
    JSON.parsefile(path)
end

# --- Comparison ---

function compare_with_baseline(rows::Vector{BenchRow})
    baseline = load_latest()
    baseline === nothing && return

    println()
    println("Comparison with previous run ($(baseline["timestamp"]))")
    w = 95
    println("=" ^ w)
    println(rpad("Scenario", 28), " | ",
            rpad("Previous", 12), " | ",
            rpad("Current", 12), " | ",
            rpad("Change", 10), " | ",
            "Verdict")
    println("-" ^ w)

    scenarios = get(baseline, "scenarios", Dict())
    for row in rows
        prev = get(scenarios, row.scenario, nothing)
        prev === nothing && continue
        prev_ns = Float64(prev["cofree_ns"])
        prev_cv = Float64(get(prev, "cofree_cv", 0.0))
        curr_ns = row.cofree_time_ns
        curr_cv = row.cofree_cv
        pct = (curr_ns - prev_ns) / prev_ns * 100
        verdict = regression_verdict(prev_ns, curr_ns, prev_cv, curr_cv)
        d = cohens_d(prev_ns, curr_ns, prev_cv, curr_cv)
        verdict_str = if verdict == :invariant
            ""
        elseif verdict == :regression
            "REGRESSION (d=$(round(d; digits=2)))"
        else
            "IMPROVEMENT (d=$(round(d; digits=2)))"
        end
        println(rpad(row.scenario, 28), " | ",
                rpad(format_time(prev_ns), 12), " | ",
                rpad(format_time(curr_ns), 12), " | ",
                rpad("$(round(pct; digits=1))%", 10), " | ",
                verdict_str)
    end

    println("=" ^ w)
    println()
end
