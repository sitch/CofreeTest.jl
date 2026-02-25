"""Test filter: name substrings, required tags, excluded tags."""
@kwdef struct TestFilter
    names::Vector{String} = String[]
    tags::Set{Symbol} = Set{Symbol}()
    exclude_tags::Set{Symbol} = Set{Symbol}()
end

"""
    matches_filter(spec::TestSpec, f::TestFilter) -> Bool

Check if a single test spec passes the filter criteria.
"""
function matches_filter(spec::TestSpec, f::TestFilter)::Bool
    # Name filter: any name substring must match
    if !isempty(f.names)
        any(n -> occursin(n, spec.name), f.names) || return false
    end
    # Tag inclusion: spec must have at least one of the required tags
    if !isempty(f.tags)
        isempty(intersect(spec.tags, f.tags)) && return false
    end
    # Tag exclusion: spec must not have any excluded tags
    if !isempty(f.exclude_tags)
        !isempty(intersect(spec.tags, f.exclude_tags)) && return false
    end
    true
end

"""
    filter_tree(tree::Cofree, f::TestFilter) -> Union{Cofree, Nothing}

Prune a test tree, keeping only nodes that match the filter.
Suite nodes are kept if any descendant matches.
Returns `nothing` if the entire tree is pruned.
"""
function filter_tree(tree::Cofree, f::TestFilter)::Union{Cofree, Nothing}
    # Filter children recursively
    filtered_children = Cofree[]
    for child in tree.tail
        result = filter_tree(child, f)
        result !== nothing && push!(filtered_children, result)
    end

    spec = extract(tree)

    # Leaf node: keep only if it matches
    if isempty(tree.tail)
        return matches_filter(spec, f) ? tree : nothing
    end

    # Suite node: keep if any children survived
    if !isempty(filtered_children)
        return Cofree(spec, filtered_children)
    end

    # Suite with no surviving children — prune it
    nothing
end

"""
    parse_test_args(args::Vector{String}) -> TestFilter

Parse CLI arguments into a TestFilter.
Positional args become name filters. `--tags=a,b` and `--exclude=a,b` for tag filters.
"""
function parse_test_args(args::Vector{String})::TestFilter
    names = String[]
    tags = Set{Symbol}()
    exclude_tags = Set{Symbol}()

    for arg in args
        if startswith(arg, "--tags=")
            tag_str = arg[length("--tags=") + 1:end]
            for t in split(tag_str, ",")
                push!(tags, Symbol(strip(t)))
            end
        elseif startswith(arg, "--exclude=")
            tag_str = arg[length("--exclude=") + 1:end]
            for t in split(tag_str, ",")
                push!(exclude_tags, Symbol(strip(t)))
            end
        else
            push!(names, arg)
        end
    end

    TestFilter(; names, tags, exclude_tags)
end
