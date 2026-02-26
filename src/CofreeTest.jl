"""
    CofreeTest

Cofree testing — parallel, observable, beautifully formatted.

The parallel execution architecture is adapted from
[ParallelTestRunner.jl](https://github.com/JuliaTesting/ParallelTestRunner.jl)
by @maleadt and contributors.
"""
module CofreeTest

include("Cofree.jl")
include("Types.jl")
include("Events.jl")
include("Discovery.jl")
include("Filter.jl")
include("Macros.jl")
include("executors/Abstract.jl")
include("executors/Inline.jl")
include("executors/Process.jl")
include("executors/Pool.jl")
include("executors/Task.jl")
include("formatters/Abstract.jl")
include("formatters/TerminalComponents.jl")
include("formatters/Dot.jl")
include("formatters/Terminal.jl")
include("formatters/Json.jl")
include("formatters/Multi.jl")
include("Schedule.jl")
include("Runner.jl")
include("Compat.jl")
include("History.jl")
include("DocTest.jl")

export Cofree, extract, duplicate, extend, fmap, hoist, leaf, suite
export Outcome, Pass, Fail, Error, Skip, Pending, Timeout
export Metrics, CapturedIO, TestEvent
export TestSpec, Scheduled, TestResult
export SuiteStarted, TestStarted, TestFinished, SuiteFinished
export AssertionPassed, AssertionFailed, LogEvent, ProgressEvent
export TestFilter
export @check, @check_throws, @check_broken, @check_skip, @suite, @testcase, with_bus
export AbstractExecutor, InlineExecutor, ProcessExecutor, TaskExecutor, execute!
export AbstractFormatter, DotFormatter, TerminalFormatter, JSONFormatter, MultiFormatter
export runtests, test_summary, TestSummary
export discover_doctests, @doctest

end # module
