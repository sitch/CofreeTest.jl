"""
    is_test_file(filename::String) -> Bool

Returns true if the filename matches test file conventions:
starts with `test_` or ends with `_test` (before .jl extension).
Excludes `runtests.jl`.
"""
function is_test_file(filename::String)::Bool
    filename == "runtests.jl" && return false
    endswith(filename, ".jl") || return false
    base = first(splitext(filename))
    startswith(base, "test_") || endswith(base, "_test")
end

"""
    discover_test_files(dir::String) -> Vector{String}

Recursively find all test files in `dir` matching the `test_`/`_test` convention.
Returns sorted absolute paths.
"""
function discover_test_files(dir::String)::Vector{String}
    files = String[]
    for (root, _, filenames) in walkdir(dir)
        for f in filenames
            if is_test_file(f)
                push!(files, joinpath(root, f))
            end
        end
    end
    sort!(files)
end
