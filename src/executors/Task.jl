using IOCapture

"""
    TaskExecutor

Runs tests as Julia Tasks (green threads). Lightweight but shared memory.
"""
struct TaskExecutor <: AbstractExecutor
    id::Int
end

function execute!(exec::TaskExecutor, spec::TestSpec, bus::EventBus)::Tuple{Outcome, Metrics, CapturedIO}
    # Track assertion events to determine outcome
    collector = CollectorSubscriber()
    subscribe!(bus, collector)

    captured = IOCapture.capture() do
        mod = Module(gensym(spec.name))
        Core.eval(mod, :(using CofreeTest))

        stats = try
            @timed with_bus(bus) do
                Core.eval(mod, spec.body)
            end
        catch e
            return (Error(e, catch_backtrace()), Metrics(0.0, 0, 0.0, 0.0, 0.0), CapturedIO("", ""))
        end
        rss = Sys.maxrss() / 1_000_000
        metrics = Metrics(stats.time, stats.bytes, stats.gctime,
            stats.time > 0 ? (stats.gctime / stats.time) * 100 : 0.0, rss)
        outcome = _outcome_from_events(collector.events, stats.value)
        (outcome, metrics, CapturedIO("", ""))
    end

    result = captured.value
    if result isa Tuple{Outcome, Metrics, CapturedIO}
        outcome, metrics, _ = result
        return (outcome, metrics, CapturedIO(captured.output, ""))
    end
    outcome, metrics, _ = result
    (outcome, metrics, CapturedIO(captured.output, ""))
end
