"""
    run_tree(scheduled::Cofree{F, Scheduled}, bus::EventBus) -> Cofree{F, TestResult}

Execute a scheduled test tree, producing a result tree.
Emits events to the bus during execution.
"""
function run_tree(scheduled::Cofree, bus::EventBus)
    sched = extract(scheduled)
    spec = sched.spec

    if spec.body !== nothing
        # Leaf test — execute it
        emit!(bus, TestStarted(spec.name, spec.source, 0, time()))

        executor = _make_executor(sched.executor)
        outcome, metrics, io = execute!(executor, spec, bus)

        emit!(bus, TestFinished(spec.name, outcome, metrics, io, time()))

        result = TestResult(spec, outcome, metrics.time_s, metrics, TestEvent[], io)
        return Cofree(result, [run_tree(c, bus) for c in scheduled.tail])
    end

    # Suite node — run children, aggregate
    emit!(bus, SuiteStarted(spec.name, spec.source, time()))

    result_children = [run_tree(child, bus) for child in scheduled.tail]

    emit!(bus, SuiteFinished(spec.name, time()))

    # Aggregate suite result
    suite_outcome = _aggregate_outcome(result_children)
    suite_metrics = _aggregate_metrics(result_children)
    suite_result = TestResult(spec, suite_outcome, suite_metrics.time_s, suite_metrics, TestEvent[], CapturedIO("", ""))

    Cofree(suite_result, result_children)
end

function _make_executor(kind::Symbol)
    if kind == :inline
        InlineExecutor()
    else
        Base.error("Executor :$kind not yet implemented")
    end
end

function _aggregate_outcome(children::Vector)
    for child in children
        r = extract(child)
        r.outcome isa Error && return Error(ErrorException("suite has errors"), nothing)
        r.outcome isa Fail && return Fail(:suite, :pass, :fail, LineNumberNode(0, :unknown))
    end
    Pass(nothing)
end

function _aggregate_metrics(children::Vector)
    isempty(children) && return Metrics(0.0, 0, 0.0, 0.0, 0.0)
    total_time = sum(extract(c).metrics.time_s for c in children; init=0.0)
    total_bytes = sum(extract(c).metrics.bytes_allocated for c in children; init=0)
    total_gc = sum(extract(c).metrics.gc_time_s for c in children; init=0.0)
    gc_pct = total_time > 0 ? (total_gc / total_time) * 100 : 0.0
    max_rss = maximum(extract(c).metrics.rss_mb for c in children; init=0.0)
    Metrics(total_time, total_bytes, total_gc, gc_pct, max_rss)
end
