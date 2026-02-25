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
