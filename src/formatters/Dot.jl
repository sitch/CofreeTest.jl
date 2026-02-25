"""
    DotFormatter

Minimal formatter: prints `.` for pass, `F` for fail, `E` for error, `S` for skip.
"""
mutable struct DotFormatter <: AbstractFormatter
    io::IO
    passed::Int
    failed::Int
    errored::Int
    skipped::Int

    DotFormatter(io::IO = stdout) = new(io, 0, 0, 0, 0)
end

function handle!(fmt::DotFormatter, event::TestFinished)
    outcome = event.outcome
    if outcome isa Pass
        fmt.passed += 1
        print(fmt.io, ".")
    elseif outcome isa Fail
        fmt.failed += 1
        print(fmt.io, "F")
    elseif outcome isa Error
        fmt.errored += 1
        print(fmt.io, "E")
    elseif outcome isa Skip
        fmt.skipped += 1
        print(fmt.io, "S")
    end
end

function finalize!(fmt::DotFormatter)
    total = fmt.passed + fmt.failed + fmt.errored + fmt.skipped
    println(fmt.io)
    println(fmt.io, "$total tests: $(fmt.passed) passed, $(fmt.failed) failed, $(fmt.errored) errored, $(fmt.skipped) skipped")
end
