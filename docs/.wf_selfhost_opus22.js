export const meta = {
  name: 'selfhost-opus-classes',
  description: 'Add classes to the real body path: reference-semantics objects with fields/methods, aliasing, and single inheritance (inherited fields+methods); incremental cuts; branch-based; then merge and re-verify',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL body-lowering path exists; read docs/DEISOLATION_PLAN.md and `git log --oneline -38`.\n" +
  "Real path: packages/chir/src/TranslateFuncBody.cj + statement/expr model in AST2CHIR.cj (hasRealBody),\n" +
  "gated in TranslateFuncDecl.cj; frontend adapter in packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj.\n" +
  "STRUCTS already work via a heap buffer of Int64 slots (study `git show 72c7422`/`c406eea`): fields by\n" +
  "index, methods (this = the buffer address), construction, params/returns. CLASSES are REFERENCE types, so\n" +
  "the SAME heap-buffer rep is semantically correct for them (a class value is the heap address; copying the\n" +
  "value copies the reference, so aliasing works for free). codegen has CGClassType.cj.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/Float64/String(+interp)/control-flow/loops/break-continue/\n" +
  "funcs+recursion/Array<Int64>/match/enums(incl recursive)/structs(fields,methods,params) + all print forms.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    landedCut: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs/exit codes incl the aliasing test" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus22/classes"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Work on a BRANCH IN THE MAIN REPO (NO separate worktree):\n" +
  "  cd " + REPO + "\n" +
  "  git checkout main && git branch -D " + BRANCH + " 2>/dev/null; git checkout -b " + BRANCH + "\n" +
  "Do all edits/builds/runs in " + REPO + " on branch " + BRANCH + ". Commit there.\n\n" +
  "TASK: Add CLASSES (reference types) to the REAL body path, INCREMENTALLY (commit each cut green+verified).\n" +
  "Reuse the struct heap-buffer rep; the distinguishing semantics is REFERENCE/aliasing + inheritance.\n" +
  "  CUT 1: class with Int64 fields + init + instance methods; construct; call methods; read fields.\n" +
  "    class Counter { var n: Int64\\n init(n: Int64) { this.n = n }\\n func get(): Int64 { return this.n }\\n func inc(): Unit { this.n = this.n + 1 } }\\n main(): Int64 { let c = Counter(0)\\n c.inc()\\n c.inc()\\n return c.get() } -> exit 2\n" +
  "  CUT 2: REFERENCE ALIASING — assigning a class value shares the object; mutation via one ref is visible\n" +
  "    via another (this is the key class-vs-struct test).\n" +
  "    ... main(): Int64 { let a = Counter(5)\\n let b = a\\n b.inc()\\n return a.get() } -> exit 6\n" +
  "  CUT 3: SINGLE INHERITANCE — a subclass inherits the parent's fields and methods.\n" +
  "    open class Animal { var legs: Int64\\n init() { this.legs = 4 } }\\n class Dog <: Animal { init() { super() } }\\n main(): Int64 { let d = Dog()\\n return d.legs } -> exit 4\n" +
  "    open class Base { func greet(): Int64 { return 1 } }\\n class Sub <: Base { init() {} }\\n main(): Int64 { let s = Sub()\\n return s.greet() } -> exit 1\n" +
  "  CUT 4 (stretch): method OVERRIDE with dynamic dispatch (open/override + a virtual call through the base type).\n" +
  "Keep ADDITIVE + GATED: unsupported forms fall back (no regression). Verify each landed cut via real\n" +
  "compile+run (compare to /root/.cjv/bin/cjc if unsure of semantics). Re-run ALREADY-VERIFIED slices\n" +
  "(struct dist2->25, recursive AST ev->23, cons-list sum->6, Float add==ref, array find-max->8, interp x=42,\n" +
  "FizzBuzz, fib loop, repeat->ababab, fact(5)->120, mixed->123). If only CUT 1+2 land cleanly, that's good —\n" +
  "commit and report landedCut ACCURATELY (independent verifier re-checks; do NOT over-claim). Build green at\n" +
  "each commit on " + BRANCH + ". Return schema; evidence MUST include the aliasing test (a.get()->6).",
  { schema: SCHEMA, phase: 'Implement', label: 'classes' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " landed=" + (impl && impl.landedCut) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "classes slice not landed; restoring main", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main ONLY IF it passes; keep green; refresh status.\n" +
  "  cd " + REPO + " && git checkout main && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "The class work landed these cuts (per implementer): " + (impl.landedCut || "(unknown)") + ".\n" +
  "Re-verify LANDED class cuts with real runs AND this regression set — every applicable line must hold (if a\n" +
  "landed-cut target fails, `git reset --hard <pre-merge HEAD>` and report verified=false):\n" +
  "  class Counter{var n:Int64\\n init(n:Int64){this.n=n}\\n func get():Int64{return this.n}\\n func inc():Unit{this.n=this.n+1}}\\n main():Int64{let c=Counter(0)\\n c.inc()\\n c.inc()\\n return c.get()} -> 2  (CUT1)\n" +
  "  ... main():Int64{let a=Counter(5)\\n let b=a\\n b.inc()\\n return a.get()} -> 6  (CUT2 aliasing)\n" +
  "  open class Animal{var legs:Int64\\n init(){this.legs=4}}\\n class Dog<:Animal{init(){super()}}\\n main():Int64{let d=Dog()\\n return d.legs} -> 4  (CUT3)\n" +
  "  struct dist2->25 ; recursive AST ev->23 ; cons-list sum->6 ; Float (println(3.5+2.0)) == reference\n" +
  "  array find-max->8 ; interp x=42 ; FizzBuzz correct ; fib loop ok ; repeat->ababab ; fact(5)->120 ; mixed->123\n" +
  "Only verify cuts that landed. Refresh docs/STATUS.md with the class milestone + remaining gaps (interfaces/\n" +
  "dynamic dispatch, generics, collections, modules, silent-fallback hardening). Commit. Else reset and report\n" +
  "verified=false. Return schema.",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, landedCut: impl.landedCut, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
