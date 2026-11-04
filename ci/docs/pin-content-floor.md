# Pin weak source-shape floor

This document records the deliberately narrow contract enforced by
`gcFixWeakSourceShapePresent()` while building the pinned runtime source.

| Guarantee | Not guaranteed |
|---|---|
| Under the current canonical spelling of `MutatorManager::TryAcquireMutatorManagementRLock`, a `mgmtWritersWaiting.load(std::memory_order_acquire)` token and a `mutatorManagementRWLock.UnlockRead()` token occur after `mutatorManagementRWLock.TryLockRead()`. | Reachability; presence in the same branch; any comparison or return value; local aliases; helper extraction; macros; or any equivalent source rewrite. |

This is a weak source-shape floor, not a behavior proof. If a new spelling can
bypass or falsely trigger the matcher, record it as a limitation for the
separate behavior-level test. Do not grow this text matcher with another
special case.

The introducing commit SHA remains provenance metadata. History rewrites may
replace that SHA while retaining the current canonical spelling, so the build
guard checks the checked-out file rather than ancestry of the introducing SHA.
