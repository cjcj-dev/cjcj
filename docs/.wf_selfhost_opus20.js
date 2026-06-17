export const meta = {
  name: 'selfhost-opus-structs',
  description: 'Add structs to the real body path: fields + constructor, field read/write, methods, struct params/returns; incremental cuts; branch-based (no framework worktree isolation) so merge targets the right branch; then merge and re-verify',
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
  "BACKGROUND: a REAL body-lowering path exists; read docs/DEISOLATION_PLAN.md and `git log --oneline -34`.\n" +
  "Real path: packages/chir/src/TranslateFuncBody.cj + statement/expr model in AST2CHIR.cj (hasRealBody),\n" +
  "gated in TranslateFuncDecl.cj; frontend adapter in packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj.\n" +
  "Multi-field + recursive enums work via a heap buffer of Int64 slots {tag, f0..fN} with the value = buffer\n" +
  "address as Int64 (ptrtoint), destructure via inttoptr+GEP+Load (study `git show 74055e6` and `git show\n" +
  "61b0ff8`). A STRUCT can reuse the SAME heap-buffer idea: a value is a buffer of its fields (no tag), the\n" +
  "value = address as Int64; field access = inttoptr+GEP(field index)+Load; field write = Store. codegen has\n" +
  "CGStructType.cj / CGTupleType.cj too.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/String(+interp)/control-flow/loops/break-continue/funcs+\n" +
  "recursion/Array<Int64>/match/enums(payload-less,single,multi-field,recursive) + all print forms.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    landedCut: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs/exit codes for the struct programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus20/structs"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Work on a BRANCH IN THE MAIN REPO (NO separate worktree). Set up:\n" +
  "  cd " + REPO + "\n" +
  "  git checkout main && git branch -D " + BRANCH + " 2>/dev/null; git checkout -b " + BRANCH + "\n" +
  "Do all edits/builds/runs in " + REPO + " on branch " + BRANCH + ". Commit there.\n\n" +
  "TASK: Add STRUCTS to the REAL body path, INCREMENTALLY (commit each cut green+verified). Represent a struct\n" +
  "value as a heap buffer of its Int64 fields (reuse the enum multi-field machinery without a tag); the value\n" +
  "is the buffer address as Int64; field read = inttoptr+GEP(index)+Load; field write = Store.\n" +
  "  CUT 1: struct decl with Int64 fields + an `init`; construct; read field by name.\n" +
  "    struct Point { var x: Int64\\n var y: Int64\\n init(x: Int64, y: Int64) { this.x = x\\n this.y = y } }\\n main(): Int64 { let p = Point(3, 4)\\n return p.x + p.y } -> exit 7\n" +
  "  CUT 2: mutable field write `p.x = expr` (var binding).\n" +
  "    struct Point {...}\\n main(): Int64 { var p = Point(1, 1)\\n p.x = 5\\n return p.x + p.y } -> exit 6\n" +
  "  CUT 3: instance methods (`func dist2(): Int64 { return this.x*this.x + this.y*this.y }`), called as p.m().\n" +
  "    ... main(): Int64 { let p = Point(3, 4)\\n return p.dist2() } -> exit 25\n" +
  "  CUT 4: struct as function param and return value.\n" +
  "    func mk(a: Int64, b: Int64): Point { return Point(a, b) }\\n func sx(p: Point): Int64 { return p.x }\\n main(): Int64 { return sx(mk(8, 2)) } -> exit 8\n" +
  "Keep ADDITIVE + GATED: unsupported forms fall back (no regression). Verify each landed cut via real\n" +
  "compile+run. Re-run ALREADY-VERIFIED slices (recursive AST ev->23, cons-list sum->6, multi-field big->\n" +
  "3000000000, single Some(42)->42, color->1, array find-max->8, interp x=42, FizzBuzz, fib loop, repeat->\n" +
  "ababab, fact(5)->120, mixed->123). If only CUT 1 lands cleanly, that is good progress — commit and report\n" +
  "landedCut ACCURATELY (independent verifier re-checks; do NOT over-claim). Build green at each commit on\n" +
  BRANCH + ". Return schema; evidence MUST include p.x+p.y->7 and (if landed) p.dist2()->25.",
  { schema: SCHEMA, phase: 'Implement', label: 'structs' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " landed=" + (impl && impl.landedCut) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "structs slice not landed; restoring main", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main ONLY IF it passes; keep green; refresh status.\n" +
  "  cd " + REPO + " && git checkout main && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "The struct work landed these cuts (per implementer): " + (impl.landedCut || "(unknown)") + ".\n" +
  "Re-verify LANDED struct cuts with real runs AND this regression set — EVERY applicable line must hold (if a\n" +
  "landed-cut target fails, `git reset --hard <pre-merge HEAD>` and report verified=false):\n" +
  "  struct Point{var x:Int64\\n var y:Int64\\n init(x:Int64,y:Int64){this.x=x\\n this.y=y}}\\n main():Int64{let p=Point(3,4)\\n return p.x+p.y} -> 7  (CUT1)\n" +
  "  ... main():Int64{var p=Point(1,1)\\n p.x=5\\n return p.x+p.y} -> 6  (CUT2)\n" +
  "  ... func dist2():Int64{return this.x*this.x+this.y*this.y} ... return p.dist2() -> 25  (CUT3)\n" +
  "  ... func sx(p:Point):Int64{return p.x} func mk(a:Int64,b:Int64):Point{return Point(a,b)} ... return sx(mk(8,2)) -> 8  (CUT4)\n" +
  "  recursive AST ev(Add(Lit(3),Mul(Lit(4),Lit(5))))->23 ; cons-list sum->6 ; multi-field big->3000000000\n" +
  "  color->1 ; array find-max->8 ; interp x=42 ; FizzBuzz correct ; fib loop ok ; repeat->ababab ; fact(5)->120 ; mixed->123\n" +
  "Only verify cuts that landed. Refresh docs/STATUS.md with the struct milestone + remaining gaps (classes/\n" +
  "methods+inheritance, Float64, generics, collections, modules, silent-fallback hardening). Commit. Else\n" +
  "reset and report verified=false. Return schema.",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, landedCut: impl.landedCut, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
