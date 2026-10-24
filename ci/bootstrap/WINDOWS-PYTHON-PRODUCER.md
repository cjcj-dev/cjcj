# Windows CPython development producer

The public entry is `node ci/bootstrap/native-python-windows.mjs config.json`.
It is a native Windows x64 producer, not the existing 3.11.9 embeddable runtime
bundle. The fixed source is the official CPython 3.11.17 tar.xz with SHA256
`bfb74ad39efae27cda510f134ab408e00f9992c56851cfc0b1cdb5646da11599`.
The admitted runner supplies that archive and an explicit bootstrap Python and
MSBuild. The entry does not obtain a Windows execution slot or grant permission
to start a native build.

```json
{
  "work": "C:/private/python-development",
  "archive": "C:/private/inputs/Python-3.11.17.tar.xz",
  "jobs": 4,
  "mode": "build",
  "tools": {
    "bootstrapPython": "C:/approved-bootstrap/python.exe",
    "msbuild": "C:/approved-vs/MSBuild/Current/Bin/MSBuild.exe",
    "tar": "tar",
    "cmd": "C:/Windows/System32/cmd.exe"
  }
}
```

There is no minimum CPU count. Omit `jobs` to use the actual available CPU
domain, or set a positive safe integer, including explicit oversubscription.
Memory, disk pressure and the CI time budget remain separate constraints. The selected
value reaches PCbuild as `/m:<jobs>` and is recorded with the build. Standard
official Windows runners are valid; their memory, free disk, and runtime must
be assessed independently of CPU count.

`build` (default) requires an empty work directory. `resume` reuses the same
materialized source and PCbuild output after a failed invocation, retaining
original command attempts and failures. A failed extraction remains separately
named, and a new extraction does not overlay it. `reuse` verifies an existing
completed installation's recorded bytes and runs the installed Python again;
it does not claim that this invocation rebuilt Python. It returns the original
record unchanged. The source version, work root and bootstrap/MSBuild paths
cannot silently change during resume. These are ordinary build input and
command records, not an installation permission mechanism.

The normal chain is:

1. Verify the fixed source archive and extract it into private `work/source`.
2. Run the explicitly supplied bootstrap Python and upstream
   `PCbuild/get_externals.bat --no-tkinter`; preserve its own rc.
3. Run `PCbuild/build.bat -p x64 -c Release -e --no-tkinter -M /m:<jobs>
   /p:KillPython=false /bl:../pcbuild.binlog`. SSL and ctypes remain enabled.
   Upstream `-e` fetches/caches normal dependencies; no arbitrary package or
   mutable target label is substituted. `-M` removes upstream's default
   unbounded `/m`. The global MSBuild property disables its process-kill target. The child
   environment explicitly enables SSL/ctypes/libffi and removes inherited
   source/version/regeneration selectors across the SDK command overlay.
4. Execute the newly built interpreter and check exact 3.11.17, then invoke its
   own `PC/layout --include-dev --include-stable --source ... --build ...
   --arch amd64 --copy <pending-independent-install> --temp ...`.
5. Execute the independent installation with `-I -B`, checking its prefix,
   interpreter, include path, SSL and ctypes module locations. Check actual
   headers, import library, DLL/Lib files and VC runtime DLLs. Rename the same
   installation into its final location and repeat the installed probe there.
6. Only after that final probe succeeds write `PYTHON-BUILD-INPUTS.json`, with
   actual source/version, host/target, jobs, producer identity, commands and
   installed file hashes. Preserve prior installations and failed attempts.

Tkinter, pip, docs and tests are not required by N/CJDB and are not included by
these layout options. Standard `Lib`, `_ssl`, `_ctypes`, external crypto/ffi
DLLs, `python311.dll`, stable `python3.dll`, and VC runtime DLLs are required.
HLE's Python >=3.13 build dependency is separate.

The entry prints the existing interface, without a new receipt:

```json
{
  "python": "C:/private/python-development/install",
  "pythonInputs": {
    "record": "C:/private/python-development/install/PYTHON-BUILD-INPUTS.json",
    "sha256": "<actual record digest>"
  }
}
```

The existing SDK `pythonSourceInputs` binds `source` and
`files[relative].sha256` to the interpreter, `include/Python.h` and
`libs/python311.lib` actually selected by `pythonConfiguration`. The record also
contains `installation.entries` for the actual complete top-level layout,
including `python3.dll` and VC runtime DLLs; copying only `python311.dll` is
insufficient. `originals` gives installation-relative references to the actual
MSBuild binary log and installation/relocation probe JSON. Carry the unedited
record and originals with the same N artifact. CI owns that shared caller and
copy/reader composition, and must preserve its newer Python source fields and
the N/AST source binding. Producer support alone does not close that integration.

Current verification is limited to the *unmodified official PC/layout* running
on Linux over explicitly non-executable fixture files, actual layout bytes and
relative paths, omission of `--include-dev`, loader-file rejection and public
foreign-host rejection. The official layout's documented `PYTHON_HEXVERSION`
override is used only by that fixture; the producer clears it and uses the newly
built interpreter. Windows PCbuild, external dependency acquisition, installed
Windows Python/SSL/ctypes, and CJDB execution remain NOT_RUN. No Windows/GHA/stage
qualification follows from these fixture results.

The native N caller supplies its effective `jobs` when `pythonProducer.jobs`
is omitted. See `NATIVE-CJDB-JOBS.md` for the public caller's finite configure
and build verification; it does not establish Windows PCbuild execution.

## Shared native and package consumers

`native-cjdb.mjs` accepts an explicit `pythonProducer` configuration on the
Windows native branch, or the producer's frozen `{python, pythonInputs}` result;
the two selections cannot be mixed. It copies every original installation entry
and the unedited producer record/original outputs before the existing installed
Python/LLDB checks. `BUILD-INPUTS.pythonInstallationInput` names the carried
record relative to N. Configure uses that record's actual digest; SDK copies
carry it with `third_party/llvm`. `installedInputs` checks the complete recorded
Windows layout and original output bytes after relocation, including the stable
and VC runtime DLLs. Windows `CONFIG_ARGS=null` remains an observed fact; Unix
configure requirements remain unchanged. This is source integration, not a
claim that Windows PCbuild, N or LLDB has executed.
