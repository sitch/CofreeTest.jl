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
