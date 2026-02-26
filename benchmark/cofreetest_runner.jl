# cofreetest_runner.jl — CofreeTest benchmark harnesses

using CofreeTest
using CofreeTest: AbstractFormatter, TestEvent, schedule_tree, run_tree,
    EventBus, subscribe!, emit!, finalize!, CollectorSubscriber
using IOCapture

# --- NullFormatter ---

struct NullFormatter <: AbstractFormatter end

# --- Runners ---

function run_cofreetest_null(tree::Cofree)
    scheduled = schedule_tree(tree)
    bus = EventBus()
    fmt = NullFormatter()
    subscribe!(bus, fmt)
    result = run_tree(scheduled, bus)
    finalize!(fmt)
    result
end

function run_cofreetest_formatter(tree::Cofree, formatter_sym::Symbol)
    io = IOBuffer()
    runtests(tree; io, color=false, formatter=formatter_sym, verbose=false)
    nothing
end

function run_cofreetest_task(tree::Cofree)
    scheduled = schedule_tree(tree; executor=:task)
    bus = EventBus()
    subscribe!(bus, NullFormatter())
    run_tree(scheduled, bus)
end

function run_cofreetest_process(tree::Cofree)
    scheduled = schedule_tree(tree; executor=:process)
    bus = EventBus()
    subscribe!(bus, NullFormatter())
    run_tree(scheduled, bus)
end

function run_cofreetest_schedule_only(tree::Cofree)
    schedule_tree(tree)
end

# --- Per-phase micro-benchmarks ---

function bench_tree_construction(n::Int)
    [leaf(TestSpec(name="test_$i", body=:(@check true))) for i in 1:n]
    nothing
end

function bench_event_emission(n::Int)
    bus = EventBus()
    subscribe!(bus, NullFormatter())
    evt = TestStarted("t", LineNumberNode(0, :unknown), 0, time())
    for _ in 1:n
        emit!(bus, evt)
    end
    nothing
end

function bench_module_creation(n::Int)
    for i in 1:n
        mod = Module(gensym("bench_$i"))
        Core.eval(mod, :(1 + 1))
    end
    nothing
end

function bench_iocapture(n::Int)
    for _ in 1:n
        IOCapture.capture() do
            nothing
        end
    end
    nothing
end
