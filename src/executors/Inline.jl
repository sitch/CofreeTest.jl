using IOCapture

"""
    InlineExecutor

Runs tests in the current process and task. No isolation.
Useful for debugging and as the simplest executor implementation.
"""
struct InlineExecutor <: AbstractExecutor end

function execute!(::InlineExecutor, spec::TestSpec, bus::EventBus)::Tuple{Outcome, Metrics, CapturedIO}
    captured = IOCapture.capture() do
        mod = Module(gensym(spec.name))

        # Make CofreeTest available in the test module
        Core.eval(mod, :(using CofreeTest))

        # Set up event bus access for @check macros
        Core.eval(mod, :(const __cofreetest_bus__ = $bus))

        stats = try
            @timed with_bus(bus) do
                Core.eval(mod, spec.body)
            end
        catch e
            return (Error(e, catch_backtrace()),
                    Metrics(0.0, 0, 0.0, 0.0, 0.0),
                    CapturedIO("", ""))
        end

        rss = Sys.maxrss() / 1_000_000  # bytes to MB
        metrics = Metrics(
            stats.time,
            stats.bytes,
            stats.gctime,
            stats.time > 0 ? (stats.gctime / stats.time) * 100 : 0.0,
            rss,
        )

        # Check for assertion failures in events
        (Pass(stats.value), metrics, CapturedIO("", ""))
    end

    # If the body returned early (Error case), the result is already a tuple
    result = captured.value
    if result isa Tuple{Outcome, Metrics, CapturedIO}
        outcome, metrics, _ = result
        return (outcome, metrics, CapturedIO(captured.output, ""))
    end

    outcome, metrics, _ = result
    (outcome, metrics, CapturedIO(captured.output, ""))
end
