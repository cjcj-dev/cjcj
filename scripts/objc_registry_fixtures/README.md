# ObjC registry companion front-end fixtures

These are test inputs, not an Objective-C runtime implementation. The `objc.internal`
and `objc.lang` modules permit a real stage1 compiler to reach the frontend interop
pipeline on Linux. They do not validate native glue, object lifetime at runtime, or
Darwin execution.

`declarations.cj` exercises the pre-typecheck producer for an implementation registry
companion and a mirror interface handle wrapper. The full member relocation and
constructor tests require cjcj#166's marker constructor prerequisite and remain to
be completed in cjcj#161. Do not interpret a pre-typecheck AST check as evidence for
AfterTypeCheck member relocation.
