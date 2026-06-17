export const meta = {
  name: 'selfhost-opus-fix-mixed-print',
  description: 'Fix the correctness bug where a body mixing literal-int prints with a runtime-value print falls back to the summary path and silently drops the runtime print; verify thoroughly and keep all slices green',
  phases: [
    { title: 'Fix' },
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
  "BACKGROUND: a REAL (non-facade) body-lowering path exists (packages/chir/src/TranslateFuncBody.cj +\n" +
  "statement model in AST2CHIR.cj, gated by hasRealBody in TranslateFuncDecl.cj; frontend real-parse adapter\n" +
  "in packages/frontend). It already lowers let/var/assign, arithmetic, relational, if/else, while, user\n" +
  "function calls + recursion, and println/print of RUNTIME Int64 values via in-body printf. Separately, an\n" +
  "older path captures println/print of LITERAL strings/ints via an entry-block side-channel (EmitPrintIR.cj)\n" +
  "and literal/let/arith returns via folding. Read docs/DEISOLATION_PLAN.md and `git log --oneline -12`.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" },
    rootCause: { type: "string" }, fix: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs for the mixed cases proving the fix" },
  },
  required: ["built", "verified", "committed", "summary"],
}

phase('Fix')
const fix = await agent(
  PREAMBLE +
  "Work directly on main in " + REPO + " (single agent, no worktree needed).\n\n" +
  "BUG (reproduce first): a function body that MIXES literal-int prints with a runtime-value print does NOT\n" +
  "fully adapt to the real body path; it falls back to the summary path, which emits the literal prints via\n" +
  "the entry-block side-channel but SILENTLY DROPS the runtime print. Repro (with runtime env set):\n" +
  "  printf 'main() { print(1)\\n print(2)\\n let y = 1 + 2\\n println(y) }\\n' > /tmp/mix.cj\n" +
  "  " + CJC + " /tmp/mix.cj -o /tmp/mix && /tmp/mix      # prints '12', SHOULD print '123' then newline\n" +
  "These work in isolation (confirm): `let y=1+2; println(y)` prints 3; `print(1); println(2)` prints 12.\n\n" +
  "ROOT-CAUSE then FIX: make the real body adapter ALSO handle print/println of integer LITERALS (treat a\n" +
  "literal-int print like a runtime print of a constant value) so a mixed body fully adapts to the real path\n" +
  "and all prints lower as ordered in-body printf calls — instead of falling back to the summary path. Ensure\n" +
  "NO double-printing (when the real path handles a body, the entry-block side-channel must not also fire for\n" +
  "it). Keep it additive/gated: bodies still outside the supported grammar fall back as before. Prefer fixing\n" +
  "the gating/coverage in the frontend real-parse adapter (and statement model if needed) over hacking the\n" +
  "side-channel.\n\n" +
  "VERIFY (build green; runtime env set; binary " + CJC + "); EVERY line must hold:\n" +
  "  main() { print(1)\\n print(2)\\n let y = 1 + 2\\n println(y) }            -> prints `123` then newline\n" +
  "  main() { println(\"start\")\\n let n = 6 * 7\\n println(n) }                -> prints `start` then `42`\n" +
  "  main() { print(\"x=\")\\n let v = 5\\n println(v) }                          -> prints `x=5`\n" +
  "  main() { var s=0\\n var i=1\\n while(i<=10){s=s+i\\n i=i+1}\\n println(s) }   -> prints 55\n" +
  "  main(){ println(\"hello selfhost\") } -> hello selfhost ; main(){ println(42) } -> 42 ; main(){ print(1)\\n println(2) } -> 12\n" +
  "  func fact(n: Int64): Int64 { if(n<=1){return 1}else{return n*fact(n-1)} }\\n main(){ println(fact(10)) } -> 3628800\n" +
  "  main(): Int64 { return fact(5) } (with fact defined) -> exit 120 ; main(): Int64 { var sum=0\\n var i=1\\n while(i<=5){sum=sum+i\\n i=i+1}\\n return sum } -> exit 15\n" +
  "  main(): Int64 { return 2 + 3 * 4 } -> exit 14\n" +
  "Then `git add -A && git commit` on main. Refresh docs/STATUS.md if it lists print behavior. Return schema\n" +
  "with rootCause + fix + evidence (the literal `123` and `start`/`42` outputs).",
  { schema: SCHEMA, phase: 'Fix', label: 'fix-mixed-print' }
)

return { fix: { built: fix && fix.built, verified: fix && fix.verified, commit: fix && fix.commit, rootCause: fix && fix.rootCause } }
