"""MultiFormatter — dispatch events to multiple formatters."""
struct MultiFormatter <: AbstractFormatter
    formatters::Vector{AbstractFormatter}
end

function handle!(fmt::MultiFormatter, event::TestEvent)
    for f in fmt.formatters
        handle!(f, event)
    end
end

function finalize!(fmt::MultiFormatter)
    for f in fmt.formatters
        finalize!(f)
    end
end
