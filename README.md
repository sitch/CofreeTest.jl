# CofreeTest.jl

Cofree testing -- parallel, observable, beautifully formatted.

A test framework for Julia built on cofree comonads. Tests form a tree (`Cofree{Vector, TestSpec}`) that flows through a pipeline of natural transformations: **discover -> filter -> schedule -> execute -> format**.

The parallel execution architecture is adapted from [ParallelTestRunner.jl](https://github.com/JuliaTesting/ParallelTestRunner.jl) by @maleadt and contributors.

## Quick Start

```julia
using CofreeTest

tree = @suite "my app" begin
    @testcase "arithmetic" begin
        @check 1 + 1 == 2
        @check 3 * 7 == 21
    end

    @testcase "strings" begin
        @check "hello " * "world" == "hello world"
    end

    @suite "edge cases" begin
        @testcase "empty" begin
            @check isempty([])
        end
    end
end

runtests(tree)
```

## Assertions

CofreeTest provides `@check` macros that emit structured events instead of throwing on failure:

```julia
@check expr              # assert truthy
@check a == b            # comparison with rich diff on failure
@check_throws ErrorException error("boom")
@check_broken 1 == 2     # expected failure (known bug)
@check_skip "not yet"    # skip with reason
```

## Executors

Three execution strategies, chosen per-run:

| Executor | Isolation | Overhead | Use Case |
|----------|-----------|----------|----------|
| `:inline` | None (same task) | Minimal | Debugging, fast iteration |
| `:task` | Green thread | Low | Concurrent I/O-bound tests |
| `:process` | OS process (Malt.jl) | Higher | CPU-bound, OOM-safe, full isolation |

```julia
runtests(tree; executor=:process)
```

## Formatters

```julia
runtests(tree; formatter=:terminal)  # Rich terminal UI (default)
runtests(tree; formatter=:dot)       # Minimal dot output
runtests(tree; formatter=:json)      # Machine-readable JSON
```

## Filtering

```julia
using CofreeTest: TestFilter, filter_tree

f = TestFilter(names=["arithmetic"], tags=Set([:fast]))
filtered = filter_tree(tree, f)
runtests(filtered)
```

## `@test` Compatibility

CofreeTest intercepts stdlib `@test` results via `CofreeTestSet`, so existing `@test` assertions emit structured events alongside `@check`:

```julia
using Test
using CofreeTest: CofreeTestSet, EventBus

bus = EventBus()
ts = CofreeTestSet(bus, "compat")
Test.push_testset(ts)
@test 1 + 1 == 2  # emits AssertionPassed event
Test.pop_testset()
```

## Architecture

The core data structure is `Cofree{F, A}` -- a cofree comonad that pairs an annotation (`head :: A`) with a branching structure (`tail :: F`). Test trees are `Cofree{Vector, TestSpec}` where leaves have a non-nothing `body` field.

The pipeline transforms annotations via natural transformations:

```
TestSpec -> Scheduled -> TestResult
```

Each stage preserves the tree shape via `hoist`:

```julia
scheduled = hoist(spec -> Scheduled(spec, :inline, 0.0), tree)
```

Events flow through an `EventBus` with pluggable `Subscriber`s. Formatters implement `Subscriber` to render output as tests execute.

## Installation

```julia
] add CofreeTest
```

## License

MIT
