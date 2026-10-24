# G2 tuple entry migration

Invoke the leaves with `npx --yes zx@8 ci/platform_tuples/fetch_sources.mjs`
and `npx --yes zx@8 ci/platform_tuples/build_tuple.mjs` from the original caller
directory. Environment names, relative path interpretation, source mirror policy,
private runtime identity checks, configure flags, build order, and artifact names
are retained. The existing `build/lib/srcbuild_git.sh` remains the shared Git
transport policy; this group does not replace that separately owned helper.

`entry.mjs` uses a small Bash descriptor primitive to retain the original merged,
live `tee` log. It does not interpret or rewrite the tuple source. `build_tuple`
retains individual awk/grep pipelines where their early exit or pipefail behavior
is part of the existing contract.

The dedicated gate is `node --test ci/platform_tuples/migration.integration.mjs`.
Set `G2_MIGRATION_EVIDENCE` to a new private directory and
`CJCJ_BASH_AST_PARSER` to the pinned shfmt described in `ci/g3-parser-input.json`.
It uses real local Git repositories and CMake, and needs the existing zx cache.
The exact old Bash entries are nonproduction fixtures under `ci/fixtures/g2/`.
All required environment cases are derived from the complete typed AST; native
manifest cases and unmaterialized branches remain NOT_RUN in its inventory.

The CMake consumer checks actual selected runtime bytes and LIBXML2=OFF, then
stops configuration intentionally. It does not compile LLVM, a shim, or a native
SDK. Windows/static archive branches and complete native production need their
real platform inputs. CI workflow/registry/shared tests must be integrated by the
CI owner against the supplied fixed interface diff before the combined workflow
can be called complete.
