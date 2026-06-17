export const meta = {
  name: 'selfhost-opus-enum-payload',
  description: 'Add payload-carrying enum variants (tagged unions) with destructuring match patterns to the real body path: single Int64 payload, then String payload and multi-variant payloads; incremental cuts; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus16"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists; read docs/DEISOLATION_PLAN.md and study\n" +
  "`git log --oneline -28`. Real path: packages/chir/src/TranslateFuncBody.cj (CreateRealBody) + statement/\n" +
  "expr model in AST2CHIR.cj (hasRealBody), gated in TranslateFuncDecl.cj; frontend real-parse adapter in\n" +
  "packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj. PAYLOAD-LESS enums already work (variant =\n" +
  "Int64 tag; match-on-variant) — study `git show 8b38261`. match (literal/wildcard/binding) works. Arrays,\n" +
  "String, struct-like tuples may exist in codegen (CGEnumType.cj, CGTupleType.cj, CGStructType.cj). The real\n" +
  "parser parses payload variants (EnumDecl constructors with type args) and destructuring EnumPattern\n" +
  "`case Ctor(binding)`. Represent a payload enum value as a {tag, payload...} aggregate (tuple/struct or the\n" +
  "existing CHIR enum support — investigate which is simplest to lower correctly).\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/String(+interpolation)/control-flow/loops/break-continue/\n" +
  "funcs+recursion/Array<Int64>/match-on-Int64/payload-less enums + all print forms. Real programs (FizzBuzz,\n" +
  "fib, repeat->ababab, array find-max->8, enum opp->1) work end-to-end — keep them working.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    landedCut: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs/exit codes for the payload-enum programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus16/enum-payload"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/p 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/p\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/p main\n" +
  "  cd " + WTROOT + "/p\n\n" +
  "TASK: Add PAYLOAD-CARRYING enum variants (tagged unions) to the REAL body path, INCREMENTALLY (commit each\n" +
  "cut green+verified). Construction stores tag+payload; destructuring match `case Ctor(x) =>` binds the payload.\n" +
  "  CUT 1 (single Int64 payload): \n" +
  "    enum Opt { | Some(Int64) | None }\\n func unwrap(o: Opt, dflt: Int64): Int64 { match (o) { case Some(n) => return n\\n case None => return dflt } }\\n main(): Int64 { return unwrap(Some(42), 0) } -> exit 42\n" +
  "    ... main(): Int64 { return unwrap(None, 7) } -> exit 7\n" +
  "    enum Expr { | Lit(Int64) | Neg(Int64) }\\n func eval(e: Expr): Int64 { match (e) { case Lit(n) => return n\\n case Neg(n) => return 0 - n } }\\n main() { println(eval(Neg(5))) } -> prints `-5`\n" +
  "  CUT 2 (mix payload + payload-less in one enum; multiple distinct payload variants): handled by CUT1 design;\n" +
  "    verify eval(Lit(9)) -> 9 and a 3-variant enum.\n" +
  "  CUT 3 (stretch): String payload (enum Msg { | Text(String) | Empty }; match case Text(s) => println(s)).\n" +
  "Keep ADDITIVE + GATED: unsupported forms fall back (no regression). Verify each landed cut via real\n" +
  "compile+run. Re-run ALREADY-VERIFIED slices (payload-less enum color->1, match valexpr->200, array\n" +
  "find-max->8, interp x=42, FizzBuzz, fib loop, repeat->ababab, fact(5)->120, mixed->123). If only CUT 1\n" +
  "lands cleanly, that is strong progress — commit it and report landedCut ACCURATELY (independent verifier\n" +
  "re-checks every claim; do NOT over-claim). Build green at each commit. Commit on " + BRANCH + ". Return\n" +
  "schema; evidence MUST be real run outputs (esp. unwrap(Some(42))->42 and eval(Neg(5))->-5).",
  { schema: SCHEMA, phase: 'Implement', label: 'enum-payload', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " landed=" + (impl && impl.landedCut) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "enum-payload slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "The enum-payload work landed these cuts (per implementer): " + (impl.landedCut || "(unknown)") + ".\n" +
  "Re-verify LANDED cuts with real runs AND this regression set (every line must hold):\n" +
  "  enum Opt { | Some(Int64) | None }\\n func unwrap(o: Opt, d: Int64): Int64 { match(o){case Some(n)=>return n\\n case None=>return d} }\\n main(): Int64 { return unwrap(Some(42),0) } -> 42 ; unwrap(None,7) -> 7\n" +
  "  enum Expr { | Lit(Int64) | Neg(Int64) }\\n func eval(e: Expr): Int64 { match(e){case Lit(n)=>return n\\n case Neg(n)=>return 0-n} }\\n main(){ println(eval(Neg(5))) } -> -5 ; eval(Lit(9)) -> 9\n" +
  "  enum Color { | Red | Green | Blue }\\n main(): Int64 { let c=Green\\n match(c){case Red=>return 0\\n case Green=>return 1\\n case Blue=>return 2} } -> 1\n" +
  "  main() { let x=42\\n println(\"x=${x}\") } -> x=42 ; array find-max [5,3,8,1] -> 8 ; FizzBuzz 1..15 correct\n" +
  "  fib loop -> 0 1 1 2 3 5 8 13 21 34 ; repeat(\"ab\",3) -> ababab ; match valexpr -> 200\n" +
  "  func fact(n: Int64): Int64 {...}\\n main(): Int64 { return fact(5) } -> 120 ; main(){print(1)\\n print(2)\\n let y=1+2\\n println(y)} -> 123\n" +
  "Only verify cuts that actually landed. Refresh docs/STATUS.md with the enum-payload milestone + remaining\n" +
  "gaps (structs/classes, Float64, lambdas, generics, collections, silent-fallback hardening). Clean up\n" +
  "worktrees (git worktree remove --force " + WTROOT + "/p + prune + rm -rf " + WTROOT + "). Commit. Return\n" +
  "schema (verified=ALL applicable pass).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, landedCut: impl.landedCut, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
