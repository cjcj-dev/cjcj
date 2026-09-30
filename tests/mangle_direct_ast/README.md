# Direct AST mangling (#693)

Run `../mangle_task_ownership/generate_inputs.py INPUTS`, then copy `shapes.cj`,
`packages/mangle/testdata/hfixH2/{259_raw_ref_type,261_generic_extend_key}.cj`
and `tests/devirtualization/inst_mangle.cj` into INPUTS. Run `run.py` with
`--compiler ELF --sdk SDK --inputs INPUTS --output OUT` for the baseline, then
with `--reference BASE_OUT --reference-is-baseline` for the candidate.

The runner reads the real compiler's CJO declarations (raw name, exportId,
mangled name) and LLVM definitions. It compares parallel and single-worker
results, prints every target assertion and records artifact/dependency hashes,
compiler rc, affinity and both uptime values. Compilation failures do not count
as a successful cut. Successful intermediate products are removed after hashing.

The only baseline delta is the second extend in `261_generic_extend_key`:
`Box<Int64>` and `Box<String>` each have index zero because upstream
`src/Mangle/BaseMangler.cpp:1419-1421` keys by the original `Ty.String()`.
The removed mirror returned only `Box` and assigned index one to the second
specialization. The baseline transition checks that exact witness and changes
only its expected exportId; all other fields and declarations remain compared.
Cut/restored runs use the candidate as reference without that transition.

`cut.py TREE --kind KIND --diff FILE` changes one real product result in an
isolated source copy. Lambda producer/consumer cuts perturb only lambda names;
raw/export cuts target the actual `acceptRawType` declaration. Each arm must be
rebuilt, run through the same runner, and show the expected assertion failure
while controls remain green. `raw-producer` changes a candidate-added line;
report it separately from baseline-existing consumer cuts.

`gc.py` implements the fixed #666 std.ast experiment: original input hashes,
5376MB heap, default jobs, 900s timeout, two same-baseline noise samples, three
baseline samples and three candidate samples. Samples run sequentially to avoid
mutual contention. Counts require completed GC log events and valid BC output.

`lambda.py` separately emits RAW CHIR and decodes `Lambda.identifier` from the
compiler's serialized result. Local lambda names can disappear before LLVM
output, so LLVM equality alone is not a sensitive assertion for the lambda
producer/consumer cuts. Baseline/candidate/cuts/restored use the same script and
inputs; the ordinary/control/shapes cases must contain observed lambdas. Other
function identifiers are a separate control assertion.

Additional coverage uses `coverage/locals.cj` with the normal recipe and
`coverage/mock.cj` with `--compiler-option=--mock=on --compiler-option=--test`.
Keep the ordinary/parallel controls in each input directory. The mock case
exercises the generated default-method accessor on an extend declaration.
`coverage/annotations.cj` is retained as an explicit coverage gap: cjcj#758
tracks its pre-mangling failure in both frozen and candidate stage1, while the
same official compiler accepts it. It is not a passing mangler test.

`phases.py KEEP_GC` applies the original #666 sequential Main Stage bounds and
one-second clock/rounding margin. It reports GC completion-phase observations,
not allocation stack attribution. Unknown stages or negative slack invalidate
this extra phase ruler without converting them into a zero observation.
