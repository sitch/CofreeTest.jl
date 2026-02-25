# CofreeTest.jl Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a categorical-grade test framework for Julia based on cofree comonads with parallel execution, real-time event streaming, and a rich terminal UI.

**Architecture:** Tests are `Cofree{F, A}` trees that flow through a pipeline of natural transformations: `TestSpec → Scheduled → TestResult`. An event bus provides real-time observation as a side-channel of comonadic `extend`. Pluggable executors handle parallelism; pluggable formatters handle output.

**Tech Stack:** Julia 1.10+, Malt.jl (process workers), IOCapture.jl (stdio capture), Scratch.jl (persistent history)

**Credit:** Parallel execution architecture adapted from [ParallelTestRunner.jl](https://github.com/JuliaTesting/ParallelTestRunner.jl) by @maleadt.

**Conventions:**
- Snake_case directory names, TitleCase `.jl` file names
- Test files: `test_*.jl` or `*_test.jl`
- Never add "Co-Authored-By: Claude" to commits

---

## Task 1: Project Skeleton

**Files:**
- Create: `Project.toml`
- Create: `src/CofreeTest.jl`
- Modify: `test/runtests.jl` (create)

**Step 1: Create Project.toml**

```toml
name = "CofreeTest"
uuid = "GENERATE-UUID"
authors = ["Sitch"]
version = "0.1.0"

[deps]
Malt = "d8e834d1-a621-5a5c-8a8a-4a2e66aaa7e4"
IOCapture = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
Scratch = "6c6a2e73-6563-6170-7368-637461726353"

[compat]
julia = "1.10"
Malt = "1.4"
IOCapture = "0.2"
Scratch = "1"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```

Generate a real UUID with: `using UUIDs; uuid4()`

**Step 2: Create minimal module root**

```julia
# src/CofreeTest.jl
"""
    CofreeTest

Cofree testing — parallel, observable, beautifully formatted.

A categorical-grade test framework for Julia. Tests are modeled as cofree
comonads with parallel execution, real-time event streaming, and a rich
terminal UI.

The parallel execution architecture (process-based worker pools, historical
duration scheduling, RSS-based worker recycling) is adapted from
[ParallelTestRunner.jl](https://github.com/JuliaTesting/ParallelTestRunner.jl)
by @maleadt and contributors, originally built for CUDA.jl.
"""
module CofreeTest

end # module
```

**Step 3: Create test entry point**

```julia
# test/runtests.jl
using Test

@testset "CofreeTest.jl" begin
    include("test_cofree.jl")
end
```

**Step 4: Create placeholder test file**

```julia
# test/test_cofree.jl
using Test
using CofreeTest

@testset "Cofree" begin
    @test true  # placeholder — replaced in Task 2
end
```

**Step 5: Install deps and verify**

Run: `cd /home/sitch/sites/sitch.ai/CofreeTest.jl && julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add Project.toml src/CofreeTest.jl test/runtests.jl test/test_cofree.jl
git commit -m "Bootstrap project skeleton with deps and test harness"
```

---

## Task 2: Cofree Type & Comonad Laws

The foundation. Everything else builds on this.

**Files:**
- Create: `src/Cofree.jl`
- Modify: `src/CofreeTest.jl` (add include + exports)
- Modify: `test/test_cofree.jl` (real tests)

**Step 1: Write the failing tests**

```julia
# test/test_cofree.jl
using Test
using CofreeTest
using CofreeTest: Cofree, extract, duplicate, extend, fmap, hoist, leaf, suite

@testset "Cofree" begin
    @testset "construction and extract" begin
        c = Cofree(1, Cofree{Vector{Cofree{Vector{Nothing}, Int}}, Int}[])
        @test extract(c) == 1
        @test c.tail == []

        c2 = Cofree("hello", [Cofree("world", Cofree{Vector{Cofree{Vector{Nothing}, String}}, String}[])])
        @test extract(c2) == "hello"
        @test length(c2.tail) == 1
        @test extract(c2.tail[1]) == "world"
    end

    @testset "leaf and suite constructors" begin
        l = leaf(42)
        @test extract(l) == 42
        @test isempty(l.tail)

        s = suite(0, [leaf(1), leaf(2), leaf(3)])
        @test extract(s) == 0
        @test length(s.tail) == 3
        @test extract(s.tail[2]) == 2
    end

    @testset "fmap" begin
        children = [leaf(1), leaf(2), leaf(3)]
        result = fmap(c -> Cofree(extract(c) * 10, c.tail), children)
        @test extract(result[1]) == 10
        @test extract(result[2]) == 20
        @test extract(result[3]) == 30
    end

    @testset "hoist" begin
        tree = suite("root", [leaf("a"), suite("mid", [leaf("b")])])
        upper = hoist(uppercase, tree)
        @test extract(upper) == "ROOT"
        @test extract(upper.tail[1]) == "A"
        @test extract(upper.tail[2]) == "MID"
        @test extract(upper.tail[2].tail[1]) == "B"
    end

    @testset "duplicate" begin
        tree = suite(1, [leaf(2), leaf(3)])
        d = duplicate(tree)
        # extract(duplicate(x)) == x  (comonad law 1)
        @test extract(d) === tree
        # each child is the original subtree
        @test extract(d.tail[1]) === tree.tail[1]
        @test extract(d.tail[2]) === tree.tail[2]
    end

    @testset "extend" begin
        tree = suite(1, [leaf(2), leaf(3)])
        # extend extract == id  (comonad law 2)
        result = extend(extract, tree)
        @test extract(result) == extract(tree)
        @test extract(result.tail[1]) == extract(tree.tail[1])
        @test extract(result.tail[2]) == extract(tree.tail[2])
    end

    @testset "comonad law: extract ∘ duplicate == id" begin
        tree = suite("a", [leaf("b"), suite("c", [leaf("d")])])
        @test extract(duplicate(tree)) === tree
    end

    @testset "comonad law: fmap extract ∘ duplicate == id" begin
        tree = suite(1, [leaf(2), leaf(3)])
        d = duplicate(tree)
        unwrapped = Cofree(extract(extract(d)), fmap(c -> Cofree(extract(extract(c)), extract(c).tail), d.tail))
        @test extract(unwrapped) == extract(tree)
        @test extract(unwrapped.tail[1]) == extract(tree.tail[1])
    end

    @testset "extend composes" begin
        tree = suite(1, [leaf(2), leaf(3)])
        f = c -> extract(c) + 1
        g = c -> extract(c) * 2
        # extend f ∘ extend g == extend (f ∘ extend g)
        left = extend(f, extend(g, tree))
        right = extend(c -> f(extend(g, c)), tree)
        @test extract(left) == extract(right)
        @test extract(left.tail[1]) == extract(right.tail[1])
    end
end
```

**Step 2: Run tests to verify they fail**

Run: `julia --project -e 'include("test/test_cofree.jl")'`
Expected: FAIL — `Cofree` not defined.

**Step 3: Implement Cofree.jl**

```julia
# src/Cofree.jl

"""
    Cofree{F, A}

The cofree comonad over functor `F` with annotation type `A`.

Each node carries a `head::A` (the annotation) and a `tail::F` (children shaped by functor F).
For rose trees, `F = Vector{Cofree{Vector, A}}`.

# Comonad operations
- `extract(c)` — get the annotation at this node
- `duplicate(c)` — each node sees its full subtree
- `extend(f, c)` — apply f to each node-in-context

# Natural transformations
- `hoist(f, c)` — transform annotations preserving tree shape
- `fmap(f, children)` — map over child nodes
"""
struct Cofree{F, A}
    head::A
    tail::F
end

"""
    extract(c::Cofree) -> A

Get the annotation at this node. The counit of the comonad.
"""
extract(c::Cofree) = c.head

"""
    fmap(f, v::Vector) -> Vector

Map `f` over a Vector of children. This is the functor instance for Vector (rose trees).
"""
fmap(f, v::Vector) = map(f, v)

"""
    fmap(f, t::Tuple) -> Tuple

Map `f` over a Tuple of children. Functor instance for fixed-arity branching.
"""
fmap(f, t::Tuple) = map(f, t)

"""
    duplicate(c::Cofree) -> Cofree{F, Cofree{F, A}}

Each node sees its entire subtree. The comultiplication of the comonad.
"""
duplicate(c::Cofree) = Cofree(c, fmap(duplicate, c.tail))

"""
    extend(f, c::Cofree) -> Cofree

Apply `f` to each node-in-context. The coKleisli extension.
`f` receives a `Cofree` (the node plus its entire subtree) and returns a new annotation.
"""
extend(f, c::Cofree) = Cofree(f(c), fmap(w -> extend(f, w), c.tail))

"""
    hoist(f, c::Cofree) -> Cofree

Natural transformation: transform annotations while preserving tree structure.
`f` is applied to each `head` value.
"""
hoist(f, c::Cofree) = Cofree(f(c.head), fmap(child -> hoist(f, child), c.tail))

"""
    leaf(a) -> Cofree

Create a leaf node (no children) with annotation `a`.
"""
leaf(a) = Cofree(a, Cofree[])

"""
    suite(a, children::Vector) -> Cofree

Create a suite node with annotation `a` and child nodes.
"""
suite(a, children::Vector) = Cofree(a, children)
```

**Step 4: Wire into module**

```julia
# src/CofreeTest.jl — replace contents
"""
    CofreeTest

Cofree testing — parallel, observable, beautifully formatted.

The parallel execution architecture is adapted from
[ParallelTestRunner.jl](https://github.com/JuliaTesting/ParallelTestRunner.jl)
by @maleadt and contributors.
"""
module CofreeTest

include("Cofree.jl")

export Cofree, extract, duplicate, extend, fmap, hoist, leaf, suite

end # module
```

**Step 5: Run tests to verify they pass**

Run: `julia --project -e 'include("test/test_cofree.jl")'`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add src/Cofree.jl src/CofreeTest.jl test/test_cofree.jl
git commit -m "Implement Cofree type with comonad laws"
```

---

## Task 3: Pipeline Types

All annotation types, outcomes, and supporting structs.

**Files:**
- Create: `src/Types.jl`
- Create: `test/test_types.jl`
- Modify: `src/CofreeTest.jl` (include + exports)
- Modify: `test/runtests.jl` (include test file)

**Step 1: Write failing tests**

```julia
# test/test_types.jl
using Test
using CofreeTest

@testset "Types" begin
    @testset "Outcome types" begin
        p = Pass(42)
        @test p.value == 42

        f = Fail(:(@test 1 == 2), 1, 2, LineNumberNode(1, :file))
        @test f.expected == 1
        @test f.got == 2

        e = Error(ErrorException("boom"), nothing)
        @test e.exception == ErrorException("boom")

        s = Skip("not implemented")
        @test s.reason == "not implemented"

        pd = Pending("todo")
        @test pd.reason == "todo"

        t = Timeout(5.0, 10.0)
        @test t.limit == 5.0
        @test t.actual == 10.0
    end

    @testset "Metrics" begin
        m = Metrics(1.5, 1024, 0.1, 6.7, 128.0)
        @test m.time_s == 1.5
        @test m.bytes_allocated == 1024
        @test m.gc_time_s == 0.1
        @test m.gc_pct == 6.7
        @test m.rss_mb == 128.0
    end

    @testset "CapturedIO" begin
        io = CapturedIO("hello", "warn")
        @test io.stdout == "hello"
        @test io.stderr == "warn"
    end

    @testset "TestSpec" begin
        spec = TestSpec(
            name="my test",
            tags=Set([:unit]),
            source=LineNumberNode(10, Symbol("test.jl")),
            body=:(@check true),
            setup=nothing,
            teardown=nothing,
        )
        @test spec.name == "my test"
        @test :unit in spec.tags
        @test spec.body == :(@check true)
    end

    @testset "Scheduled" begin
        spec = TestSpec("t", Set{Symbol}(), LineNumberNode(1, :f), nothing, nothing, nothing)
        sched = Scheduled(spec, :inline, nothing, 0.0)
        @test sched.spec === spec
        @test sched.executor == :inline
    end

    @testset "TestResult" begin
        spec = TestSpec("t", Set{Symbol}(), LineNumberNode(1, :f), nothing, nothing, nothing)
        metrics = Metrics(0.1, 512, 0.0, 0.0, 64.0)
        result = TestResult(spec, Pass(true), 0.1, metrics, TestEvent[], CapturedIO("", ""))
        @test result.outcome isa Pass
        @test result.duration == 0.1
    end

    @testset "Cofree integration" begin
        spec1 = TestSpec("suite", Set{Symbol}(), LineNumberNode(1, :f), nothing, nothing, nothing)
        spec2 = TestSpec("test1", Set([:unit]), LineNumberNode(2, :f), :(1+1), nothing, nothing)
        tree = suite(spec1, [leaf(spec2)])
        @test extract(tree).name == "suite"
        @test extract(tree.tail[1]).name == "test1"
    end
end
```

**Step 2: Run tests to verify they fail**

Run: `julia --project -e 'include("test/test_types.jl")'`
Expected: FAIL — types not defined.

**Step 3: Implement Types.jl**

```julia
# src/Types.jl

# --- Outcomes ---

"""Extensible outcome types for test results."""
abstract type Outcome end

struct Pass <: Outcome
    value::Any
end

struct Fail <: Outcome
    expr::Any
    expected::Any
    got::Any
    source::LineNumberNode
end

struct Error <: Outcome
    exception::Exception
    backtrace::Any
end

struct Skip <: Outcome
    reason::String
end

struct Pending <: Outcome
    reason::String
end

struct Timeout <: Outcome
    limit::Float64
    actual::Float64
end

# --- Supporting types ---

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

# --- Forward declaration for events (needed by TestResult) ---

abstract type TestEvent end

# --- Pipeline stage annotations ---

"""Test definition — the unannotated spec before execution."""
@kwdef struct TestSpec
    name::String
    tags::Set{Symbol} = Set{Symbol}()
    source::LineNumberNode = LineNumberNode(0, :unknown)
    body::Union{Expr, Nothing} = nothing
    setup::Union{Expr, Nothing} = nothing
    teardown::Union{Expr, Nothing} = nothing
end

"""Scheduled test — spec plus execution plan."""
struct Scheduled
    spec::TestSpec
    executor::Symbol
    worker_id::Union{Int, Nothing}
    priority::Float64
end

"""Test result — spec plus outcome and metrics."""
struct TestResult
    spec::TestSpec
    outcome::Outcome
    duration::Float64
    metrics::Metrics
    events::Vector{TestEvent}
    output::CapturedIO
end
```

**Step 4: Wire into module**

Add to `src/CofreeTest.jl` after the Cofree include:

```julia
include("Types.jl")

export Outcome, Pass, Fail, Error, Skip, Pending, Timeout
export Metrics, CapturedIO, TestEvent
export TestSpec, Scheduled, TestResult
```

**Step 5: Update test/runtests.jl**

```julia
using Test

@testset "CofreeTest.jl" begin
    include("test_cofree.jl")
    include("test_types.jl")
end
```

**Step 6: Run tests to verify they pass**

Run: `julia --project -e 'using Pkg; Pkg.test()'`
Expected: All tests pass.

**Step 7: Commit**

```bash
git add src/Types.jl src/CofreeTest.jl test/test_types.jl test/runtests.jl
git commit -m "Add pipeline annotation types and outcomes"
```

---

## Task 4: Event System

Event types and the EventBus for real-time observation.

**Files:**
- Create: `src/Events.jl`
- Create: `test/test_events.jl`
- Modify: `src/CofreeTest.jl` (include + exports)
- Modify: `test/runtests.jl`

**Step 1: Write failing tests**

```julia
# test/test_events.jl
using Test
using CofreeTest
using CofreeTest: EventBus, emit!, subscribe!, CollectorSubscriber

@testset "Events" begin
    @testset "event construction" begin
        e = SuiteStarted("auth", LineNumberNode(1, :f), 1.0)
        @test e.name == "auth"
        @test e.timestamp == 1.0

        e2 = TestStarted("login", LineNumberNode(2, :f), 1, 2.0)
        @test e2.worker_id == 1

        e3 = TestFinished("login", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 3.0)
        @test e3.outcome isa Pass

        e4 = AssertionPassed(:(@check true), true, LineNumberNode(1, :f), 1.0)
        @test e4.value == true

        e5 = AssertionFailed(:(@check 1==2), 1, 2, LineNumberNode(1, :f), 1.0)
        @test e5.expected == 1
    end

    @testset "EventBus emit and subscribe" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        emit!(bus, SuiteStarted("test", LineNumberNode(1, :f), 1.0))
        emit!(bus, TestStarted("t1", LineNumberNode(2, :f), 1, 2.0))
        emit!(bus, TestFinished("t1", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 3.0))

        @test length(collector.events) == 3
        @test collector.events[1] isa SuiteStarted
        @test collector.events[2] isa TestStarted
        @test collector.events[3] isa TestFinished
    end

    @testset "EventBus multiple subscribers" begin
        bus = EventBus()
        c1 = CollectorSubscriber()
        c2 = CollectorSubscriber()
        subscribe!(bus, c1)
        subscribe!(bus, c2)

        emit!(bus, SuiteStarted("s", LineNumberNode(1, :f), 1.0))

        @test length(c1.events) == 1
        @test length(c2.events) == 1
    end
end
```

**Step 2: Run tests to verify they fail**

Run: `julia --project -e 'include("test/test_events.jl")'`
Expected: FAIL — event types not defined.

**Step 3: Implement Events.jl**

```julia
# src/Events.jl

# --- Lifecycle events ---

struct SuiteStarted <: TestEvent
    name::String
    source::LineNumberNode
    timestamp::Float64
end

struct TestStarted <: TestEvent
    name::String
    source::LineNumberNode
    worker_id::Int
    timestamp::Float64
end

struct TestFinished <: TestEvent
    name::String
    outcome::Outcome
    metrics::Metrics
    output::CapturedIO
    timestamp::Float64
end

struct SuiteFinished <: TestEvent
    name::String
    timestamp::Float64
end

# --- Assertion-level events ---

struct AssertionPassed <: TestEvent
    expr::Any
    value::Any
    source::LineNumberNode
    timestamp::Float64
end

struct AssertionFailed <: TestEvent
    expr::Any
    expected::Any
    got::Any
    source::LineNumberNode
    timestamp::Float64
end

# --- Diagnostic events ---

struct LogEvent <: TestEvent
    level::Symbol
    message::String
    timestamp::Float64
end

struct ProgressEvent <: TestEvent
    completed::Int
    total::Int
    timestamp::Float64
end

# --- Event bus ---

abstract type Subscriber end

"""Collect all events into a vector. Useful for testing and post-hoc analysis."""
mutable struct CollectorSubscriber <: Subscriber
    events::Vector{TestEvent}
    CollectorSubscriber() = new(TestEvent[])
end

function handle!(sub::CollectorSubscriber, event::TestEvent)
    push!(sub.events, event)
end

"""
    EventBus

Channel-based event bus. Subscribers receive events synchronously via `handle!`.
Thread-safe via a lock on emit.
"""
mutable struct EventBus
    subscribers::Vector{Subscriber}
    lock::ReentrantLock
    EventBus() = new(Subscriber[], ReentrantLock())
end

function subscribe!(bus::EventBus, sub::Subscriber)
    lock(bus.lock) do
        push!(bus.subscribers, sub)
    end
end

function emit!(bus::EventBus, event::TestEvent)
    lock(bus.lock) do
        for sub in bus.subscribers
            handle!(sub, event)
        end
    end
end
```

**Step 4: Wire into module**

Add to `src/CofreeTest.jl` after Types include:

```julia
include("Events.jl")

export SuiteStarted, TestStarted, TestFinished, SuiteFinished
export AssertionPassed, AssertionFailed, LogEvent, ProgressEvent
```

**Step 5: Update test/runtests.jl**

Add `include("test_events.jl")` to the testset.

**Step 6: Run tests**

Run: `julia --project -e 'using Pkg; Pkg.test()'`
Expected: All tests pass.

**Step 7: Commit**

```bash
git add src/Events.jl src/CofreeTest.jl test/test_events.jl test/runtests.jl
git commit -m "Implement event system with EventBus and subscribers"
```

---

## Task 5: Test Discovery

File-based test discovery with `test_`/`_test` convention.

**Files:**
- Create: `src/Discovery.jl`
- Create: `test/test_discovery.jl`
- Create: `test/fixtures/discovery/` (test fixture directory)
- Modify: `src/CofreeTest.jl`
- Modify: `test/runtests.jl`

**Step 1: Create fixture files for discovery tests**

```bash
mkdir -p test/fixtures/discovery/api
```

```julia
# test/fixtures/discovery/test_auth.jl
# fixture — intentionally minimal
@suite "auth" begin end

# test/fixtures/discovery/models_test.jl
@suite "models" begin end

# test/fixtures/discovery/helpers.jl
# NOT a test file — should be ignored

# test/fixtures/discovery/api/test_users.jl
@suite "users" begin end

# test/fixtures/discovery/api/posts_test.jl
@suite "posts" begin end
```

**Step 2: Write failing tests**

```julia
# test/test_discovery.jl
using Test
using CofreeTest
using CofreeTest: is_test_file, discover_test_files

@testset "Discovery" begin
    @testset "is_test_file" begin
        @test is_test_file("test_auth.jl") == true
        @test is_test_file("auth_test.jl") == true
        @test is_test_file("helpers.jl") == false
        @test is_test_file("runtests.jl") == false
        @test is_test_file("test_auth.jl") == true
        @test is_test_file("my_test.jl") == true
        @test is_test_file("testing.jl") == false
        @test is_test_file("test_.jl") == true
    end

    @testset "discover_test_files" begin
        fixture_dir = joinpath(@__DIR__, "fixtures", "discovery")
        files = discover_test_files(fixture_dir)

        basenames = Set(basename.(files))
        @test "test_auth.jl" in basenames
        @test "models_test.jl" in basenames
        @test "test_users.jl" in basenames
        @test "posts_test.jl" in basenames
        @test !("helpers.jl" in basenames)
        @test length(files) == 4
    end

    @testset "discover_test_files returns sorted paths" begin
        fixture_dir = joinpath(@__DIR__, "fixtures", "discovery")
        files = discover_test_files(fixture_dir)
        @test issorted(files)
    end
end
```

**Step 3: Run tests to verify they fail**

Run: `julia --project -e 'include("test/test_discovery.jl")'`
Expected: FAIL — functions not defined.

**Step 4: Implement Discovery.jl**

```julia
# src/Discovery.jl

"""
    is_test_file(filename::String) -> Bool

Returns true if the filename matches test file conventions:
starts with `test_` or ends with `_test` (before .jl extension).
Excludes `runtests.jl`.
"""
function is_test_file(filename::String)::Bool
    filename == "runtests.jl" && return false
    endswith(filename, ".jl") || return false
    base = first(splitext(filename))
    startswith(base, "test_") || endswith(base, "_test")
end

"""
    discover_test_files(dir::String) -> Vector{String}

Recursively find all test files in `dir` matching the `test_`/`_test` convention.
Returns sorted absolute paths.
"""
function discover_test_files(dir::String)::Vector{String}
    files = String[]
    for (root, _, filenames) in walkdir(dir)
        for f in filenames
            if is_test_file(f)
                push!(files, joinpath(root, f))
            end
        end
    end
    sort!(files)
end
```

**Step 5: Wire into module**

Add to `src/CofreeTest.jl`:

```julia
include("Discovery.jl")
```

(Keep `is_test_file` and `discover_test_files` unexported — internal API for now.)

**Step 6: Update test/runtests.jl**

Add `include("test_discovery.jl")` to the testset.

**Step 7: Run tests**

Run: `julia --project -e 'using Pkg; Pkg.test()'`
Expected: All tests pass.

**Step 8: Commit**

```bash
git add src/Discovery.jl src/CofreeTest.jl test/test_discovery.jl test/fixtures/
git commit -m "Implement test file discovery with test_/\_test convention"
```

---

## Task 6: Test Filtering

Filter test trees by name and tags.

**Files:**
- Create: `src/Filter.jl`
- Create: `test/test_filter.jl`
- Modify: `src/CofreeTest.jl`
- Modify: `test/runtests.jl`

**Step 1: Write failing tests**

```julia
# test/test_filter.jl
using Test
using CofreeTest
using CofreeTest: TestFilter, filter_tree, parse_test_args

@testset "Filter" begin
    # Build a test tree
    function make_tree()
        suite(
            TestSpec(name="root", tags=Set{Symbol}()),
            [
                leaf(TestSpec(name="fast test", tags=Set([:unit, :fast]))),
                leaf(TestSpec(name="slow test", tags=Set([:integration, :slow]))),
                suite(
                    TestSpec(name="auth", tags=Set([:unit])),
                    [
                        leaf(TestSpec(name="login", tags=Set([:unit]))),
                        leaf(TestSpec(name="logout", tags=Set([:unit, :slow]))),
                    ]
                ),
            ]
        )
    end

    @testset "filter by name" begin
        tree = make_tree()
        f = TestFilter(names=["login"], tags=Set{Symbol}(), exclude_tags=Set{Symbol}())
        result = filter_tree(tree, f)
        # Should keep root > auth > login path
        @test !isnothing(result)
        names = collect_names(result)
        @test "login" in names
        @test !("slow test" in names)
        @test !("fast test" in names)
    end

    @testset "filter by tag inclusion" begin
        tree = make_tree()
        f = TestFilter(names=String[], tags=Set([:fast]), exclude_tags=Set{Symbol}())
        result = filter_tree(tree, f)
        @test !isnothing(result)
        names = collect_names(result)
        @test "fast test" in names
        @test !("slow test" in names)
    end

    @testset "filter by tag exclusion" begin
        tree = make_tree()
        f = TestFilter(names=String[], tags=Set{Symbol}(), exclude_tags=Set([:slow]))
        result = filter_tree(tree, f)
        @test !isnothing(result)
        names = collect_names(result)
        @test "fast test" in names
        @test "login" in names
        @test !("slow test" in names)
        @test !("logout" in names)
    end

    @testset "parse CLI args" begin
        args = ["auth", "login", "--tags=unit,fast", "--exclude=slow"]
        f = parse_test_args(args)
        @test f.names == ["auth", "login"]
        @test f.tags == Set([:unit, :fast])
        @test f.exclude_tags == Set([:slow])
    end

    @testset "empty filter returns full tree" begin
        tree = make_tree()
        f = TestFilter(names=String[], tags=Set{Symbol}(), exclude_tags=Set{Symbol}())
        result = filter_tree(tree, f)
        @test !isnothing(result)
        names = collect_names(result)
        @test length(names) == 5  # all 5 named nodes (excl root)
    end
end

# Helper to collect all names from a Cofree tree
function collect_names(c::Cofree)
    names = String[]
    _collect!(names, c)
    names
end

function _collect!(names, c::Cofree)
    name = extract(c).name
    name != "root" && push!(names, name)
    for child in c.tail
        _collect!(names, child)
    end
end
```

**Step 2: Run tests to verify they fail**

Run: `julia --project -e 'include("test/test_filter.jl")'`
Expected: FAIL.

**Step 3: Implement Filter.jl**

```julia
# src/Filter.jl

"""Test filter: name substrings, required tags, excluded tags."""
@kwdef struct TestFilter
    names::Vector{String} = String[]
    tags::Set{Symbol} = Set{Symbol}()
    exclude_tags::Set{Symbol} = Set{Symbol}()
end

"""
    matches_filter(spec::TestSpec, f::TestFilter) -> Bool

Check if a single test spec passes the filter criteria.
"""
function matches_filter(spec::TestSpec, f::TestFilter)::Bool
    # Name filter: any name substring must match
    if !isempty(f.names)
        any(n -> occursin(n, spec.name), f.names) || return false
    end
    # Tag inclusion: spec must have at least one of the required tags
    if !isempty(f.tags)
        isempty(intersect(spec.tags, f.tags)) && return false
    end
    # Tag exclusion: spec must not have any excluded tags
    if !isempty(f.exclude_tags)
        !isempty(intersect(spec.tags, f.exclude_tags)) && return false
    end
    true
end

"""
    filter_tree(tree::Cofree, f::TestFilter) -> Union{Cofree, Nothing}

Prune a test tree, keeping only nodes that match the filter.
Suite nodes are kept if any descendant matches.
Returns `nothing` if the entire tree is pruned.
"""
function filter_tree(tree::Cofree, f::TestFilter)::Union{Cofree, Nothing}
    # Filter children recursively
    filtered_children = Cofree[]
    for child in tree.tail
        result = filter_tree(child, f)
        result !== nothing && push!(filtered_children, result)
    end

    spec = extract(tree)

    # Leaf node: keep only if it matches
    if isempty(tree.tail)
        return matches_filter(spec, f) ? tree : nothing
    end

    # Suite node: keep if any children survived
    if !isempty(filtered_children)
        return Cofree(spec, filtered_children)
    end

    # Suite with no surviving children — prune it
    nothing
end

"""
    parse_test_args(args::Vector{String}) -> TestFilter

Parse CLI arguments into a TestFilter.
Positional args become name filters. `--tags=a,b` and `--exclude=a,b` for tag filters.
"""
function parse_test_args(args::Vector{String})::TestFilter
    names = String[]
    tags = Set{Symbol}()
    exclude_tags = Set{Symbol}()

    for arg in args
        if startswith(arg, "--tags=")
            tag_str = arg[length("--tags=") + 1:end]
            for t in split(tag_str, ",")
                push!(tags, Symbol(strip(t)))
            end
        elseif startswith(arg, "--exclude=")
            tag_str = arg[length("--exclude=") + 1:end]
            for t in split(tag_str, ",")
                push!(exclude_tags, Symbol(strip(t)))
            end
        else
            push!(names, arg)
        end
    end

    TestFilter(; names, tags, exclude_tags)
end
```

**Step 4: Wire into module**

Add to `src/CofreeTest.jl`:

```julia
include("Filter.jl")

export TestFilter
```

**Step 5: Update test/runtests.jl, run tests, commit**

Run: `julia --project -e 'using Pkg; Pkg.test()'`

```bash
git add src/Filter.jl src/CofreeTest.jl test/test_filter.jl test/runtests.jl
git commit -m "Implement test tree filtering by name and tags"
```

---

## Task 7: InlineExecutor

Start with the simplest executor — runs tests in the current process. This validates the executor interface before we add parallelism.

**Files:**
- Create: `src/executors/Abstract.jl`
- Create: `src/executors/Inline.jl`
- Create: `test/test_executor.jl`
- Modify: `src/CofreeTest.jl`
- Modify: `test/runtests.jl`

**Step 1: Write failing tests**

```julia
# test/test_executor.jl
using Test
using CofreeTest
using CofreeTest: InlineExecutor, execute!, EventBus, CollectorSubscriber, subscribe!

@testset "Executors" begin
    @testset "InlineExecutor — passing test" begin
        spec = TestSpec(
            name="simple pass",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=quote
                @check 1 + 1 == 2
            end,
        )
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        exec = InlineExecutor()
        outcome, metrics, io = execute!(exec, spec, bus)

        @test outcome isa Pass
        @test metrics.time_s >= 0.0
        @test io isa CapturedIO
    end

    @testset "InlineExecutor — failing test" begin
        spec = TestSpec(
            name="simple fail",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=quote
                @check 1 == 2
            end,
        )
        bus = EventBus()
        exec = InlineExecutor()
        outcome, metrics, io = execute!(exec, spec, bus)

        @test outcome isa Fail
    end

    @testset "InlineExecutor — error test" begin
        spec = TestSpec(
            name="throws error",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=quote
                error("boom")
            end,
        )
        bus = EventBus()
        exec = InlineExecutor()
        outcome, metrics, io = execute!(exec, spec, bus)

        @test outcome isa Error
        @test outcome.exception isa ErrorException
    end

    @testset "InlineExecutor — captures stdout" begin
        spec = TestSpec(
            name="prints stuff",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=quote
                println("hello from test")
            end,
        )
        bus = EventBus()
        exec = InlineExecutor()
        outcome, metrics, io = execute!(exec, spec, bus)

        @test contains(io.stdout, "hello from test")
    end
end
```

**Step 2: Run tests to verify they fail**

Run: `julia --project -e 'include("test/test_executor.jl")'`
Expected: FAIL.

**Step 3: Implement executor abstract interface**

```julia
# src/executors/Abstract.jl

"""
    AbstractExecutor

Interface for test executors. Implement `execute!` to define how test bodies run.
"""
abstract type AbstractExecutor end

"""
    execute!(executor, spec, bus) -> Tuple{Outcome, Metrics, CapturedIO}

Run a test spec and return its outcome, metrics, and captured IO.
Emit events to the bus during execution.
"""
function execute! end

"""Optional lifecycle hooks with defaults."""
setup!(::AbstractExecutor) = nothing
teardown!(::AbstractExecutor) = nothing
recycle!(::AbstractExecutor) = nothing
```

**Step 4: Implement InlineExecutor**

```julia
# src/executors/Inline.jl

using IOCapture

"""
    InlineExecutor

Runs tests in the current process and task. No isolation.
Useful for debugging and as the simplest executor implementation.
"""
struct InlineExecutor <: AbstractExecutor end

function execute!(::InlineExecutor, spec::TestSpec, bus::EventBus)::Tuple{Outcome, Metrics, CapturedIO}
    captured = IOCapture.capture() do
        mod = Module(gensym(spec.name))

        # Make @check available in the test module
        Core.eval(mod, :(using CofreeTest))

        # Set up event bus access for @check macros
        Core.eval(mod, :(const __cofreetest_bus__ = $bus))

        stats = try
            @timed Core.eval(mod, spec.body)
        catch e
            return (Error(e, catch_backtrace()),
                    Metrics(0.0, 0, 0.0, 0.0, 0.0),
                    CapturedIO("", ""))
        end

        rss = Sys.maxrss() / 1_000_000  # bytes to MB
        metrics = Metrics(
            stats.time,
            stats.bytes,
            stats.gctime,
            stats.time > 0 ? (stats.gctime / stats.time) * 100 : 0.0,
            rss,
        )

        (Pass(stats.value), metrics, CapturedIO("", ""))
    end

    # If the body returned early (Error case), the result is already a tuple
    result = captured.value
    if result isa Tuple{Outcome, Metrics, CapturedIO}
        outcome, metrics, _ = result
        return (outcome, metrics, CapturedIO(captured.output, ""))
    end

    outcome, metrics, _ = result
    (outcome, metrics, CapturedIO(captured.output, ""))
end
```

Note: This is a minimal first pass. The `@check` macro integration will be refined in Task 8. For now, tests use raw expressions.

**Step 5: Wire into module**

Add to `src/CofreeTest.jl`:

```julia
include("executors/Abstract.jl")
include("executors/Inline.jl")

export AbstractExecutor, InlineExecutor, execute!
```

**Step 6: Run tests, commit**

Run: `julia --project -e 'using Pkg; Pkg.test()'`

```bash
mkdir -p src/executors
git add src/executors/ src/CofreeTest.jl test/test_executor.jl test/runtests.jl
git commit -m "Implement AbstractExecutor interface and InlineExecutor"
```

---

## Task 8: @check Macros

Native assertion macros that emit events to the bus.

**Files:**
- Create: `src/Macros.jl`
- Create: `test/test_macros.jl`
- Modify: `src/CofreeTest.jl`
- Modify: `test/runtests.jl`

**Step 1: Write failing tests**

```julia
# test/test_macros.jl
using Test
using CofreeTest
using CofreeTest: EventBus, CollectorSubscriber, subscribe!

# We test macros by setting up a bus, running @check, and inspecting events

@testset "Macros" begin
    @testset "@check passing" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        # Simulate what happens inside a test execution context
        CofreeTest.with_bus(bus) do
            @check 1 + 1 == 2
        end

        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionPassed
    end

    @testset "@check failing" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check 1 == 2
        end

        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionFailed
        @test collector.events[1].expected == 1
        @test collector.events[1].got == 2
    end

    @testset "@check_throws passing" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check_throws ErrorException error("boom")
        end

        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionPassed
    end

    @testset "@check_throws failing — no exception" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check_throws ErrorException 1 + 1
        end

        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionFailed
    end

    @testset "@check_throws failing — wrong exception" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check_throws ArgumentError error("boom")
        end

        @test length(collector.events) == 1
        @test collector.events[1] isa AssertionFailed
    end

    @testset "@check_skip" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        CofreeTest.with_bus(bus) do
            @check_skip "not ready"
        end

        # check_skip doesn't emit assertion events — it sets outcome
        # This is handled at a higher level
    end
end
```

**Step 2: Run tests to verify they fail**

**Step 3: Implement Macros.jl**

```julia
# src/Macros.jl

# --- Bus context (task-local storage) ---

const _CURRENT_BUS = ScopedValue{Union{EventBus, Nothing}}(nothing)

"""
    with_bus(f, bus::EventBus)

Run `f` with `bus` as the current event bus for @check macros.
"""
function with_bus(f, bus::EventBus)
    @with _CURRENT_BUS => bus f()
end

function current_bus()::EventBus
    bus = _CURRENT_BUS[]
    bus === nothing && Base.error("@check used outside of a CofreeTest execution context")
    bus
end

# --- @check macro ---

"""
    @check expr

Assert that `expr` is true. Emits AssertionPassed or AssertionFailed to the event bus.
For comparison expressions (==, !=, <, etc.), captures both sides for rich failure output.
"""
macro check(expr)
    check_impl(expr, __source__)
end

function check_impl(expr, source)
    if expr isa Expr && expr.head == :call && length(expr.args) == 3
        op = expr.args[1]
        if op in (:(==), :(!=), :(<), :(>), :(<=), :(>=), :isequal, :isapprox, :(===))
            lhs = expr.args[2]
            rhs = expr.args[3]
            return quote
                local _lhs = $(esc(lhs))
                local _rhs = $(esc(rhs))
                local _result = $(esc(op))(_lhs, _rhs)
                local _bus = $current_bus()
                if _result
                    $emit!(_bus, $AssertionPassed(
                        $(QuoteNode(expr)), _result, $(QuoteNode(source)), time()))
                else
                    $emit!(_bus, $AssertionFailed(
                        $(QuoteNode(expr)), _rhs, _lhs, $(QuoteNode(source)), time()))
                end
                _result
            end
        end
    end

    # Fallback: non-comparison expression
    quote
        local _result = $(esc(expr))
        local _bus = $current_bus()
        if _result
            $emit!(_bus, $AssertionPassed(
                $(QuoteNode(expr)), _result, $(QuoteNode(source)), time()))
        else
            $emit!(_bus, $AssertionFailed(
                $(QuoteNode(expr)), true, _result, $(QuoteNode(source)), time()))
        end
        _result
    end
end

# --- @check_throws macro ---

"""
    @check_throws ExceptionType expr

Assert that `expr` throws an exception of type `ExceptionType`.
"""
macro check_throws(extype, expr)
    quote
        local _bus = $current_bus()
        local _threw = false
        local _exc = nothing
        try
            $(esc(expr))
        catch e
            _threw = true
            _exc = e
        end
        if _threw && _exc isa $(esc(extype))
            $emit!(_bus, $AssertionPassed(
                $(QuoteNode(expr)), _exc, $(QuoteNode(__source__)), time()))
        elseif _threw
            $emit!(_bus, $AssertionFailed(
                $(QuoteNode(expr)), $(esc(extype)), typeof(_exc), $(QuoteNode(__source__)), time()))
        else
            $emit!(_bus, $AssertionFailed(
                $(QuoteNode(expr)), $(esc(extype)), :no_exception, $(QuoteNode(__source__)), time()))
        end
        _threw && _exc isa $(esc(extype))
    end
end

# --- @check_broken macro ---

"""
    @check_broken expr

Mark a test as expected to fail. Passes if the expression fails, fails if it succeeds.
"""
macro check_broken(expr)
    quote
        local _bus = $current_bus()
        local _result = try
            $(esc(expr))
        catch
            false
        end
        if !_result
            # Expected failure — this is a pass
            $emit!(_bus, $AssertionPassed(
                $(QuoteNode(expr)), :broken, $(QuoteNode(__source__)), time()))
        else
            # Unexpectedly passed — this is a failure
            $emit!(_bus, $AssertionFailed(
                $(QuoteNode(expr)), :broken, :passed, $(QuoteNode(__source__)), time()))
        end
        !_result
    end
end

# --- @check_skip macro ---

"""
    @check_skip reason

Skip the current test with a reason string. Emits a LogEvent.
"""
macro check_skip(reason)
    quote
        local _bus = $current_bus()
        $emit!(_bus, $LogEvent(:skip, $(esc(reason)), time()))
        return  # exit the test body early
    end
end
```

**Step 4: Wire into module**

Add to `src/CofreeTest.jl`:

```julia
include("Macros.jl")

export @check, @check_throws, @check_broken, @check_skip, with_bus
```

**Step 5: Run tests, commit**

```bash
git add src/Macros.jl src/CofreeTest.jl test/test_macros.jl test/runtests.jl
git commit -m "Implement @check assertion macros with event emission"
```

---

## Task 9: Runner (InlineExecutor Pipeline)

Wire together the full pipeline: define → schedule → execute → result tree. Start with InlineExecutor only.

**Files:**
- Create: `src/Schedule.jl`
- Create: `src/Runner.jl`
- Create: `test/test_runner.jl`
- Modify: `src/CofreeTest.jl`
- Modify: `test/runtests.jl`

**Step 1: Write failing tests**

```julia
# test/test_runner.jl
using Test
using CofreeTest
using CofreeTest: schedule_tree, run_tree, EventBus, CollectorSubscriber, subscribe!

@testset "Runner" begin
    @testset "schedule assigns inline executor" begin
        tree = suite(
            TestSpec(name="root"),
            [
                leaf(TestSpec(name="t1", body=:(@check true))),
                leaf(TestSpec(name="t2", body=:(@check 1 == 1))),
            ]
        )

        scheduled = schedule_tree(tree)
        @test extract(scheduled) isa Scheduled
        @test extract(scheduled).executor == :inline
        @test length(scheduled.tail) == 2
    end

    @testset "run_tree produces TestResult tree" begin
        tree = suite(
            TestSpec(name="root"),
            [
                leaf(TestSpec(name="t1", body=:(@check true))),
                leaf(TestSpec(name="t2", body=:(@check 1 + 1 == 2))),
            ]
        )

        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        scheduled = schedule_tree(tree)
        results = run_tree(scheduled, bus)

        @test extract(results) isa TestResult
        @test extract(results).spec.name == "root"

        # Children should have results
        @test extract(results.tail[1]) isa TestResult
        @test extract(results.tail[1]).outcome isa Pass
        @test extract(results.tail[2]) isa TestResult
        @test extract(results.tail[2]).outcome isa Pass

        # Events should have been emitted
        @test any(e -> e isa TestStarted, collector.events)
        @test any(e -> e isa TestFinished, collector.events)
    end

    @testset "run_tree handles failures" begin
        tree = suite(
            TestSpec(name="root"),
            [
                leaf(TestSpec(name="pass", body=:(@check true))),
                leaf(TestSpec(name="fail", body=:(@check 1 == 2))),
            ]
        )

        bus = EventBus()
        scheduled = schedule_tree(tree)
        results = run_tree(scheduled, bus)

        @test extract(results.tail[1]).outcome isa Pass
        @test extract(results.tail[2]).outcome isa Fail
    end

    @testset "run_tree handles errors" begin
        tree = leaf(TestSpec(name="boom", body=:(error("kaboom"))))

        bus = EventBus()
        scheduled = schedule_tree(tree)
        results = run_tree(scheduled, bus)

        @test extract(results).outcome isa Error
    end
end
```

**Step 2: Run tests to verify they fail**

**Step 3: Implement Schedule.jl**

```julia
# src/Schedule.jl

"""
    schedule_tree(tree::Cofree; executor=:inline, history=Dict{String,Float64}()) -> Cofree{F, Scheduled}

Natural transformation: TestSpec → Scheduled.
Assigns executor type and priority based on historical durations.
"""
function schedule_tree(
    tree::Cofree;
    executor::Symbol = :inline,
    history::Dict{String, Float64} = Dict{String, Float64}(),
)
    hoist(tree) do spec
        priority = get(history, spec.name, Inf)
        Scheduled(spec, executor, nothing, priority)
    end
end
```

**Step 4: Implement Runner.jl**

```julia
# src/Runner.jl

"""
    run_tree(scheduled::Cofree{F, Scheduled}, bus::EventBus) -> Cofree{F, TestResult}

Execute a scheduled test tree, producing a result tree.
Emits events to the bus during execution.
"""
function run_tree(scheduled::Cofree, bus::EventBus)
    sched = extract(scheduled)
    spec = sched.spec

    if spec.body !== nothing
        # Leaf test — execute it
        emit!(bus, TestStarted(spec.name, spec.source, 0, time()))

        executor = _make_executor(sched.executor)
        outcome, metrics, io = execute!(executor, spec, bus)

        emit!(bus, TestFinished(spec.name, outcome, metrics, io, time()))

        result = TestResult(spec, outcome, metrics.time_s, metrics, TestEvent[], io)
        return Cofree(result, [run_tree(c, bus) for c in scheduled.tail])
    end

    # Suite node — run children, aggregate
    emit!(bus, SuiteStarted(spec.name, spec.source, time()))

    result_children = [run_tree(child, bus) for child in scheduled.tail]

    emit!(bus, SuiteFinished(spec.name, time()))

    # Aggregate suite result
    suite_outcome = _aggregate_outcome(result_children)
    suite_metrics = _aggregate_metrics(result_children)
    suite_result = TestResult(spec, suite_outcome, suite_metrics.time_s, suite_metrics, TestEvent[], CapturedIO("", ""))

    Cofree(suite_result, result_children)
end

function _make_executor(kind::Symbol)
    if kind == :inline
        InlineExecutor()
    else
        Base.error("Executor :$kind not yet implemented")
    end
end

function _aggregate_outcome(children::Vector)
    for child in children
        r = extract(child)
        r.outcome isa Error && return Error(ErrorException("suite has errors"), nothing)
        r.outcome isa Fail && return Fail(:suite, :pass, :fail, LineNumberNode(0, :unknown))
    end
    Pass(nothing)
end

function _aggregate_metrics(children::Vector)
    total_time = sum(extract(c).metrics.time_s for c in children; init=0.0)
    total_bytes = sum(extract(c).metrics.bytes_allocated for c in children; init=0)
    total_gc = sum(extract(c).metrics.gc_time_s for c in children; init=0.0)
    gc_pct = total_time > 0 ? (total_gc / total_time) * 100 : 0.0
    max_rss = maximum(extract(c).metrics.rss_mb for c in children; init=0.0)
    Metrics(total_time, total_bytes, total_gc, gc_pct, max_rss)
end
```

**Step 5: Wire into module**

Add to `src/CofreeTest.jl`:

```julia
include("Schedule.jl")
include("Runner.jl")
```

**Step 6: Run tests, commit**

```bash
git add src/Schedule.jl src/Runner.jl src/CofreeTest.jl test/test_runner.jl test/runtests.jl
git commit -m "Implement schedule and run pipeline with InlineExecutor"
```

---

## Task 10: DotFormatter (Minimal Formatter)

Start with the simplest formatter before tackling the rich terminal UI.

**Files:**
- Create: `src/formatters/Abstract.jl`
- Create: `src/formatters/Dot.jl`
- Create: `test/test_formatter.jl`
- Modify: `src/CofreeTest.jl`
- Modify: `test/runtests.jl`

**Step 1: Write failing tests**

```julia
# test/test_formatter.jl
using Test
using CofreeTest
using CofreeTest: DotFormatter, handle!, finalize!, EventBus, CollectorSubscriber

@testset "Formatters" begin
    @testset "DotFormatter — pass" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, TestFinished("t1", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        @test String(take!(io)) == "."
    end

    @testset "DotFormatter — fail" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, TestFinished("t1", Fail(:e, 1, 2, LineNumberNode(1, :f)), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        @test String(take!(io)) == "F"
    end

    @testset "DotFormatter — error" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, TestFinished("t1", Error(ErrorException("x"), nothing), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        @test String(take!(io)) == "E"
    end

    @testset "DotFormatter — skip" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, TestFinished("t1", Skip("r"), Metrics(0.0, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        @test String(take!(io)) == "S"
    end

    @testset "DotFormatter — ignores non-TestFinished events" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, SuiteStarted("s", LineNumberNode(1, :f), 1.0))
        @test String(take!(io)) == ""
    end

    @testset "DotFormatter — finalize prints newline and summary" begin
        io = IOBuffer()
        fmt = DotFormatter(io)
        handle!(fmt, TestFinished("t1", Pass(true), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        handle!(fmt, TestFinished("t2", Fail(:e, 1, 2, LineNumberNode(1, :f)), Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
        take!(io)  # clear dots
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "2 tests")
        @test contains(output, "1 passed")
        @test contains(output, "1 failed")
    end
end
```

**Step 2: Run tests to verify they fail**

**Step 3: Implement Abstract.jl and Dot.jl**

```julia
# src/formatters/Abstract.jl

"""
    AbstractFormatter

Interface for test output formatters. Formatters are event subscribers
that produce human- or machine-readable output.
"""
abstract type AbstractFormatter <: Subscriber end

"""
    handle!(formatter, event)

Process a single test event. Called for each event emitted during execution.
Default: no-op for unknown event types.
"""
handle!(::AbstractFormatter, ::TestEvent) = nothing

"""
    finalize!(formatter)

Called after all tests complete. Produce final summary output.
"""
finalize!(::AbstractFormatter) = nothing
```

```julia
# src/formatters/Dot.jl

"""
    DotFormatter

Minimal formatter: prints `.` for pass, `F` for fail, `E` for error, `S` for skip.
"""
mutable struct DotFormatter <: AbstractFormatter
    io::IO
    passed::Int
    failed::Int
    errored::Int
    skipped::Int

    DotFormatter(io::IO = stdout) = new(io, 0, 0, 0, 0)
end

function handle!(fmt::DotFormatter, event::TestFinished)
    outcome = event.outcome
    if outcome isa Pass
        fmt.passed += 1
        print(fmt.io, ".")
    elseif outcome isa Fail
        fmt.failed += 1
        print(fmt.io, "F")
    elseif outcome isa Error
        fmt.errored += 1
        print(fmt.io, "E")
    elseif outcome isa Skip
        fmt.skipped += 1
        print(fmt.io, "S")
    end
end

function finalize!(fmt::DotFormatter)
    total = fmt.passed + fmt.failed + fmt.errored + fmt.skipped
    println(fmt.io)
    println(fmt.io, "$total tests: $(fmt.passed) passed, $(fmt.failed) failed, $(fmt.errored) errored, $(fmt.skipped) skipped")
end
```

**Step 4: Wire into module**

```julia
include("formatters/Abstract.jl")
include("formatters/Dot.jl")

export AbstractFormatter, DotFormatter
```

**Step 5: Run tests, commit**

```bash
mkdir -p src/formatters
git add src/formatters/ src/CofreeTest.jl test/test_formatter.jl test/runtests.jl
git commit -m "Implement AbstractFormatter interface and DotFormatter"
```

---

## Task 11: Terminal Components

Box drawing, spinners, bar charts, and color utilities for the rich UI.

**Files:**
- Create: `src/formatters/TerminalComponents.jl`
- Create: `test/test_terminal_components.jl`
- Modify: `src/CofreeTest.jl`
- Modify: `test/runtests.jl`

**Step 1: Write failing tests**

```julia
# test/test_terminal_components.jl
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
        @test format_duration(0.5) == "0.50s"
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
end
```

**Step 2: Run tests to verify they fail**

**Step 3: Implement TerminalComponents.jl**

```julia
# src/formatters/TerminalComponents.jl

# --- Box drawing ---

const BOX_TL = "╭"
const BOX_TR = "╮"
const BOX_BL = "╰"
const BOX_BR = "╯"
const BOX_H  = "─"
const BOX_V  = "│"

"""Draw a box with title and content lines."""
function box(title::String, lines::Vector{String}; width::Int = 72)
    buf = IOBuffer()
    inner = width - 4  # 2 for border + 2 for padding

    # Top border with title
    title_segment = "─ $title "
    remaining = width - 2 - length(title_segment)
    println(buf, " $BOX_TL$title_segment$(BOX_H ^ max(0, remaining))$BOX_TR")

    # Content
    for line in lines
        padded = rpad(line, inner)
        println(buf, " $BOX_V  $(padded[1:min(end, inner)])  $BOX_V")
    end

    # Bottom border
    println(buf, " $BOX_BL$(BOX_H ^ (width - 2))$BOX_BR")

    String(take!(buf))
end

# --- Progress bar ---

"""Render a progress bar: ━━━━━━━━━━━━━━━  5/10  50%"""
function progress_bar(completed::Int, total::Int; width::Int = 30)
    pct = total > 0 ? completed / total : 0.0
    filled = round(Int, pct * width)
    bar = "━" ^ filled * " " ^ (width - filled)
    "$bar  $completed/$total  $(round(Int, pct * 100))%"
end

# --- Spinner ---

const SPINNER_FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧']

"""Get a spinner frame by index (wraps around)."""
spinner_frame(i::Int) = SPINNER_FRAMES[mod(i, length(SPINNER_FRAMES)) + 1]

# --- Bar chart ---

const BAR_CHARS = ['▏', '▎', '▍', '▌', '▋', '▊', '▉', '█']

"""Render a proportional bar chart."""
function bar_chart(value::Number, max_value::Number; width::Int = 10)
    max_value <= 0 && return " " ^ width
    ratio = clamp(value / max_value, 0.0, 1.0)
    total_eighths = round(Int, ratio * width * 8)
    full_blocks = div(total_eighths, 8)
    remainder = mod(total_eighths, 8)

    result = "█" ^ full_blocks
    if remainder > 0
        result *= string(BAR_CHARS[remainder])
    end
    rpad(result, width)
end

# --- Sparkline ---

const SPARK_CHARS = "▁▂▃▄▅▆▇█"

"""Render a sparkline from a vector of values."""
function sparkline(values::Vector{<:Number})
    isempty(values) && return ""
    lo, hi = extrema(values)
    range = hi - lo
    range == 0 && return string(SPARK_CHARS[4]) ^ length(values)

    String(map(values) do v
        idx = clamp(round(Int, (v - lo) / range * 7) + 1, 1, 8)
        SPARK_CHARS[idx]
    end)
end

# --- Dot leader ---

"""Connect a left label to a right value with dots."""
function dot_leader(left::String, right::String; width::Int = 60)
    dots_needed = width - length(left) - length(right) - 2
    dots_needed = max(dots_needed, 1)
    "$left $(repeat('·', dots_needed)) $right"
end

# --- Formatting helpers ---

"""Format a duration in seconds to human-readable string."""
function format_duration(seconds::Float64)
    if seconds < 0.01
        "$(round(Int, seconds * 1000))ms"
    elseif seconds < 60
        "$(round(seconds; digits=2))s"
    else
        m = floor(Int, seconds / 60)
        s = round(Int, seconds - m * 60)
        "$(m)m $(lpad(string(s), 2, '0'))s"
    end
end

"""Format bytes to human-readable string."""
function format_bytes(bytes::Number)
    if bytes < 1024
        "$(round(Int, bytes)) B"
    elseif bytes < 1024^2
        "$(round(bytes / 1024; digits=1)) KB"
    elseif bytes < 1024^3
        "$(round(bytes / 1024^2; digits=1)) MB"
    else
        "$(round(bytes / 1024^3; digits=1)) GB"
    end
end

"""Return a color symbol based on duration thresholds."""
function color_for_duration(seconds::Float64;
    fast::Float64 = 0.1, medium::Float64 = 1.0)
    seconds < fast ? :green : seconds < medium ? :yellow : :red
end
```

**Step 4: Wire into module, run tests, commit**

```bash
git add src/formatters/TerminalComponents.jl src/CofreeTest.jl test/test_terminal_components.jl test/runtests.jl
git commit -m "Implement terminal UI components: box, spinner, bars, sparklines"
```

---

## Task 12: TerminalFormatter

The rich live-updating terminal UI.

**Files:**
- Create: `src/formatters/Terminal.jl`
- Modify: `test/test_formatter.jl` (add terminal formatter tests)
- Modify: `src/CofreeTest.jl`

**Step 1: Add failing tests to test/test_formatter.jl**

```julia
# Append to test/test_formatter.jl

@testset "TerminalFormatter" begin
    @testset "renders header" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        start!(fmt, 5)
        output = String(take!(io))
        @test contains(output, "CofreeTest")
    end

    @testset "renders pass" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        start!(fmt, 2)
        take!(io)
        handle!(fmt, TestFinished("my test", Pass(true),
            Metrics(0.05, 1024, 0.0, 0.0, 64.0), CapturedIO("", ""), 1.0))
        output = String(take!(io))
        @test contains(output, "✔")
        @test contains(output, "my test")
    end

    @testset "renders failure with detail" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        start!(fmt, 1)
        take!(io)
        handle!(fmt, TestFinished("bad test",
            Fail(:(@check 1 == 2), 2, 1, LineNumberNode(42, Symbol("test.jl"))),
            Metrics(0.1, 512, 0.0, 0.0, 64.0), CapturedIO("", ""), 1.0))
        output = String(take!(io))
        @test contains(output, "✘")
        @test contains(output, "bad test")
        @test contains(output, "Failure")
    end

    @testset "finalize renders summary" begin
        io = IOBuffer()
        fmt = TerminalFormatter(io; color=false)
        start!(fmt, 2)
        handle!(fmt, TestFinished("t1", Pass(true),
            Metrics(0.1, 1024, 0.0, 0.0, 64.0), CapturedIO("", ""), 1.0))
        handle!(fmt, TestFinished("t2", Fail(:e, 1, 2, LineNumberNode(1, :f)),
            Metrics(0.2, 2048, 0.0, 0.0, 128.0), CapturedIO("", ""), 2.0))
        take!(io)
        finalize!(fmt)
        output = String(take!(io))
        @test contains(output, "passed")
        @test contains(output, "failed")
    end
end
```

**Step 2: Run tests to verify they fail**

**Step 3: Implement Terminal.jl**

This is a large file. The implementation should include:

```julia
# src/formatters/Terminal.jl

mutable struct TerminalFormatter <: AbstractFormatter
    io::IO
    color::Bool
    verbose::Bool
    lock::ReentrantLock
    total::Int
    completed::Int
    passed::Int
    failed::Int
    errored::Int
    skipped::Int
    start_time::Float64
    failures::Vector{TestFinished}
    durations::Vector{Float64}
    running::Dict{Int, Tuple{String, Float64}}  # worker_id => (name, start_time)

    function TerminalFormatter(io::IO = stdout;
        color::Bool = get(io, :color, false),
        verbose::Bool = false,
    )
        new(io, color, verbose, ReentrantLock(),
            0, 0, 0, 0, 0, 0, time(),
            TestFinished[], Float64[],
            Dict{Int, Tuple{String, Float64}}())
    end
end

"""Initialize the formatter with total test count and render header."""
function start!(fmt::TerminalFormatter, total::Int)
    fmt.total = total
    fmt.start_time = time()
    _render_header(fmt)
end

function _render_header(fmt::TerminalFormatter)
    w = displaysize(fmt.io)[2]
    w = min(w, 72)
    println(fmt.io, " $(BOX_TL)$(BOX_H ^ (w - 2))$(BOX_TR)")
    title = "  ☕ CofreeTest"
    padding = w - length(title) - 3
    println(fmt.io, " $(BOX_V)$(title)$(repeat(' ', max(1, padding)))$(BOX_V)")
    println(fmt.io, " $(BOX_BL)$(BOX_H ^ (w - 2))$(BOX_BR)")
    println(fmt.io)
end

function handle!(fmt::TerminalFormatter, event::TestStarted)
    lock(fmt.lock) do
        fmt.running[event.worker_id] = (event.name, event.timestamp)
    end
end

function handle!(fmt::TerminalFormatter, event::TestFinished)
    lock(fmt.lock) do
        fmt.completed += 1
        push!(fmt.durations, event.metrics.time_s)

        outcome = event.outcome
        if outcome isa Pass
            fmt.passed += 1
            _render_pass(fmt, event)
        elseif outcome isa Fail
            fmt.failed += 1
            push!(fmt.failures, event)
            _render_fail(fmt, event)
        elseif outcome isa Error
            fmt.errored += 1
            push!(fmt.failures, event)
            _render_error(fmt, event)
        elseif outcome isa Skip
            fmt.skipped += 1
            _render_skip(fmt, event)
        end
    end
end

function _styled(fmt::TerminalFormatter, text, color; bold=false)
    if fmt.color
        printstyled(fmt.io, text; color, bold)
    else
        print(fmt.io, text)
    end
end

function _render_pass(fmt::TerminalFormatter, event::TestFinished)
    _styled(fmt, "  ✔ ", :green)
    dur = format_duration(event.metrics.time_s)
    mem = format_bytes(event.metrics.bytes_allocated)
    leader = dot_leader(event.name, "$dur    $mem"; width=66)
    println(fmt.io, leader)
end

function _render_fail(fmt::TerminalFormatter, event::TestFinished)
    _styled(fmt, "  ✘ ", :red)
    dur = format_duration(event.metrics.time_s)
    mem = format_bytes(event.metrics.bytes_allocated)
    leader = dot_leader(event.name, "$dur    $mem"; width=66)
    println(fmt.io, leader)
    println(fmt.io)

    # Failure detail box
    fail = event.outcome::Fail
    lines = String[]
    push!(lines, "$(fail.source.file):$(fail.source.line)")
    push!(lines, "")
    push!(lines, "  Expected │ $(fail.expected)")
    push!(lines, "  Got      │ $(fail.got)")
    print(fmt.io, box("Failure", lines; width=66))
    println(fmt.io)
end

function _render_error(fmt::TerminalFormatter, event::TestFinished)
    _styled(fmt, "  ✘ ", :red; bold=true)
    dur = format_duration(event.metrics.time_s)
    leader = dot_leader(event.name, dur; width=66)
    println(fmt.io, leader)
    println(fmt.io)

    err = event.outcome::Error
    lines = ["$(typeof(err.exception)): $(err.exception)"]
    print(fmt.io, box("Error", lines; width=66))
    println(fmt.io)
end

function _render_skip(fmt::TerminalFormatter, event::TestFinished)
    _styled(fmt, "  ○ ", :light_black)
    skip = event.outcome::Skip
    println(fmt.io, "$(event.name) — $(skip.reason)")
end

function finalize!(fmt::TerminalFormatter)
    elapsed = time() - fmt.start_time
    println(fmt.io)

    # Summary line
    parts = String[]
    fmt.passed > 0 && push!(parts, "$(fmt.passed) passed")
    fmt.failed > 0 && push!(parts, "$(fmt.failed) failed")
    fmt.errored > 0 && push!(parts, "$(fmt.errored) errored")
    fmt.skipped > 0 && push!(parts, "$(fmt.skipped) skipped")

    summary = "  " * join(parts, "   ") * "    $(format_duration(elapsed)) total"

    if fmt.color
        fmt.failed + fmt.errored > 0 ? _styled(fmt, "  ✘ ", :red; bold=true) : _styled(fmt, "  ✔ ", :green; bold=true)
    end
    println(fmt.io, summary)
end
```

**Step 4: Wire into module, run tests, commit**

```bash
git add src/formatters/Terminal.jl src/CofreeTest.jl test/test_formatter.jl
git commit -m "Implement TerminalFormatter with rich box-drawn output"
```

---

## Task 13: @test Compatibility Layer

**Files:**
- Create: `src/Compat.jl`
- Create: `test/test_compat.jl`
- Modify: `src/CofreeTest.jl`
- Modify: `test/runtests.jl`

**Step 1: Write failing tests**

```julia
# test/test_compat.jl
using Test
using CofreeTest
using CofreeTest: CofreeTestSet, EventBus, CollectorSubscriber, subscribe!

@testset "Compat" begin
    @testset "@test pass intercepted" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        ts = CofreeTestSet(bus, "compat test")
        Test.push_testset(ts)
        try
            @test 1 + 1 == 2
        finally
            Test.pop_testset()
        end

        @test any(e -> e isa AssertionPassed, collector.events)
    end

    @testset "@test fail intercepted" begin
        bus = EventBus()
        collector = CollectorSubscriber()
        subscribe!(bus, collector)

        ts = CofreeTestSet(bus, "compat test")
        Test.push_testset(ts)
        try
            @test 1 == 2
        finally
            Test.pop_testset()
        end

        @test any(e -> e isa AssertionFailed, collector.events)
    end
end
```

**Step 2: Run tests to verify they fail**

**Step 3: Implement Compat.jl**

```julia
# src/Compat.jl

import Test

"""
    CofreeTestSet

A Test.AbstractTestSet shim that intercepts @test results and converts
them to CofreeTest events on the EventBus.
"""
struct CofreeTestSet <: Test.AbstractTestSet
    bus::EventBus
    description::String
end

CofreeTestSet(bus::EventBus, desc::AbstractString) = CofreeTestSet(bus, String(desc))

function Test.record(ts::CofreeTestSet, result::Test.Pass)
    emit!(ts.bus, AssertionPassed(
        something(result.orig_expr, :unknown),
        result.value,
        something(result.source, LineNumberNode(0, :unknown)),
        time()
    ))
    result
end

function Test.record(ts::CofreeTestSet, result::Test.Fail)
    expr = try
        Meta.parse(result.orig_expr)
    catch
        Symbol(result.orig_expr)
    end
    emit!(ts.bus, AssertionFailed(
        expr,
        result.data,
        result.value,
        result.source,
        time()
    ))
    result
end

function Test.record(ts::CofreeTestSet, result::Test.Error)
    emit!(ts.bus, AssertionFailed(
        :error,
        :no_error,
        result.value,
        something(result.source, LineNumberNode(0, :unknown)),
        time()
    ))
    result
end

function Test.record(ts::CofreeTestSet, result::Test.Broken)
    emit!(ts.bus, AssertionPassed(
        something(result.orig_expr, :unknown),
        :broken,
        something(result.source, LineNumberNode(0, :unknown)),
        time()
    ))
    result
end

Test.finish(ts::CofreeTestSet) = nothing
```

**Step 4: Wire into module, run tests, commit**

```bash
git add src/Compat.jl src/CofreeTest.jl test/test_compat.jl test/runtests.jl
git commit -m "Implement @test compatibility layer via CofreeTestSet shim"
```

---

## Task 14: runtests Entry Point

The public `runtests()` function that ties everything together.

**Files:**
- Modify: `src/Runner.jl` (add runtests function)
- Create: `test/test_integration.jl`
- Modify: `test/runtests.jl`

**Step 1: Write failing integration tests**

```julia
# test/test_integration.jl
using Test
using CofreeTest

@testset "Integration" begin
    @testset "runtests with inline executor" begin
        tree = suite(
            TestSpec(name="integration suite"),
            [
                leaf(TestSpec(name="addition", body=:(@check 1 + 1 == 2))),
                leaf(TestSpec(name="string", body=:(@check "hello" == "hello"))),
            ]
        )

        io = IOBuffer()
        result_tree = runtests(tree; io, color=false)

        @test extract(result_tree) isa TestResult
        @test extract(result_tree.tail[1]).outcome isa Pass
        @test extract(result_tree.tail[2]).outcome isa Pass

        output = String(take!(io))
        @test contains(output, "CofreeTest")
        @test contains(output, "passed")
    end

    @testset "runtests with failures" begin
        tree = suite(
            TestSpec(name="mixed suite"),
            [
                leaf(TestSpec(name="pass", body=:(@check true))),
                leaf(TestSpec(name="fail", body=:(@check 1 == 2))),
            ]
        )

        io = IOBuffer()
        result_tree = runtests(tree; io, color=false)

        @test extract(result_tree.tail[1]).outcome isa Pass
        @test extract(result_tree.tail[2]).outcome isa Fail

        output = String(take!(io))
        @test contains(output, "passed")
        @test contains(output, "failed")
    end
end
```

**Step 2: Run tests to verify they fail**

**Step 3: Add runtests to Runner.jl**

```julia
# Append to src/Runner.jl

"""
    runtests(tree::Cofree; kwargs...) -> Cofree{F, TestResult}

Run a test tree end-to-end: schedule → execute → format.

# Keywords
- `io::IO = stdout` — output destination
- `color::Bool = true` — enable ANSI colors
- `formatter::Symbol = :terminal` — `:terminal`, `:dot`, `:json`
- `executor::Symbol = :inline` — `:inline`, `:task`, `:process`
- `history::Dict{String,Float64} = Dict()` — historical durations for scheduling
- `verbose::Bool = false` — show passing tests in detail
"""
function runtests(tree::Cofree;
    io::IO = stdout,
    color::Bool = get(io, :color, true),
    formatter::Symbol = :terminal,
    executor::Symbol = :inline,
    history::Dict{String, Float64} = Dict{String, Float64}(),
    verbose::Bool = false,
)
    # 1. Schedule
    scheduled = schedule_tree(tree; executor, history)

    # 2. Set up event bus with formatter
    bus = EventBus()
    fmt = _make_formatter(formatter, io; color, verbose)
    subscribe!(bus, fmt)

    # Count total leaf tests
    total = _count_leaves(tree)
    if fmt isa TerminalFormatter
        start!(fmt, total)
    end

    # 3. Execute
    result_tree = run_tree(scheduled, bus)

    # 4. Finalize formatter
    finalize!(fmt)

    result_tree
end

function _make_formatter(kind::Symbol, io::IO; color::Bool, verbose::Bool)
    if kind == :terminal
        TerminalFormatter(io; color, verbose)
    elseif kind == :dot
        DotFormatter(io)
    else
        Base.error("Unknown formatter: $kind")
    end
end

function _count_leaves(tree::Cofree)::Int
    spec = extract(tree)
    if isempty(tree.tail) && spec isa TestSpec && spec.body !== nothing
        return 1
    end
    sum(_count_leaves(c) for c in tree.tail; init=0)
end
```

**Step 4: Export runtests**

Add to `src/CofreeTest.jl` exports:

```julia
export runtests
```

**Step 5: Run tests, commit**

```bash
git add src/Runner.jl src/CofreeTest.jl test/test_integration.jl test/runtests.jl
git commit -m "Implement runtests entry point wiring full pipeline"
```

---

## Task 15: History Persistence

Save and load test durations for scheduling optimization.

**Files:**
- Create: `src/History.jl`
- Modify: `src/CofreeTest.jl`

**Step 1: Implement History.jl** (simpler, doesn't need heavy TDD)

```julia
# src/History.jl

using Scratch
using Serialization

const HISTORY_DIR = Ref{String}("")

function _history_dir()
    if isempty(HISTORY_DIR[])
        HISTORY_DIR[] = @get_scratch!("test_history")
    end
    HISTORY_DIR[]
end

function _history_path(mod::Module)
    v = "$(VERSION.major).$(VERSION.minor)"
    joinpath(_history_dir(), "$(nameof(mod))_$v.jls")
end

"""Load historical test durations for a module."""
function load_history(mod::Module)::Dict{String, Float64}
    path = _history_path(mod)
    isfile(path) || return Dict{String, Float64}()
    try
        open(deserialize, path)
    catch
        Dict{String, Float64}()
    end
end

"""Save test durations from a result tree."""
function save_history!(mod::Module, result_tree::Cofree)
    durations = Dict{String, Float64}()
    _collect_durations!(durations, result_tree)
    path = _history_path(mod)
    mkpath(dirname(path))
    open(path, "w") do io
        serialize(io, durations)
    end
end

function _collect_durations!(durations::Dict, tree::Cofree)
    result = extract(tree)
    if result isa TestResult && result.spec.body !== nothing
        durations[result.spec.name] = result.duration
    end
    for child in tree.tail
        _collect_durations!(durations, child)
    end
end
```

**Step 2: Wire into module, commit**

```bash
git add src/History.jl src/CofreeTest.jl
git commit -m "Implement test duration history persistence via Scratch.jl"
```

---

## Task 16: MultiFormatter & JSON Formatter

**Files:**
- Create: `src/formatters/Multi.jl`
- Create: `src/formatters/Json.jl`
- Modify: `src/CofreeTest.jl`
- Modify: `test/test_formatter.jl` (add tests)

**Step 1: Write failing tests**

```julia
# Append to test/test_formatter.jl

@testset "JSONFormatter" begin
    io = IOBuffer()
    fmt = JSONFormatter(io)
    handle!(fmt, TestFinished("t1", Pass(true),
        Metrics(0.1, 1024, 0.0, 0.0, 64.0), CapturedIO("", ""), 1.0))
    finalize!(fmt)
    output = String(take!(io))
    @test contains(output, "\"name\":\"t1\"")
    @test contains(output, "\"outcome\":\"pass\"")
end

@testset "MultiFormatter" begin
    io1 = IOBuffer()
    io2 = IOBuffer()
    fmt = MultiFormatter([DotFormatter(io1), DotFormatter(io2)])
    handle!(fmt, TestFinished("t1", Pass(true),
        Metrics(0.1, 0, 0.0, 0.0, 0.0), CapturedIO("", ""), 1.0))
    @test String(take!(io1)) == "."
    @test String(take!(io2)) == "."
end
```

**Step 2: Implement Json.jl and Multi.jl**

```julia
# src/formatters/Json.jl

"""JSONFormatter — structured JSON output for CI/tooling."""
mutable struct JSONFormatter <: AbstractFormatter
    io::IO
    results::Vector{Dict{String, Any}}
    JSONFormatter(io::IO = stdout) = new(io, Dict{String, Any}[])
end

function handle!(fmt::JSONFormatter, event::TestFinished)
    outcome_str = if event.outcome isa Pass; "pass"
    elseif event.outcome isa Fail; "fail"
    elseif event.outcome isa Error; "error"
    elseif event.outcome isa Skip; "skip"
    else "unknown"
    end

    push!(fmt.results, Dict(
        "name" => event.name,
        "outcome" => outcome_str,
        "duration" => event.metrics.time_s,
        "bytes" => event.metrics.bytes_allocated,
        "timestamp" => event.timestamp,
    ))
end

function finalize!(fmt::JSONFormatter)
    # Simple JSON serialization without dependency
    print(fmt.io, "[")
    for (i, r) in enumerate(fmt.results)
        i > 1 && print(fmt.io, ",")
        print(fmt.io, "{")
        entries = collect(pairs(r))
        for (j, (k, v)) in enumerate(entries)
            j > 1 && print(fmt.io, ",")
            print(fmt.io, "\"$k\":")
            if v isa String
                print(fmt.io, "\"$v\"")
            else
                print(fmt.io, v)
            end
        end
        print(fmt.io, "}")
    end
    print(fmt.io, "]")
end
```

```julia
# src/formatters/Multi.jl

"""MultiFormatter — dispatch events to multiple formatters."""
struct MultiFormatter <: AbstractFormatter
    formatters::Vector{AbstractFormatter}
end

function handle!(fmt::MultiFormatter, event::TestEvent)
    for f in fmt.formatters
        handle!(f, event)
    end
end

function finalize!(fmt::MultiFormatter)
    for f in fmt.formatters
        finalize!(f)
    end
end
```

**Step 3: Wire into module, run tests, commit**

```bash
git add src/formatters/Json.jl src/formatters/Multi.jl src/CofreeTest.jl test/test_formatter.jl
git commit -m "Add JSONFormatter and MultiFormatter"
```

---

## Task 17: ProcessExecutor (Parallel Execution)

The Malt.jl-based process executor for real parallel isolation.

**Files:**
- Create: `src/executors/Process.jl`
- Create: `src/executors/Pool.jl`
- Modify: `src/CofreeTest.jl`
- Modify: `test/test_executor.jl` (add process executor tests)
- Modify: `src/Runner.jl` (wire up :process executor)

**Step 1: Write failing tests**

```julia
# Append to test/test_executor.jl
using CofreeTest: ProcessExecutor, ExecutorPool, create_pool

@testset "ProcessExecutor" begin
    @testset "executes in separate process" begin
        spec = TestSpec(
            name="process test",
            source=LineNumberNode(1, Symbol("test.jl")),
            body=quote
                # This runs in a worker process
                1 + 1
            end,
        )
        bus = EventBus()
        exec = ProcessExecutor(1)
        try
            outcome, metrics, io = execute!(exec, spec, bus)
            @test outcome isa Pass
            @test metrics.time_s >= 0.0
        finally
            teardown!(exec)
        end
    end
end

@testset "ExecutorPool" begin
    @testset "creates pool of workers" begin
        pool = create_pool(ProcessExecutor; njobs=2)
        try
            @test length(pool.executors) == 2
        finally
            teardown!(pool)
        end
    end
end
```

**Step 2: Implement Process.jl**

```julia
# src/executors/Process.jl

using Malt

"""
    ProcessExecutor

Runs tests in isolated OS processes via Malt.jl. Maximum isolation —
no shared state, OOM-safe, independent GC.
"""
mutable struct ProcessExecutor <: AbstractExecutor
    worker::Union{Malt.Worker, Nothing}
    id::Int
    max_rss_mb::Float64

    function ProcessExecutor(id::Int; max_rss_mb::Float64 = _default_max_rss())
        w = Malt.Worker(; exeflags=["--threads=1"])
        new(w, id, max_rss_mb)
    end
end

function _default_max_rss()
    mem_gb = Sys.total_memory() / 1_000_000_000
    Sys.WORD_SIZE == 64 ? (mem_gb > 8 ? 3800.0 : 3000.0) : 1536.0
end

function execute!(exec::ProcessExecutor, spec::TestSpec, bus::EventBus)::Tuple{Outcome, Metrics, CapturedIO}
    exec.worker === nothing && _respawn!(exec)

    try
        result = Malt.remote_call_fetch(exec.worker) do
            mod = Module(gensym(spec.name))
            stats = try
                @timed Core.eval(mod, spec.body)
            catch e
                return (Error(e, nothing), Metrics(0.0, 0, 0.0, 0.0, 0.0), CapturedIO("", ""))
            end
            rss = Sys.maxrss() / 1_000_000
            metrics = Metrics(stats.time, stats.bytes, stats.gctime,
                stats.time > 0 ? (stats.gctime / stats.time) * 100 : 0.0, rss)
            (Pass(stats.value), metrics, CapturedIO("", ""))
        end

        # Check RSS for recycling
        if result[2].rss_mb > exec.max_rss_mb
            recycle!(exec)
        end

        result
    catch e
        (Error(e isa Exception ? e : ErrorException(string(e)), nothing),
         Metrics(0.0, 0, 0.0, 0.0, 0.0), CapturedIO("", ""))
    end
end

function recycle!(exec::ProcessExecutor)
    exec.worker !== nothing && Malt.stop(exec.worker)
    _respawn!(exec)
end

function _respawn!(exec::ProcessExecutor)
    exec.worker = Malt.Worker(; exeflags=["--threads=1"])
end

function teardown!(exec::ProcessExecutor)
    if exec.worker !== nothing
        Malt.stop(exec.worker)
        exec.worker = nothing
    end
end

function setup!(exec::ProcessExecutor)
    exec.worker === nothing && _respawn!(exec)
end
```

**Step 3: Implement Pool.jl**

```julia
# src/executors/Pool.jl

"""
    ExecutorPool{E}

A pool of executors with work-stealing dispatch.
"""
mutable struct ExecutorPool{E <: AbstractExecutor}
    executors::Vector{E}
    available::Channel{E}
    max_rss_mb::Float64
end

"""Create a pool of ProcessExecutors."""
function create_pool(::Type{ProcessExecutor};
    njobs::Int = default_njobs(),
    max_rss_mb::Float64 = _default_max_rss(),
)
    executors = [ProcessExecutor(i; max_rss_mb) for i in 1:njobs]
    available = Channel{ProcessExecutor}(njobs)
    for exec in executors
        put!(available, exec)
    end
    ExecutorPool(executors, available, max_rss_mb)
end

function default_njobs()
    min(Sys.CPU_THREADS, max(1, floor(Int, Sys.free_memory() / 2_000_000_000)))
end

function teardown!(pool::ExecutorPool)
    close(pool.available)
    for exec in pool.executors
        teardown!(exec)
    end
end
```

**Step 4: Update Runner.jl _make_executor**

```julia
function _make_executor(kind::Symbol)
    if kind == :inline
        InlineExecutor()
    elseif kind == :process
        ProcessExecutor(0)
    else
        Base.error("Executor :$kind not yet implemented")
    end
end
```

**Step 5: Wire into module, run tests, commit**

```bash
git add src/executors/Process.jl src/executors/Pool.jl src/Runner.jl src/CofreeTest.jl test/test_executor.jl
git commit -m "Implement ProcessExecutor with Malt.jl and ExecutorPool"
```

---

## Task 18: TaskExecutor

**Files:**
- Create: `src/executors/Task.jl`
- Modify: `src/CofreeTest.jl`
- Modify: `test/test_executor.jl`

**Step 1: Write failing test**

```julia
# Append to test/test_executor.jl
using CofreeTest: TaskExecutor

@testset "TaskExecutor" begin
    spec = TestSpec(
        name="task test",
        source=LineNumberNode(1, Symbol("test.jl")),
        body=:(1 + 1),
    )
    bus = EventBus()
    exec = TaskExecutor(1)
    outcome, metrics, io = execute!(exec, spec, bus)
    @test outcome isa Pass
end
```

**Step 2: Implement Task.jl**

```julia
# src/executors/Task.jl

using IOCapture

"""
    TaskExecutor

Runs tests as Julia Tasks (green threads). Lightweight but shared memory.
"""
struct TaskExecutor <: AbstractExecutor
    id::Int
end

function execute!(exec::TaskExecutor, spec::TestSpec, bus::EventBus)::Tuple{Outcome, Metrics, CapturedIO}
    captured = IOCapture.capture() do
        mod = Module(gensym(spec.name))
        stats = try
            @timed Core.eval(mod, spec.body)
        catch e
            return (Error(e, catch_backtrace()), Metrics(0.0, 0, 0.0, 0.0, 0.0), CapturedIO("", ""))
        end
        rss = Sys.maxrss() / 1_000_000
        metrics = Metrics(stats.time, stats.bytes, stats.gctime,
            stats.time > 0 ? (stats.gctime / stats.time) * 100 : 0.0, rss)
        (Pass(stats.value), metrics, CapturedIO("", ""))
    end

    result = captured.value
    if result isa Tuple{Outcome, Metrics, CapturedIO}
        outcome, metrics, _ = result
        return (outcome, metrics, CapturedIO(captured.output, ""))
    end
    outcome, metrics, _ = result
    (outcome, metrics, CapturedIO(captured.output, ""))
end
```

**Step 3: Wire into module, run tests, commit**

```bash
git add src/executors/Task.jl src/CofreeTest.jl test/test_executor.jl
git commit -m "Implement TaskExecutor for lightweight green-thread execution"
```

---

## Task 19: @suite Macro & Tree Building

Wire the `@suite` macro to actually build `Cofree{Vector, TestSpec}` trees.

**Files:**
- Modify: `src/Macros.jl` (add @suite, @test as definition macros, @setup, @teardown)
- Create: `test/test_suite_macro.jl`
- Modify: `test/runtests.jl`

**Step 1: Write failing tests**

```julia
# test/test_suite_macro.jl
using Test
using CofreeTest
using CofreeTest: extract, Cofree

@testset "Suite Macro" begin
    @testset "basic @suite with @test children" begin
        tree = @suite "my suite" begin
            @test "first" begin
                @check 1 == 1
            end
            @test "second" begin
                @check true
            end
        end

        @test tree isa Cofree
        @test extract(tree).name == "my suite"
        @test length(tree.tail) == 2
        @test extract(tree.tail[1]).name == "first"
        @test extract(tree.tail[2]).name == "second"
        @test extract(tree.tail[1]).body isa Expr
    end

    @testset "@suite with tags" begin
        tree = @suite "tagged" tags=[:slow, :integration] begin
            @test "t1" begin end
        end

        @test :slow in extract(tree).tags
        @test :integration in extract(tree).tags
    end

    @testset "nested @suite" begin
        tree = @suite "outer" begin
            @suite "inner" begin
                @test "deep" begin
                    @check true
                end
            end
        end

        @test extract(tree).name == "outer"
        @test extract(tree.tail[1]).name == "inner"
        @test extract(tree.tail[1].tail[1]).name == "deep"
    end
end
```

**Step 2: Run tests to verify they fail**

**Step 3: Implement @suite and @test macros for tree building in Macros.jl**

Add to `src/Macros.jl`:

```julia
# --- @suite macro (tree builder) ---

"""
    @suite name [tags=[:tag1]] body

Define a test suite. Returns a `Cofree{Vector, TestSpec}` tree.
The body can contain @test and nested @suite definitions.
"""
macro suite(name, args...)
    _suite_impl(name, args, __source__)
end

function _suite_impl(name, args, source)
    tags = Set{Symbol}()
    body = nothing

    for arg in args
        if arg isa Expr && arg.head == :(=) && arg.args[1] == :tags
            tag_expr = arg.args[2]
            # Handle both [:a, :b] and Set([:a, :b])
            tags_quoted = tag_expr
            return _suite_impl_with_tags(name, tags_quoted, args[end], source)
        else
            body = arg
        end
    end

    if body === nothing
        Base.error("@suite requires a body block")
    end

    _suite_from_body(name, :(Set{Symbol}()), body, source)
end

function _suite_impl_with_tags(name, tags_expr, body, source)
    _suite_from_body(name, :(Set{Symbol}($tags_expr)), body, source)
end

function _suite_from_body(name, tags_expr, body, source)
    # Extract @test and @suite children from the body block
    children_exprs = Expr[]

    if body isa Expr && body.head == :block
        for stmt in body.args
            if stmt isa Expr
                if stmt.head == :macrocall && stmt.args[1] == Symbol("@test")
                    push!(children_exprs, stmt)
                elseif stmt.head == :macrocall && stmt.args[1] == Symbol("@suite")
                    push!(children_exprs, stmt)
                end
            end
        end
    end

    children_code = [esc(c) for c in children_exprs]

    quote
        local _spec = $TestSpec(
            name = $name,
            tags = $tags_expr,
            source = $(QuoteNode(source)),
        )
        local _children = $Cofree[$(children_code...)]
        $Cofree(_spec, _children)
    end
end

# --- @test macro (dual purpose) ---
# When used at top-level in a @suite body, it builds a tree leaf.
# When used inside a test body (with_bus context), it runs an assertion.
# We distinguish by argument count: @test "name" begin...end is a definition,
# @test expr is an assertion.

"""
    @test name body  — define a test leaf (inside @suite)
    @test expr       — assert expression (inside test execution, via compat layer)
"""
macro test(name::String, args...)
    _test_leaf_impl(name, args, __source__)
end

function _test_leaf_impl(name, args, source)
    tags = Set{Symbol}()
    body = nothing

    for arg in args
        if arg isa Expr && arg.head == :(=) && arg.args[1] == :tags
            tag_expr = arg.args[2]
            tags = :(Set{Symbol}($tag_expr))
            continue
        end
        body = arg
    end

    body === nothing && Base.error("@test requires a body block")

    quote
        local _spec = $TestSpec(
            name = $name,
            tags = $(esc(tags isa Expr ? tags : :(Set{Symbol}()))),
            source = $(QuoteNode(source)),
            body = $(QuoteNode(body)),
        )
        $leaf(_spec)
    end
end
```

**Step 4: Run tests, commit**

```bash
git add src/Macros.jl test/test_suite_macro.jl test/runtests.jl
git commit -m "Implement @suite and @test macros for tree building"
```

---

## Task 20: End-to-End Integration Test

A full end-to-end test that exercises the entire pipeline from @suite definition through formatted output.

**Files:**
- Modify: `test/test_integration.jl` (add full e2e test)

**Step 1: Write the test**

```julia
# Append to test/test_integration.jl

@testset "End-to-end: define → schedule → execute → format" begin
    tree = @suite "e2e" begin
        @test "math works" begin
            @check 2 + 2 == 4
            @check 3 * 3 == 9
        end

        @test "strings work" begin
            @check "hello " * "world" == "hello world"
        end

        @suite "nested" begin
            @test "deep test" begin
                @check true
            end
        end
    end

    io = IOBuffer()
    result_tree = runtests(tree; io, color=false, formatter=:terminal)

    # Verify result tree structure
    @test extract(result_tree) isa TestResult
    @test extract(result_tree).spec.name == "e2e"

    # All tests should pass
    for child in result_tree.tail
        r = extract(child)
        if r.spec.body !== nothing
            @test r.outcome isa Pass
        end
    end

    # Verify terminal output
    output = String(take!(io))
    @test contains(output, "CofreeTest")
    @test contains(output, "✔")
    @test contains(output, "math works")
    @test contains(output, "passed")
end
```

**Step 2: Run tests**

Run: `julia --project -e 'using Pkg; Pkg.test()'`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add test/test_integration.jl
git commit -m "Add end-to-end integration test for full pipeline"
```

---

## Task 21: README & Documentation

**Files:**
- Modify: `README.md`

**Step 1: Write README**

The README should include:
- The project tagline and credit to ParallelTestRunner.jl
- Quick start example showing @suite/@test/@check
- Example terminal output (the rich UI mockup)
- API overview
- Installation instructions
- Comparison with Test stdlib

**Step 2: Commit**

```bash
git add README.md
git commit -m "Write comprehensive README with examples and API docs"
```

---

## Dependency Graph

```
Task 1  (skeleton)
  └→ Task 2  (Cofree)
       └→ Task 3  (Types)
            ├→ Task 4  (Events)
            │    ├→ Task 8  (Macros / @check)
            │    │    ├→ Task 7  (InlineExecutor) ← needs @check
            │    │    │    └→ Task 9  (Runner)
            │    │    │         └→ Task 14 (runtests entry)
            │    │    │              └→ Task 20 (e2e test)
            │    │    │                   └→ Task 21 (README)
            │    │    └→ Task 19 (@suite macro)
            │    ├→ Task 10 (DotFormatter)
            │    ├→ Task 11 (Terminal Components)
            │    │    └→ Task 12 (TerminalFormatter)
            │    └→ Task 13 (Compat layer)
            ├→ Task 5  (Discovery)
            ├→ Task 6  (Filter)
            ├→ Task 15 (History)
            ├→ Task 16 (JSON + Multi formatter)
            ├→ Task 17 (ProcessExecutor)
            └→ Task 18 (TaskExecutor)
```

Critical path: 1 → 2 → 3 → 4 → 8 → 7 → 9 → 14 → 20

Parallelizable after Task 4: Tasks 5, 6, 10, 11, 13, 15, 16, 17, 18 can all proceed independently.
