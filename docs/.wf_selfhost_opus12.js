export const meta = {
  name: 'selfhost-opus-interp',
  description: 'Add string interpolation "...${expr}..." (desugar to String concat + toString of Int64/Bool/String) to the real body path, plus Int64/Bool toString; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus12"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists; read docs/DEISOLATION_PLAN.md and study\n" +
  "`git log --oneline -20`. Real path: packages/chir/src/TranslateFuncBody.cj (CreateRealBody) + statement/\n" +
  "expr model in AST2CHIR.cj (hasRealBody), gated in TranslateFuncDecl.cj; frontend real-parse adapter in\n" +
  "packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj. The real parser (packages/parse) already\n" +
  "PARSES string interpolation (see packages/parse/src/ParseAtom.cj ProcessStringInterpolation /\n" +
  "ParseInterpolationExpr / StringPart) into structured parts. Real String support already landed: String\n" +
  "let/var, concatenation `+`, String params/returns, println/print(String) (commit b01b305/3946817); int and\n" +
  "bool runtime values can be printed via in-body printf. You need an Int64->String and Bool->String to build\n" +
  "the interpolated String (investigate the runtime/reference for an itoa-style or String-from-int routine, or\n" +
  "reuse the printf approach by formatting into a String). \n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/control-flow/loops(for+while)/break/continue/funcs/recursion,\n" +
  "String (var/concat/params/returns/print), all print forms incl mixed->123. Real programs FizzBuzz, recursive\n" +
  "fib loop, and repeat(\"ab\",3)->ababab currently work end-to-end — keep them working.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    supported: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact printed outputs for the interpolation programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus12/interp"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/i 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/i\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/i main\n" +
  "  cd " + WTROOT + "/i\n\n" +
  "TASK: Add STRING INTERPOLATION to the real body path. A literal like \"a=${x} b=${y+1}\" must lower to a\n" +
  "String built by concatenating the literal text parts with the stringified interpolated expressions, in\n" +
  "order. Support interpolated expressions of type Int64, Bool, and String (String passes through; Int64 and\n" +
  "Bool are converted to their textual form: e.g. 42 -> \"42\", true -> \"true\"). Implement Int64->String and\n" +
  "Bool->String conversion as real lowering (reuse the runtime; e.g. an in-body call that formats the value\n" +
  "into a String, or a runtime itoa/String-from-int). The real parser already parses interpolation into parts\n" +
  "(packages/parse ProcessStringInterpolation/StringPart) — map those parts in the frontend adapter\n" +
  "(RealParseBridge.cj) into concat-of-(literal-part, toString(expr)) using the existing String concat support.\n" +
  "Keep ADDITIVE + GATED: unsupported interpolation cases fall back without regressing plain strings.\n" +
  "PRIMARY TARGETS (verify PRINTED output exactly):\n" +
  "  main() { let x = 42\\n println(\"x=${x}\") }                               -> prints `x=42`\n" +
  "  main() { let a = 3\\n let b = 4\\n println(\"${a} + ${b} = ${a + b}\") }      -> prints `3 + 4 = 7`\n" +
  "  main() { let name = \"cj\"\\n println(\"hi ${name}\") }                       -> prints `hi cj`\n" +
  "  main() { let ok = 5 > 3\\n println(\"ok=${ok}\") }                          -> prints `ok=true`\n" +
  "  let s = \"v=${1+2}\" via a String var then println(s)                       -> prints `v=3`\n" +
  "Confirm via real compile+run. ALSO confirm plain `Int64->String`/`Bool->String` works if you exposed it\n" +
  "(e.g. interpolation of a sole expr). Re-run ALREADY-VERIFIED slices (FizzBuzz, fib loop, repeat->ababab,\n" +
  "while_break->10, fact(5)->120, mixed->123, println(5>3)->true, hello). If too large, land a smaller\n" +
  "GREEN+VERIFIED+committed cut first (interpolating a single Int64 var), then expressions, then Bool/String.\n" +
  "Build green at each commit. Commit on " + BRANCH + ". Return schema; evidence MUST include `x=42` and `3 + 4 = 7`.",
  { schema: SCHEMA, phase: 'Implement', label: 'interp', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "interp slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "Re-verify with real runs (runtime env; binary " + CJC + "); every line must hold:\n" +
  "  main() { let x = 42\\n println(\"x=${x}\") }                          -> x=42\n" +
  "  main() { let a=3\\n let b=4\\n println(\"${a} + ${b} = ${a + b}\") }    -> 3 + 4 = 7\n" +
  "  main() { let name=\"cj\"\\n println(\"hi ${name}\") }                   -> hi cj\n" +
  "  main() { let ok = 5 > 3\\n println(\"ok=${ok}\") }                     -> ok=true\n" +
  "  repeat(\"ab\",3)->ababab ; fib loop 0..9 -> 0 1 1 2 3 5 8 13 21 34 ; FizzBuzz 1..15 correct\n" +
  "  main(): Int64 { var s=0\\n var i=0\\n while(i<100){i=i+1\\n if(i==5){break}\\n s=s+i}\\n return s } -> 10\n" +
  "  func fact(n: Int64): Int64 {...}\\n main(): Int64 { return fact(5) } -> 120 ; main(){print(1)\\n print(2)\\n let y=1+2\\n println(y)} -> 123\n" +
  "  main(){ println(\"hello selfhost\") } -> hello selfhost ; main(){ println(5>3) } -> true\n" +
  "Refresh docs/STATUS.md with the interpolation milestone + the KNOWN GAPS discovered (still unsupported,\n" +
  "silently fall back: arrays, match, structs/classes, Float64, lambdas, for-in over String, String.size/\n" +
  "indexing) and the latent silent-fallback issue. Clean up worktrees (git worktree remove --force " + WTROOT +
  "/i + prune + rm -rf " + WTROOT + "). Commit. Return schema (verified=ALL pass).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, supported: impl.supported, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
