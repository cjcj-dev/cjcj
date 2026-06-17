export const meta = {
  name: 'selfhost-opus-enums',
  description: 'Add enums to the real body path: payload-less enums (variant tag + match-on-variant) first, then single-Int64-payload variants with destructuring patterns; incremental cuts; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus15"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists; read docs/DEISOLATION_PLAN.md and study\n" +
  "`git log --oneline -26`. Real path: packages/chir/src/TranslateFuncBody.cj (CreateRealBody) + statement/\n" +
  "expr model in AST2CHIR.cj (hasRealBody), gated in TranslateFuncDecl.cj; frontend real-parse adapter in\n" +
  "packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj. `match` on Int64 just landed (literal/wildcard/\n" +
  "binding patterns, as stmt + value expr) — reuse that machinery. The real parser parses enum decls\n" +
  "(EnumDecl, constructors) and enum/constructor patterns (EnumPattern). For payload-less enums the simplest\n" +
  "real lowering is: each variant = a distinct Int64 tag constant; a value of the enum is its tag; match on\n" +
  "variant = match on tag. For single-payload variants, represent as a small struct/tuple {tag, payload} or\n" +
  "use the existing CHIR enum/tuple support (investigate codegen CGEnumType.cj / CGTupleType.cj).\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/String(+interpolation)/control-flow/loops(for+while)/\n" +
  "break/continue/funcs/recursion/Array<Int64>/match-on-Int64 + all print forms. Real programs (FizzBuzz, fib\n" +
  "loop, repeat->ababab, array find-max->8, match) work end-to-end — keep them working.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    landedCut: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs/exit codes for the enum programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus15/enums"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/e 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/e\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/e main\n" +
  "  cd " + WTROOT + "/e\n\n" +
  "TASK: Add enums to the REAL body path, INCREMENTALLY (commit each cut green+verified):\n" +
  "  CUT 1 (payload-less): a top-level `enum E { | A | B | C }` decl; constructing a variant as a value\n" +
  "    (bound to let/var, returned, passed, used as a match selector); and `match` on the enum value with\n" +
  "    constructor patterns `case A => ...` + wildcard. Lower each variant to a distinct Int64 tag.\n" +
  "    Target: enum Color { | Red | Green | Blue }\\n main(): Int64 { let c = Green\\n match (c) { case Red => return 0\\n case Green => return 1\\n case Blue => return 2 } } -> exit 1\n" +
  "    Target: enum Dir { | N | S | E | W }\\n func opp(d: Dir): Dir { match (d) { case N => return S\\n case S => return N\\n case E => return W\\n case W => return E } }\\n main(): Int64 { match (opp(N)) { case S => return 1\\n case _ => return 0 } } -> exit 1\n" +
  "  CUT 2 (single Int64 payload): variants like `| Num(Int64) | Zero`; construct `Num(7)`; match with\n" +
  "    destructuring `case Num(n) => ...` binding the payload. Represent the value as {tag, payload}.\n" +
  "    Target: enum Opt { | Some(Int64) | None }\\n func unwrap(o: Opt): Int64 { match (o) { case Some(n) => return n\\n case None => return -1 } }\\n main(): Int64 { return unwrap(Some(42)) } -> exit 42\n" +
  "    Target: ... main(): Int64 { return unwrap(None) } -> exit -1 (exit shows 255 due to clamp; prefer printing or use a positive sentinel)\n" +
  "  CUT 3 (stretch): an enum value stored/printed; multiple payloads or recursive enum if easy.\n" +
  "Keep ADDITIVE + GATED: unsupported enum/match forms fall back (no regression). Verify each landed cut via\n" +
  "real compile+run. Re-run ALREADY-VERIFIED slices (FizzBuzz, fib loop, repeat->ababab, interp x=42, array\n" +
  "find-max->8, match valexpr->200, while_break->10, fact(5)->120, mixed->123). If only CUT 1 lands cleanly,\n" +
  "that is strong progress — commit it and report landedCut ACCURATELY (independent verifier re-checks every\n" +
  "claim; do NOT over-claim). Build green at each commit. Commit on " + BRANCH + ". Return schema; evidence\n" +
  "MUST be real run outputs; set landedCut to exactly what you verified.",
  { schema: SCHEMA, phase: 'Implement', label: 'enums', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " landed=" + (impl && impl.landedCut) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "enums slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "The enum work landed these cuts (per implementer): " + (impl.landedCut || "(unknown)") + ".\n" +
  "Re-verify LANDED enum cuts with real runs AND this regression set (every line must hold):\n" +
  "  enum Color { | Red | Green | Blue }\\n main(): Int64 { let c=Green\\n match(c){case Red=>return 0\\n case Green=>return 1\\n case Blue=>return 2} } -> exit 1  (CUT1)\n" +
  "  enum Opt { | Some(Int64) | None }\\n func unwrap(o: Opt): Int64 { match(o){case Some(n)=>return n\\n case None=>return -1} }\\n main(): Int64 { return unwrap(Some(42)) } -> exit 42  (CUT2)\n" +
  "  main() { let x=42\\n println(\"x=${x}\") } -> x=42 ; main(){ let a=[5,3,8,1]\\n var mx=a[0]\\n for(x in a){if(x>mx){mx=x}}\\n println(mx) } -> 8\n" +
  "  FizzBuzz 1..15 correct ; fib loop -> 0 1 1 2 3 5 8 13 21 34 ; repeat(\"ab\",3) -> ababab\n" +
  "  main(): Int64 { let x=2\\n let r=match(x){case 1=>100\\n case _=>200}\\n return r } -> 200\n" +
  "  main(): Int64 { var s=0\\n var i=0\\n while(i<100){i=i+1\\n if(i==5){break}\\n s=s+i}\\n return s } -> 10\n" +
  "  func fact(n: Int64): Int64 {...}\\n main(): Int64 { return fact(5) } -> 120 ; main(){print(1)\\n print(2)\\n let y=1+2\\n println(y)} -> 123\n" +
  "Only verify enum cuts that actually landed. Refresh docs/STATUS.md with the enum milestone + remaining gaps\n" +
  "(structs/classes, Float64, lambdas, generics, collections, silent-fallback hardening). Clean up worktrees\n" +
  "(git worktree remove --force " + WTROOT + "/e + prune + rm -rf " + WTROOT + "). Commit. Return schema\n" +
  "(verified=ALL applicable pass).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, landedCut: impl.landedCut, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
