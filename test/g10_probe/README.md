# G10 AST2CHIR local-value identity probe

`src/RawString.cj` contains `@C` structs and `CPointer<T>` return values and member calls.
`src/Literals.cj` is the recovered W2 integer-only match table. The three probe variants move
`RtArenaCreate()` behind zero, one, or two same-package literal calls without changing the result.

Run each arrangement twice in a fresh directory:

```bash
bash test/g10_probe/run_matrix.sh
bash test/g10_probe/run_matrix.sh /root/.cjv/bin/cjc
```
