# Signal-safe temporary-file cleanup

`fixture.cj` imports the release `cjcj::option` product. `run.py` compiles only
that fixture and links the existing basic/utils/option archives; it never
recompiles or substitutes a copy of TempFileManager.

After a normal workspace `cjpm build`, run on kkk2:

```sh
python3 tests/temp_file_signal_safe/run.py --tree "$PWD" --sdk "$CANGJIE_HOME" --out /root/<lane>/evidence/green
python3 tests/temp_file_signal_safe/run.py --tree "$PWD" --sdk "$CANGJIE_HOME" --out /root/<lane>/evidence/sigint --sigint
```

The first invocation observes the registered file and parent directory after
both direct signal-safe deletion and normal deletion, in separate processes.
The SIGINT invocation registers the product handler, raises SIGINT, and checks
exit status 130 and both paths from the parent process. It requires a Unix host.
Every invocation records build/run status, product archive and ELF hashes,
full defined-symbol output, affinity, elapsed time, and uptime before/after.

For the consumer control arm, replace only the product body of
`DeleteTempFilesSignalSafe` with an empty return, rebuild the product, and run
the same two-case fixture. Only `direct` must fail; `normal` must pass. Restore
the source and rebuild before repeating. Separately disconnect the registered
path insertion in `CreateTempBcFileInfo` to test the producer. For handler
wiring, remove the direct call from `ctrlCSignalHandler` and run `--sigint`:
exit status must remain 130, while the parent must observe retained paths.
A compilation failure is never a successful control arm.

Windows console/unhandled-exception routing has the same direct-call shape
in `packages/option/src/Signal.cj`; the Unix execution does not establish
Windows runtime behavior.

On x86-64, the optional `allocations.gdb.py` observer records CString return
addresses, caller symbols, and matching native frees without altering calls:

```sh
EXPECT_LIVE=0 ALLOCATION_RESULT=/root/<lane>/normal.json \
  gdb -q -batch -ex 'set breakpoint pending on' \
  -ex 'handle SIGUSR1 SIGUSR2 SIGPWR nostop noprint pass' \
  -x tests/temp_file_signal_safe/allocations.gdb.py --args /root/<lane>/green/fixture normal
```

Use `reinit` with `EXPECT_LIVE=0` to exercise cleanup of the native paths kept
by signal-safe deletion. The positive control is `direct` with
`EXPECT_LIVE=2`: signal-safe deletion must keep both native path buffers.
The observer requires normal process exit, at least one observed allocation,
no debugger read errors, and the stated live allocation count. SDK runtime
search paths and `TMPDIR` must be set as in `run.py`.
