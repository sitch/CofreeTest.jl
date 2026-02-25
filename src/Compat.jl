import Test

"""
    CofreeTestSet

A Test.AbstractTestSet shim that intercepts @test results and converts
them to CofreeTest events on the EventBus.
"""
struct CofreeTestSet <: Test.AbstractTestSet
    bus::EventBus
    description::String
end

CofreeTestSet(bus::EventBus, desc::AbstractString) = CofreeTestSet(bus, String(desc))

function Test.record(ts::CofreeTestSet, result::Test.Pass)
    emit!(ts.bus, AssertionPassed(
        something(result.orig_expr, :unknown),
        result.value,
        something(result.source, LineNumberNode(0, :unknown)),
        time()
    ))
    result
end

function Test.record(ts::CofreeTestSet, result::Test.Fail)
    expr = try
        Meta.parse(string(result.orig_expr))
    catch
        Symbol(string(result.orig_expr))
    end
    emit!(ts.bus, AssertionFailed(
        expr,
        result.data,
        result.value,
        result.source,
        time()
    ))
    result
end

function Test.record(ts::CofreeTestSet, result::Test.Error)
    emit!(ts.bus, AssertionFailed(
        :error,
        :no_error,
        result.value,
        something(result.source, LineNumberNode(0, :unknown)),
        time()
    ))
    result
end

function Test.record(ts::CofreeTestSet, result::Test.Broken)
    source = hasproperty(result, :source) ? something(result.source, LineNumberNode(0, :unknown)) : LineNumberNode(0, :unknown)
    emit!(ts.bus, AssertionPassed(
        something(result.orig_expr, :unknown),
        :broken,
        source,
        time()
    ))
    result
end

Test.finish(ts::CofreeTestSet) = nothing
