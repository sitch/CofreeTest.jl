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
include(joinpath(@__DIR__, "doctest_runner.jl"))

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

    # Complexity analysis: fit per-test time vs log10(N)
    if length(scaling_points) >= 4
        ns = [Float64(p.n) for p in scaling_points]
        ts = [p.cofree_per_test_ns for p in scaling_points]
        log_ns = log10.(ns)
        mean_log_n = mean(log_ns)
        mean_t = mean(ts)
        slope = sum((log_ns[i] - mean_log_n) * (ts[i] - mean_t) for i in eachindex(ns)) /
                sum((log_ns[i] - mean_log_n)^2 for i in eachindex(ns))
        pct_per_decade = slope / mean_t * 100
        println("Complexity: per-test cost slope = $(round(pct_per_decade; digits=1))%/decade of N")
        println("  (0% = perfect O(N), positive = super-linear, negative = amortization)")
        println()
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

# --- Phase 6: Doctest overhead analysis ---

if should_run(:doctest)
    println("Phase 6: Doctest overhead analysis")
    println("=" ^ 60)

    # Generate fixture modules at different scales
    doctest_mod_100 = generate_doctest_module(100)
    doctest_docstrings_100 = generate_doctest_docstrings(100)
    doctest_blocks_100 = generate_doctest_blocks(100)
    doctest_inputs_100 = [("$i * 2 + 0", "$(i * 2)") for i in 1:100]
    meta_parse_inputs = ["$i * 2 + 0" for i in 1:100]

    # Warmup
    bench_doctest_parsing(doctest_docstrings_100[1:2])
    bench_doctest_body_generation(doctest_blocks_100[1:2])
    bench_doctest_discovery(generate_doctest_module(2))

    # Micro-benchmarks
    print("  Docstring parsing (100) ...")
    parse_trial = @benchmark bench_doctest_parsing($doctest_docstrings_100)
    println(" done")

    print("  Body generation (100) ...")
    bodygen_trial = @benchmark bench_doctest_body_generation($doctest_blocks_100)
    println(" done")

    print("  Discovery (100 fns) ...")
    discovery_trial = @benchmark bench_doctest_discovery($doctest_mod_100)
    println(" done")

    print("  Meta.parse (100) ...")
    metaparse_trial = @benchmark bench_meta_parse($meta_parse_inputs)
    println(" done")

    print("  _doctest_eval! (100) ...")
    # Need event bus context for _doctest_eval!
    eval_bus = CofreeTest.EventBus()
    subscribe!(eval_bus, NullFormatter())
    eval_trial = @benchmark CofreeTest.with_bus($eval_bus) do
        bench_doctest_eval($doctest_inputs_100)
    end
    println(" done")

    print("  Full pipeline (100 fns) ...")
    full_doctest_trial = @benchmark bench_doctest_full_pipeline($doctest_mod_100)
    println(" done")

    # Print micro-benchmark table
    doctest_phase_rows = Tuple{String, Float64, Int, Int}[
        ("Docstring parsing (100)",  median(parse_trial).time,      Int(median(parse_trial).allocs),      Int(memory(parse_trial))),
        ("Body generation (100)",    median(bodygen_trial).time,    Int(median(bodygen_trial).allocs),    Int(memory(bodygen_trial))),
        ("Discovery (100 fns)",      median(discovery_trial).time,  Int(median(discovery_trial).allocs),  Int(memory(discovery_trial))),
        ("Meta.parse (100)",         median(metaparse_trial).time,  Int(median(metaparse_trial).allocs),  Int(memory(metaparse_trial))),
        ("_doctest_eval! (100)",     median(eval_trial).time,       Int(median(eval_trial).allocs),       Int(memory(eval_trial))),
        ("Full pipeline (100 fns)",  median(full_doctest_trial).time, Int(median(full_doctest_trial).allocs), Int(memory(full_doctest_trial))),
    ]

    print_doctest_table(doctest_phase_rows)

    # Derived estimates
    full_t = median(full_doctest_trial).time
    discovery_t = median(discovery_trial).time
    parse_t = median(parse_trial).time
    bodygen_t = median(bodygen_trial).time
    eval_t = median(eval_trial).time

    println("Derived estimates (as % of full pipeline):")
    println("  Discovery:       $(format_time(discovery_t)) ($(round(discovery_t / full_t * 100; digits=1))%)")
    println("  Parsing:         $(format_time(parse_t)) ($(round(parse_t / full_t * 100; digits=1))%)")
    println("  Body generation: $(format_time(bodygen_t)) ($(round(bodygen_t / full_t * 100; digits=1))%)")
    println("  Eval (runtime):  $(format_time(eval_t)) ($(round(eval_t / full_t * 100; digits=1))%)")
    println("  Per-doctest:     $(format_time(full_t / 100))")
    println()

    # Scaling analysis
    println("  Doctest scaling analysis:")
    doctest_scaling_ns = [10, 50, 100, 500]
    for n in doctest_scaling_ns
        mod = generate_doctest_module(n)
        print("    N=$n ...")
        trial = @benchmark bench_doctest_full_pipeline($mod)
        t = median(trial).time
        per_test = t / n
        println(" $(format_time(t)) total, $(format_time(per_test))/doctest")
    end
    println()

    # Optional: Documenter.jl reference (uses CofreeTest package itself, not fixture module)
    if has_documenter()
        print("  Documenter.jl reference (CofreeTest pkg) ...")
        try
            documenter_trial = @benchmark bench_documenter_doctest(CofreeTest)
            dt = median(documenter_trial).time
            println(" done")

            # Also benchmark CofreeTest's own doctest discovery for apples-to-apples
            cofree_self_trial = @benchmark bench_doctest_full_pipeline(CofreeTest)
            ct = median(cofree_self_trial).time
            println("  Documenter.jl: $(format_time(dt)) vs CofreeTest: $(format_time(ct)) (on CofreeTest's own docs)")
        catch e
            println(" skipped ($(sprint(showerror, e)))")
        end
        println()
    end
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
