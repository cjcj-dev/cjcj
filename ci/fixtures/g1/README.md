Six data fixtures are byte-for-byte Bash entries from
`a65c82b648b32f9f3fcbeaf9cb84825852129af3:ci/test-*.sh`.
They are inputs to the migration AST/differential tests, not installed entries.
Keeping data permits depth-one CI checkouts to test the frozen old language.

The joined tuple entry uses the actual pre-migration shell at
`87fea61097486afac68f310d36d5a05148649780:ci/test-llvm-tuple-layout.sh`.
It carries the platform field required by the already-integrated tuple producer.
The original a65 bytes remain in `test-llvm-tuple-layout.a65-original.txt`;
the inventory records the tuple's actual baseline separately. Other six fixtures are unchanged.
