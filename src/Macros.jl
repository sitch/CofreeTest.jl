# --- Bus context (task-local storage) ---

using Base.ScopedValues: ScopedValue, @with

const _CURRENT_BUS = ScopedValue{Union{EventBus, Nothing}}(nothing)

"""
    with_bus(f, bus::EventBus)

Run `f` with `bus` as the current event bus for @check macros.
"""
function with_bus(f, bus::EventBus)
    @with _CURRENT_BUS => bus f()
end

function current_bus()::EventBus
    bus = _CURRENT_BUS[]
    bus === nothing && Base.error("@check used outside of a CofreeTest execution context")
    bus
end

# --- @check macro ---

"""
    @check expr

Assert that `expr` is true. Emits AssertionPassed or AssertionFailed to the event bus.
For comparison expressions (==, !=, <, etc.), captures both sides for rich failure output.
"""
macro check(expr)
    check_impl(expr, __source__)
end

function check_impl(expr, source)
    if expr isa Expr && expr.head == :call && length(expr.args) == 3
        op = expr.args[1]
        if op in (:(==), :(!=), :(<), :(>), :(<=), :(>=), :isequal, :isapprox, :(===))
            lhs = expr.args[2]
            rhs = expr.args[3]
            return quote
                local _lhs = $(esc(lhs))
                local _rhs = $(esc(rhs))
                local _result = $(esc(op))(_lhs, _rhs)
                local _bus = $current_bus()
                if _result
                    $emit!(_bus, $AssertionPassed(
                        $(QuoteNode(expr)), _result, $(QuoteNode(source)), time()))
                else
                    $emit!(_bus, $AssertionFailed(
                        $(QuoteNode(expr)), _rhs, _lhs, $(QuoteNode(source)), time()))
                end
                _result
            end
        end
    end

    # Fallback: non-comparison expression
    quote
        local _result = $(esc(expr))
        local _bus = $current_bus()
        if _result
            $emit!(_bus, $AssertionPassed(
                $(QuoteNode(expr)), _result, $(QuoteNode(source)), time()))
        else
            $emit!(_bus, $AssertionFailed(
                $(QuoteNode(expr)), true, _result, $(QuoteNode(source)), time()))
        end
        _result
    end
end

# --- @check_throws macro ---

"""
    @check_throws ExceptionType expr

Assert that `expr` throws an exception of type `ExceptionType`.
"""
macro check_throws(extype, expr)
    quote
        local _bus = $current_bus()
        local _threw = false
        local _exc = nothing
        try
            $(esc(expr))
        catch e
            _threw = true
            _exc = e
        end
        if _threw && _exc isa $(esc(extype))
            $emit!(_bus, $AssertionPassed(
                $(QuoteNode(expr)), _exc, $(QuoteNode(__source__)), time()))
        elseif _threw
            $emit!(_bus, $AssertionFailed(
                $(QuoteNode(expr)), $(esc(extype)), typeof(_exc), $(QuoteNode(__source__)), time()))
        else
            $emit!(_bus, $AssertionFailed(
                $(QuoteNode(expr)), $(esc(extype)), :no_exception, $(QuoteNode(__source__)), time()))
        end
        _threw && _exc isa $(esc(extype))
    end
end

# --- @check_broken macro ---

"""
    @check_broken expr

Mark a test as expected to fail. Passes if the expression fails, fails if it succeeds.
"""
macro check_broken(expr)
    quote
        local _bus = $current_bus()
        local _result = try
            $(esc(expr))
        catch
            false
        end
        if !_result
            # Expected failure — this is a pass
            $emit!(_bus, $AssertionPassed(
                $(QuoteNode(expr)), :broken, $(QuoteNode(__source__)), time()))
        else
            # Unexpectedly passed — this is a failure
            $emit!(_bus, $AssertionFailed(
                $(QuoteNode(expr)), :broken, :passed, $(QuoteNode(__source__)), time()))
        end
        !_result
    end
end

# --- @check_skip macro ---

"""
    @check_skip reason

Skip the current test with a reason string. Emits a LogEvent.
"""
macro check_skip(reason)
    quote
        local _bus = $current_bus()
        $emit!(_bus, $LogEvent(:skip, $(esc(reason)), time()))
        return  # exit the test body early
    end
end

# --- @suite macro (tree builder) ---

"""
    @suite name body
    @suite name tags=[:tag1] body

Define a test suite. Returns a `Cofree{Vector, TestSpec}` tree.
The body can contain `@testcase` and nested `@suite` definitions.
"""
macro suite(name::String, args...)
    _suite_impl(name, args, __source__)
end

function _suite_impl(name, args, source)
    tags_expr = :(Set{Symbol}())
    body = nothing

    for arg in args
        if arg isa Expr && arg.head == :(=) && arg.args[1] == :tags
            tags_expr = :(Set{Symbol}($(arg.args[2])))
        else
            body = arg
        end
    end

    body === nothing && Base.error("@suite requires a body block")
    _suite_from_body(name, tags_expr, body, source)
end

function _suite_from_body(name, tags_expr, body, source)
    children_exprs = Expr[]

    if body isa Expr && body.head == :block
        for stmt in body.args
            if stmt isa Expr && stmt.head == :macrocall
                macname = stmt.args[1]
                if macname == Symbol("@testcase") || macname == Symbol("@suite")
                    push!(children_exprs, stmt)
                end
            end
        end
    end

    children_code = [esc(c) for c in children_exprs]

    quote
        local _spec = $TestSpec(
            name = $name,
            tags = $tags_expr,
            source = $(QuoteNode(source)),
        )
        local _children = $Cofree[$(children_code...)]
        $Cofree(_spec, _children)
    end
end

# --- @testcase macro (leaf test definition) ---

"""
    @testcase name body
    @testcase name tags=[:tag1] body

Define a test leaf (used inside @suite). The body is captured as an
expression and executed later by an executor.
"""
macro testcase(name::String, args...)
    _testcase_impl(name, args, __source__)
end

function _testcase_impl(name, args, source)
    tags_expr = :(Set{Symbol}())
    body = nothing

    for arg in args
        if arg isa Expr && arg.head == :(=) && arg.args[1] == :tags
            tags_expr = :(Set{Symbol}($(arg.args[2])))
        else
            body = arg
        end
    end

    body === nothing && Base.error("@testcase requires a body block")

    quote
        local _spec = $TestSpec(
            name = $name,
            tags = $(esc(tags_expr)),
            source = $(QuoteNode(source)),
            body = $(QuoteNode(body)),
        )
        $leaf(_spec)
    end
end
