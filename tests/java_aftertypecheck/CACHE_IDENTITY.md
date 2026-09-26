# JNI member cache identity

`cache_identity.py --compiler <stage1 ELF> --out <fresh directory>` compiles
`internal.cj`, then `lang.cj`, then the member fixtures with that compiler.
The SDK environment must match the compiler's build environment. Independent
fixtures run two at a time; two runner arms can therefore run concurrently
without exceeding four fixture compiler processes.

The observations are references in the compiler's `5_desugar_ast.txt`, restricted
to the tested member's body. No reconstructed cache implementation is tested.
`First` and `Second` represent different Java members and must refer to disjoint
cache slots. `Alias` represents exactly the same member as `First` and must
reuse its slot. Field getter and setter references must agree. Compilation and
reference presence are recorded separately from these target assertions; all
assertions print a result, including when an earlier observation is missing.

Both field and method fixtures exercise:

| Input | Identity distinction |
|---|---|
| `collision` | `demo/A$$m` + `n` versus `demo/A` + `m$$n`; the old `$$` string key collides |
| `control` | Change the second member to `p$$n`; the original counterexample's positive control |
| `hash_collision` | `demo/A$m` + `n` versus `demo/A` + `m$n`; the upstream-shaped hash input collides, but equality must distinguish the members |
| `class` | Same member name/signature, different declaring Java class |
| `name` | Same Java class/signature, different member name |
| `signature` | Same Java class/name, `Int32` versus `Int64` |
| `staticness` | Same Java class/name/signature, instance versus static |
| `nested` | Literal-dollar `demo.A\\$m` versus nested `demo.A$m`: same JNI spelling, different source class identity |
| `nested_control` | Second is nested `demo.B$m`: distinct JNI spelling control |

The kind discriminator is constructed by the three product factories:
`FromMethod`, `FromConstructor`, and `FromProperty`. Fields and methods live in
separate caches; constructor names are reserved as `<init>`, so legal source
cannot create a pair differing only in kind in one cache. The existing
`mirror_user.cj` covers constructor generation through the normal stage.

Specification: upstream `71b92a0b9ff2f19b6206964efa2c721a2cd218ae`,
`src/Sema/NativeFFI/Java/JavaMemberSignature.cpp:147-162` and
`JavaMemberSignature.h:87-98`; class identity is
`JavaClassSignature.cpp:34-46` and `:117-119`; consumers are
`src/Sema/NativeFFI/Java/CachingApi/JMethodIdCache.cpp:70-89` and
`JFieldIdCache.cpp:65-84`.

Expected causal checks, always using the same ordinary assertions:

- Restoring the old string key in the field cache fails only the field
  `collision` separation assertion.
- Restoring it in the method cache fails only the method `collision` separation
  assertion.
- Replacing member equality with hash equality fails only the two
  `hash_collision` separation assertions.
- Restoring the saved candidate compiler restores all assertions.
- Replacing `FromDecl`'s unqualified-name separator `.` with `$`, or comparing
  `classTypeJniName` instead of `classSignature`, fails only the two `nested`
  separation assertions. Alias reuse and `nested_control` stay green.

These tests establish compiler AST cache identity. They do not claim execution
of JNI calls in a Java VM; the imported JNI declarations are compilation fixtures.
