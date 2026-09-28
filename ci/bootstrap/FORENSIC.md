# Stage2 source-line forensics

Set `CJCJ_FORENSIC_STAGE2=1` when invoking `bootstrap.sh --stage stage1`
or `--stage all`. The default build is unchanged. `tools/srcbuild_kkk2.sh`
inherits this environment variable when its step 32 invokes the same bootstrap
entry. There is no separate implementation in `build-stage2.mjs` or stage3.

After a successful stage1, the optional segment copies the source into
`WORK/cjcj-src-stage1-forensic`, uses the same stage1 SDK and shim inputs,
and adds only `-g` to `cjpm build -j JOBS`. Workspace optimisation stays
unchanged. cjpm writes this profile to `target/debug/bin`.

To rerun only this segment after completing a bootstrap stage1, use its existing
work directory, source revision, host runtime and target runtime:

```sh
bash ci/bootstrap/bootstrap.sh --stage forensic \
  --work "$work" --src "$source" --cjcj-sha "$source_sha" \
  --cpp-src "$cpp_source" \
  --host-rt "$host_runtime" --colour-rt "$target_runtime" \
  --stage1-heap 32GB
```

This entry reuses `WORK/sdk-stage1` and requires `WORK/cjcj-stage2`. It does
not rebuild std or overwrite the release executable. Keep the source and SDK
from the same bootstrap run. The parent compiler and std-core archive hashes
are included in the resulting source stamps.

Retain these independent outputs together:

- `WORK/cjcj-stage2-forensic`
- `WORK/cjcj-stage2-forensic.source-stamps.txt`
- `WORK/cjcj-stage2-forensic.SHA256SUMS`

Capture the release ELF's SHA256 before the build, then check the actual outputs:

```sh
python3 ci/bootstrap/verify_forensic_stage2.py \
  --release "$work/cjcj-stage2" --release-sha256 "$release_sha_before" \
  --forensic "$work/cjcj-stage2-forensic" --output "$evidence"
```

The verifier checks release identity independently of the DWARF assertions. It
requires cjcj package source paths, resolves a line-table PC in
`CHIRBuilder::GetAllCustomTypes` to `CHIRBuilder.cj`, and compares std source/line
sets after excluding relocated instruction addresses. It retains command output,
return codes and a JSON result. A `.debug_line` section alone is insufficient:
the release executable can already contain std line tables.

Use addresses from the forensic ELF itself. Its instruction addresses need not
match a release ELF, so a release crash's `pc_off` cannot simply be passed to
the forensic ELF's `addr2line` command.
