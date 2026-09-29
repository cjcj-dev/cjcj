# Repeated operator-call desugaring

Run `python3 run.py --compiler /absolute/cjcj-stage1 --sdk /absolute/host-sdk --out /absolute/results`.
The compiler must be built from the candidate source with its matching host libraries.

`empty`, `nonempty`, and `generic` call an instance with an Array-only `operator ()`
in a constant initializer. The compiler must reject the synthesized Array as
nonconstant and report the source call on line 9 with a nonzero column.
`control` exercises a scalar operator call without variadic desugaring.
Every assertion prints its result independently; a failed diagnostic assertion
cannot hide the source-position assertion. Each case has its own output directory.
The result records compiler/runtime hashes, actual compiler exit codes, affinity,
uptime, fixture hashes, and elapsed time. An internal compiler error is a failure.

Specification: upstream fdd47893726b186e30b342a9a33a15ec6b6221fe,
ConstEvaluationChecker.cpp:670, DesugarInTypeCheck.cpp:485/514,
PartialInstantiation.cpp:788. Tests require candidate/cut/restored execution;
source inspection alone does not establish coverage of each copied field.
