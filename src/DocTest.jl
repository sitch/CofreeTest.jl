using IOCapture

# --- Types ---

"""
    DocTestBlock

A parsed `jldoctest` block from a docstring. Contains input/expected-output pairs
and optional metadata.

- `pairs`: Vector of `(input, expected_output)` tuples. Empty expected means setup-only.
- `name`: Named group (from `` ```jldoctest groupname ``), or `nothing`.
- `source`: Source location for error reporting.
"""
struct DocTestBlock
    pairs::Vector{Tuple{String, String}}
    name::Union{String, Nothing}
    source::LineNumberNode
end

# --- Parsing ---

const _DOCTEST_FENCE_RE = r"```jldoctest(?:\s+(\w+))?\s*\n(.*?)```"s

"""
    _extract_doctest_blocks(docstr::AbstractString) -> Vector{DocTestBlock}

Parse a docstring and extract all `jldoctest` fenced code blocks.
Each block is parsed for `julia> ` prompt lines and expected output.
"""
function _extract_doctest_blocks(docstr::AbstractString)::Vector{DocTestBlock}
    blocks = DocTestBlock[]
    for m in eachmatch(_DOCTEST_FENCE_RE, docstr)
        group_name = m.captures[1]
        content = m.captures[2]
        pairs = _parse_repl_pairs(content)
        isempty(pairs) && continue
        push!(blocks, DocTestBlock(
            pairs,
            group_name === nothing ? nothing : String(group_name),
            LineNumberNode(0, :unknown),
        ))
    end
    blocks
end

"""
    _parse_repl_pairs(content::String) -> Vector{Tuple{String, String}}

Parse the interior of a jldoctest block into (input, expected_output) pairs.
Lines starting with `julia> ` begin a new input. Continuation lines (starting with
whitespace after the prompt column) are appended. Everything else is expected output.
"""
function _parse_repl_pairs(content::AbstractString)::Vector{Tuple{String, String}}
    pairs = Tuple{String, String}[]
    current_input = nothing
    output_lines = String[]

    for line in split(content, '\n')
        prompt_match = match(r"^julia>\s?(.*)", line)
        if prompt_match !== nothing
            # Flush previous pair
            if current_input !== nothing
                push!(pairs, (current_input, _join_output(output_lines)))
            end
            current_input = String(prompt_match.captures[1])
            output_lines = String[]
        elseif current_input !== nothing && match(r"^\s{6,}", line) !== nothing
            # Continuation line (indented with 6+ spaces)
            current_input *= "\n" * strip(line)
        elseif current_input !== nothing
            # Expected output line (or blank between statements)
            push!(output_lines, line)
        end
    end

    # Flush last pair
    if current_input !== nothing
        push!(pairs, (current_input, _join_output(output_lines)))
    end

    pairs
end

function _join_output(lines::Vector{String})::String
    # Strip trailing empty lines, then join
    while !isempty(lines) && isempty(strip(lines[end]))
        pop!(lines)
    end
    while !isempty(lines) && isempty(strip(lines[1]))
        popfirst!(lines)
    end
    join(lines, "\n")
end

# --- Body generation ---

"""
    _doctest_block_to_body(block::DocTestBlock, parent_mod::Module) -> Expr

Convert a DocTestBlock into an Expr suitable for `TestSpec.body`.
Each input/expected pair becomes a call to `_doctest_eval!` (or `_doctest_eval_setup!`
for pairs with no expected output).

The `parent_mod` reference is embedded directly in the expression so that
doctests evaluate in a context where the parent module's names are available.
"""
function _doctest_block_to_body(block::DocTestBlock, parent_mod::Module)::Expr
    stmts = Expr[]
    src = block.source
    for (input, expected) in block.pairs
        if isempty(expected)
            push!(stmts, :(CofreeTest._doctest_eval_setup!($(parent_mod), $(input))))
        else
            push!(stmts, :(CofreeTest._doctest_eval!($(parent_mod), $(input), $(expected), $(QuoteNode(src)))))
        end
    end
    Expr(:block, stmts...)
end

# --- Runtime helpers (called during test execution) ---

"""
    _format_doctest_output(value, printed::String) -> String

Combine a return value and captured stdout into the output string for comparison.
"""
function _format_doctest_output(value, printed::String)::String
    cleaned_print = rstrip(printed, '\n')
    if value !== nothing && isempty(cleaned_print)
        repr(MIME("text/plain"), value)
    elseif value === nothing || value === nothing
        cleaned_print
    else
        cleaned_print * "\n" * repr(MIME("text/plain"), value)
    end
end

"""
    _doctest_eval!(mod::Module, input::String, expected::String, source::LineNumberNode)

Runtime helper: evaluate `input` in `mod`'s scope, capture output, compare to `expected`.
Emits `AssertionPassed` or `AssertionFailed` to the current event bus.
"""
function _doctest_eval!(mod::Module, input::String, expected::String, source::LineNumberNode)
    bus = current_bus()

    local captured
    try
        captured = IOCapture.capture() do
            Base.eval(mod, Meta.parse(input))
        end
    catch e
        emit!(bus, AssertionFailed(
            Meta.parse(input), expected, sprint(showerror, e), source, time()))
        return
    end

    actual = _format_doctest_output(captured.value, captured.output)

    if rstrip(actual) == rstrip(expected)
        emit!(bus, AssertionPassed(
            Meta.parse(input), actual, source, time()))
    else
        emit!(bus, AssertionFailed(
            Meta.parse(input), expected, actual, source, time()))
    end
end

"""
    _doctest_eval_setup!(mod::Module, input::String)

Runtime helper: evaluate `input` in `mod`'s scope without checking output.
Used for setup-only statements (no expected output).
"""
function _doctest_eval_setup!(mod::Module, input::String)
    Base.eval(mod, Meta.parse(input))
    nothing
end

# --- Discovery ---

"""
    discover_doctests(mod::Module; tags=Set([:doctest])) -> Cofree{Vector, TestSpec}

Discover all `jldoctest` blocks in docstrings of `mod` and build a Cofree test tree.

The tree structure is:
- Root suite: "Doctests: ModuleName"
  - Per-symbol suites: "ModuleName.symbol_name"
    - Per-block leaves: "symbol_name doctest #1", etc.
"""
function discover_doctests(mod::Module; tags::Set{Symbol}=Set{Symbol}([:doctest]))
    children = Cofree[]

    md = Base.Docs.meta(mod; autoinit=false)
    md === nothing && return _empty_doctest_tree(mod, tags)

    for (binding, multidoc) in md
        sym_name = string(binding.var)
        full_name = "$(nameof(mod)).$sym_name"

        # Get all docstrings for this binding
        docstrings = _get_docstrings(multidoc)
        all_blocks = DocTestBlock[]
        for ds in docstrings
            append!(all_blocks, _extract_doctest_blocks(ds))
        end

        isempty(all_blocks) && continue

        # Build leaf TestSpecs for each block
        block_children = Cofree[]
        for (i, block) in enumerate(all_blocks)
            name = "$sym_name doctest #$i"
            body = _doctest_block_to_body(block, mod)
            spec = TestSpec(name=name, tags=tags, source=block.source, body=body)
            push!(block_children, leaf(spec))
        end

        # Symbol-level suite
        sym_spec = TestSpec(name=full_name, tags=tags)
        push!(children, Cofree(sym_spec, block_children))
    end

    # Sort children by name for deterministic order
    sort!(children; by=c -> extract(c).name)

    root_spec = TestSpec(name="Doctests: $(nameof(mod))", tags=tags)
    Cofree(root_spec, children)
end

function _empty_doctest_tree(mod::Module, tags::Set{Symbol})
    root_spec = TestSpec(name="Doctests: $(nameof(mod))", tags=tags)
    Cofree(root_spec, Cofree[])
end

function _get_docstrings(multidoc)::Vector{String}
    result = String[]
    if multidoc isa Base.Docs.MultiDoc
        for (_, docstr) in multidoc.docs
            push!(result, join(docstr.text))
        end
    elseif multidoc isa Base.Docs.DocStr
        push!(result, join(multidoc.text))
    else
        # Try to convert to string
        s = string(multidoc)
        isempty(s) || push!(result, s)
    end
    result
end

# --- @doctest macro ---

"""
    @doctest Module

Discover and return a doctest tree for `Module`.
Can be used standalone or inside a `@suite` block.

# Example

```julia
tree = @doctest MyModule
runtests(tree)
```

Or combined with other tests:

```julia
tree = @suite "MyPackage" begin
    @doctest MyModule
    @testcase "unit test" begin
        @check 1 + 1 == 2
    end
end
runtests(tree)
```
"""
macro doctest(mod)
    :(discover_doctests($(esc(mod))))
end
