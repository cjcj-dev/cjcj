export const meta = {
  name: 'selfhost-opus-enum-multi',
  description: 'Extend payload enums to multiple Int64 fields per variant (e.g. Add(Int64,Int64)) with multi-binding destructuring, enabling a small ADT interpreter; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus17"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists; read docs/DEISOLATION_PLAN.md and study\n" +
  "`git log --oneline -30`. Real path: packages/chir/src/TranslateFuncBody.cj + statement/expr model in\n" +
  "AST2CHIR.cj (hasRealBody), gated in TranslateFuncDecl.cj; frontend adapter in packages/frontend/src/\n" +
  "RealParseBridge.cj + CodeGenBridge.cj. SINGLE-Int64-payload enums already work (study `git show 148b84d`):\n" +
  "a payload enum value is represented as a {tag, payload} aggregate; `case Ctor(n)` binds the payload. match,\n" +
  "arrays, recursion all work.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/String(+interp)/control-flow/loops/break-continue/funcs+\n" +
  "recursion/Array<Int64>/match/payload-less enums/single-Int64-payload enums (Some(42)->42, eval(Neg(5))->-5)\n" +
  "+ all print forms. Real programs (FizzBuzz, fib, repeat->ababab, array find-max->8) work — keep them working.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    landedCut: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs for the multi-field enum / interpreter programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus17/enum-multi"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/em 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/em\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/em main\n" +
  "  cd " + WTROOT + "/em\n\n" +
  "TASK: Extend payload enums to support MULTIPLE Int64 fields per variant (generalize the {tag, payload}\n" +
  "representation to {tag, field0, field1, ...}). Construction stores all fields; destructuring\n" +
  "`case Ctor(a, b) =>` binds each field in order. Mix freely with payload-less and single-payload variants.\n" +
  "PRIMARY TARGETS (verify with real compile+run):\n" +
  "  enum E { | Num(Int64) | Add(Int64, Int64) | Mul(Int64, Int64) }\\n" +
  "  func ev(e: E): Int64 { match (e) { case Num(n) => return n\\n case Add(a, b) => return a + b\\n case Mul(a, b) => return a * b } }\\n" +
  "  main() { println(ev(Add(3, 4)))\\n println(ev(Mul(6, 7)))\\n println(ev(Num(99))) }   -> prints 7, 42, 99\n" +
  "  enum Tri { | P(Int64, Int64, Int64) | Z }\\n func sum3(t: Tri): Int64 { match (t) { case P(a,b,c) => return a+b+c\\n case Z => return 0 } }\\n main(): Int64 { return sum3(P(10,20,5)) }  -> exit 35\n" +
  "  (regression) single-payload still works: enum Opt{|Some(Int64)|None}\\n unwrap(Some(42),0) -> 42\n" +
  "STRETCH (only if clean): a recursive/boxed enum via Array indices or an explicit heap rep is NOT required;\n" +
  "stay with flat multi-Int64-field variants this run.\n" +
  "Keep ADDITIVE + GATED: unsupported forms fall back (no regression). Re-run ALREADY-VERIFIED slices\n" +
  "(payload-less color->1, single-payload Some(42)->42 & Neg(5)->-5, match valexpr->200, array find-max->8,\n" +
  "interp x=42, FizzBuzz, fib loop, repeat->ababab, fact(5)->120, mixed->123). Commit green at each step on\n" +
  BRANCH + ". Report landedCut ACCURATELY (independent verifier re-checks; do NOT over-claim). Return schema;\n" +
  "evidence MUST include ev(Add(3,4))->7 and sum3(P(10,20,5))->35.",
  { schema: SCHEMA, phase: 'Implement', label: 'enum-multi', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " landed=" + (impl && impl.landedCut) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "enum-multi slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "Re-verify with real runs (every line must hold):\n" +
  "  enum E { | Num(Int64) | Add(Int64, Int64) | Mul(Int64, Int64) }\\n func ev(e: E): Int64 { match(e){case Num(n)=>return n\\n case Add(a,b)=>return a+b\\n case Mul(a,b)=>return a*b} }\\n main(){ println(ev(Add(3,4)))\\n println(ev(Mul(6,7)))\\n println(ev(Num(99))) } -> 7 / 42 / 99\n" +
  "  enum Tri { | P(Int64,Int64,Int64) | Z }\\n func sum3(t: Tri): Int64 { match(t){case P(a,b,c)=>return a+b+c\\n case Z=>return 0} }\\n main(): Int64 { return sum3(P(10,20,5)) } -> 35\n" +
  "  enum Opt{|Some(Int64)|None}\\n func unwrap(o:Opt,d:Int64):Int64{match(o){case Some(n)=>return n\\n case None=>return d}}\\n main(): Int64 { return unwrap(Some(42),0) } -> 42\n" +
  "  enum Color{|Red|Green|Blue}\\n main(): Int64 { let c=Green\\n match(c){case Red=>return 0\\n case Green=>return 1\\n case Blue=>return 2} } -> 1\n" +
  "  array find-max [5,3,8,1] -> 8 ; main(){let x=42\\n println(\"x=${x}\")} -> x=42 ; FizzBuzz 1..15 correct\n" +
  "  fib loop -> 0 1 1 2 3 5 8 13 21 34 ; repeat(\"ab\",3) -> ababab ; match valexpr -> 200\n" +
  "  func fact(n:Int64):Int64{...}\\n main(): Int64 { return fact(5) } -> 120 ; main(){print(1)\\n print(2)\\n let y=1+2\\n println(y)} -> 123\n" +
  "Refresh docs/STATUS.md with the multi-field-enum milestone (note: a small ADT interpreter now compiles) +\n" +
  "remaining gaps (structs/classes, recursive/generic enums, Float64, lambdas, generics, collections, silent-\n" +
  "fallback hardening). Clean up worktrees (git worktree remove --force " + WTROOT + "/em + prune + rm -rf " +
  WTROOT + "). Commit. Return schema (verified=ALL pass).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, landedCut: impl.landedCut, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
