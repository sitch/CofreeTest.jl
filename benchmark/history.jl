# history.jl — Save and compare benchmark results over time

using JSON

const RESULTS_DIR = joinpath(@__DIR__, "results")

struct HistoryEntry
    timestamp::String
    scenarios::Dict{String, Dict{String, Any}}
end

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

function compare_with_baseline(rows::Vector{BenchRow})
    baseline = load_latest()
    baseline === nothing && return

    println()
    println("Comparison with previous run ($(baseline["timestamp"]))")
    w = 70
    println("=" ^ w)
    println(rpad("Scenario", 28), " | ",
            rpad("Previous", 12), " | ",
            rpad("Current", 12), " | ",
            "Change")
    println("-" ^ w)

    scenarios = get(baseline, "scenarios", Dict())
    for row in rows
        prev = get(scenarios, row.scenario, nothing)
        prev === nothing && continue
        prev_ns = prev["cofree_ns"]
        curr_ns = row.cofree_time_ns
        pct = (curr_ns - prev_ns) / prev_ns * 100
        marker = abs(pct) < 5 ? "" : (pct > 0 ? " REGRESSION" : " IMPROVEMENT")
        println(rpad(row.scenario, 28), " | ",
                rpad(format_time(prev_ns), 12), " | ",
                rpad(format_time(curr_ns), 12), " | ",
                "$(round(pct; digits=1))%$marker")
    end

    println("=" ^ w)
    println()
end
