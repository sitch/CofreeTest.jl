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

Test trees display as readable hierarchies in the REPL:

```
"my app" [suite]
├─ "arithmetic" [test]
├─ "strings" [test]
└─ "edge cases" [suite]
   └─ "empty" [test]
```

After execution, results show pass/fail status:

```
✓ my app
├─ ✓ arithmetic
├─ ✓ strings
└─ ✓ edge cases
   └─ ✓ empty
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

## Doc Testing

CofreeTest can discover and run code examples embedded in docstrings. Write standard `jldoctest` blocks (compatible with Documenter.jl) and CofreeTest runs them through the full pipeline with event streaming, formatters, and parallel execution.

### Writing testable docstrings

Add `jldoctest` fenced code blocks with `julia>` prompts to your docstrings:

````julia
"""
    double(x)

Double the input.

```jldoctest
julia> double(3)
6

julia> double(0)
0
```
"""
double(x) = 2x
````

Statements share state within a block — variables defined earlier are available later:

````julia
"""
```jldoctest
julia> x = 10
10

julia> x + 5
15
```
"""
````

Lines without expected output act as setup:

````julia
"""
```jldoctest
julia> data = [1, 2, 3]

julia> sum(data)
6
```
"""
````

### Running doctests

```julia
using CofreeTest

tree = discover_doctests(MyModule)
runtests(tree)
```

Or use the `@doctest` macro inside a `@suite` to combine with regular tests:

```julia
tree = @suite "MyPackage" begin
    @doctest MyModule

    @testcase "unit test" begin
        @check 1 + 1 == 2
    end
end

runtests(tree)
```

Doctests support all the same options as regular tests — executors, formatters, filtering by tags:

```julia
runtests(tree; executor=:task, formatter=:terminal, verbose=true)
```

## Architecture

The core data structure is `Cofree{F, A}` -- a cofree comonad that pairs an annotation (`head :: A`) with a branching structure (`tail :: F`). Test trees are `Cofree{Vector, TestSpec}` where leaves have a non-nothing `body` field.

The pipeline transforms annotations via natural transformations:

```
TestSpec -> Scheduled -> TestResult
```

Each stage preserves the tree shape via `hoist`:

```julia
scheduled = hoist(spec -> Scheduled(spec, :inline, nothing, 0.0), tree)
```

Events flow through an `EventBus` with pluggable `Subscriber`s. Formatters implement `Subscriber` to render output as tests execute.

## Installation

```julia
] add CofreeTest
```

## License

MIT
