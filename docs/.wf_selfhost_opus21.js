export const meta = {
  name: 'selfhost-opus-float',
  description: 'Add Float64 to the real body path: literals, arithmetic (+ - * /), comparison, let/var/assign, params/returns, and println/print (matching reference formatting); branch-based; then merge and re-verify',
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
  "BACKGROUND: a REAL body-lowering path exists; read docs/DEISOLATION_PLAN.md and `git log --oneline -36`.\n" +
  "Real path: packages/chir/src/TranslateFuncBody.cj + statement/expr model in AST2CHIR.cj (hasRealBody),\n" +
  "gated in TranslateFuncDecl.cj; frontend adapter in packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj.\n" +
  "Int64 arithmetic/relational, runtime int printing (snprintf %ld), and the typed local-slot machinery all\n" +
  "exist. CHIR/codegen support Float64 (CGPrimitiveType etc.); relational/arith exprs are typed. For printing\n" +
  "a Float64 match the REFERENCE cjc output exactly (compile the same program with /root/.cjv/bin/cjc and\n" +
  "compare): e.g. println(5.5) and println(4.5). Use the runtime/printf with an appropriate float format.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/String(+interp)/control-flow/loops/break-continue/funcs+\n" +
  "recursion/Array<Int64>/match/enums(incl recursive)/structs(fields,methods,params) + all print forms.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    supported: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact float outputs, compared to reference cjc" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus21/float"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Work on a BRANCH IN THE MAIN REPO (NO separate worktree):\n" +
  "  cd " + REPO + "\n" +
  "  git checkout main && git branch -D " + BRANCH + " 2>/dev/null; git checkout -b " + BRANCH + "\n" +
  "Do all edits/builds/runs in " + REPO + " on branch " + BRANCH + ". Commit there.\n\n" +
  "TASK: Add Float64 to the REAL body path: float literals (3.5, 2.0), arithmetic + - * / on Float64,\n" +
  "relational comparison (< <= > >= == !=) on Float64, Float64 let/var/assign, Float64 function params and\n" +
  "return type, and println/print(Float64). Track Float64 as a distinct local/slot type (do NOT treat as\n" +
  "Int64). For printing, match the REFERENCE cjc's float formatting EXACTLY — for each target below, first\n" +
  "run `/root/.cjv/bin/cjc <prog> -o /tmp/ref && /tmp/ref` (with runtime env) to get the expected text, then\n" +
  "match it.\n" +
  "PRIMARY TARGETS (verify printed output equals the reference cjc's output):\n" +
  "  main() { let x = 3.5\\n let y = 2.0\\n println(x + y) }                 -> reference output (e.g. 5.500000)\n" +
  "  main() { println(9.0 / 2.0) }                                          -> reference output (4.5...)\n" +
  "  main(): Int64 { let x = 3.5\\n if (x > 2.0) { return 1 } else { return 0 } } -> exit 1\n" +
  "  func half(x: Float64): Float64 { return x / 2.0 }\\n main() { println(half(9.0)) } -> reference output\n" +
  "  main() { var s = 0.0\\n var i = 0\\n while (i < 4) { s = s + 1.5\\n i = i + 1 }\\n println(s) } -> reference output (6.0...)\n" +
  "Keep ADDITIVE + GATED: unsupported forms fall back (no regression). Re-run ALREADY-VERIFIED slices\n" +
  "(struct read7/method25, recursive AST ev->23, cons-list sum->6, array find-max->8, interp x=42, FizzBuzz,\n" +
  "fib loop, repeat->ababab, fact(5)->120, mixed->123). Build green at each commit on " + BRANCH + ". Report\n" +
  "honestly (independent verifier compares to reference cjc). Return schema; evidence MUST show the float\n" +
  "outputs alongside the reference outputs you compared against.",
  { schema: SCHEMA, phase: 'Implement', label: 'float' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "float slice not landed; restoring main", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main ONLY IF it passes; keep green; refresh status.\n" +
  "  cd " + REPO + " && git checkout main && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "Re-verify with real runs; for each float program compare the self-host output to the REFERENCE cjc\n" +
  "(`/root/.cjv/bin/cjc`) output for the SAME program — they must match. EVERY line must hold (else\n" +
  "`git reset --hard <pre-merge HEAD>` and report verified=false):\n" +
  "  main(){ let x=3.5\\n let y=2.0\\n println(x+y) } == reference ; main(){ println(9.0/2.0) } == reference\n" +
  "  main(): Int64 { let x=3.5\\n if (x>2.0){return 1}else{return 0} } -> exit 1\n" +
  "  func half(x: Float64): Float64 { return x/2.0 }\\n main(){ println(half(9.0)) } == reference\n" +
  "  main(){ var s=0.0\\n var i=0\\n while(i<4){s=s+1.5\\n i=i+1}\\n println(s) } == reference\n" +
  "  struct Point{...} p.x+p.y->7, p.dist2()->25 ; recursive AST ev->23 ; cons-list sum->6 ; array find-max->8\n" +
  "  interp x=42 ; FizzBuzz correct ; fib loop ok ; repeat->ababab ; fact(5)->120 ; mixed->123\n" +
  "Refresh docs/STATUS.md with the Float64 milestone + remaining gaps (classes/inheritance, generics,\n" +
  "collections, modules, silent-fallback hardening). Commit. Else reset and report verified=false. Return schema.",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, supported: impl.supported, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
