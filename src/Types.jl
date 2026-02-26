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

Base.show(io::IO, ::Pass) = print(io, "Pass")
Base.show(io::IO, ::Fail) = print(io, "Fail")
Base.show(io::IO, o::Error) = print(io, "Error(", typeof(o.exception).name.name, ")")
Base.show(io::IO, o::Skip) = print(io, "Skip(\"", o.reason, "\")")
Base.show(io::IO, o::Pending) = print(io, "Pending(\"", o.reason, "\")")
Base.show(io::IO, o::Timeout) = print(io, "Timeout(", o.limit, "s)")

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

function Base.show(io::IO, s::TestSpec)
    kind = s.body === nothing ? "suite" : "test"
    tags_str = isempty(s.tags) ? "" : " " * join(sort(collect(s.tags)), ",")
    print(io, "TestSpec(\"", s.name, "\"", tags_str, " [", kind, "])")
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

function Base.show(io::IO, r::TestResult)
    status = r.outcome isa Pass ? "✓" :
             r.outcome isa Fail ? "✗" :
             r.outcome isa Error ? "!" :
             r.outcome isa Skip ? "⊘" :
             r.outcome isa Pending ? "…" :
             r.outcome isa Timeout ? "⏱" : "?"
    print(io, status, " ", r.spec.name)
end
