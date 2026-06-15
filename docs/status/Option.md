# Option Port Status

Implemented a multi-file Cangjie Option package replacing the scaffold:
`OptionTable.cj`, `Option.cj`, `OptionAction.cj`, `Triple.cj`,
`WarningOptionMgr.cj`, and support/enums files.

The port contains real command-line table parsing, option occurrence tracking,
global option mutation, target triple parsing, diagnostic mode/warning toggles,
optimization/output mode handling, selected post-parse validations, and
serialization helpers. Remaining fidelity gaps are not hidden behind self-host
TODO markers: the local filesystem surface is still more limited than the C++
`FileUtil`, and only the core option table/action surface has been filled out in
this pass.
