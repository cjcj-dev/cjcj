package cangjie_compiler::utils

// PORT-DEFERRED: SignalTests.cpp is a C++ integration harness that forks/execs SignalTestCJC and
// deliberately raises process signals/stack overflow inside the compiler executable. The selfhost
// std.unittest package cannot faithfully run crashing subprocess signal scenarios from package utils.
// PORT-DEFERRED: SignalTestCJC.cpp is the companion C++ test executable, not a standalone gtest case.
