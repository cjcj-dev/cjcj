# Const-eval insertion contract

These are real Cangjie source inputs for a stage1 compiler, compiled with
`--no-prelude --emit-chir=opt --dump-chir --output-type=staticlib --jobs 1`.
Each defines a minimal `std.core` (Object and CType) so unrelated imported
constant initializers do not prevent interpreter completion.

Literal global variables supply the values. Local literal expression lowering
has a separate known defect (cjcj#235); the inputs avoid depending on that path.
`scalar.cj` exercises CreateNewInitializer's direct literal consumer;
`tuple.cj` and `nested.cj` exercise recursive ConvertToChir with integer, boolean,
float and rune results. The final CHIR must contain the reconstructed constants.

Build the baseline and candidate with the same SDK and `--trimpath` recipe.
For the assertion arms, run `instrument.py` on disposable candidate source
copies, then build each copy: green, `--cut producer`, `--cut consumer`, restored.
The assertions inspect the actual expression's membership in the product block;
no test entry point, counter, or callback is added to the shipped compiler.

A separate formal `cut-result` arm changes the existing
`return ExprResultAsValue(constant)` in ConvertToChir to `return None`.
This baseline-line cut is checked by `entry_cut_check.py`. It leaves compilation
successful but must falsify the final-CHIR constant assertions. The callback cut
is on a candidate-added line and is reported separately.

`run.py` accepts repeated `--arm name=/absolute/cjcj-stage1`, a shared `--sdk`,
and `--out`. Add `--ordinary-dir tests/chir_builder --ordinary-dir ci/smoke`
for the unrelated-input controls. Independent inputs run concurrently;
`--jobs 1` keeps each serialization deterministic (the existing #203 constraint).
The collector records actual compiler rc, product/SDK hashes, affinity, uptime,
CHIR hashes and assertion output. A successful exit without an observation
never establishes coverage.

`verify.py result.json` compares baseline/candidate CHIR bytes and the exact
failure sets, and checks green/restored compiler identity. Run
`verify.py result.json --target-arm candidate` (then `cut-result`, then `restored`)
to record the target CHIR assertions' actual process rc (0, 1, 0).
