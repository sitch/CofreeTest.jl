# stdlib_runner.jl — Run Test stdlib benchmarks

function run_stdlib(f::Function)
    f()
    nothing
end
