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
    elseif kind == :process
        ProcessExecutor(0)
    elseif kind == :task
        TaskExecutor(0)
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
    isempty(children) && return Metrics(0.0, 0, 0.0, 0.0, 0.0)
    total_time = sum(extract(c).metrics.time_s for c in children; init=0.0)
    total_bytes = sum(extract(c).metrics.bytes_allocated for c in children; init=0)
    total_gc = sum(extract(c).metrics.gc_time_s for c in children; init=0.0)
    gc_pct = total_time > 0 ? (total_gc / total_time) * 100 : 0.0
    max_rss = maximum(extract(c).metrics.rss_mb for c in children; init=0.0)
    Metrics(total_time, total_bytes, total_gc, gc_pct, max_rss)
end

# --- runtests entry point ---

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
    elseif kind == :json
        JSONFormatter(io)
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

# --- Summary ---

"""
    TestSummary

Summary statistics for a test result tree.

```jldoctest
julia> using CofreeTest

julia> tree = @suite "demo" begin
           @testcase "pass" begin
               @check 1 + 1 == 2
           end
           @testcase "also pass" begin
               @check true
           end
       end

julia> result = runtests(tree; formatter=:dot, io=devnull)

julia> s = test_summary(result)

julia> s.pass
2

julia> s.total
2
```
"""
struct TestSummary
    pass::Int
    fail::Int
    error::Int
    skip::Int
    pending::Int
    timeout::Int
    total::Int
end

function Base.show(io::IO, s::TestSummary)
    parts = String[]
    s.pass > 0 && push!(parts, "$(s.pass) passed")
    s.fail > 0 && push!(parts, "$(s.fail) failed")
    s.error > 0 && push!(parts, "$(s.error) errors")
    s.skip > 0 && push!(parts, "$(s.skip) skipped")
    s.pending > 0 && push!(parts, "$(s.pending) pending")
    s.timeout > 0 && push!(parts, "$(s.timeout) timed out")
    print(io, "TestSummary(", join(parts, ", "), ")")
end

"""
    test_summary(result::Cofree) -> TestSummary

Count test outcomes in a result tree.

Only counts leaf tests (nodes with a test body), not suite aggregates.
"""
function test_summary(result::Cofree)
    counts = Dict{Symbol, Int}(
        :pass => 0, :fail => 0, :error => 0,
        :skip => 0, :pending => 0, :timeout => 0
    )
    _count_outcomes!(counts, result)
    TestSummary(
        counts[:pass], counts[:fail], counts[:error],
        counts[:skip], counts[:pending], counts[:timeout],
        sum(values(counts))
    )
end

function _count_outcomes!(counts::Dict{Symbol, Int}, tree::Cofree)
    r = extract(tree)
    if r isa TestResult && r.spec.body !== nothing
        if r.outcome isa Pass
            counts[:pass] += 1
        elseif r.outcome isa Fail
            counts[:fail] += 1
        elseif r.outcome isa Error
            counts[:error] += 1
        elseif r.outcome isa Skip
            counts[:skip] += 1
        elseif r.outcome isa Pending
            counts[:pending] += 1
        elseif r.outcome isa Timeout
            counts[:timeout] += 1
        end
    end
    for child in tree.tail
        _count_outcomes!(counts, child)
    end
end
