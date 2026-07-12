# Local analysis tools

- `calldiff.py` compares direct LLVM-IR `call`/`invoke` callee multisets for
  matching ABI-mangled functions. It consumes `.ll`/`.bc` saved by sc_bcgate;
  no source parser or C++→CJ translation dictionary is involved. Its header
  has smoke and codegen commands; `--check-identical 3` mechanically verifies
  three byte-identical function bodies have an empty callee diff.
