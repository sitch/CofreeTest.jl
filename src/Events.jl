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
