# VTable attribute snapshots

Run `run.py --compiler <stage1> --output <directory> --jobs 1 1 1` with the
frozen baseline first. Then run the candidate with `--reference <baseline-output>`
(default candidate jobs: 1, 192, 192, 192). Use the same SDK and source fixtures.

The runner compiles the existing literal and generic receiver fixtures through
real CLI Canonicalization. It decodes every custom definition's VTable method
attributes from binary CHIR, using only the FlatBuffer reader from
`chir_builder/decoded_compare.py` (never that file's exception comparator).
It checks entry coverage, imported Iterator witnesses, non-FINAL bits, and the
exact FINAL snapshot independently. Cross-process stability alone is insufficient:
the reference is the original serial candidate-definition order.

Product producer fault: omit the serial `UpdateInstanceAttr(vtable)` call.
Product consumer fault: omit `UpdateInstanceAttributeInfo`'s `CopyFrom`.
Both must change `final_snapshot`, with compilation, entry coverage and non-FINAL
control assertions still passing. Keep each arm's executable and output files.
