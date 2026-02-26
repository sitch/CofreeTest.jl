# doctest_runner.jl — Doctest benchmark harnesses and workload generators

using CofreeTest
using CofreeTest: _extract_doctest_blocks, _doctest_block_to_body, _doctest_eval!,
    _doctest_eval_setup!, _format_doctest_output, DocTestBlock,
    schedule_tree, run_tree, EventBus, subscribe!, with_bus, emit!,
    AssertionPassed, current_bus
using IOCapture

# --- Fixture module generator ---

"""
    generate_doctest_module(n_functions; statements_per_block=2)

Create a module with `n_functions` documented functions, each having a
`jldoctest` block with `statements_per_block` input/output pairs.
Returns the module.
"""
function generate_doctest_module(n_functions::Int; statements_per_block::Int=2)
    mod = Module(gensym("DocTestBench"))

    for i in 1:n_functions
        # Build a docstring with a jldoctest block
        pairs = String[]
        for j in 1:statements_per_block
            push!(pairs, "julia> $i * $j + 0\n$(i * j)")
        end
        docstring = """
            bench_fn_$i(x)

        Benchmark fixture function $i.

        ```jldoctest
        $(join(pairs, "\n\n"))
        ```
        """

        # Define the function with a docstring in the module
        fn_name = Symbol("bench_fn_$i")
        Core.eval(mod, :(
            Core.@doc $docstring function $fn_name(x)
                x * $i
            end
        ))
    end

    mod
end

"""
    generate_doctest_docstrings(n; statements_per_block=2) -> Vector{String}

Generate N synthetic docstrings containing jldoctest blocks.
For benchmarking parsing in isolation.
"""
function generate_doctest_docstrings(n::Int; statements_per_block::Int=2)
    docstrings = String[]
    for i in 1:n
        pairs = String[]
        for j in 1:statements_per_block
            push!(pairs, "julia> $i * $j + 0\n$(i * j)")
        end
        ds = """
            fn_$i(x)

        Doc $i.

        ```jldoctest
        $(join(pairs, "\n\n"))
        ```
        """
        push!(docstrings, ds)
    end
    docstrings
end

"""
    generate_doctest_blocks(n; statements_per_block=2) -> Vector{DocTestBlock}

Generate N DocTestBlock objects. For benchmarking body generation in isolation.
"""
function generate_doctest_blocks(n::Int; statements_per_block::Int=2)
    blocks = DocTestBlock[]
    for i in 1:n
        pairs = Tuple{String, String}[]
        for j in 1:statements_per_block
            push!(pairs, ("$i * $j + 0", "$(i * j)"))
        end
        push!(blocks, DocTestBlock(pairs, nothing, LineNumberNode(0, :unknown)))
    end
    blocks
end

# --- Micro-benchmark harnesses ---

function bench_doctest_parsing(docstrings::Vector{String})
    for ds in docstrings
        _extract_doctest_blocks(ds)
    end
    nothing
end

function bench_doctest_body_generation(blocks::Vector{DocTestBlock})
    for block in blocks
        _doctest_block_to_body(block, Main)
    end
    nothing
end

function bench_doctest_discovery(mod::Module)
    discover_doctests(mod)
end

function bench_meta_parse(inputs::Vector{String})
    for input in inputs
        Meta.parse(input)
    end
    nothing
end

function bench_doctest_eval(inputs::Vector{Tuple{String, String}})
    mod = Module(gensym("eval_bench"))
    src = LineNumberNode(0, :unknown)
    for (input, expected) in inputs
        _doctest_eval!(mod, input, expected, src)
    end
    nothing
end

function bench_doctest_full_pipeline(mod::Module)
    tree = discover_doctests(mod)
    run_cofreetest_null(tree)
end

# --- Documenter.jl reference (optional, loaded lazily) ---

const _has_documenter = Ref{Union{Nothing, Bool}}(nothing)

function has_documenter()
    if _has_documenter[] === nothing
        _has_documenter[] = try
            @eval using Documenter
            true
        catch
            false
        end
    end
    _has_documenter[]
end

"""
    bench_documenter_doctest(pkg::Module)

Run Documenter.jl's doctest on a registered package module.
Note: Documenter.doctest() requires a top-level package module, not dynamically created ones.
Use with e.g. `bench_documenter_doctest(CofreeTest)`.
"""
function bench_documenter_doctest(pkg::Module)
    if !has_documenter()
        return nothing
    end
    redirect_stdout(devnull) do
        redirect_stderr(devnull) do
            @eval Documenter.doctest($pkg; manual=false)
        end
    end
    nothing
end
