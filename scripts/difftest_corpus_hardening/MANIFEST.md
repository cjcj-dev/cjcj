# Corpus-hardening blind-spot programs

These programs exercise language features used heavily in the compiler's own
source but exercised 0x by the existing 113-program difftest corpus. Every file
compiles EXIT=0 and runs to a deterministic result under the REFERENCE compiler
(/root/.cjv/bin/cjc, nightly-1.2.0-alpha.20260619020029), which defines the
expected stdout. They are intended to be run by scripts/difftest.sh against both
the selfhost and reference compilers.

filename | feature guarded | reference stdout (first line) | self-host task most stressed
---------|-----------------|-------------------------------|------------------------------
131_foreign_call.cj | @C `foreign func` declared + CALLED inside `unsafe { }`, result used (libc `abs`) | `7` | #51 (@C/foreign CALL result-type Invalid → CHIRType:325); prereq for #26 CFFI ABI
132_foreign_call_void.cj | foreign func with CString arg via LibC.mallocCString, return used in expr (libc `strlen`) | `5` | #51 (@C/foreign CALL); #26 (CFunc/C-FFI ABI path, CString marshalling)
133_user_iterator_forin.cj | user `class <: Iterable<Int64>` with `iterator()` returning user `Iterator<Int64>` impl (`next(): Option<Int64>`), driven by `for (v in x)` | `10` | #42b (CHIR ForInExpr / user-iterator for-in lowering); #47 (generic iterator enum field-extraction)
134_is_as.cj | class hierarchy A/B; `if (x is B)` and `x as B` (Option), match Some/None branches | `not B` | TypeCast / InstanceOf lowering (runtime type test + downcast)
135_str_interp_multi.cj | multi-segment string interpolation with arithmetic segment, overridden `toString()`, and method-call segment | `3 + 4 = 7, name=(1,2), lbl=P` | expected PASS (locks in no-regression for interpolation desugaring + virtual toString dispatch)
136_overflow_wrapping.cj | `@OverflowWrapping` and `@OverflowSaturating` on Int8 arithmetic that overflows | `-128` | #26 (overflow-strategy casts in codegen-abi)
137_try_finally_throw.cj | `try { throw } catch finally` where body throws; finally runs on throw path | `before throw` | expected PASS (locks in no-regression for exception unwind + finally ordering)
138_try_resource.cj | try-with-resource `try (r = ...) { throw }`; resource `close()` runs before catch | `body 1` | expected PASS (locks in no-regression for try-with-resource desugaring + Resource.close ordering)
139_operator_overload.cj | struct with `operator func +`, `operator func ==`, `operator func []` | `4` | expected PASS (locks in no-regression for operator-overload resolution + struct value semantics)
140_prop_getset.cj | class with `prop` (getter-only) and `mut prop` (get+set); read & write | `21` | expected PASS (locks in no-regression for property getter/setter desugaring)
141_generic_enum.cj | user generic `enum Tree<T> { Leaf(T) | Node(Tree<T>, Tree<T>) }`, recursive pattern-match | `6` | generics (generic enum instantiation + recursive constructor-pattern match)
142_nested_generic_map.cj | nested generics `HashMap<String, ArrayList<Int64>>`; insert, sorted-key iterate | `alpha=3` | generics (nested generic instantiation + stdlib collection codegen)
143_match_guard_range.cj | match with `where`-guards spanning a numeric range, plus `?.` and `??` on runtime Option | `neg` | generics / Option lowering (`?.` question-mark desugaring + `??` coalescing)
144_when_condcomp.cj | `@When[os == "Linux"]` conditional compilation selecting the Linux func overload | `linux` | expected PASS (locks in no-regression for @When conditional-compilation evaluation on Linux)

Note on dropped programs: none dropped. Two programs were adjusted to match the
reference compiler's accepted syntax while keeping the feature genuinely exercised:
- 142: keys sorted via the `sort(ArrayList)` global func from `std.sort` (the
  `ArrayList.sort()` method is deprecated; global `sort` is the current API).
- 143: the literal range pattern `case 0..10 =>` is not accepted as a case pattern
  by the reference cjc ("expected '=>' in case, found '..'"), so the numeric range
  is expressed with a `where`-guard (`case n where n >= 0 && n < 10`). The `?.`/`??`
  operators are driven by Option values returned from a function (not statically
  foldable) so they are exercised at runtime rather than constant-folded away.
