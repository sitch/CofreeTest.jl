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

export Cofree, extract, duplicate, extend, fmap, hoist, leaf, suite
export Outcome, Pass, Fail, Error, Skip, Pending, Timeout
export Metrics, CapturedIO, TestEvent
export TestSpec, Scheduled, TestResult
export SuiteStarted, TestStarted, TestFinished, SuiteFinished
export AssertionPassed, AssertionFailed, LogEvent, ProgressEvent

end # module
