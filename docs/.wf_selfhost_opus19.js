export const meta = {
  name: 'selfhost-opus-recursive-enums',
  description: 'Allow enum-typed payload fields so recursive enums (AST trees, cons-lists) work: a recursive expression evaluator and a linked-list sum compile and run on the real body path; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus19"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL body-lowering path exists; read docs/DEISOLATION_PLAN.md and `git log --oneline -32`.\n" +
  "Real path: packages/chir/src/TranslateFuncBody.cj + statement/expr model in AST2CHIR.cj (hasRealBody),\n" +
  "gated in TranslateFuncDecl.cj; frontend adapter in packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj.\n" +
  "MULTI-FIELD payload enums already work (study `git show 61b0ff8`): a multi-field enum value is a heap buffer\n" +
  "{tag, f0..fN} of Int64 slots; the enum VALUE is the buffer address reinterpreted as Int64 (ptrtoint), and\n" +
  "destructuring inttoptr+GEP+Load each slot. Crucially: ANY enum value is already encoded as an Int64. So an\n" +
  "enum-typed payload field can be stored in an Int64 slot holding the child's encoded value.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/String(+interp)/control-flow/loops/break-continue/funcs+\n" +
  "recursion/Array<Int64>/match/enums(payload-less, single+multi Int64 payload incl large/negative values).\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    supported: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs for the recursive-enum programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus19/recursive-enums"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/r 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/r\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/r main\n" +
  "  cd " + WTROOT + "/r\n\n" +
  "TASK: Allow ENUM-TYPED payload fields so RECURSIVE enums work. A payload field whose declared type is an\n" +
  "enum (including the same enum, i.e. recursive) is stored in its Int64 slot as the child's encoded enum\n" +
  "value (the existing Int64 encoding). Construction stores the child's value; destructuring binds the field\n" +
  "as that enum type so it can be matched/passed recursively. Generalize the adapter's field-type gate from\n" +
  "'all Int64' to 'Int64 or a supported enum type' (treat enum-typed fields as Int64 slots; track the field's\n" +
  "enum type so the bound variable has the right type for nested match/calls). Any multi-field variant should\n" +
  "use the heap-buffer representation so recursion is unbounded.\n" +
  "PRIMARY TARGETS (verify with real compile+run):\n" +
  "  enum Expr { | Lit(Int64) | Add(Expr, Expr) | Mul(Expr, Expr) }\\n" +
  "  func ev(e: Expr): Int64 { match (e) { case Lit(n) => return n\\n case Add(a, b) => return ev(a) + ev(b)\\n case Mul(a, b) => return ev(a) * ev(b) } }\\n" +
  "  main() { println(ev(Add(Lit(3), Mul(Lit(4), Lit(5))))) }    -> prints 23\n" +
  "  main() { println(ev(Add(Add(Lit(1), Lit(2)), Add(Lit(3), Lit(4))))) }  -> prints 10\n" +
  "  enum List { | Nil | Cons(Int64, List) }\\n" +
  "  func sum(l: List): Int64 { match (l) { case Nil => return 0\\n case Cons(h, t) => return h + sum(t) } }\\n" +
  "  main() { println(sum(Cons(1, Cons(2, Cons(3, Nil))))) }    -> prints 6\n" +
  "  func len(l: List): Int64 { match (l) { case Nil => return 0\\n case Cons(h, t) => return 1 + len(t) } }\\n main() { println(len(Cons(7, Cons(8, Nil)))) } -> prints 2\n" +
  "Keep ADDITIVE + GATED: unsupported forms fall back (no regression). Re-run ALREADY-VERIFIED slices\n" +
  "(multi-field ev(Add(3,4))->7 [non-recursive int args still ok], large-value ev(Add(1000000000,2000000000))\n" +
  "->3000000000, single-payload Some(42)->42, payload-less color->1, array find-max->8, interp x=42, FizzBuzz,\n" +
  "fib loop, repeat->ababab, fact(5)->120, mixed->123). Commit green at each step on " + BRANCH + ". Report\n" +
  "honestly (independent verifier WILL run the recursive tests). Return schema; evidence MUST include the\n" +
  "recursive AST eval ->23 and the cons-list sum ->6.",
  { schema: SCHEMA, phase: 'Implement', label: 'recursive-enums', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "recursive-enums slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main ONLY IF it passes; keep green, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "Re-verify with real runs — EVERY line must hold (if any recursive target fails, the field-type handling is\n" +
  "wrong: `git reset --hard <pre-merge HEAD>` and report verified=false):\n" +
  "  enum Expr{|Lit(Int64)|Add(Expr,Expr)|Mul(Expr,Expr)}\\n func ev(e:Expr):Int64{match(e){case Lit(n)=>return n\\n case Add(a,b)=>return ev(a)+ev(b)\\n case Mul(a,b)=>return ev(a)*ev(b)}}\\n main(){println(ev(Add(Lit(3),Mul(Lit(4),Lit(5)))))} -> 23\n" +
  "  ... main(){println(ev(Add(Add(Lit(1),Lit(2)),Add(Lit(3),Lit(4)))))} -> 10\n" +
  "  enum List{|Nil|Cons(Int64,List)}\\n func sum(l:List):Int64{match(l){case Nil=>return 0\\n case Cons(h,t)=>return h+sum(t)}}\\n main(){println(sum(Cons(1,Cons(2,Cons(3,Nil)))))} -> 6\n" +
  "  multi-field ev(Add(3,4))->7 (non-recursive) ; large ev(Add(1000000000,2000000000))->3000000000\n" +
  "  single Some(42)->42 ; color->1 ; array find-max->8 ; interp x=42 ; FizzBuzz correct ; fib loop ok ; repeat->ababab ; fact(5)->120 ; mixed->123\n" +
  "If all pass: refresh docs/STATUS.md (RECURSIVE enums / AST trees compile — a recursive expression evaluator\n" +
  "and cons-list both run) + remaining gaps (structs/classes, Float64, generics, collections, modules). Commit.\n" +
  "Else reset and report verified=false. Clean up worktrees (git worktree remove --force " + WTROOT +
  "/r + prune + rm -rf " + WTROOT + "). Return schema.",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, supported: impl.supported, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
