#!/usr/bin/env julia
# benchmark/run.jl — Compare CofreeTest vs Test stdlib performance
#
# Usage:
#   julia --project=benchmark benchmark/run.jl              # full run
#   julia --project=benchmark benchmark/run.jl --quick       # fewer samples
#   julia --project=benchmark benchmark/run.jl --phase=scaling
#   julia --project=benchmark benchmark/run.jl --markdown
#
# Phases: comparison, executors, scaling, phases, formatters
# Flags:  --quick, --full (default), --markdown, --save, --phase=NAME

using Pkg
if !isfile(joinpath(@__DIR__, "Manifest.toml"))
    println("Installing benchmark dependencies...")
    Pkg.instantiate()
end

using BenchmarkTools
using BenchmarkTools: Trial, median, memory, allocs
using Test
using Dates
using CofreeTest

include(joinpath(@__DIR__, "generators.jl"))
include(joinpath(@__DIR__, "cofreetest_runner.jl"))
include(joinpath(@__DIR__, "stdlib_runner.jl"))
include(joinpath(@__DIR__, "table.jl"))
include(joinpath(@__DIR__, "history.jl"))

# --- CLI flags ---

const QUICK    = "--quick" in ARGS
const MARKDOWN = "--markdown" in ARGS
const SAVE     = "--save" in ARGS || !QUICK

function requested_phase()
    for arg in ARGS
        if startswith(arg, "--phase=")
            return Symbol(split(arg, "=")[2])
        end
    end
    nothing
end

const PHASE = requested_phase()

function should_run(phase::Symbol)
    PHASE === nothing || PHASE == phase
end

# --- BenchmarkTools config ---

if QUICK
    BenchmarkTools.DEFAULT_PARAMETERS.samples = 10
    BenchmarkTools.DEFAULT_PARAMETERS.seconds = 1
else
    BenchmarkTools.DEFAULT_PARAMETERS.samples = 30
    BenchmarkTools.DEFAULT_PARAMETERS.seconds = 5
end

# --- Warmup ---

println("Warming up...")
warmup_tree = generate_flat_suite(2)
run_cofreetest_null(warmup_tree)
run_cofreetest_formatter(warmup_tree, :dot)
stdlib_flat_suite(2)()
println("Warmup complete.\n")

# --- Phase 1: Framework comparison ---

rows = BenchRow[]

if should_run(:comparison)
    println("Phase 1: Framework comparison (CofreeTest vs Test stdlib)")
    println("=" ^ 60)

    scenarios = [
        (name = "Small flat (10 tests)",
         cofree = () -> generate_flat_suite(10),
         stdlib = () -> stdlib_flat_suite(10),
         n = 10),

        (name = "Medium flat (100 tests)",
         cofree = () -> generate_flat_suite(100),
         stdlib = () -> stdlib_flat_suite(100),
         n = 100),

        (name = "Large flat (1000 tests)",
         cofree = () -> generate_flat_suite(1000),
         stdlib = () -> stdlib_flat_suite(1000),
         n = 1000),

        (name = "Nested (5 deep, 3 wide)",
         cofree = () -> generate_nested_suite(5, 3),
         stdlib = () -> stdlib_nested_suite(5, 3),
         n = 3^5),

        (name = "Multi-assert (10x50)",
         cofree = () -> generate_multi_assertion_suite(10, 50),
         stdlib = () -> stdlib_multi_assertion(10, 50),
         n = 10),
    ]

    for s in scenarios
        print("  $(s.name) ...")
        cofree_tree = s.cofree()
        stdlib_fn = s.stdlib()
        cofree_trial = @benchmark run_cofreetest_null($cofree_tree)
        stdlib_trial = @benchmark run_stdlib($stdlib_fn)
        push!(rows, make_row(s.name, cofree_trial, stdlib_trial; n_tests=s.n))
        println(" done")
    end

    if MARKDOWN
        print_markdown_comparison(rows)
    else
        print_comparison_table(rows)
    end
end

# --- Phase 2: Executor comparison ---

if should_run(:executors)
    println("Phase 2: Executor comparison (100 flat tests)")
    println("=" ^ 60)

    exec_tree = generate_flat_suite(100)

    print("  InlineExecutor ...")
    inline_trial = @benchmark run_cofreetest_null($exec_tree)
    println(" done")

    print("  TaskExecutor ...")
    task_trial = @benchmark run_cofreetest_task($exec_tree)
    println(" done")

    # Process executor is slower — use fewer samples
    print("  ProcessExecutor ...")
    prev_samples = BenchmarkTools.DEFAULT_PARAMETERS.samples
    prev_seconds = BenchmarkTools.DEFAULT_PARAMETERS.seconds
    BenchmarkTools.DEFAULT_PARAMETERS.samples = max(3, prev_samples ÷ 3)
    BenchmarkTools.DEFAULT_PARAMETERS.seconds = max(1, prev_seconds ÷ 2)
    process_trial = @benchmark run_cofreetest_process($exec_tree)
    BenchmarkTools.DEFAULT_PARAMETERS.samples = prev_samples
    BenchmarkTools.DEFAULT_PARAMETERS.seconds = prev_seconds
    println(" done")

    print("  Test stdlib ...")
    stdlib_fn = stdlib_flat_suite(100)
    stdlib_trial = @benchmark run_stdlib($stdlib_fn)
    println(" done")

    executor_rows = Tuple{String, Float64, Int, Int}[
        ("InlineExecutor",  median(inline_trial).time,  Int(median(inline_trial).allocs),  Int(memory(inline_trial))),
        ("TaskExecutor",    median(task_trial).time,    Int(median(task_trial).allocs),    Int(memory(task_trial))),
        ("ProcessExecutor", median(process_trial).time, Int(median(process_trial).allocs), Int(memory(process_trial))),
        ("Test stdlib",     median(stdlib_trial).time,  Int(median(stdlib_trial).allocs),  Int(memory(stdlib_trial))),
    ]

    print_executor_table(executor_rows)
end

# --- Phase 3: Scaling analysis ---

scaling_points = ScalingPoint[]

if should_run(:scaling)
    println("Phase 3: Scaling analysis")
    println("=" ^ 60)

    for (n, cofree_tree, stdlib_fn) in generate_scaling_points()
        print("  N=$n ...")
        cofree_trial = @benchmark run_cofreetest_null($cofree_tree)
        stdlib_trial = @benchmark run_stdlib($stdlib_fn)
        push!(scaling_points, make_scaling_point(n, cofree_trial, stdlib_trial))
        println(" done")
    end

    if MARKDOWN
        print_markdown_scaling(scaling_points)
    else
        print_scaling_table(scaling_points)
    end
end

# --- Phase 4: Per-phase instrumentation ---

if should_run(:phases)
    println("Phase 4: Per-phase bottleneck analysis")
    println("=" ^ 60)

    phase_tree = generate_flat_suite(100)

    print("  Tree construction ...")
    construct_trial = @benchmark bench_tree_construction(100)
    println(" done")

    print("  Schedule only ...")
    sched_trial = @benchmark run_cofreetest_schedule_only($phase_tree)
    println(" done")

    print("  Full pipeline ...")
    full_trial = @benchmark run_cofreetest_null($phase_tree)
    println(" done")

    print("  Event emission (1000) ...")
    event_trial = @benchmark bench_event_emission(1000)
    println(" done")

    print("  Module creation (100) ...")
    mod_trial = @benchmark bench_module_creation(100)
    println(" done")

    print("  IOCapture (100) ...")
    iocap_trial = @benchmark bench_iocapture(100)
    println(" done")

    phase_rows = Tuple{String, Float64}[
        ("Tree construction (100)",   median(construct_trial).time),
        ("schedule_tree (100 tests)", median(sched_trial).time),
        ("Full pipeline (100 tests)", median(full_trial).time),
        ("Event emission (1000)",     median(event_trial).time),
        ("Module creation (100)",     median(mod_trial).time),
        ("IOCapture (100)",           median(iocap_trial).time),
    ]

    print_phase_table(phase_rows)

    # Derived estimates
    sched_t = median(sched_trial).time
    full_t = median(full_trial).time
    mod_t = median(mod_trial).time
    iocap_t = median(iocap_trial).time
    exec_t = max(0.0, full_t - sched_t)

    println("Derived estimates:")
    println("  Execution phase:     $(format_time(exec_t))")
    println("  Module+eval per test: $(format_time(mod_t / 100))")
    println("  IOCapture per test:  $(format_time(iocap_t / 100))")
    overhead = mod_t + iocap_t
    println("  Module+IOCapture:    $(format_time(overhead)) ($(round(overhead / full_t * 100; digits=1))% of full pipeline)")
    println()
end

# --- Phase 5: Formatter overhead ---

if should_run(:formatters)
    println("Phase 5: Formatter overhead (100 flat tests)")
    println("=" ^ 60)

    fmt_tree = generate_flat_suite(100)

    print("  NullFormatter ...")
    null_trial = @benchmark run_cofreetest_null($fmt_tree)
    println(" done")

    print("  DotFormatter ...")
    dot_trial = @benchmark run_cofreetest_formatter($fmt_tree, :dot)
    println(" done")

    print("  JSONFormatter ...")
    json_trial = @benchmark run_cofreetest_formatter($fmt_tree, :json)
    println(" done")

    print("  TerminalFormatter ...")
    terminal_trial = @benchmark run_cofreetest_formatter($fmt_tree, :terminal)
    println(" done")

    formatter_rows = Tuple{String, Float64, Int, Int}[
        ("NullFormatter",     median(null_trial).time,     Int(median(null_trial).allocs),     Int(memory(null_trial))),
        ("DotFormatter",      median(dot_trial).time,      Int(median(dot_trial).allocs),      Int(memory(dot_trial))),
        ("JSONFormatter",     median(json_trial).time,     Int(median(json_trial).allocs),     Int(memory(json_trial))),
        ("TerminalFormatter", median(terminal_trial).time, Int(median(terminal_trial).allocs), Int(memory(terminal_trial))),
    ]

    print_formatter_table(formatter_rows)
end

# --- Save & compare ---

if !isempty(rows) || !isempty(scaling_points)
    if !isempty(rows)
        compare_with_baseline(rows)
    end

    if SAVE && !isempty(rows)
        save_results(rows, scaling_points)
    end
end

println("Benchmark complete.")
