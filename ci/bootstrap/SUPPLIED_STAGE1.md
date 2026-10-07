# Resume bootstrap from a pinned stage1 ELF

`bootstrap.sh --stage supplied-stage1` runs the existing full initial std recipe,
assembles its SDK, builds stage2 with that std, and compiles/runs an Int64 main
with stage2. It never rebuilds stage0 or runs stage3, and publishes nothing.
A nonzero child exit stops dependent steps and remains the entry's exit code.
Use an absent private `--work` directory and a private std source copy: the
normal build.py recipe cleans/builds/installs in that copy.

Supply all normal bootstrap input options (see `bootstrap.sh --help`), plus:

- `--stage1-elf FILE --stage1-sha256 64HEX`: executable ELF input and identity.
- `--host-sdk DIR`: complete official SDK, copied before use, never modified.
- `--runtime-sha 40HEX --runtime-pin FILE`: actual target runtime commit; the
  existing runtime selection policy still applies. Non-formal selections need
  its explicit authorization environment; an external pin alone cannot override.
- `--host-identities FILE --host-identities-sha256 64HEX`: explicit native host
  runtime/boundscheck/LLVM triple in the existing platform-scoped runner format.
  Use the triple paired with the supplied stage1, not another SDK generation.

`--colour-tuple` is the existing build_tuple/published tuple, with
`--colour-llvm-sha` pinning its source commit and the normal strict manifest check.
`--host-llvm-so` is the host SDK's actual auxiliary-tool LLVM; the stage1 compiler
loads `--colour-llvm-so` separately. AST SDK inputs retain their existing pin.

Unset inherited `LD_LIBRARY_PATH` and `CANGJIE_HOME`; either makes this entry
refuse mixed domains. `--check-only` verifies declared inputs without creating
work directories or compiling. Its success is identity validation, not a build.
For real execution use the existing resource-controlled bootstrap lane entry;
std/compiler builds use the host's full core domain (at least 64 cores).

Tool domains follow the 1478 domain-table: cjc uses host runtime + compiler LLVM;
opt/llc/ld.lld must have static LLVM and load only their target LLVM tool directory;
llvm-objcopy/llvm-ar use the official host domain; GNU ar/ld use an empty LD path.
Target runtime is used for output linking and execution, not native tool loading.

For the colour runtime packaging gate, add `--colour-gate-source RUNTIME_ROOT`
and `--colour-gate-install INSTALL_ROOT`. The std source must be that clean
runtime checkout's `stdlib`, and its commit must match `--runtime-sha`. After
initial std and SDK assembly, the entry runs the unchanged complete native gate
with the assembled SDK's std and the same-build runtime pair. A gate failure
stops stage2. The input-only check does not run this gate or establish a verdict.

To continue an interrupted colour gate with its completed same-source std, use
`--resume-colour-gate SHA256_FILE` and the original private `--work` directory.
The captured file must identify the completed std artifacts with sha256sum
records. The entry verifies these records, the std source commit, the SDK lock's
compiler/runtime identities and the actual stage1 ELF before reusing them.
It then assembles/verifies the SDK through the normal recipe, runs the complete
gate and, only after success, builds stage2. This option requires the colour gate
inputs and `--stage supplied-stage1`; it does not authorize another execution.
