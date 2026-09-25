# OHOS linker hash style

After a normal host `cjpm build`, run on Linux:

```sh
python3 tests/driver_hash_style/run.py --tree "$PWD" --sdk "$CANGJIE_HOME" --out /path/to/evidence
```

The fixture links the existing product archives. `CJNATIVEBackend.Generate()` selects
the real toolchain and fills backend batches; `Tool.GetArgs()` supplies the values
for both assertions. It does not execute a cross-target linker. The SDK must contain
its normal LLVM tools, and `/usr/bin` must contain the host GNU linker and archiver.

Expected: OHOS has one `--hash-style=gnu` and no `both`; Linux has one `both` and no
`gnu`. Each reached assertion prints its counts. Exit 0 means both passed, exit 1
means an assertion failed, and exit 2 means the fixture could not generate batches.
Build errors are recorded separately in `result.json` and are not assertion failures.

Negative control: change only the hash-style argument in
`packages/driver/src/Ohos_CJNATIVE.cj` back to `both`, rebuild the product with the
same configuration, and rerun. Only `hash_style_ohos` should fail. Restore the line,
rebuild and rerun to recover both passing assertions.
