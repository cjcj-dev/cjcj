# CPointer stride regression (#661)

Compile `main.cj` as a separate package against a std.core rebuilt with the
compiler under test, then run it. The four STRIDE lines expose the observed
address difference and expected `3 * sizeOf<T>()`, and check subtraction
returns to the original address. No memory is dereferenced.

Candidate and restored runs must return 0 with four `ok=true` lines. Replacing
CPointerAdd's element size with LLVM i64 constant 1 before rebuilding std must
return 3: Int64, Triple24 and CPointer fail, while UInt8 remains true. All four
assertions run even when one fails. An official prebuilt std is not evidence
for this regression because its generic pointer operators bypass our codegen.

Reference: cangjie_compiler/src/CodeGen/Base/IntrinsicsDispatcher.cpp:529-551.
