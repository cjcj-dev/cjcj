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
