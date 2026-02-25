using IOCapture

"""
    TaskExecutor

Runs tests as Julia Tasks (green threads). Lightweight but shared memory.
"""
struct TaskExecutor <: AbstractExecutor
    id::Int
end

function execute!(exec::TaskExecutor, spec::TestSpec, bus::EventBus)::Tuple{Outcome, Metrics, CapturedIO}
    captured = IOCapture.capture() do
        mod = Module(gensym(spec.name))
        stats = try
            @timed Core.eval(mod, spec.body)
        catch e
            return (Error(e, catch_backtrace()), Metrics(0.0, 0, 0.0, 0.0, 0.0), CapturedIO("", ""))
        end
        rss = Sys.maxrss() / 1_000_000
        metrics = Metrics(stats.time, stats.bytes, stats.gctime,
            stats.time > 0 ? (stats.gctime / stats.time) * 100 : 0.0, rss)
        (Pass(stats.value), metrics, CapturedIO("", ""))
    end

    result = captured.value
    if result isa Tuple{Outcome, Metrics, CapturedIO}
        outcome, metrics, _ = result
        return (outcome, metrics, CapturedIO(captured.output, ""))
    end
    outcome, metrics, _ = result
    (outcome, metrics, CapturedIO(captured.output, ""))
end
