# CofreeTest.jl Design Document

> Cofree testing — parallel, observable, beautifully formatted.

**Date:** 2026-02-25
**Status:** Approved

## Overview

CofreeTest.jl is a categorical-grade test framework for Julia. Tests are modeled as cofree comonads — each node in a test tree carries an annotation (spec, schedule, result) and the ability to observe its full substructure. The framework provides parallel execution, real-time event streaming, and a rich terminal UI.

The parallel execution architecture (process-based worker pools, historical duration scheduling, RSS-based worker recycling) is adapted from [ParallelTestRunner.jl](https://github.com/JuliaTesting/ParallelTestRunner.jl) by @maleadt and contributors, originally built for CUDA.jl.

## Design Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| CT depth | Deep foundations | Tests as cofree comonads with extract/duplicate/extend |
| Base functor | Parameterized, Vector default | Maximum flexibility; rose tree covers 95% of cases |
| Observability | Event stream + metrics | Metrics are folds over the coalgebraic event stream |
| Parallelism | Pluggable executor | Ship ProcessExecutor (Malt), TaskExecutor, InlineExecutor |
| Formatting | Rich terminal UI + pluggable | Formatters are folds over the event stream |
| Test stdlib | Clean break + @test compat shim | Own macros/execution; shim intercepts @test assertions |

## 1. Core CT Abstractions

### Cofree type

```julia
struct Cofree{F, A}
    head::A              # extract — the annotation at this node
    tail::F              # the "rest", shaped by functor F
end

# Comonad interface
extract(c::Cofree) = c.head
duplicate(c::Cofree{F,A}) where {F,A} = Cofree(c, fmap(duplicate, c.tail))
extend(f, c::Cofree) = Cofree(f(c), fmap(w -> extend(f, w), c.tail))
```

### Functor interface

```julia
fmap(f, v::Vector) = map(f, v)           # Vector — rose tree (default)
fmap(f, t::Tuple) = map(f, t)            # fixed-arity branching
# Users extend fmap for custom functors
```

### Natural transformations

```julia
# Transform annotations while preserving structure
hoist(f, c::Cofree) = Cofree(f(c.head), fmap(child -> hoist(f, child), c.tail))
```

### Rose tree convenience

```julia
const TestTree{A} = Cofree{Vector{Cofree{Vector, A}}, A}

leaf(a) = Cofree(a, Cofree[])
suite(a, children::Vector) = Cofree(a, children)
```

### Key properties

- `extract(tree)` — get the annotation at this node
- `duplicate(tree)` — each node sees its entire subtree (context-aware operations)
- `extend(f, tree)` — apply f to each node-in-context (execution, metric computation)
- `hoist(f, tree)` — change annotation type (pipeline stage transitions)
- `fmap` over children — parallel map over subtrees

## 2. Pipeline Stages & Annotation Types

Each lifecycle stage is a `Cofree` tree with a different annotation. Stage transitions are natural transformations.

```
Cofree{F, TestSpec}  →  Cofree{F, Scheduled}  →  Cofree{F, TestResult}
      define              schedule                   execute
```

### TestSpec (definition time)

```julia
struct TestSpec
    name::String
    tags::Set{Symbol}              # :slow, :integration, :unit, etc.
    source::LineNumberNode         # file:line where defined
    body::Union{Expr, Nothing}     # Nothing for suites (containers)
    setup::Union{Expr, Nothing}    # per-node setup
    teardown::Union{Expr, Nothing} # per-node teardown
end
```

### Scheduled (planning time)

```julia
struct Scheduled
    spec::TestSpec
    executor::Symbol               # :process, :task, :inline
    worker_id::Union{Int, Nothing} # assigned worker (or any)
    priority::Float64              # from historical duration data
end
```

### Running (execution time — transient)

```julia
struct Running
    scheduled::Scheduled
    started_at::Float64
    events::Channel{TestEvent}     # side-channel for real-time observation
end
```

### TestResult (completion time)

```julia
struct TestResult
    spec::TestSpec
    outcome::Outcome
    duration::Float64
    metrics::Metrics
    events::Vector{TestEvent}      # captured event log
    output::CapturedIO             # stdout/stderr
end
```

### Outcome types (extensible, not closed)

```julia
abstract type Outcome end
struct Pass    <: Outcome; value::Any; end
struct Fail    <: Outcome; expr::Expr; expected::Any; got::Any; source::LineNumberNode; end
struct Error   <: Outcome; exception::Exception; backtrace::Any; end
struct Skip    <: Outcome; reason::String; end
struct Pending <: Outcome; reason::String; end
struct Timeout <: Outcome; limit::Float64; actual::Float64; end
```

### Supporting types

```julia
struct Metrics
    time_s::Float64
    bytes_allocated::Int64
    gc_time_s::Float64
    gc_pct::Float64
    rss_mb::Float64
end

struct CapturedIO
    stdout::String
    stderr::String
end
```

## 3. Event System

Events are the real-time observable primitive. Metrics and formatted output are folds over the event stream.

### Event types

```julia
abstract type TestEvent end

# Lifecycle events
struct SuiteStarted   <: TestEvent; name; source; timestamp; end
struct TestStarted    <: TestEvent; name; source; worker_id; timestamp; end
struct TestFinished   <: TestEvent; name; outcome; metrics; output; timestamp; end
struct SuiteFinished  <: TestEvent; name; timestamp; end

# Assertion-level events
struct AssertionPassed <: TestEvent; expr; value; source; timestamp; end
struct AssertionFailed <: TestEvent; expr; expected; got; source; timestamp; end

# Diagnostic events
struct LogEvent      <: TestEvent; level; message; timestamp; end
struct ProgressEvent <: TestEvent; completed; total; timestamp; end
```

### Event bus

```julia
struct EventBus
    channel::Channel{TestEvent}
    subscribers::Vector{Subscriber}
end

abstract type Subscriber end

subscribe!(bus::EventBus, sub::Subscriber)
emit!(bus::EventBus, event::TestEvent)
```

### Connection to pipeline

During `extend(run, scheduled_tree)`, each test execution emits events as a side-channel. The Cofree pipeline remains pure in structure (tree in, tree out) while the event bus provides real-time observation. Subscribers consume events concurrently — the terminal formatter updates live, the metrics accumulator tallies, the history recorder persists durations.

## 4. Executor Interface

### Abstract interface

```julia
abstract type AbstractExecutor end

function execute!(executor::AbstractExecutor, spec::TestSpec, bus::EventBus
)::Tuple{Outcome, Metrics, CapturedIO} end

# Optional lifecycle hooks
setup!(executor::AbstractExecutor) = nothing
teardown!(executor::AbstractExecutor) = nothing
recycle!(executor::AbstractExecutor) = nothing
```

### Built-in executors

```julia
struct ProcessExecutor <: AbstractExecutor  # Malt.jl — maximum isolation
    worker::Malt.Worker
    id::Int
    max_rss_mb::Float64
end

struct TaskExecutor <: AbstractExecutor     # @spawn — lightweight
    task::Union{Task, Nothing}
    id::Int
end

struct InlineExecutor <: AbstractExecutor end  # current process — debugging
```

### Executor pool

```julia
struct ExecutorPool{E <: AbstractExecutor}
    executors::Vector{E}
    available::Channel{E}          # work-stealing queue
    max_rss_mb::Float64
end

function default_njobs()
    min(Sys.CPU_THREADS, floor(Int, Sys.free_memory() / 2_000_000_000))
end
```

Workers are recycled when RSS exceeds configurable thresholds (adapted from PTR).

## 5. Test Definition DSL & Discovery

### Macros

```julia
@suite "name" [tags=[:tag1, :tag2]] begin ... end
@test "name" [tags=[:tag1]] begin ... end
@setup begin ... end
@teardown begin ... end

# Native assertions
@check expr
@check_throws ExType expr
@check_broken expr
@check_skip reason
```

### Discovery

Files in `test/` are auto-discovered if they match the naming convention:

- Starts with `test_` (e.g., `test_auth.jl`)
- Ends with `_test` (e.g., `auth_test.jl`)

Other files (helpers, fixtures, support) are ignored. Subdirectories become nested suites. Each discovered file is evaluated in its own module for isolation.

```julia
function is_test_file(filename::String)::Bool
    base = splitext(basename(filename))[1]
    startswith(base, "test_") || endswith(base, "_test")
end
```

### Filtering

```julia
struct TestFilter
    names::Vector{String}
    tags::Set{Symbol}
    exclude_tags::Set{Symbol}
end

# CLI: julia runtests.jl auth api/users --tags=unit --exclude=slow
```

### Setup/teardown semantics

- Suite setup runs once before any child
- Suite teardown runs once after all children complete
- Setup propagates down via `duplicate` (each node sees ancestor context)
- Teardown unwinds up (innermost first)

## 6. Formatter System & Rich Terminal UI

### Abstract interface

```julia
abstract type AbstractFormatter end
function handle!(formatter::AbstractFormatter, event::TestEvent) end
function finalize!(formatter::AbstractFormatter) end
```

### Built-in formatters

- **TerminalFormatter** — rich, live-updating terminal UI (default)
- **JSONFormatter** — structured output for tooling
- **JUnitFormatter** — CI integration
- **DotFormatter** — minimal

### Rich terminal UI

**During execution — live dashboard:**

```
 ╭─────────────────────────────────────────────────────────────────────╮
 │  ☕ CofreeTest                                          v0.1.0     │
 │  Running: test_auth.jl, test_api.jl, test_models.jl               │
 ╰─────────────────────────────────────────────────────────────────────╯

   Workers ⣿⣿⣿⣷  4/4 active          Elapsed 00:03.2          ETA 00:08.1

   ⠸ worker 1  auth / rate limiting / locks after 5        1.2s
   ⠼ worker 2  api / users / create                        0.4s
   ⠴ worker 3  api / posts / pagination                    0.6s
   ⠦ worker 4  models / user / validations                 0.1s

 ╭─ Results ───────────────────────────────────────────────────────────╮
 │                                                                     │
 │  ✔ auth / valid credentials ·················· 0.03s    1.2 MB  │
 │  ✔ auth / invalid credentials ················ 0.01s    0.8 MB  │
 │  ✔ api / users / list ······················· 0.24s    4.1 MB  │
 │  ✘ auth / rate limiting / locks after 5 ······ 0.12s    3.1 MB  │
 │                                                                     │
 │    ╭─ Failure ────────────────────────────────────────────────────╮ │
 │    │  test/test_auth.jl:42                                        │ │
 │    │                                                              │ │
 │    │    @check_throws RateLimitError authenticate(db, "a", "x")   │ │
 │    │                                                              │ │
 │    │    Expected │ RateLimitError                                  │ │
 │    │    Got      │ AuthError("too many attempts")                  │ │
 │    ╰──────────────────────────────────────────────────────────────╯ │
 │                                                                     │
 ╰─────────────────────────────────────────────────────────────────────╯

   ✔ 6   ✘ 1   ○ 1   ◌ 4        ━━━━━━━━━━━━━━━━━━━━━━━━━  8/12  67%
```

**After completion — summary with performance and trend:**

```
 ╭─────────────────────────────────────────────────────────────────────╮
 │  ☕ CofreeTest                                    Finished in 2.8s  │
 ╰─────────────────────────────────────────────────────────────────────╯

 ╭─ Suite Results ─────────────────────────────────────────────────────╮
 │  Suite                    Tests  Pass  Fail  Err  Skip     Time     │
 │ ───────────────────────────────────────────────────────────────────  │
 │  auth                        3   ██ 2    1    ·    ·      0.16s     │
 │   └─ rate limiting           1   ·· ·    1    ·    ·      0.12s     │
 │  api                         9   ██████████████ 9  ·  ·   2.10s     │
 │   ├─ users                   5   ██████████ 5  ·    ·    ·  1.23s   │
 │   └─ posts                   4   ████████ 4    ·    ·    ·  0.87s   │
 ╰─────────────────────────────────────────────────────────────────────╯

 ╭─ Performance ───────────────────────────────────────────────────────╮
 │  Slowest tests                          Alloc     GC    Time        │
 │  api / users / search                  18.2 MB   3.1%   1.23s  ▓▓▓ │
 │  api / posts / pagination               9.8 MB   1.2%   0.87s  ▓▓  │
 │                                                                     │
 │  Workers         Memory              Throughput                     │
 │  4 processes     Peak 482 MB         5.7 tests/s                    │
 │  0 recycled      Avg  312 MB         Speedup 2.4x vs serial        │
 ╰─────────────────────────────────────────────────────────────────────╯

 ╭─ Trend ─────────────────────────────────────────────────────────────╮
 │  Last 5 runs                                                        │
 │  3.4s  ┊  3.1s  ┊  2.9s  ┊  3.2s  ┊  2.8s                         │
 │  ▇▇▇▇▇ ┊ ▇▇▇▇  ┊ ▇▇▇   ┊ ▇▇▇▇  ┊ ▇▇▇  ← current                │
 ╰─────────────────────────────────────────────────────────────────────╯

   ✔ 14 passed   ✘ 1 failed   ○ 1 skipped                  2.78s total
```

### Visual design principles

- Box-drawing with rounded corners (`╭╮╰╯│─`)
- Braille spinners (`⠸⠼⠴⠦⠧⠇⠏⠋`) per-worker
- Dot leaders connecting test names to metrics
- Inline bar charts (`██████`) for pass ratios, (`▓▓▓`) for slowest tests
- Sparkline history (`▇▇▇`) for run duration trends
- Color temperature for timing: green (<0.1s) → yellow (<1s) → red (>1s)
- Structural diffs on failures with field-level highlighting
- Adaptive layout based on terminal width
- Non-TTY graceful degradation for CI

## 7. @test Compatibility Layer

A `CofreeTestSet <: Test.AbstractTestSet` shim intercepts `Test.record()` calls and converts them into CofreeTest events:

```julia
struct CofreeTestSet <: Test.AbstractTestSet
    bus::EventBus
    source::LineNumberNode
end

function Test.record(ts::CofreeTestSet, result::Test.Pass)
    emit!(ts.bus, AssertionPassed(...))
end

function Test.record(ts::CofreeTestSet, result::Test.Fail)
    emit!(ts.bus, AssertionFailed(...))
end

Test.finish(ts::CofreeTestSet) = nothing
```

Both `@check` (native) and `@test` (shimmed) emit to the same event bus. Native `@check` produces richer events; `@test` goes through the shim with slightly reduced fidelity.

### Migration path

1. **Drop-in** — CofreeTest runner, keep `@test` everywhere
2. **Gradual swap** — replace `@test` with `@check` where richer output matters
3. **Full native** — all `@check`, full structural diffs and event fidelity

## 8. Package Structure

```
CofreeTest.jl/
├── src/
│   ├── CofreeTest.jl
│   ├── Cofree.jl
│   ├── Types.jl
│   ├── Events.jl
│   ├── Discovery.jl
│   ├── Filter.jl
│   ├── Schedule.jl
│   ├── executors/
│   │   ├── Abstract.jl
│   │   ├── Process.jl
│   │   ├── Task.jl
│   │   ├── Inline.jl
│   │   └── Pool.jl
│   ├── Runner.jl
│   ├── formatters/
│   │   ├── Abstract.jl
│   │   ├── Terminal.jl
│   │   ├── TerminalComponents.jl
│   │   ├── Json.jl
│   │   ├── Junit.jl
│   │   ├── Dot.jl
│   │   └── Multi.jl
│   ├── Macros.jl
│   ├── Compat.jl
│   └── History.jl
├── test/
│   ├── runtests.jl
│   ├── test_cofree.jl
│   ├── test_discovery.jl
│   ├── test_executor.jl
│   ├── test_formatter.jl
│   └── test_integration.jl
├── docs/
│   └── plans/
├── Project.toml
├── LICENSE
└── README.md
```

### Dependencies

- **Malt** — process-based worker spawning
- **IOCapture** — stdout/stderr capture
- **Scratch** — persistent test duration history
- **Test** (stdlib) — for @test compatibility shim only

### Public API

```julia
# Running
runtests(mod, args; kwargs...)

# Defining
@suite, @test, @setup, @teardown
@check, @check_throws, @check_broken, @check_skip

# Cofree operations
extract, duplicate, extend, hoist, fmap

# Extensibility
AbstractExecutor, AbstractFormatter
execute!, handle!, finalize!
```
