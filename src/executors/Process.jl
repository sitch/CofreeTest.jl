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
        # Use remote_eval_fetch with a quoted expression to avoid closure
        # serialization issues (CofreeTest module can't be deserialized on worker)
        worker_expr = quote
            let _body = $(QuoteNode(spec.body)),
                _name = $(spec.name)
                mod = Module(gensym(_name))
                stats = try
                    @timed Core.eval(mod, _body)
                catch e
                    (nothing, (:error, string(e), 0.0, 0, 0.0, 0.0))
                end
                if stats isa Tuple{Nothing, Tuple}
                    stats[2]
                else
                    rss = Sys.maxrss() / 1_000_000
                    (:pass, stats.time, stats.bytes, stats.gctime, rss)
                end
            end
        end

        raw = Malt.remote_eval_fetch(exec.worker, worker_expr)

        if raw[1] === :error
            err_msg = raw[2]
            return (Error(ErrorException(err_msg), nothing),
                    Metrics(0.0, 0, 0.0, 0.0, 0.0), CapturedIO("", ""))
        end

        _, time_s, bytes, gc_time, rss = raw
        gc_pct = time_s > 0 ? (gc_time / time_s) * 100 : 0.0
        metrics = Metrics(time_s, bytes, gc_time, gc_pct, rss)

        # Check RSS for recycling
        if rss > exec.max_rss_mb
            recycle!(exec)
        end

        (Pass(nothing), metrics, CapturedIO("", ""))
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
