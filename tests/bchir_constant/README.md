# Constant literal emission through the real compiler

Run each source with the product stage1 compiler, `--no-prelude --emit-chir=opt
--dump-chir --output-type=staticlib --jobs 1`. The final CHIR of the `pair`
initializer must reconstruct its elements from evaluated constants. `enum.cj`
requires selector 1 and no remaining `Load(chosen)`; the literal tuples require
all the source values, while `load_control.cj` supplies a positive control that
already evaluates without local Constant emission.

Use the same sources, SDK and compiler recipe for baseline, candidate, isolated
product cuts and restored builds. A compiler launch/build error is not a target
assertion failure. Record the compiler rc separately from the final CHIR checks.

For the paired Package declaration fix, include `ci/smoke/04_iface_enum.cj`
in `run.py --ordinary-dir` and run `verify_declarations.py <arm-output>`.
It independently observes the abstract `Shape.area` declaration and concrete
`Circle.area` implementation. Restoring the old Package filtering must fail
that target while the enum literal assertion still passes.
