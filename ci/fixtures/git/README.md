The offline contract tests fetch exact commits and check out their complete
trees. They exercise local Git transport without an external mirror.

| Component | Base pack commit | Current fixture commit |
| --- | --- | --- |
| runtime | 37e4fe3d14e41103643c5975f21dd75f8201ac04 | 16c006c8d87cf1eeec96c5cbb687b9a6151b4924 |
| tools | 52adc7a2b67f8f1e711b6a50fbd0c83d85558a58 | 4d14d051c58a5574d6525314b2c695e2e5dd26e6 |
| llvm | ba518962f0cda46ea71cad033214e8fe1ea83249 | eb7ad0120f43f802fbc60615e6c6f068183fffe3 |

The base pack contains the original commit and tree. The LLVM base pack is
split into 64 MiB parts. Each update pack supplies the new commit and only
the tree objects missing from its base. The test imports both packs and
checks the requested SHA; it never fetches from the network to repair a stale
fixture. To replace an update pack using a reviewed source repository:

```sh
{ echo "$new"; git rev-list --objects --no-object-names "$new^{tree}" "^$base^{tree}"; } |
  git pack-objects --stdout > "$fixtures/$component.update.pack"
```
