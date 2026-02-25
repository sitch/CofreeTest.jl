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
