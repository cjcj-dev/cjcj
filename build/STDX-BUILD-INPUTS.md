# stdx producer facts

The public `build/cli.mjs ... build stdx` entry uses the normal producer:
`begin → clean (unless incremental) → build.py build → build facts → build.py install → install facts`.
Before build, the shared caller does not create the native build directory.
Upstream owns configure/generation and normal cache reuse; build failures propagate.
No upstream `build.py` change is needed for shared recording.

`full` installs into `SDK/stdx`; `sdk-tools` uses the producer's three exclusion
options and its normal `target` directory. The requested profile is an input,
not proof that full stdx was produced or consumed. Effective cache option values,
source path, platform and existing runtime/ABI checks remain applicable.

The ordinary record is `share/cjcj/build-inputs/stdx.json` within that installation,
and `workspace/build/stdx/build-inputs.json` during production. Each old record
is atomically saved beside itself, including across workspace/install filesystems.
Failed build/install attempts leave no current installed-success record. The
old installation bytes, prior records and caller's FAILED results stay available.

Recorded facts:

- Source repository from actual origin or explicit fixed sourceSelection, HEAD,
  tree and diagnostic checkout path. Existing source selection checks reject
  conflicting origin/commit or an unmaterialized/edited source checkout.
- Actual build argv, platform, mode, requested profile, environment, effective
  CMake cache values and successful command rc.
- Actual install argv/rc/prefix and native install-manifest location.
- Installed file paths relative to the installation, sizes and symlink text.

There is no File API query/reply, embedded build graph, generated-rule copy,
configuration/source/manifest digest, installation-rule replay or per-file hash
qualification. Readers use the current installation root, check source/platform,
command success, full-vs-subset configuration and present contained paths. Real
consumer compilation/execution establishes usefulness. The existing release row
records its representative artifact checksum at packaging, rather than requiring
all native install files to carry producer hashes.

`beginStdxBuild` preserves old facts outside the native build tree.
`finishStdxBuild` records only after successful native build.
`prepareStdxInstall` preserves the previous native manifest and rejects unrelated
configured install directories; `finishStdxInstall` reads the current native
manifest after successful install. No helper substitutes a second build/install.
Existing incremental configuration and selected compiler runtime checks remain.

Controlled tests use Git/CMake/native C fixtures and public CLI calls, including
first configure, clean, incremental, generation/build/install failures and
relocated install consumers. They do not qualify real Cangjie full stdx. SDK's
original producer owner performs the actual paired build/install/consumer run.

## Native C++ toolchain input

When the selected host SDK requires matching GCC C++ headers and libraries, pass
`--stdx-gcc-toolchain /absolute/gcc-prefix` before `build stdx` (or set
`CJCJ_STDX_GCC_TOOLCHAIN`). The prefix is the directory containing `include` and
`lib`, such as an extracted distribution's `usr`, not its versioned GCC bin or
header directory. The native stdx stage forwards the prefix to the upstream
`build.py --gcc-toolchain` option, and existing build facts retain the actual
argv and `BUILD_GCC_TOOLCHAIN` CMake value. Cross targets reject this native option.

Repeat the selection when resuming. Incremental builds reject a changed or
omitted prefix before reusing native objects; select a separate build workspace
or use the explicit clean mode to change it. A successful host hello program
does not qualify C++ ABI compatibility: the installed syntax FFI and its actual
C++ header dependencies must be checked with the selected host SDK.
