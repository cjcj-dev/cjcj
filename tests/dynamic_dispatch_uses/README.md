# Dynamic dispatch callee uses

Run `python3 tests/dynamic_dispatch_uses/run.py --compiler /path/to/cjcj-stage1 --out /path/to/evidence` in that compiler's matching SDK environment. The runner invokes the real compiler on five source programs and records compiler/input hashes, commands, statuses, CPU affinity, uptime, and observed CHIR declarations.

The invariant is that a getter still referenced by a virtual call keeps its declaration and declaring type after dead function elimination. Executable output mode allows the dead-function pass to remove otherwise unused declarations; a library export can independently retain the getter and hide a missing user edge. The test reads the first optimization dump after `RulesChecking` has performed dead function elimination. Devirtualization is disabled for this observation so a malformed parent cannot terminate compilation before the declaration assertion. The separate full std compilation exercises devirtualization normally.

`instance` and `static` exercise `Invoke` and `InvokeStatic`. `exception` and `exception_static` exercise their exception successors and serve as controls for the constructor fix. `control` checks a concrete getter. Before the fix, both ordinary virtual getter assertions fail; both exception cases and the concrete getter pass. The virtual-call existence check is nonfatal, and every invariant assertion prints its result.

Upstream anchors: `src/CHIR/IR/Expression/Expression.cpp:1036-1043` registers the callee in `DynamicDispatch`; `src/CHIR/Optimization/DeadCodeElimination.cpp:765-768` retains functions with users (upstream/main `71b92a0b9ff2f19b6206964efa2c721a2cd218ae`).
