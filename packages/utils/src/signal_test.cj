package cjcj::utils

// PORT-DEFERRED: Utils/SignalTests main/parser signal and stack-overflow cases require the C++ fork/exec
// harness ExecuteProcess from /root/cj_build/cangjie_compiler/unittests/Utils/SignalTests.cpp:154 and
// Windows CreateProcessA branch at :189; the selfhost std.unittest harness cannot faithfully run crashing
// compiler subprocess scenarios from package utils.
// PORT-DEFERRED: Utils/SignalTestCJC.cpp is the companion executable that wires SetSignalTestCallbackFunc at
// /root/cj_build/cangjie_compiler/unittests/Utils/SignalTestCJC.cpp:82 and :118, not a standalone gtest case.
