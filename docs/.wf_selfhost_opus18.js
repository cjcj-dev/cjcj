export const meta = {
  name: 'selfhost-opus-enum-multi2',
  description: 'Multi-Int64-field enum variants done CORRECTLY: each field is its own slot in a {tag, f0, f1, ...} aggregate (NO bit-packing), with multi-binding destructuring; verified incl large values; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus18"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL body-lowering path exists; read docs/DEISOLATION_PLAN.md and `git log --oneline -30`.\n" +
  "Real path: packages/chir/src/TranslateFuncBody.cj + statement/expr model in AST2CHIR.cj (hasRealBody),\n" +
  "gated in TranslateFuncDecl.cj; frontend adapter in packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj.\n" +
  "SINGLE-Int64-payload enums already work (study `git show 148b84d`): a payload enum value is a {tag, payload}\n" +
  "aggregate; `case Ctor(n)` binds the payload. Codegen has aggregate/tuple/struct support (CGTupleType.cj,\n" +
  "CGStructType.cj, CGEnumType.cj) and array/allocate primitives.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/String(+interp)/control-flow/loops/break-continue/funcs+\n" +
  "recursion/Array<Int64>/match/payload-less enums/single-Int64-payload enums + all print forms.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    representation: { type: "string", description: "how a multi-field payload value is represented (MUST be separate slots, not bit-packed)" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs incl the LARGE-value test" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus18/enum-multi2"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/em 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/em\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/em main\n" +
  "  cd " + WTROOT + "/em\n\n" +
  "TASK: Support enum variants with MULTIPLE Int64 payload fields, represented CORRECTLY. \n" +
  "CRITICAL CONSTRAINT: each payload field MUST be stored in its OWN slot of a {tag, f0, f1, ...} aggregate\n" +
  "(generalize the existing single-payload {tag, payload} aggregate to N+1 slots — e.g. a heap struct/tuple\n" +
  "or an N+1-length Int64 array). Do NOT bit-pack multiple fields into a single Int64 (that is lossy and\n" +
  "WRONG for large values). Construction stores each field in its slot; destructuring `case Ctor(a, b, c) =>`\n" +
  "loads each field in order and binds them. Mix freely with payload-less and single-payload variants.\n" +
  "PRIMARY TARGETS (verify with real compile+run):\n" +
  "  enum E { | Num(Int64) | Add(Int64, Int64) | Mul(Int64, Int64) }\\n" +
  "  func ev(e: E): Int64 { match (e) { case Num(n) => return n\\n case Add(a, b) => return a + b\\n case Mul(a, b) => return a * b } }\\n" +
  "  main() { println(ev(Add(3, 4)))\\n println(ev(Mul(6, 7)))\\n println(ev(Num(99))) }   -> 7 / 42 / 99\n" +
  "  enum Tri { | P(Int64, Int64, Int64) | Z }\\n func sum3(t: Tri): Int64 { match (t) { case P(a,b,c) => return a+b+c\\n case Z => return 0 } }\\n main(): Int64 { return sum3(P(10,20,5)) } -> exit 35\n" +
  "  LARGE-VALUE TEST (this FAILS if you bit-pack — it must pass):\n" +
  "    enum E { | Add(Int64, Int64) }\\n func ev(e: E): Int64 { match (e) { case Add(a,b) => return a + b } }\\n main() { println(ev(Add(1000000000, 2000000000))) } -> prints 3000000000\n" +
  "  (regression) single-payload Some(42)->42 ; payload-less color->1.\n" +
  "Keep ADDITIVE + GATED: unsupported forms fall back (no regression). Re-run ALREADY-VERIFIED slices\n" +
  "(single-payload Some(42)->42 & Neg(5)->-5, payload-less color->1, match valexpr->200, array find-max->8,\n" +
  "interp x=42, FizzBuzz, fib loop, repeat->ababab, fact(5)->120, mixed->123). Commit green at each step on\n" +
  BRANCH + ". In the schema set `representation` to exactly how you store fields (must be separate slots).\n" +
  "Report honestly (independent verifier WILL run the large-value test). Return schema; evidence MUST include\n" +
  "ev(Add(3,4))->7, sum3(P(10,20,5))->35, and ev(Add(1000000000,2000000000))->3000000000.",
  { schema: SCHEMA, phase: 'Implement', label: 'enum-multi2', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " rep=" + (impl && impl.representation) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "enum-multi2 slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main ONLY IF it passes verification; keep green, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "Re-verify with real runs — EVERY line must hold (if the large-value test fails, the representation is\n" +
  "wrong: do NOT leave a broken merge — reset main to before the merge and report verified=false):\n" +
  "  enum E{|Num(Int64)|Add(Int64,Int64)|Mul(Int64,Int64)}\\n func ev(e:E):Int64{match(e){case Num(n)=>return n\\n case Add(a,b)=>return a+b\\n case Mul(a,b)=>return a*b}}\\n main(){println(ev(Add(3,4)))\\n println(ev(Mul(6,7)))\\n println(ev(Num(99)))} -> 7/42/99\n" +
  "  enum Tri{|P(Int64,Int64,Int64)|Z}\\n func sum3(t:Tri):Int64{match(t){case P(a,b,c)=>return a+b+c\\n case Z=>return 0}}\\n main(): Int64{return sum3(P(10,20,5))} -> 35\n" +
  "  enum E{|Add(Int64,Int64)}\\n func ev(e:E):Int64{match(e){case Add(a,b)=>return a+b}}\\n main(){println(ev(Add(1000000000,2000000000)))} -> 3000000000  (LARGE-VALUE)\n" +
  "  single-payload Some(42)->42 ; payload-less color->1 ; array find-max [5,3,8,1]->8 ; interp x=42 -> x=42\n" +
  "  FizzBuzz 1..15 correct ; fib loop -> 0 1 1 2 3 5 8 13 21 34 ; repeat(\"ab\",3)->ababab ; fact(5)->120 ; mixed->123\n" +
  "If all pass: refresh docs/STATUS.md (multi-field enums correct; a small ADT interpreter compiles) and commit.\n" +
  "If the large-value or any line fails: `git reset --hard <pre-merge HEAD>` so main stays at its prior good\n" +
  "state, and report verified=false with the failure. Clean up worktrees (git worktree remove --force " +
  WTROOT + "/em + prune + rm -rf " + WTROOT + "). Return schema.",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, representation: impl.representation, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
