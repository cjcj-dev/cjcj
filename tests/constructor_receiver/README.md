# Constructor receiver consumer

Status: NOT_RUN. Requires the reviewed receiver-returning compiler, CJO major 1 target std, and the fixed qualified N/R pair. The 8ba3/old-N install is not a valid producer for this case.

Run through the installed `bin/cjc`, at both `-O0` and `-O2`, then run the emitted native executable. `consumer.cj` covers explicit Object(), a super chain, delegated this(), post-construction field/method access, ordinary and finalizable receivers, struct ABI control, and an escaping constructor exception. Preserve argv/environment, compiler/runtime identities, compiler and child rc/signal separately.

Passing this program alone does not prove that registration returned a moved reference. The R2 exact cut must disconnect the production registration result store (Translator.EmitObjectInitReturn) and use the normal frontend/IR consumer to detect that disconnection; ordinary/struct controls must still pass. The new CHIR serialization/inline tests check the reference data path, and the frontend test consumes real source. Those unit tests do not replace this native entrance or the paired runtime relocation evidence. Normal/cut/restored execution and relocation evidence remain NOT_RUN.

Cross-module production must rebuild the target std and every CJO consumer with the same CJO major 1 / CHIR CR01 compiler ABI; no old-CJO fallback is permitted. Do not relabel old host executables or archives.
