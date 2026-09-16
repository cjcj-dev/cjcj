These patches apply only to isolated copies of the compiler product source.
Build green/cut/restored compilers through the same recipe and compile the
same fixture with each compiler. Preserve the compiler/std/ELF/runtime hashes.

- registration: changes the original CreateStringLiteral registration input;
  existing baseline entry, certified by entry_cut_check.
- consumer-read: disconnects the real static aggregate read for String only;
  ordinary aggregate and array controls must still pass.
- payload: copies zero payload bytes; heap-domain checks must remain true,
  exact literal bytes must fail.
- root: omits the cache root attribute; check_ir must report missing cache
  roots. This arm has not yet established a runtime GC failure.
- allocation: forces an oversized allocation only for literal_probe. This
  exercises the real generated cleanup; it is not a passing-suite red arm.
  The library failure mode expects original initialization failure, followed
  by the generated native Abort(70) on retry. Work in progress.

The pre-ABI registration/payload/consumer-read/restored runs are preserved in
REPORT-sym_cjcj_48_implement_r5685150408.md with their original identities.
Do not label them as coverage of the subsequently added completion ABI.
