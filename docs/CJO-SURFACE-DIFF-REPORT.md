# CJO official/manual surface differential (2026-08-14)

## Verdict

The authoritative kkk2 run produced:

> `N=383 A=0 B=0 C=0 D=383 CHECKS=3264858`

This establishes equality for the 22 field groups enumerated below. It does **not**
establish equality for the whole handwritten reader: the covered groups touch 23
declared schema fields out of 217 (10.6%), while the existing migration inventory
still contains 524 handwritten access sites.

## Field inventory and coverage

The probe compares 12 package-level groups:

> `fullPkgName`, `pkgDepInfo`, `imports`, `allFiles`, `allFileImports` count,
> `allTypes` count, `allDecls` count, `allExprs` count, `kind`, `access`,
> `allFileInfo` count, `allDependentStdPkgs`.

It compares 10 fields for every declaration:

> `kind`, `isTopLevel`, `identifier`, `fullPkgName`, `exportId`, `mangledName`,
> `mangledBeforeSema`, `genericArity`, `type`, `infoType`.

`genericArity` traverses both `Decl.generic` and `Generic.typeParameters`; therefore
the 22 reported groups touch 23 declared schema fields. A source-schema inventory
reported:

> `blocks=72 fields=217 Package=17 Decl=18 Generic=2`

Coverage is therefore:

> surface inventory: `22/22 = 100%`; whole generated schema: `23/217 = 10.6%`.

Uncovered examples include package `version`, `cjoVersion`, `allValues`,
`moduleName`, `options`, the contents of `allFileImports`/`allTypes`/`allExprs`,
and the remaining nested declaration tables. They are unresolved, not passed.

## Four-way result

The classification rule is:

> `A`: official readable, manual unreadable; `B`: both readable but unequal;
> `C`: official unreadable, manual readable; `D`: both readable and equal.

The authoritative result was:

> `N=383 A=0 B=0 C=0 D=383 CHECKS=3264858`

There are no non-D corpus instances to list. The negative control below is a
deliberate C instance and names its concrete CJO.

## Controls

Positive control, with the newly built full shim object:

> `RESULT D checks=16141 /root/cleanchain-run/src/cjcj/target/release/parse@cjcj/parse@cjcj.cjo`

Negative control, with `CJOFPackageViewOpen` link-wrapped to return null while the
manual arm remained present:

> `RESULT C checks=0 /root/cleanchain-run/src/cjcj/target/release/parse@cjcj/parse@cjcj.cjo`

Thus the apparatus can observe a non-zero C count and is not merely returning D.

## Trust hardening

The first Cangjie-hosted versions of the extended probe were rejected as an
authoritative device. Under load they produced transient B values, signal 11, and
even impossible zero hash words; immediate serial retries returned D. The final
device is the C++ `surface_probe.cpp`: the official arm still calls the shim C ABI,
while the manual arm ports the same bounds, vtable, indirect-offset, vector, and
string operations without allocating results in the colored Cangjie heap.

The final run was pinned to cores 0-95 and reported:

> `real 0.93`
> `user 0.82`
> `sys 0.11`

Immediately after the authoritative run, the concurrent build-process inventory
contained 0 lines.

## Recipe and provenance

Host and core domain:

> `kkk2`; `taskset -c 0-95`; corpus manifest SHA256
> `16d102807cec2c58cea829b16c722ca38a19678bc561bd63ffe1c584666ebcb1`.

Source lineage:

> cjcj `064229205` (working branch source); Cangjie compiler headers
> `ec27dfa0f77b449042c47b4c21a670185664b449`; LLVM
> `fc16fc667def36249f1f2f2018f8be752c739351`.

Artifacts:

> extended shim object SHA256
> `4bb900fadbe42f204920e7ce2fe155e55dad0e9c2afc07facff25253af10c41b`;
> positive probe SHA256
> `8dfd196f09ca118f1b9540f274d61e8ff57c42e19677412ff5096801443cff51`;
> negative probe SHA256
> `3e51855ad3f6c79cd8cad57bcf728160206ccee179f6867bec09ae7ef5cd5eb2`.

SDK archive and components:

> archive `8715027866b98c72ff92557e9aa2f809152b974b91d0c240bea0fcbf1b9aee7a`;
> runtime `488330e244d01a197b01d19fe12a82545cb2d1239d2524c93256b6ad4c15b693`;
> llc `ee8746160fc339771cc3ed0d67ec9490eab12c299374bb6f856c42f6bff1ea7e`;
> extracted cjc `ed806687b1fa0228b84d18b72e01cdc174d75d140cf5f7dd6267598fb80cb509`.

Runtime self-check:

> `nm -D .../libcangjie-runtime.so | grep -c g_cjLoadBadMask` => `1`.

The task sheet's stated final-cjc hash `998a3686...` is not the cjc contained in
the stated `871502...` archive. A fresh extraction and the pre-expanded directory
both contain `ed806687...`; the archive, runtime, and llc hashes otherwise match.

