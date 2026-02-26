# benchmarks.jl — PkgBenchmark / AirspeedVelocity compatibility layer
# Defines SUITE::BenchmarkGroup wrapping the same workloads as run.jl.
# Do NOT print results here — this file is driven by PkgBenchmark.

using BenchmarkTools
using CofreeTest

include(joinpath(@__DIR__, "generators.jl"))
include(joinpath(@__DIR__, "cofreetest_runner.jl"))
include(joinpath(@__DIR__, "stdlib_runner.jl"))

const SUITE = BenchmarkGroup()

# --- comparison ---
SUITE["comparison"] = BenchmarkGroup()
for (label, gen) in [
    ("flat_10",     () -> generate_flat_suite(10)),
    ("flat_100",    () -> generate_flat_suite(100)),
    ("flat_1000",   () -> generate_flat_suite(1000)),
    ("nested_5x3",  () -> generate_nested_suite(5, 3)),
    ("multi_10x50", () -> generate_multi_assertion_suite(10, 50)),
]
    tree = gen()
    SUITE["comparison"][label] = @benchmarkable run_cofreetest_null($tree)
end

# --- executors (skip process — too slow for CI) ---
SUITE["executors"] = BenchmarkGroup()
let tree = generate_flat_suite(100)
    SUITE["executors"]["inline"] = @benchmarkable run_cofreetest_null($tree)
    SUITE["executors"]["task"]   = @benchmarkable run_cofreetest_task($tree)
end

# --- scaling (skip 5000 — too slow for CI) ---
SUITE["scaling"] = BenchmarkGroup()
for n in [10, 50, 100, 500, 1000]
    tree = generate_flat_suite(n)
    SUITE["scaling"]["flat_$n"] = @benchmarkable run_cofreetest_null($tree)
end

# --- micro-benchmarks ---
SUITE["micro"] = BenchmarkGroup()
SUITE["micro"]["tree_construction_100"] = @benchmarkable bench_tree_construction(100)
SUITE["micro"]["event_emission_1000"]   = @benchmarkable bench_event_emission(1000)
SUITE["micro"]["module_creation_100"]   = @benchmarkable bench_module_creation(100)
SUITE["micro"]["iocapture_100"]         = @benchmarkable bench_iocapture(100)

# --- formatters ---
SUITE["formatters"] = BenchmarkGroup()
let tree = generate_flat_suite(100)
    for sym in [:dot, :json, :terminal]
        SUITE["formatters"][string(sym)] = @benchmarkable run_cofreetest_formatter($tree, $(QuoteNode(sym)))
    end
end
