export const meta = {
  name: 'selfhost-opus-arrays',
  description: 'Add Array<Int64> support to the real body path: array literals, index read, .size, index write/mutation, and for-in over an array; incremental cuts; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus13"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists; read docs/DEISOLATION_PLAN.md and study\n" +
  "`git log --oneline -22`. Real path: packages/chir/src/TranslateFuncBody.cj (CreateRealBody) + statement/\n" +
  "expr model in AST2CHIR.cj (hasRealBody), gated in TranslateFuncDecl.cj; frontend real-parse adapter in\n" +
  "packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj. The real parser (packages/parse) parses array\n" +
  "literals (ArrayLit) and subscripts (SubscriptExpr). For the runtime Array<Int64> representation, INVESTIGATE\n" +
  "packages/codegen (CGArrayType.cj, CGVArrayType.cj, ArrayImpl.cj, AllocateImpl.cj) and how the REFERENCE\n" +
  "cjc at /root/cj_build/cangjie_compiler lowers `[1,2,3]`, indexing, `.size`, and array allocation (inspect\n" +
  "the reference C++ + runtime symbols). Use the CHIR/codegen array + allocate primitives.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/String(+interpolation)/control-flow/loops(for+while)/\n" +
  "break/continue/funcs/recursion + all print forms. Real programs FizzBuzz, recursive fib loop,\n" +
  "repeat(\"ab\",3)->ababab, and interpolation (\"x=${x}\"->x=42) work end-to-end — keep them working.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    landedCut: { type: "string", description: "which array cuts actually landed+verified by real run" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs for the array programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus13/arrays"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/a 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/a\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/a main\n" +
  "  cd " + WTROOT + "/a\n\n" +
  "TASK: Add Array<Int64> support to the REAL body path, INCREMENTALLY. Land each cut\n" +
  "GREEN+VERIFIED+committed before the next so partial progress is preserved:\n" +
  "  CUT 1: array literal `[e0, e1, ...]` (Int64 elements) bound to a let/var, index READ `a[i]`, and `.size`.\n" +
  "    Targets: main() { let a = [10,20,30]\\n println(a[1]) } -> 20 ; main(){ let a=[10,20,30]\\n println(a.size) } -> 3\n" +
  "  CUT 2: index WRITE / mutation `a[i] = expr`.\n" +
  "    Target: main(): Int64 { let a = [0,0,0]\\n a[1] = 7\\n return a[1] } -> exit 7\n" +
  "  CUT 3: for-in over an array binds each element.\n" +
  "    Target: main(): Int64 { let a = [1,2,3,4]\\n var s = 0\\n for (x in a) { s = s + x }\\n return s } -> exit 10\n" +
  "  CUT 4 (stretch): `Array<Int64>(n, repeat: 0)` or `Array<Int64>(n, item: 0)` sized constructor + index loop fill.\n" +
  "Use the runtime Array<Int64> representation (study reference + codegen CGArrayType/ArrayImpl/AllocateImpl).\n" +
  "Keep ADDITIVE + GATED: unsupported constructs fall back to the existing path (no regression).\n" +
  "Verify each landed cut via real compile+run. If only CUT 1 lands cleanly, that is acceptable progress —\n" +
  "commit it and report landedCut ACCURATELY (do NOT claim cuts you didn't actually run; an independent\n" +
  "verifier will re-check every claim). Re-run ALREADY-VERIFIED slices (FizzBuzz, fib loop, repeat->ababab,\n" +
  "interp x=42, while_break->10, fact(5)->120, mixed->123). Build green at each commit. Commit on " + BRANCH + ".\n" +
  "Return schema; evidence MUST be real run outputs; set landedCut to exactly what you verified.",
  { schema: SCHEMA, phase: 'Implement', label: 'arrays', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " landed=" + (impl && impl.landedCut) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "arrays slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "The array work landed these cuts (per implementer): " + (impl.landedCut || "(unknown)") + ".\n" +
  "Re-verify the LANDED array cuts with real runs AND this regression set (every line must hold):\n" +
  "  main() { let a = [10,20,30]\\n println(a[1]) } -> 20 ; main(){ let a=[10,20,30]\\n println(a.size) } -> 3  (CUT1)\n" +
  "  main(): Int64 { let a=[0,0,0]\\n a[1]=7\\n return a[1] } -> exit 7  (CUT2)\n" +
  "  main(): Int64 { let a=[1,2,3,4]\\n var s=0\\n for (x in a){ s=s+x }\\n return s } -> exit 10  (CUT3)\n" +
  "  main() { let x=42\\n println(\"x=${x}\") } -> x=42 ; func repeat... repeat(\"ab\",3) -> ababab\n" +
  "  FizzBuzz 1..15 correct ; fib loop 0..9 -> 0 1 1 2 3 5 8 13 21 34\n" +
  "  main(): Int64 { var s=0\\n var i=0\\n while(i<100){i=i+1\\n if(i==5){break}\\n s=s+i}\\n return s } -> 10\n" +
  "  func fact(n: Int64): Int64 {...}\\n main(): Int64 { return fact(5) } -> 120 ; main(){print(1)\\n print(2)\\n let y=1+2\\n println(y)} -> 123\n" +
  "Only verify array cuts that actually landed (per landedCut). Refresh docs/STATUS.md with the array milestone\n" +
  "(which cuts) + remaining gaps (match/enums, structs/classes, Float64, lambdas, generics, silent-fallback\n" +
  "hardening). Clean up worktrees (git worktree remove --force " + WTROOT + "/a + prune + rm -rf " + WTROOT +
  "). Commit. Return schema (verified=ALL applicable pass).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, landedCut: impl.landedCut, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
