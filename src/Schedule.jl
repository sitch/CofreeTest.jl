"""
    schedule_tree(tree::Cofree; executor=:inline, history=Dict{String,Float64}()) -> Cofree{F, Scheduled}

Natural transformation: TestSpec → Scheduled.
Assigns executor type and priority based on historical durations.
"""
function schedule_tree(
    tree::Cofree;
    executor::Symbol = :inline,
    history::Dict{String, Float64} = Dict{String, Float64}(),
)
    hoist(tree) do spec
        priority = get(history, spec.name, Inf)
        Scheduled(spec, executor, nothing, priority)
    end
end
