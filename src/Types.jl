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
