"""JSONFormatter — structured JSON output for CI/tooling."""
mutable struct JSONFormatter <: AbstractFormatter
    io::IO
    results::Vector{Dict{String, Any}}
    JSONFormatter(io::IO = stdout) = new(io, Dict{String, Any}[])
end

function handle!(fmt::JSONFormatter, event::TestFinished)
    outcome_str = if event.outcome isa Pass; "pass"
    elseif event.outcome isa Fail; "fail"
    elseif event.outcome isa Error; "error"
    elseif event.outcome isa Skip; "skip"
    else "unknown"
    end

    push!(fmt.results, Dict(
        "name" => event.name,
        "outcome" => outcome_str,
        "duration" => event.metrics.time_s,
        "bytes" => event.metrics.bytes_allocated,
        "timestamp" => event.timestamp,
    ))
end

function _json_escape(s::String)
    s = replace(s, '\\' => "\\\\")
    s = replace(s, '"' => "\\\"")
    s = replace(s, '\n' => "\\n")
    s = replace(s, '\t' => "\\t")
    s = replace(s, '\r' => "\\r")
    s
end

function finalize!(fmt::JSONFormatter)
    # Simple JSON serialization without dependency
    print(fmt.io, "[")
    for (i, r) in enumerate(fmt.results)
        i > 1 && print(fmt.io, ",")
        print(fmt.io, "{")
        entries = sort(collect(pairs(r)); by=first)
        for (j, (k, v)) in enumerate(entries)
            j > 1 && print(fmt.io, ",")
            print(fmt.io, "\"$(_json_escape(string(k)))\":")
            if v isa String
                print(fmt.io, "\"$(_json_escape(v))\"")
            else
                print(fmt.io, v)
            end
        end
        print(fmt.io, "}")
    end
    print(fmt.io, "]")
end
