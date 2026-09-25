# Property annotation factory registration

Upstream: `00df0d7c9fea76c8682d2bdc145777648a771fdf`,
`src/CHIR/AST2CHIR/TranslateASTNode/TranslateAnnotation.cpp:204-237`.

Compile each input separately with the real candidate stage1 compiler:

```
cjcj-stage1 nonliteral.cj --emit-chir=raw --output-type=staticlib --jobs 1 -o output.chir
python3 verify.py output.chir
```

For `literal.cj`, pass `--literal` to the verifier. `mixed.cj` checks that a
nonliteral argument clears previously collected literal annotation instances.
Use a separate output directory for every input and compiler arm. Record the
compiler exit code independently of the verifier; a failed compilation does
not qualify as a passing arm even if an intermediate CHIR file exists.

The verifier decodes the product's serialized accessor AnnoInfo and matching
factory definitions. It prints every predicate, so the name/presence checks do
not hide the factory-count assertion. The literal control also checks rawString
collection. No translator copy or test-only product hook is used.

The producer cut restores the early return at the nonliteral argument. The
consumer cut bypasses reuse of a cached empty-instance AnnoInfo. Both must fail
`accessors_share_one_factory` for nonliteral inputs and preserve literal results;
the restored compiler must recover the candidate result. Compile/load/exit
failures do not count as this targeted failure.

For a Cangjie stage1 host, use the bootstrap host/target split: the compiler
process uses its official host runtime and std, while `CANGJIE_HOME` and the
compiler-relative macro runtime point to the matching coloured target SDK.
Validate the target std/runtime pair with `ci/bootstrap/std_runtime_colour.py`.
An official-runtime-only host can reach the unrelated macro initialization
failure tracked by cjcj#258; do not interpret that process failure as this test's
expected red result. The qualified red result is compilation rc=0 followed by
verifier rc=1 only for `accessors_share_one_factory`.
