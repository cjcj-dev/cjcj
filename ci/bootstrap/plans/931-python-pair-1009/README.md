# CJDB Python pair revision

Source producer: `b22dd5dfe924ffca45cebba6dbc3d5f899fb4242` (tree
`a630b5b73cc3078be50fe15ad9ce59270a043ad1`). The commit containing these
records is a separate delivery identity. This is preparation, without native
production or independent review clearance.

The existing freezer produced `complete.plan.json` on kkk2 with rc=0. All seven
components remain. Original official/runtime producers, receipt locators,
receipt digests, origin build roots and build IDs remain unchanged. The native,
compiler and std build IDs are new. AST/schema IDs also change with the private
build root, without changing their source or producer. `refreeze-result.json`
contains the exact old/new identities. No new native success receipt exists.
Original native recipe b9a2ac5d and receipt a4d988aa remain historical inputs.

The first real qualification at bf3415df used the producer's inherited
Python3_ROOT_DIR hint. Its parent and LLDB configurations returned 0, but the
actual identity assertion returned 1: LLDB selected Python3.10. Release and
Python-enabled controls passed. CMake3.22 enumerates Python versions only through
3.10. The dependent LLDB build, install and Python import did not run.

The final source revision uses the existing BuildCJDB LLVM_BUILD_ARG cache entry
for explicit interpreter, include and library artifacts. It also compares the
relocated current Python library prefix, rather than sysconfig's stale original
LIBDIR. This revision has passed syntax checking only; its real child configure,
parameter cut, restored arm, link NEEDED and SBDebugger import remain NOT_RUN.
The first product assertion failure stopped execution under this run's contract.
These records do not authorize complete native production, stage1/std, CI, push,
main or release operations. A different agent must review the stopped evidence
and any next execution contract.

Evidence: kkk2 `/root/sym_cjcj_931_implement_r6089250606/normal-1/` and
`normal-1.log`; local `/root/cj_build/reports/EVIDENCE-sym_cjcj_931_implement_r6089250606/`.
