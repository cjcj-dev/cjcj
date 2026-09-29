# ReduceMultiTypeSubst regressions

Specification: upstream `15a1dfea7a4abf036182f1079922d7f9cdc57dbd`,
`src/Sema/MultiTypeSubstUtils.cpp:212–258`.

Build the real sema package and its dependencies with `cjpm build -m packages/sema`.
Then run `python3 test/reduce_multi_type_subst/run.py --release <target/release>
--sdk <official-host-sdk> --out <evidence-directory>`.
The runner compiles only test source and links the supplied product archives.
It captures archive, CJO, runtime and executable identities before execution.
For fault arms, pass `--reference-release <candidate-release>` to freeze every
interface and dependency archive; only `sema@cjcj/libsema@cjcj.a` is exchanged.
Independent full builds can have different archive bytes even for unchanged
source, so those differences must not enter the fault comparison.

All four cases enter `TypeManager.GetInstantiatedTys`; the returned type set
is the assertion input. The `EnumTest<Y>` fixtures reproduce the substitution
shape from the upstream `extend<Y>` example. A root variable keeps X and Y in
the mapping used during recursive instantiation; checking the initial reduction
result directly would miss the filtering of that private mapping.

* Shared target, X before Y: each pair must be checked, retaining X's target.
* Multiple targets of Y: keep the concrete target when removing `EnumTest<Y>`.
* Shared target, Y before X: removing an empty Y key must preserve X.
* Acyclic mapping: unrelated control must remain green under the targeted cuts.

The old self-reference filtering is a producer mutation. Replacing the recursive
`GetInstantiatedTys` call inside `ReduceMultiTypeSubst` with its input type is the
consumer mutation. Both mutate the real product and leave assertions intact.
