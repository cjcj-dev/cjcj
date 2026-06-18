export const meta = {
  name: 'selfhost-opus-deisolate-parse-ast',
  description: 'De-isolate the #1 island: make packages/parse construct REAL cangjie_compiler::ast nodes and delete its 5 duplicate *Nodes.cj; extend ast where needed; update frontend/macro consumers; keep whole-workspace cjpm build green; incremental; branch-in-main-repo; then merge + re-verify regressions',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const REF = "/root/cj_build/cangjie_compiler"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler (faithful rewrite of the C++ cangjie_compiler).\n" +
  "Repo: " + REPO + " (git, branch main). Build whole workspace: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "C++ REFERENCE (READ-ONLY, never modify): " + REF + " (study src/Parse, src/AST, include/cangjie/AST).\n" +
  "Commits: NO AI attribution. You write the code yourself (Codex unavailable). Keep `cjpm build` GREEN for the WHOLE workspace.\n" +
  "Use the MCP tool cangjie_search_docs (server cj-mcp) when unsure of Cangjie syntax. Cangjie: parentheses in if/while; interface\n" +
  "impl uses <:; let immutable/var mutable; no var shadowing in same scope; Option instead of null; default visibility internal;\n" +
  "C interop via foreign. Package qualified name is `organization::package` with `::` (e.g. cangjie_compiler::ast); sub-packages and\n" +
  "member selection use `.`; alias import is `import a::b.Member as Alias`.\n"

const PROBLEM =
  "THE #1 ISLAND: There must be ONE AST (mirroring the C++ compiler, where the Parser in src/Parse constructs AST node classes\n" +
  "defined in src/AST / include/cangjie/AST). Right now `packages/parse` re-declares its OWN duplicate AST node classes instead of\n" +
  "using the real `packages/ast` ones, so parse.Expr != ast.Expr and the package graph is not connected. This blocks a real\n" +
  "end-to-end pipeline.\n" +
  "GROUND TRUTH (verified):\n" +
  "  - packages/parse/src/ has 5 duplicate node files (~1726 lines) to ELIMINATE: DeclNodes.cj, ExprNodes.cj, PatternNodes.cj,\n" +
  "    TypeNodes.cj, ImportPackageNodes.cj.\n" +
  "  - packages/ast/src/ ALREADY defines the canonical equivalents (ast.Expr/Decl/FuncDecl/CallExpr/BinaryExpr/Block/FuncBody/\n" +
  "    File/RefExpr/LitConstExpr etc., in ast/src/ExprNodes.cj, DeclNodes.cj, ImportPackageNodes.cj, ...).\n" +
  "  - packages/parse/cjpm.toml ALREADY depends on cangjie_compiler::ast.\n" +
  "  - The ONLY downstream consumers of the parse package are packages/frontend and packages/macro (small blast radius).\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    dupDeleted: { type: "string", description: "which of the 5 *Nodes.cj were deleted" },
    dupRemaining: { type: "string" }, astAdded: { type: "string" }, consumersUpdated: { type: "string" },
    completeness: { type: "integer", minimum: 0, maximum: 100 },
    summary: { type: "string" }, evidence: { type: "string" }, remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "deisolate/parse-ast"

phase('Implement')
const impl = await agent(
  PREAMBLE + "\n" + PROBLEM + "\n" +
  "Work on a BRANCH IN THE MAIN REPO (NO separate worktree):\n" +
  "  cd " + REPO + "\n" +
  "  git checkout main && git branch -D " + BRANCH + " 2>/dev/null; git checkout -b " + BRANCH + "\n" +
  "Do all edits/builds/commits in " + REPO + " on branch " + BRANCH + ".\n\n" +
  "GOAL: make packages/parse construct/return the REAL cangjie_compiler::ast node types, and DELETE parse's 5 duplicate *Nodes.cj.\n" +
  "After this, parse produces ast.* nodes (one unified AST), exactly like the C++ compiler. Keep `cjpm build` GREEN for the WHOLE\n" +
  "workspace at EVERY commit.\n\n" +
  "METHOD (incremental — commit each green step):\n" +
  "  1. READ the C++ reference (src/Parse builds which AST nodes; src/AST + include/cangjie/AST define them) AND both Cangjie node\n" +
  "     sets (packages/parse/src/*Nodes.cj vs packages/ast/src/*.cj). Map parse-local node -> ast node, field by field.\n" +
  "  2. For each node CATEGORY, repoint parse's CONSTRUCTION sites (ParseExpr.cj, ParseDecl.cj, ParsePattern.cj, ParseType.cj,\n" +
  "     ParseAtom.cj, ParserTypes.cj, ...) to build ast.* nodes. `import cangjie_compiler::ast.*` (or aliased) in parse files.\n" +
  "  3. Where `ast` is MISSING a field/constructor/node that parse genuinely needs, ADD it to packages/ast faithfully per the C++\n" +
  "     AST (do NOT keep a forked parse-local copy — the whole point is ONE AST). Prefer extending ast over duplicating.\n" +
  "  4. Once every class in a parse *Nodes.cj file is migrated + unused, DELETE that file; fix all references inside parse.\n" +
  "  5. Update consumers packages/frontend and packages/macro to use ast.* where they used parse.* node types.\n" +
  "  6. `cjpm build` after each step; read errors; FIX; never finish on a broken build. Commit each green step:\n" +
  "     git add -A && git commit -m \"deisolate(parse): <what migrated>\" (NO AI attribution).\n\n" +
  "INCREMENTAL IS ENCOURAGED: land Expr nodes first (commit green), then Decl, Type, Pattern, Import/File. If you can only fully\n" +
  "migrate SOME categories while keeping the whole workspace BUILDING, that is real progress — commit and report EXACTLY which\n" +
  "*Nodes.cj were deleted and which remain. Do NOT regress: never delete real parser logic, never stub. LLVM/native stays external\n" +
  "via FFI; never modify the C++ reference.\n" +
  "ALSO MUST NOT REGRESS the facade end-to-end subset (frontend uses parse): after your changes the self-host cjc must still build\n" +
  "and these must still hold via real compile+run — `main(){return 42}`->exit42, `main(){println(\"hi\")}` prints hi,\n" +
  "`main(){println(6*7)}`->42, FizzBuzz 1..15 correct, fact(5)->120, a struct/enum probe. If frontend's parse usage breaks, FIX it.\n\n" +
  "Report schema honestly (an independent verifier re-checks). evidence MUST include: final `cjpm build` result, `ls\n" +
  "packages/parse/src/*Nodes*.cj` (which dup files remain), and a grep showing parse now references ast.* heavily.",
  { schema: SCHEMA, phase: 'Implement', label: 'deisolate-parse' }
)

log("Implement: built=" + (impl && impl.built) + " committed=" + (impl && impl.committed) +
  " dupDeleted=" + (impl && impl.dupDeleted) + " completeness=" + (impl && impl.completeness) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "de-isolation slice not landed green; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE + "\n" +
  "TASK: Merge branch " + BRANCH + " into main ONLY IF it passes; keep the whole workspace green; refresh status.\n" +
  "  cd " + REPO + " && git checkout main && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any cross-module break;\n" +
  "  prefer converging on the real ast.* types; do NOT re-stub or delete real logic).\n" +
  "The implementer reports it migrated: dupDeleted=[" + (impl.dupDeleted || "?") + "] completeness=" + (impl.completeness || 0) + "%.\n" +
  "RE-VERIFY (if any fails: `git reset --hard <pre-merge HEAD>` and report verified=false):\n" +
  "  (a) `cjpm build` GREEN for the whole workspace.\n" +
  "  (b) parse really uses ast.* now: `grep -rh 'ast\\.' packages/parse/src/*.cj | wc -l` is large (was ~1), and the reported\n" +
  "      deleted *Nodes.cj are actually gone (`ls packages/parse/src/*Nodes*.cj`).\n" +
  "  (c) NO facade regression — real compile+run: `main(){return 42}`->42, `main(){println(\"hi\")}`->hi,\n" +
  "      `main(){println(6*7)}`->42, FizzBuzz 1..15 correct, fact(5)->120, one struct probe, one enum probe.\n" +
  "Refresh docs/STATUS.md with the parse->ast de-isolation milestone (one AST island collapsed) + remaining gaps (sema/chir/codegen\n" +
  "islands still to de-isolate, finish Wave 4 CodeGen, real end-to-end Integrate to replace the frontend facade). Commit. Else reset\n" +
  "and report verified=false. Return schema.",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, committed: impl.committed, dupDeleted: impl.dupDeleted, dupRemaining: impl.dupRemaining, completeness: impl.completeness, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
