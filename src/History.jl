using Scratch
using Serialization

const HISTORY_DIR = Ref{String}("")

function _history_dir()
    if isempty(HISTORY_DIR[])
        HISTORY_DIR[] = @get_scratch!("test_history")
    end
    HISTORY_DIR[]
end

function _history_path(mod::Module)
    v = "$(VERSION.major).$(VERSION.minor)"
    joinpath(_history_dir(), "$(nameof(mod))_$v.jls")
end

"""Load historical test durations for a module."""
function load_history(mod::Module)
    path = _history_path(mod)
    isfile(path) || return Dict{String, Float64}()
    try
        result = open(deserialize, path)
        result isa Dict{String, Float64} ? result : Dict{String, Float64}()
    catch
        Dict{String, Float64}()
    end
end

"""Save test durations from a result tree."""
function save_history!(mod::Module, result_tree::Cofree)
    durations = Dict{String, Float64}()
    _collect_durations!(durations, result_tree)
    path = _history_path(mod)
    mkpath(dirname(path))
    open(path, "w") do io
        serialize(io, durations)
    end
end

function _collect_durations!(durations::Dict, tree::Cofree)
    result = extract(tree)
    if result isa TestResult && result.spec.body !== nothing
        durations[result.spec.name] = result.duration
    end
    for child in tree.tail
        _collect_durations!(durations, child)
    end
end
