mutable struct TerminalFormatter <: AbstractFormatter
    io::IO
    color::Bool
    verbose::Bool
    lock::ReentrantLock
    total::Int
    completed::Int
    passed::Int
    failed::Int
    errored::Int
    skipped::Int
    start_time::Float64
    failures::Vector{TestFinished}
    durations::Vector{Float64}
    running::Dict{Int, Tuple{String, Float64}}  # worker_id => (name, start_time)

    function TerminalFormatter(io::IO = stdout;
        color::Bool = get(io, :color, false),
        verbose::Bool = false,
    )
        new(io, color, verbose, ReentrantLock(),
            0, 0, 0, 0, 0, 0, time(),
            TestFinished[], Float64[],
            Dict{Int, Tuple{String, Float64}}())
    end
end

"""Initialize the formatter with total test count and render header."""
function start!(fmt::TerminalFormatter, total::Int)
    fmt.total = total
    fmt.start_time = time()
    _render_header(fmt)
end

function _render_header(fmt::TerminalFormatter)
    w = try
        displaysize(fmt.io)[2]
    catch
        72
    end
    w = min(w, 72)
    println(fmt.io, " $(BOX_TL)$(BOX_H ^ (w - 2))$(BOX_TR)")
    title = "  ☕ CofreeTest"
    padding = w - length(title) - 3
    println(fmt.io, " $(BOX_V)$(title)$(repeat(' ', max(1, padding)))$(BOX_V)")
    println(fmt.io, " $(BOX_BL)$(BOX_H ^ (w - 2))$(BOX_BR)")
    println(fmt.io)
end

function handle!(fmt::TerminalFormatter, event::TestStarted)
    lock(fmt.lock) do
        fmt.running[event.worker_id] = (event.name, event.timestamp)
    end
end

function handle!(fmt::TerminalFormatter, event::TestFinished)
    lock(fmt.lock) do
        fmt.completed += 1
        push!(fmt.durations, event.metrics.time_s)

        outcome = event.outcome
        if outcome isa Pass
            fmt.passed += 1
            _render_pass(fmt, event)
        elseif outcome isa Fail
            fmt.failed += 1
            push!(fmt.failures, event)
            _render_fail(fmt, event)
        elseif outcome isa Error
            fmt.errored += 1
            push!(fmt.failures, event)
            _render_error(fmt, event)
        elseif outcome isa Skip
            fmt.skipped += 1
            _render_skip(fmt, event)
        end
    end
end

function _styled(fmt::TerminalFormatter, text, color; bold=false)
    if fmt.color
        printstyled(fmt.io, text; color, bold)
    else
        print(fmt.io, text)
    end
end

function _render_pass(fmt::TerminalFormatter, event::TestFinished)
    _styled(fmt, "  ✔ ", :green)
    dur = format_duration(event.metrics.time_s)
    mem = format_bytes(event.metrics.bytes_allocated)
    leader = dot_leader(event.name, "$dur    $mem"; width=66)
    println(fmt.io, leader)
end

function _render_fail(fmt::TerminalFormatter, event::TestFinished)
    _styled(fmt, "  ✘ ", :red)
    dur = format_duration(event.metrics.time_s)
    mem = format_bytes(event.metrics.bytes_allocated)
    leader = dot_leader(event.name, "$dur    $mem"; width=66)
    println(fmt.io, leader)
    println(fmt.io)

    # Failure detail box
    fail = event.outcome::Fail
    lines = String[]
    push!(lines, "$(fail.source.file):$(fail.source.line)")
    push!(lines, "")
    push!(lines, "  Expected │ $(fail.expected)")
    push!(lines, "  Got      │ $(fail.got)")
    print(fmt.io, box("Failure", lines; width=66))
    println(fmt.io)
end

function _render_error(fmt::TerminalFormatter, event::TestFinished)
    _styled(fmt, "  ✘ ", :red; bold=true)
    dur = format_duration(event.metrics.time_s)
    leader = dot_leader(event.name, dur; width=66)
    println(fmt.io, leader)
    println(fmt.io)

    err = event.outcome::Error
    lines = ["$(typeof(err.exception)): $(err.exception)"]
    print(fmt.io, box("Error", lines; width=66))
    println(fmt.io)
end

function _render_skip(fmt::TerminalFormatter, event::TestFinished)
    _styled(fmt, "  ○ ", :light_black)
    skip = event.outcome::Skip
    println(fmt.io, "$(event.name) — $(skip.reason)")
end

function finalize!(fmt::TerminalFormatter)
    elapsed = time() - fmt.start_time
    println(fmt.io)

    # Summary line
    parts = String[]
    fmt.passed > 0 && push!(parts, "$(fmt.passed) passed")
    fmt.failed > 0 && push!(parts, "$(fmt.failed) failed")
    fmt.errored > 0 && push!(parts, "$(fmt.errored) errored")
    fmt.skipped > 0 && push!(parts, "$(fmt.skipped) skipped")

    summary = "  " * join(parts, "   ") * "    $(format_duration(elapsed)) total"

    if fmt.color
        fmt.failed + fmt.errored > 0 ? _styled(fmt, "  ✘ ", :red; bold=true) : _styled(fmt, "  ✔ ", :green; bold=true)
    end
    println(fmt.io, summary)
end
