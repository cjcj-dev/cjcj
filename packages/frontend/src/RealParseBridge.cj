package cangjie_compiler::frontend

import std.collection.*
import std.convert.*
import cangjie_compiler::basic.SourceManager
import cangjie_compiler::parse.Decl as ParseDecl
import cangjie_compiler::lex.TokenKind
import cangjie_compiler::parse.Parser as RealParser
import cangjie_compiler::parse.DiagnosticEngine as ParseDiagnosticEngine
import cangjie_compiler::parse.File as ParseFile
import cangjie_compiler::parse.FuncDecl as ParseFuncDecl
import cangjie_compiler::parse.VarDecl as ParseVarDecl
import cangjie_compiler::parse.Expr as ParseExpr
import cangjie_compiler::parse.BinaryExpr as ParseBinaryExpr
import cangjie_compiler::parse.UnaryExpr as ParseUnaryExpr
import cangjie_compiler::parse.AssignExpr as ParseAssignExpr
import cangjie_compiler::parse.RefExpr as ParseRefExpr
import cangjie_compiler::parse.CallExpr as ParseCallExpr
import cangjie_compiler::parse.LitConstExpr as ParseLitConstExpr
import cangjie_compiler::parse.ReturnExpr as ParseReturnExpr
import cangjie_compiler::parse.ParenExpr as ParseParenExpr
import cangjie_compiler::parse.IfExpr as ParseIfExpr
import cangjie_compiler::parse.WhileExpr as ParseWhileExpr
import cangjie_compiler::parse.ForInExpr as ParseForInExpr
import cangjie_compiler::parse.RangeExpr as ParseRangeExpr
import cangjie_compiler::parse.JumpExpr as ParseJumpExpr
import cangjie_compiler::parse.VarPattern as ParseVarPattern
import cangjie_compiler::parse.WildcardPattern as ParseWildcardPattern
import cangjie_compiler::parse.ConstPattern as ParseConstPattern
import cangjie_compiler::parse.Pattern as ParsePattern
import cangjie_compiler::parse.EnumPattern as ParseEnumPattern
import cangjie_compiler::parse.MatchExpr as ParseMatchExpr
import cangjie_compiler::parse.MatchCase as ParseMatchCase
import cangjie_compiler::parse.Block as ParseBlock
import cangjie_compiler::parse.LitConstKind as ParseLitConstKind
import cangjie_compiler::parse.InterpolationExpr as ParseInterpolationExpr
import cangjie_compiler::parse.ArrayLit as ParseArrayLit
import cangjie_compiler::parse.SubscriptExpr as ParseSubscriptExpr
import cangjie_compiler::parse.MemberAccess as ParseMemberAccess
import cangjie_compiler::parse.EnumDecl as ParseEnumDecl
import cangjie_compiler::lex.StringPartKind
import cangjie_compiler::chir.AST2CHIRStmtSpec as ChirStmtSpec
import cangjie_compiler::chir.AST2CHIRExprSpec as ChirExprSpec
import cangjie_compiler::chir.ExprKind as ChirExprKind

// Real-expression body-lowering adapter. Runs the real recursive-descent parser over the same
// source the frontend already summarized, and for any function whose body matches the supported
// grammar (Int64 locals: `let`/`var` decls, reassignment, arithmetic + relational binary ops,
// `if`/`else`, `while`, and `return`) builds a recursive CHIR statement spec tree directly and
// sets hasRealBody.
//
// Promotion is gated: a body is promoted only when it genuinely needs runtime computation -- it
// must contain at least one non-trivial construct (a binary op, a `var`, an assignment, an `if`,
// or a `while`). This leaves the already-verified summary slices (literal returns, let-folded
// returns, pure-literal arithmetic folds, println/print) on their existing path with no
// regression. Anything outside the grammar simply leaves hasRealBody == false (silent fallback).
public func AdaptRealBodies(file: File, fileID: UInt64, sourceCode: String, sm: SourceManager): Unit {
    let parseDiag = ParseDiagnosticEngine()
    let parser = RealParser(fileID, sourceCode, parseDiag, sm)
    let parsedFile = parser.ParseTopLevel()
    if (parseDiag.HasError()) {
        return
    }
    // Collect the names of all top-level functions in this file so a call site can be recognized as
    // a user-defined function call (vs an unknown reference) and lowered to a real CHIR Apply.
    let funcNames = HashSet<String>()
    // Top-level functions whose declared return type is String, so a call to one classifies as a
    // String-valued expression (for concat / print promotion).
    let strReturningFuncs = HashSet<String>()
    // Payload-less enum variants in scope: each variant name maps to a distinct Int64 tag (its index
    // within the declaring enum). A value of such an enum is just its tag, so constructing a variant
    // lowers to an Int64 constant and matching a constructor pattern compares the selector tag.
    let enums = collectEnumRegistry(parsedFile)
    for (decl in parsedFile.decls) {
        if (let Some(parsedFunc) <- (decl as ParseFuncDecl)) {
            let n = parsedFunc.identifier.Val()
            if (!n.isEmpty()) {
                funcNames.add(n)
                if (parsedFuncReturnsString(parsedFunc)) {
                    strReturningFuncs.add(n)
                }
            }
        }
    }
    for (decl in file.decls) {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            tryAdaptFunction(funcDecl, parsedFile, funcNames, strReturningFuncs, enums)
        }
    }
}

// Tag/payload bit-packing for payload-carrying enum values. A payload-carrying enum value is encoded
// in a single Int64 (so it crosses function param/return boundaries through the existing Int64 ABI,
// which the unknown-type fallback gives an enum-typed signature). The low ENUM_TAG_BITS bits hold the
// variant tag; the remaining high bits hold the (signed) payload. Decoding the payload uses an
// arithmetic right shift (RSHIFT over a signed Int64 emits `ashr`), so small negative payloads would
// round-trip too -- though the supported construction sites only build small non-negative payloads.
// 8 tag bits allow up to 256 variants and leave 56 bits for the payload, ample for the supported
// programs. A payload-less variant in such an enum encodes as just its tag (payload 0).
let ENUM_TAG_BITS: Int64 = 8
let ENUM_TAG_MASK: Int64 = 255 // (1 << ENUM_TAG_BITS) - 1

// The payload classification of an enum constructor, used to gate construction/destructuring:
//   NONE    -- payload-less (`| Red`), encodes as just its tag.
//   INT     -- single Int64 payload (`| Some(Int64)`).
//   STRING  -- single String payload (`| Text(String)`), CUT 3.
//   MULTI   -- two or more Int64 payload fields (`| Add(Int64, Int64)`). Represented as separate
//              slots of a heap-style {tag, f0, f1, ...} Int64 buffer (NOT bit-packed) -- see below.
let ENUM_PAYLOAD_NONE: Int64 = 0
let ENUM_PAYLOAD_INT: Int64 = 1
let ENUM_PAYLOAD_STRING: Int64 = 2
let ENUM_PAYLOAD_MULTI: Int64 = 3

// A registry of enum variants discovered among the file's top-level enum declarations. `variantTags`
// maps each variant identifier to its Int64 tag (index within its enum); `variantPayloads` maps it to
// its payload classification (NONE/INT/STRING). Only enums whose every constructor is payload-less or
// carries a single Int64/String payload are registered -- an enum with a multi-field or other-typed
// constructor is skipped entirely so it never mis-lowers. A variant name that collides across two
// enums is dropped from both to stay sound. A payload-carrying enum value is encoded as a single
// Int64 (tag in the low ENUM_TAG_BITS bits, payload above) so it travels through the Int64 ABI.
private class EnumRegistry {
    let variantTags = HashMap<String, Int64>()
    let variantPayloads = HashMap<String, Int64>()
    // For a variant in a heap-represented enum, the number of Int64 payload fields it carries (0 for a
    // payload-less variant, 1 for a single-Int64 variant, N for a multi-field variant). Only populated
    // for variants whose declaring enum is heap-represented (`variantHeap`).
    let variantFieldCounts = HashMap<String, Int64>()
    // Whether `name`'s declaring enum uses the separate-slot heap representation (a {tag, f0, f1, ...}
    // Int64 buffer with each field in its own slot, NOT bit-packed). An enum is heap-represented iff at
    // least one of its constructors carries two or more Int64 fields; then ALL its variants -- including
    // payload-less and single-Int64 ones -- use the buffer form so one enum type has one uniform value
    // representation. An enum with only payload-less / single-Int64/String variants keeps the existing
    // single-Int64 bit-packed encoding.
    let variantHeap = HashSet<String>()

    func isVariant(name: String): Bool {
        return variantTags.contains(name)
    }

    func tagOf(name: String): Option<Int64> {
        return variantTags.get(name)
    }

    func payloadKindOf(name: String): Option<Int64> {
        return variantPayloads.get(name)
    }

    // Whether `name` names a variant that carries a payload (Int, String, or multi-field).
    func hasPayload(name: String): Bool {
        match (variantPayloads.get(name)) {
            case Some(k) => return k != ENUM_PAYLOAD_NONE
            case None => return false
        }
    }

    // Whether `name`'s enum uses the separate-slot heap representation.
    func isHeap(name: String): Bool {
        return variantHeap.contains(name)
    }

    // The number of Int64 payload fields `name` carries (heap-represented variants only).
    func fieldCountOf(name: String): Option<Int64> {
        return variantFieldCounts.get(name)
    }
}

// Scan the parsed file's top-level enum decls, assigning each variant a distinct Int64 tag (its
// 0-based index within its enum) and a payload classification. An enum is registered only when every
// one of its constructors is payload-less, single-Int64-payload, or single-String-payload; any enum
// with an unsupported constructor (multi-field, or a non-Int64/String payload type) is skipped whole
// (left on the existing path). Variant-name collisions across enums are removed so an ambiguous name
// is never treated as a single tag/payload. `sourceCode` is sliced to read each constructor's payload
// region (the parser does not retain enum-constructor param types on the AST).
private func collectEnumRegistry(parsedFile: ParseFile): EnumRegistry {
    let registry = EnumRegistry()
    let collided = HashSet<String>()
    // First pass: collect the names of every top-level enum type declared in this file. A payload
    // field whose declared type names one of these enums is a supported field (the child enum value is
    // already encoded as an Int64, so it lives in an Int64 slot just like an `Int64` field). This is
    // what makes RECURSIVE enums (`Add(Expr, Expr)`, `Cons(Int64, List)`) expressible.
    let enumTypeNames = HashSet<String>()
    for (decl in parsedFile.decls) {
        if (let Some(enumDecl) <- (decl as ParseEnumDecl)) {
            let nm = enumDecl.identifier.Val()
            if (!nm.isEmpty()) {
                enumTypeNames.add(nm)
            }
        }
    }
    for (decl in parsedFile.decls) {
        if (let Some(enumDecl) <- (decl as ParseEnumDecl)) {
            // Classify each constructor's payload; reject the whole enum on any unsupported shape so a
            // partially-supported enum never registers (keeps construction/match decisions sound).
            let payloads = ArrayList<Int64>()
            let fieldCounts = ArrayList<Int64>()
            var enumOk = true
            var enumHeap = false
            for (ctor in enumDecl.constructors) {
                match (classifyEnumCtorPayload(ctor, enumTypeNames)) {
                    case Some((k, n)) =>
                        payloads.add(k)
                        fieldCounts.add(n)
                        // Any multi-field constructor makes the whole enum use the separate-slot heap
                        // representation (so the enum type has one uniform value form).
                        if (k == ENUM_PAYLOAD_MULTI) {
                            enumHeap = true
                        }
                    case None =>
                        enumOk = false
                        break
                }
            }
            if (!enumOk) {
                continue
            }
            // A heap-represented enum cannot mix in a String-payload variant (the heap buffer stores
            // Int64 slots only). Reject the whole enum if it would mix String with multi-field.
            if (enumHeap) {
                for (k in payloads) {
                    if (k == ENUM_PAYLOAD_STRING) {
                        enumOk = false
                        break
                    }
                }
                if (!enumOk) {
                    continue
                }
            }
            var tag: Int64 = 0
            for (ctor in enumDecl.constructors) {
                let name = ctor.identifier.Val()
                if (!name.isEmpty()) {
                    if (registry.variantTags.contains(name)) {
                        collided.add(name)
                    } else {
                        registry.variantTags[name] = tag
                        registry.variantPayloads[name] = payloads[tag]
                        if (enumHeap) {
                            registry.variantHeap.add(name)
                            registry.variantFieldCounts[name] = fieldCounts[tag]
                        }
                    }
                }
                tag++
            }
        }
    }
    for (name in collided) {
        registry.variantTags.remove(name)
        registry.variantPayloads.remove(name)
        registry.variantFieldCounts.remove(name)
        registry.variantHeap.remove(name)
    }
    return registry
}

// Classify an enum constructor's payload from its parsed payload-type list (recorded by the parser on
// the constructor VarDecl). Returns (kind, fieldCount):
//   (NONE,   0) for a payload-less constructor (`| Red`);
//   (INT,    1) for a single `Int64`/`Int` payload;
//   (STRING, 1) for a single `String` payload;
//   (MULTI,  N) for one or more payload fields where each field is `Int64`/`Int` OR an enum type, and
//               at least one field is an enum type, OR two-or-more all-`Int64` fields (`Add(Int64,
//               Int64)`). A single `Int64` field stays INT (its packed encoding is unchanged).
// An enum-typed field (`Add(Expr, Expr)`, `Cons(Int64, List)`) is supported because an enum value is
// ALREADY encoded as an Int64, so it lives in an Int64 buffer slot identically to an `Int64` field --
// this is exactly what lets enums be RECURSIVE. `enumTypeNames` is the set of top-level enum type names
// declared in the file (an enum-typed field must name one of them). Any constructor that carries at
// least one enum-typed field is forced onto the heap (separate-slot) representation -- including a
// single enum field (`Box(Expr)`) -- so a child enum value rides in its own slot uniformly.
// Returns None (reject the enum) for any unsupported shape: a field that is neither Int64 nor a known
// enum type, or a single payload of an unsupported scalar type.
private func classifyEnumCtorPayload(ctor: ParseDecl, enumTypeNames: HashSet<String>): Option<(Int64, Int64)> {
    let varDecl = match (ctor as ParseVarDecl) {
        case Some(v) => v
        case None => return None
    }
    let types = varDecl.constructorTypes
    if (types.isEmpty()) {
        return Some((ENUM_PAYLOAD_NONE, 0))
    }
    if (types.size == 1) {
        let typeName = types[0].ToString().trimAscii()
        if (typeName == "Int64" || typeName == "Int") {
            return Some((ENUM_PAYLOAD_INT, 1))
        }
        if (typeName == "String") {
            return Some((ENUM_PAYLOAD_STRING, 1))
        }
        // A single enum-typed field (`Box(Expr)`): supported, but forced onto the heap representation
        // (MULTI with one field) so the child enum value rides in its own Int64 slot.
        if (enumTypeNames.contains(typeName)) {
            return Some((ENUM_PAYLOAD_MULTI, 1))
        }
        return None
    }
    // Two or more fields: each field must be `Int64`/`Int` or a known enum type (an enum-typed field is
    // stored as the child's encoded Int64 in its own slot). Each field is stored in its own slot of the
    // heap buffer (no bit-packing), so any field width / value -- and any nested enum -- round-trips.
    for (t in types) {
        let typeName = t.ToString().trimAscii()
        if (typeName != "Int64" && typeName != "Int" && !enumTypeNames.contains(typeName)) {
            return None
        }
    }
    return Some((ENUM_PAYLOAD_MULTI, types.size))
}

// Whether the parsed function declares a `String` return type.
private func parsedFuncReturnsString(parsedFunc: ParseFuncDecl): Bool {
    if (let Some(fb) <- parsedFunc.funcBody) {
        if (let Some(rt) <- fb.retType) {
            return rt.ToString() == "String"
        }
    }
    return false
}

private func tryAdaptFunction(funcDecl: FuncDecl, parsedFile: ParseFile, funcNames: HashSet<String>,
    strReturningFuncs: HashSet<String>, enums: EnumRegistry): Unit {
    // Note: a non-empty printStrings (the summary side-channel captured one or more literal
    // string/int prints) no longer forces the summary path. The real-parse adapter can lower
    // literal-int/string prints as in-body printf calls too, so a body that MIXES literal prints
    // with a genuine runtime construct (a binary op, var, assignment, if, while, call, or a
    // runtime-valued print) fully promotes to the real path. The CHIR bridge suppresses the
    // side-channel when hasRealBody is set, so there is no double-printing. A body whose ONLY
    // statements are literal prints does not set needsRuntime and stays on the summary path
    // (byte-for-byte parity preserved).
    let name = funcDecl.identifier.Val()
    let matched = findParsedFunc(parsedFile, name, funcDecl.begin.line)
    if (let Some(parsedFunc) <- matched) {
        adaptParsedFunc(funcDecl, parsedFunc, funcNames, strReturningFuncs, enums)
    }
}

// Match the parsed function to the frontend decl. The frontend's ad-hoc parser does not always
// recover a usable identifier (e.g. `main` surfaces as "("), so we match primarily by the
// declaration's begin line, then disambiguate by name when several functions share a line.
private func findParsedFunc(parsedFile: ParseFile, name: String, line: Int64): Option<ParseFuncDecl> {
    var nameMatch: Option<ParseFuncDecl> = None
    var lineMatch: Option<ParseFuncDecl> = None
    var lineMatchCount = 0
    for (decl in parsedFile.decls) {
        if (let Some(funcDecl) <- (decl as ParseFuncDecl)) {
            if (funcDecl.begin.line == line) {
                lineMatchCount++
                if (lineMatch.isNone()) {
                    lineMatch = Some(funcDecl)
                }
                if (funcDecl.identifier.Val() == name) {
                    nameMatch = Some(funcDecl)
                }
            }
        }
    }
    if (lineMatchCount == 1) {
        return lineMatch
    }
    return nameMatch
}

// Tracks the known local names in scope, the known top-level function names, and whether the body
// needs runtime computation. `locals` is seeded with the function's parameter names so references to
// parameters lower as runtime loads.
private class AdaptScope {
    let locals = HashSet<String>()
    let params = HashSet<String>()
    // Names of locals/params known to hold a Bool value (a `let`/`var` bound to a bool literal or a
    // bool-producing expression, or a Bool parameter). Used so a bare `println(boolLocal)` promotes
    // and lowers as a runtime Bool print rather than falling back to the int-only summary path.
    let boolNames = HashSet<String>()
    // Names of locals/params known to hold a String value (a `let`/`var` bound to a string literal, a
    // String-producing concat, a String parameter, or a call returning String). Used so a bare
    // `println(strLocal)` and `a + b` concat are recognized as String operations and promote to the
    // real path (lowered as a runtime CString print / concat) rather than falling back.
    let strNames = HashSet<String>()
    // Names of locals known to hold an Int64 array (a `let`/`var` bound to an array literal). Used to
    // recognize a[i] subscripts, a.size, a[i]=v writes, and for-in over the array as array operations.
    let arrayNames = HashSet<String>()
    // Parallel to arrayNames: the statically known element count of each array local, so `a.size`
    // lowers to an Int64 constant.
    let arrayLengths = HashMap<String, Int64>()
    let funcNames: HashSet<String>
    // Names of top-level functions whose declared return type is String, so a call to one is treated
    // as a String-valued expression for concat / print classification.
    let strReturningFuncs = HashSet<String>()
    // Payload-less enum variants in scope (variant name -> Int64 tag). A bare reference to a variant
    // name lowers to its tag constant, and a constructor pattern in a match compares the tag.
    let enums: EnumRegistry
    var needsRuntime: Bool = false
    // Depth of enclosing `for`/`while` loops currently being adapted. A `break`/`continue` is only
    // accepted (promotable) when loopDepth > 0; otherwise the body falls back to the summary path.
    var loopDepth: Int64 = 0
    // Monotonic counter for synthesizing fresh, collision-free local names for match desugaring
    // (the selector temp and value-form result temp). Source identifiers cannot contain `$`, so
    // these names never clash with user locals.
    var tempCounter: Int64 = 0

    func freshTemp(prefix: String): String {
        let n = tempCounter
        tempCounter++
        return "$" + prefix + "_" + n.toString()
    }

    init(funcNames: HashSet<String>, strReturningFuncs: HashSet<String>, enums: EnumRegistry) {
        this.funcNames = funcNames
        this.enums = enums
        for (n in strReturningFuncs) {
            this.strReturningFuncs.add(n)
        }
    }

    // Whether `name` is a payload-less enum variant in scope and is not shadowed by a local/param.
    func isEnumVariant(name: String): Bool {
        return !locals.contains(name) && enums.isVariant(name)
    }
}

private func adaptParsedFunc(funcDecl: FuncDecl, parsedFunc: ParseFuncDecl, funcNames: HashSet<String>,
    strReturningFuncs: HashSet<String>, enums: EnumRegistry): Unit {
    let body = match (parsedFunc.funcBody) {
        case Some(fb) => fb
        case None => return
    }
    let block = match (body.body) {
        case Some(b) => b
        case None => return
    }
    let scope = AdaptScope(funcNames, strReturningFuncs, enums)
    // Seed parameters as in-scope locals so references to them lower to runtime loads. Parameters
    // are also tracked separately: a reference to a parameter is inherently runtime (it cannot be
    // folded), so it promotes even a trivial body like `return x` to the real path -- needed so the
    // function emits a real typed body (matching its declared Int64 return) for callers.
    for (param in body.paramLists) {
        for (funcParam in param.params) {
            let pname = funcParam.identifier.Val()
            if (!pname.isEmpty()) {
                scope.locals.add(pname)
                scope.params.add(pname)
                // A Bool parameter is tracked so references to it lower as i1 (and a bare print of it
                // promotes as a runtime Bool print).
                if (let Some(typeNode) <- funcParam.typeNode) {
                    let tn = typeNode.ToString()
                    if (tn == "Bool" || tn == "bool") {
                        scope.boolNames.add(pname)
                    }
                    // A String parameter is tracked so references to it lower as a CString value (and
                    // a bare print of it / a concat using it promote as String operations).
                    if (tn == "String") {
                        scope.strNames.add(pname)
                    }
                }
            }
        }
    }
    let statements = match (adaptStatements(block, scope)) {
        case Some(stmts) => stmts
        case None => return
    }
    // Require genuine runtime computation; otherwise leave the summary/literal path untouched.
    if (!scope.needsRuntime) {
        return
    }
    // Clear any stale literal-return summary so the real CHIR body path wins in the bridge.
    funcDecl.funcBody.hasLiteralReturn = false
    funcDecl.funcBody.hasRealBody = true
    funcDecl.funcBody.realStatements = statements
}

// Adapt a parse Block's statement list into CHIR statement specs. Returns None on any grammar miss
// (the whole body then falls back to the summary path). `scope` accumulates locals and the
// needs-runtime flag across the (single, shared) scope.
private func adaptStatements(block: ParseBlock, scope: AdaptScope): Option<ArrayList<ChirStmtSpec>> {
    let out = ArrayList<ChirStmtSpec>()
    for (node in block.body) {
        if (let Some(varDecl) <- (node as ParseVarDecl)) {
            // `let r = match (sel) { ... }`: a value-position match initializer desugars to a prelude
            // (selector temp + result var + if-chain assigning the result) plus `let r = $res`.
            if (!varDecl.isConst) {
                if (let Some(initExpr) <- varDecl.initializer) {
                    if (let Some(matchExpr) <- (initExpr as ParseMatchExpr)) {
                        let name = varDecl.identifier.Val()
                        if (name.isEmpty()) {
                            return None
                        }
                        let mv = match (adaptMatchValue(matchExpr, scope)) {
                            case Some(v) => v
                            case None => return None
                        }
                        for (s in mv.prelude) {
                            out.add(s)
                        }
                        scope.locals.add(name)
                        scope.needsRuntime = true
                        out.add(ChirStmtSpec.Let(name, mv.resultRef, isVar: varDecl.isVar))
                        continue
                    }
                }
            }
            match (adaptVarDecl(varDecl, scope)) {
                case Some(stmt) => out.add(stmt)
                case None => return None
            }
            continue
        }
        if (let Some(returnExpr) <- (node as ParseReturnExpr)) {
            // `return match (sel) { ... }`: desugar the value-position match, then return its result.
            if (let Some(retExpr) <- returnExpr.expr) {
                if (let Some(matchExpr) <- (retExpr as ParseMatchExpr)) {
                    let mv = match (adaptMatchValue(matchExpr, scope)) {
                        case Some(v) => v
                        case None => return None
                    }
                    for (s in mv.prelude) {
                        out.add(s)
                    }
                    scope.needsRuntime = true
                    out.add(ChirStmtSpec.Return(mv.resultRef))
                    continue
                }
            }
            match (adaptReturn(returnExpr, scope)) {
                case Some(stmt) => out.add(stmt)
                case None => return None
            }
            continue
        }
        if (let Some(assignExpr) <- (node as ParseAssignExpr)) {
            match (adaptAssign(assignExpr, scope)) {
                case Some(stmt) => out.add(stmt)
                case None => return None
            }
            continue
        }
        if (let Some(ifExpr) <- (node as ParseIfExpr)) {
            match (adaptIf(ifExpr, scope)) {
                case Some(stmt) => out.add(stmt)
                case None => return None
            }
            continue
        }
        if (let Some(whileExpr) <- (node as ParseWhileExpr)) {
            match (adaptWhile(whileExpr, scope)) {
                case Some(stmt) => out.add(stmt)
                case None => return None
            }
            continue
        }
        if (let Some(forInExpr) <- (node as ParseForInExpr)) {
            match (adaptForIn(forInExpr, scope)) {
                case Some(stmt) => out.add(stmt)
                case None => return None
            }
            continue
        }
        if (let Some(jumpExpr) <- (node as ParseJumpExpr)) {
            match (adaptJump(jumpExpr, scope)) {
                case Some(stmt) => out.add(stmt)
                case None => return None
            }
            continue
        }
        if (let Some(matchExpr) <- (node as ParseMatchExpr)) {
            // A statement-position `match (sel) { ... }`: desugar to a selector temp + an
            // if/else-if chain over Int64 literal / wildcard / var-binding patterns. Each arm runs
            // its block of statements (which may themselves return, print, etc.).
            match (adaptMatchStatement(matchExpr, scope)) {
                case Some(stmts) =>
                    for (s in stmts) {
                        out.add(s)
                    }
                case None => return None
            }
            continue
        }
        if (let Some(callExpr) <- (node as ParseCallExpr)) {
            // A bare `println(<expr>)` / `print(<expr>)` statement: lower to a runtime PRINT when its
            // argument is a supported Int64 expression. (Calls to user functions are expressions, not
            // statements, so only print built-ins reach here as statement-level calls.)
            match (adaptPrint(callExpr, scope)) {
                case Some(stmt) => out.add(stmt)
                case None => return None
            }
            continue
        }
        // Any other statement kind: unsupported -> fall back.
        return None
    }
    return Some(out)
}

private func adaptVarDecl(varDecl: ParseVarDecl, scope: AdaptScope): Option<ChirStmtSpec> {
    if (varDecl.isConst) {
        return None
    }
    let name = varDecl.identifier.Val()
    if (name.isEmpty()) {
        return None
    }
    let initExpr = match (varDecl.initializer) {
        case Some(e) => e
        case None => return None
    }
    // An array-literal initializer `let a = [e0, e1, ...]` (Int64 elements) declares an Int64 array
    // local. Lowered to an ARRAY_LET (a VArray<Int64,len> slot filled element-by-element).
    if (let Some(arrayLit) <- (initExpr as ParseArrayLit)) {
        let elems = ArrayList<ChirExprSpec>()
        for (child in arrayLit.children) {
            // Only Int64-valued elements are supported (the array is VArray<Int64>). A String- or
            // Bool-classified element falls the whole body back so a non-Int64 array never mis-lowers.
            if (exprIsString(child, scope) || exprIsBool(child, scope)) {
                return None
            }
            match (adaptExpr(child, scope)) {
                case Some(e) => elems.add(e)
                case None => return None
            }
        }
        scope.locals.add(name)
        scope.arrayNames.add(name)
        scope.arrayLengths[name] = elems.size
        scope.needsRuntime = true
        return Some(ChirStmtSpec.ArrayLet(name, elems, isVar: varDecl.isVar))
    }
    // A sized array constructor `let a = Array<Int64>(n, repeat: v)` / `(n, item: v)` with a literal
    // size `n` declares an Int64 array local of length n filled with v. Lowered to an ARRAY_LET whose
    // elements are n copies of the (pure) fill expression -- the VArray representation needs a
    // statically known length, so only a literal size is accepted (anything else falls back).
    if (let Some(ctor) <- adaptArrayCtor(initExpr, scope, name)) {
        return Some(ctor)
    }
    let valueSpec = match (adaptExpr(initExpr, scope)) {
        case Some(e) => e
        case None => return None
    }
    if (varDecl.isVar) {
        scope.needsRuntime = true
    }
    scope.locals.add(name)
    // Track Bool-typed locals so a later bare `println(name)` lowers as a runtime Bool print.
    if (exprIsBool(initExpr, scope)) {
        scope.boolNames.add(name)
    }
    // Track String-typed locals so a later bare `println(name)` / concat lowers as a String op.
    if (exprIsString(initExpr, scope)) {
        scope.strNames.add(name)
    }
    return Some(ChirStmtSpec.Let(name, valueSpec, isVar: varDecl.isVar))
}

private func adaptAssign(assignExpr: ParseAssignExpr, scope: AdaptScope): Option<ChirStmtSpec> {
    // Only plain `name = expr` over a known local is supported (no compound assignment).
    if (assignExpr.op.kind != TokenKind.ASSIGN) {
        return None
    }
    let target = match (assignExpr.leftExpr) {
        case Some(e) => e
        case None => return None
    }
    // `a[i] = expr`: an indexed write into an Int64 array local.
    if (let Some(subscript) <- (target as ParseSubscriptExpr)) {
        let base = match (subscript.baseExpr) {
            case Some(b) => b
            case None => return None
        }
        let arrayName = match (arrayRefName(base, scope)) {
            case Some(n) => n
            case None => return None
        }
        if (subscript.indexExprs.size != 1) {
            return None
        }
        let indexSpec = match (adaptExpr(subscript.indexExprs[0], scope)) {
            case Some(e) => e
            case None => return None
        }
        let rhs = match (assignExpr.rightExpr) {
            case Some(e) => e
            case None => return None
        }
        let valueSpec = match (adaptExpr(rhs, scope)) {
            case Some(e) => e
            case None => return None
        }
        scope.needsRuntime = true
        return Some(ChirStmtSpec.ArrayAssign(arrayName, indexSpec, valueSpec))
    }
    let name = match (localRefName(target, scope)) {
        case Some(n) => n
        case None => return None
    }
    let rhs = match (assignExpr.rightExpr) {
        case Some(e) => e
        case None => return None
    }
    let valueSpec = match (adaptExpr(rhs, scope)) {
        case Some(e) => e
        case None => return None
    }
    scope.needsRuntime = true
    return Some(ChirStmtSpec.Assign(name, valueSpec))
}

private func adaptReturn(returnExpr: ParseReturnExpr, scope: AdaptScope): Option<ChirStmtSpec> {
    let expr = match (returnExpr.expr) {
        case Some(e) => e
        case None => return Some(ChirStmtSpec.ReturnNone())
    }
    // A `return <stringExpr>` is a String-valued return: promote so the real path lowers a CString
    // return (the summary path cannot represent a String literal return -- it would mis-lower it).
    if (exprIsString(expr, scope)) {
        scope.needsRuntime = true
    }
    let valueSpec = match (adaptExpr(expr, scope)) {
        case Some(e) => e
        case None => return None
    }
    return Some(ChirStmtSpec.Return(valueSpec))
}

private func adaptIf(ifExpr: ParseIfExpr, scope: AdaptScope): Option<ChirStmtSpec> {
    let condExpr = match (ifExpr.condExpr) {
        case Some(e) => e
        case None => return None
    }
    let condSpec = match (adaptExpr(condExpr, scope)) {
        case Some(e) => e
        case None => return None
    }
    let thenBlock = match (ifExpr.thenBody) {
        case Some(b) => b
        case None => return None
    }
    let thenStmts = match (adaptStatements(thenBlock, scope)) {
        case Some(s) => s
        case None => return None
    }
    var elseStmts = ArrayList<ChirStmtSpec>()
    if (ifExpr.hasElse) {
        let elseExpr = match (ifExpr.elseBody) {
            case Some(e) => e
            case None => return None
        }
        // `else { ... }` is a Block; `else if (...)` is a nested IfExpr.
        if (let Some(elseBlock) <- (elseExpr as ParseBlock)) {
            elseStmts = match (adaptStatements(elseBlock, scope)) {
                case Some(s) => s
                case None => return None
            }
        } else if (let Some(elseIf) <- (elseExpr as ParseIfExpr)) {
            let nested = match (adaptIf(elseIf, scope)) {
                case Some(s) => s
                case None => return None
            }
            let single = ArrayList<ChirStmtSpec>()
            single.add(nested)
            elseStmts = single
        } else {
            return None
        }
    }
    scope.needsRuntime = true
    return Some(ChirStmtSpec.If(condSpec, thenStmts, elseStmts))
}

private func adaptWhile(whileExpr: ParseWhileExpr, scope: AdaptScope): Option<ChirStmtSpec> {
    let condExpr = match (whileExpr.condExpr) {
        case Some(e) => e
        case None => return None
    }
    let condSpec = match (adaptExpr(condExpr, scope)) {
        case Some(e) => e
        case None => return None
    }
    let bodyBlock = match (whileExpr.body) {
        case Some(b) => b
        case None => return None
    }
    scope.loopDepth++
    let bodyStmts = match (adaptStatements(bodyBlock, scope)) {
        case Some(s) =>
            scope.loopDepth--
            s
        case None =>
            scope.loopDepth--
            return None
    }
    scope.needsRuntime = true
    return Some(ChirStmtSpec.While(condSpec, bodyStmts))
}

// A single normalized match arm: the list of Int64 literal values it matches (empty => catch-all,
// i.e. a wildcard `_` or a var-binding pattern), an optional binding name (a `case n =>` var
// pattern binds the selector to `n` in the arm body), and the adapted arm-body statements.
private class MatchArm {
    let literals: ArrayList<Int64>
    let isCatchAll: Bool
    let bindingName: Option<String>
    let body: ArrayList<ChirStmtSpec>
    // For a destructuring enum-constructor arm `case Ctor(n) =>` over a PACKED (single-Int64) enum: the
    // name `n` bound to the variant's decoded payload (`$sel >> ENUM_TAG_BITS`). None for non-packed-
    // destructuring arms. (Heap destructuring uses `heapFieldBindings` instead.)
    var payloadBindingName: Option<String> = None
    // For a destructuring enum-constructor arm `case Ctor(a, b, ...) =>` over a HEAP-represented enum:
    // the binding name for each payload field, in order (None for a `_` wildcard field). Each name is
    // bound to `EnumField($sel, i+1)` (slot i+1 of the buffer) when the tag matches. Empty for a
    // non-heap-destructuring arm.
    let heapFieldBindings = ArrayList<Option<String>>()

    init(literals: ArrayList<Int64>, isCatchAll: Bool, bindingName: Option<String>,
        body: ArrayList<ChirStmtSpec>) {
        this.literals = literals
        this.isCatchAll = isCatchAll
        this.bindingName = bindingName
        this.body = body
    }
}

// Whether any pattern in the match destructures an enum constructor (`case Ctor(...) =>`, an
// EnumPattern). Such a match is over a payload-carrying enum, so tag comparisons must mask off the
// payload bits (`($sel & ENUM_TAG_MASK) == tag`) rather than compare the whole encoded value. A match
// with only bare-variant / literal / wildcard patterns keeps the existing direct-compare path so the
// already-verified payload-less enum and Int64-literal matches stay byte-for-byte unchanged.
private func matchUsesTagMask(matchExpr: ParseMatchExpr): Bool {
    for (matchCase in matchExpr.matchCases) {
        for (pattern in matchCase.patterns) {
            if (let Some(_) <- (pattern as ParseEnumPattern)) {
                return true
            }
        }
    }
    return false
}

// Whether the match is over a HEAP-represented enum (its selector value is a {tag, f0, ...} buffer
// address). Detected from the patterns: a destructuring constructor pattern naming a heap variant, or
// a bare variant VarPattern naming a heap variant. A heap match tests the tag via the buffer's slot-0
// load (`EnumField($sel, 0) == tag`) and binds destructured fields via per-slot loads, rather than the
// bit-packed mask/shift used for the single-Int64 packed enums. Mutually exclusive with the packed
// tag-mask path (an enum is heap or packed, never both).
private func matchUsesHeap(matchExpr: ParseMatchExpr, scope: AdaptScope): Bool {
    for (matchCase in matchExpr.matchCases) {
        for (pattern in matchCase.patterns) {
            if (let Some(enumPat) <- (pattern as ParseEnumPattern)) {
                if (scope.enums.isHeap(enumPat.constructor.Val())) {
                    return true
                }
            }
            if (let Some(varPat) <- (pattern as ParseVarPattern)) {
                let n = varPat.identifier.Val()
                if (scope.isEnumVariant(n) && scope.enums.isHeap(n)) {
                    return true
                }
            }
        }
    }
    return false
}

// Parse a destructuring enum-constructor pattern `case Ctor(binding) =>` into (tag, payloadBinding).
// Only a single-payload variant (Int payload for CUT 1) destructured by a single VarPattern or
// WildcardPattern is supported. Returns None for anything else (multi-field, nested, type args, an
// unknown constructor, a String payload) so the whole match falls back. A wildcard payload (`case
// Ctor(_) =>`) matches the tag with no binding.
private func enumPatternMatch(pattern: ParsePattern, scope: AdaptScope): Option<(Int64, Option<String>)> {
    let enumPat = match (pattern as ParseEnumPattern) {
        case Some(p) => p
        case None => return None
    }
    // A qualified constructor (`Color.Red(...)`) records more than one constructor part; only a
    // simple unqualified constructor is supported. Type arguments (`Some<Int64>(...)`) are rejected.
    if (!enumPat.typeArguments.isEmpty() || enumPat.constructorParts.size > 1) {
        return None
    }
    let ctorName = enumPat.constructor.Val()
    if (!scope.isEnumVariant(ctorName)) {
        return None
    }
    let payloadKind = match (scope.enums.payloadKindOf(ctorName)) {
        case Some(k) => k
        case None => return None
    }
    // CUT 1 destructuring supports a single Int payload only; a String payload waits for CUT 3.
    if (payloadKind != ENUM_PAYLOAD_INT) {
        return None
    }
    let tag = match (scope.enums.tagOf(ctorName)) {
        case Some(t) => t
        case None => return None
    }
    if (enumPat.patterns.size != 1) {
        return None
    }
    let sub = enumPat.patterns[0]
    if (let Some(varPat) <- (sub as ParseVarPattern)) {
        let n = varPat.identifier.Val()
        if (n.isEmpty()) {
            return None
        }
        return Some((tag, Some(n)))
    }
    if (let Some(_) <- (sub as ParseWildcardPattern)) {
        return Some((tag, None))
    }
    return None
}

// Parse a destructuring enum-constructor pattern over a HEAP-represented enum into (tag, fieldBindings).
// Handles every variant arity of a heap enum: a payload-less variant (`case Z =>` parses as a bare
// VarPattern, handled elsewhere -- not here), a single-field `case P(x) =>`, and a multi-field
// `case Add(a, b) =>`. Each sub-pattern must be a simple VarPattern (binds the field) or a
// WildcardPattern (`_`, no binding); the sub-pattern count must equal the variant's declared field
// count. Returns None for a non-heap enum, an unknown/qualified constructor, type args, a nested or
// non-simple sub-pattern, or an arity mismatch (the whole match then falls back).
private func heapEnumPatternMatch(pattern: ParsePattern,
    scope: AdaptScope): Option<(Int64, ArrayList<Option<String>>)> {
    let enumPat = match (pattern as ParseEnumPattern) {
        case Some(p) => p
        case None => return None
    }
    if (!enumPat.typeArguments.isEmpty() || enumPat.constructorParts.size > 1) {
        return None
    }
    let ctorName = enumPat.constructor.Val()
    if (!scope.isEnumVariant(ctorName) || !scope.enums.isHeap(ctorName)) {
        return None
    }
    let tag = match (scope.enums.tagOf(ctorName)) {
        case Some(t) => t
        case None => return None
    }
    let fieldCount = match (scope.enums.fieldCountOf(ctorName)) {
        case Some(n) => n
        case None => return None
    }
    if (enumPat.patterns.size != fieldCount) {
        return None
    }
    let bindings = ArrayList<Option<String>>()
    for (sub in enumPat.patterns) {
        if (let Some(varPat) <- (sub as ParseVarPattern)) {
            let n = varPat.identifier.Val()
            if (n.isEmpty()) {
                return None
            }
            bindings.add(Some(n))
        } else if (let Some(_) <- (sub as ParseWildcardPattern)) {
            bindings.add(None)
        } else {
            return None
        }
    }
    return Some((tag, bindings))
}

// Desugar a statement-position `match (sel) { case L => ... case _ => ... }` over an Int64 selector
// into: a fresh selector temp `let $sel = <selector>` followed by an if/else-if chain that compares
// the temp against each literal value (`$sel == L`, OR-combined for `case 1 | 2 => ...`). A
// wildcard `case _ =>` or a var-binding `case n =>` arm becomes the chain's final `else`. The
// selector is evaluated exactly once (into the temp). Returns None on any unsupported shape (enum
// patterns, guards, tuple patterns, non-Int64 selector, a catch-all that is not last) so the body
// falls back to the existing path with no regression.
private func adaptMatchStatement(matchExpr: ParseMatchExpr, scope: AdaptScope): Option<ArrayList<ChirStmtSpec>> {
    let arms = match (normalizeMatchArms(matchExpr, scope)) {
        case Some(a) => a
        case None => return None
    }
    let fold = matchIsExhaustiveEnum(matchExpr, arms, scope)
    return buildMatchChain(matchExpr, arms, None, scope, foldLastAsElse: fold)
}

// Whether a match is over enum variants and has no wildcard/binding catch-all arm. Such a match is
// exhaustive by construction (the selector is always one of the enum's variants), so the final arm
// can serve as the chain's `else` (no fall-through). Detected from the source patterns: at least one
// arm pattern is a bare enum-variant VarPattern, and the final arm is not a catch-all.
private func matchIsExhaustiveEnum(matchExpr: ParseMatchExpr, arms: ArrayList<MatchArm>,
    scope: AdaptScope): Bool {
    if (arms.isEmpty() || arms[arms.size - 1].isCatchAll) {
        return false
    }
    for (matchCase in matchExpr.matchCases) {
        for (pattern in matchCase.patterns) {
            // A destructuring enum-constructor pattern (`case Ctor(n) =>`) is over an enum.
            if (let Some(_) <- (pattern as ParseEnumPattern)) {
                return true
            }
            if (let Some(varPat) <- (pattern as ParseVarPattern)) {
                if (scope.isEnumVariant(varPat.identifier.Val())) {
                    return true
                }
            }
        }
    }
    return false
}

// Parse + validate every arm of a match into the normalized MatchArm list. The selector temp is NOT
// emitted here (the caller does so via buildMatchChain); arm bodies are adapted with the var-binding
// name (if any) seeded into scope so `case n => ... n ...` resolves. Returns None on any unsupported
// arm so the whole match falls back.
private func normalizeMatchArms(matchExpr: ParseMatchExpr, scope: AdaptScope): Option<ArrayList<MatchArm>> {
    // We support only the selector form `match (sel) { case <pattern> => ... }`. The parser sets
    // matchMode = true and a non-None selector for that form, placing pattern arms in `matchCases`.
    // The selector-less form (`match { case <expr> => }`) uses `matchCaseOthers` and is out of grammar.
    if (!matchExpr.matchMode || matchExpr.selector.isNone()) {
        return None
    }
    if (!matchExpr.matchCaseOthers.isEmpty() || matchExpr.matchCases.isEmpty()) {
        return None
    }
    let arms = ArrayList<MatchArm>()
    var idx = 0
    for (matchCase in matchExpr.matchCases) {
        idx++
        // Guards are out of grammar.
        if (matchCase.patternGuard.isSome()) {
            return None
        }
        let armBlock = match (matchCase.exprOrDecls) {
            case Some(b) => b
            case None => return None
        }
        // Collect this case's patterns. A case carries one or more patterns (`case 1 | 2 => ...`).
        let literals = ArrayList<Int64>()
        var isCatchAll = false
        var bindingName: Option<String> = None
        var payloadBindingName: Option<String> = None
        let heapFieldBindings = ArrayList<Option<String>>()
        for (pattern in matchCase.patterns) {
            if (let Some(constPat) <- (pattern as ParseConstPattern)) {
                let lit = match (constPat.literal) {
                    case Some(e) => e
                    case None => return None
                }
                match (intLiteralValue(lit)) {
                    case Some(v) => literals.add(v)
                    case None => return None // only Int64 literal const patterns
                }
            } else if (let Some(_) <- (pattern as ParseWildcardPattern)) {
                isCatchAll = true
            } else if (let Some((tag, fieldBindings)) <- heapEnumPatternMatch(pattern, scope)) {
                // A destructuring enum-constructor pattern over a heap enum `case Add(a, b) =>`: match
                // the variant's tag and bind each payload field to its own per-slot load (later).
                literals.add(tag)
                if (matchCase.patterns.size != 1) {
                    return None // a destructuring pattern cannot be OR-combined
                }
                for (b in fieldBindings) {
                    heapFieldBindings.add(b)
                }
            } else if (let Some((tag, payloadName)) <- enumPatternMatch(pattern, scope)) {
                // A destructuring enum-constructor pattern `case Ctor(n) =>` / `case Ctor(_) =>`:
                // match the variant's tag and (optionally) bind the decoded payload to `n`.
                literals.add(tag)
                if (matchCase.patterns.size != 1) {
                    return None // a destructuring pattern cannot be OR-combined (`case A(n) | B =>`)
                }
                payloadBindingName = payloadName
            } else if (let Some(varPat) <- (pattern as ParseVarPattern)) {
                let n = varPat.identifier.Val()
                if (n.isEmpty()) {
                    return None
                }
                // A bare payload-less enum-variant pattern (`case Green =>`) parses as a VarPattern
                // (the parser cannot tell a constructor from a binding). Match it as a literal-tag
                // pattern over the variant's tag rather than a catch-all binding.
                if (let Some(tag) <- enumVariantPatternTag(varPat, scope)) {
                    literals.add(tag)
                } else {
                    isCatchAll = true
                    bindingName = Some(n)
                }
            } else {
                // Tuple/type/etc. patterns are out of grammar.
                return None
            }
        }
        // A catch-all combined with literals (`case 1 | _ =>`) or with a binding is not supported.
        if (isCatchAll && (!literals.isEmpty() || matchCase.patterns.size != 1)) {
            return None
        }
        // A catch-all must be the final arm (nothing after it would be reachable / well-formed).
        if (isCatchAll && idx != matchExpr.matchCases.size) {
            return None
        }
        // Adapt the arm body, seeding the binding name as an in-scope Int64 local for var patterns and
        // the payload binding name for destructuring enum patterns.
        if (let Some(name) <- bindingName) {
            scope.locals.add(name)
        }
        if (let Some(name) <- payloadBindingName) {
            scope.locals.add(name)
        }
        for (b in heapFieldBindings) {
            if (let Some(name) <- b) {
                scope.locals.add(name)
            }
        }
        let bodyStmts = match (adaptStatements(armBlock, scope)) {
            case Some(s) => s
            case None => return None
        }
        let arm = MatchArm(literals, isCatchAll, bindingName, bodyStmts)
        arm.payloadBindingName = payloadBindingName
        for (b in heapFieldBindings) {
            arm.heapFieldBindings.add(b)
        }
        arms.add(arm)
    }
    return Some(arms)
}

// Emit the selector temp + the if/else-if chain for a normalized arm list. `extraInit` is an
// optional extra statement (used by the value form to declare the result temp) inserted before the
// chain. The selector is evaluated once into `$sel`. A var-binding catch-all arm prepends a
// `let n = $sel` to its body so the bound name reads the selector value.
private func buildMatchChain(matchExpr: ParseMatchExpr, arms: ArrayList<MatchArm>,
    extraInit: Option<ChirStmtSpec>, scope: AdaptScope,
    foldLastAsElse!: Bool = false): Option<ArrayList<ChirStmtSpec>> {
    let selectorExpr = match (matchExpr.selector) {
        case Some(e) => e
        case None => return None
    }
    // A String/Bool selector is out of the Int64-literal grammar.
    if (exprIsString(selectorExpr, scope) || exprIsBool(selectorExpr, scope)) {
        return None
    }
    let selectorSpec = match (adaptExpr(selectorExpr, scope)) {
        case Some(e) => e
        case None => return None
    }
    // A match that destructures any enum constructor is over a payload-carrying enum: tag tests mask
    // off the payload bits, and a `case Ctor(n) =>` arm binds the decoded payload. A match with only
    // bare-variant / literal / wildcard patterns keeps the direct-compare path (no regression).
    let useHeap = matchUsesHeap(matchExpr, scope)
    // A heap match never uses the packed tag mask (an enum is heap or packed, never both).
    let useTagMask = !useHeap && matchUsesTagMask(matchExpr)
    let out = ArrayList<ChirStmtSpec>()
    let selName = scope.freshTemp("match_sel")
    scope.locals.add(selName)
    out.add(ChirStmtSpec.Let(selName, selectorSpec, isVar: false))
    match (extraInit) {
        case Some(s) => out.add(s)
        case None => ()
    }
    // Build the chain back-to-front so each non-final arm's else is the already-built remainder.
    // The final arm: if it is a catch-all, its body is the base else-block; otherwise the base is an
    // empty else (an unmatched selector simply falls through, matching exhaustive-by-construction use).
    var chainElse = ArrayList<ChirStmtSpec>()
    var startIdx = arms.size - 1
    if (arms[startIdx].isCatchAll) {
        chainElse = withBinding(arms[startIdx], selName)
        startIdx--
    } else if (foldLastAsElse) {
        // An enum match with no wildcard is exhaustive by construction (every variant is covered).
        // Make the final variant arm the chain's base `else` (dropping its tag test) so there is no
        // fall-through path: this keeps a value/return match well-typed (no implicit Unit fall-off
        // when the function returns a value), and is sound because the selector is always one variant.
        chainElse = withBinding(arms[startIdx], selName)
        startIdx--
    }
    var i = startIdx
    while (i >= 0) {
        let arm = arms[i]
        // A catch-all may only be the final arm (already enforced in normalize), so any arm here has
        // literal values.
        let cond = match (literalCond(selName, arm.literals, useTagMask, useHeap)) {
            case Some(c) => c
            case None => return None
        }
        let thenBody = withBinding(arm, selName)
        let ifStmt = ChirStmtSpec.If(cond, thenBody, chainElse)
        let wrapper = ArrayList<ChirStmtSpec>()
        wrapper.add(ifStmt)
        chainElse = wrapper
        i--
    }
    for (s in chainElse) {
        out.add(s)
    }
    scope.needsRuntime = true
    return Some(out)
}

// The arm body, prefixed with the bindings it introduces so they read from the selector temp:
//   - a `case n =>` var-binding catch-all prepends `let n = $sel` (the whole selector value);
//   - a PACKED `case Ctor(p) =>` arm prepends `let p = $sel >> ENUM_TAG_BITS` (the decoded payload);
//   - a HEAP `case Ctor(a, b, ...) =>` arm prepends one `let a = EnumField($sel, 1)`,
//     `let b = EnumField($sel, 2)`, ... per bound field (each loads its own buffer slot; a `_` field
//     binds nothing). Only one binding form is present on any one arm.
private func withBinding(arm: MatchArm, selName: String): ArrayList<ChirStmtSpec> {
    var prefixed = false
    let body = ArrayList<ChirStmtSpec>()
    match (arm.bindingName) {
        case Some(name) =>
            body.add(ChirStmtSpec.Let(name, ChirExprSpec.Ref(selName), isVar: false))
            prefixed = true
        case None => ()
    }
    match (arm.payloadBindingName) {
        case Some(name) =>
            body.add(ChirStmtSpec.Let(name, enumPayloadDecode(ChirExprSpec.Ref(selName)), isVar: false))
            prefixed = true
        case None => ()
    }
    // Heap field bindings: bind each named field to its own slot load (slot 0 is the tag, so payload
    // field i is at slot i+1).
    var fieldIdx = 0
    for (b in arm.heapFieldBindings) {
        match (b) {
            case Some(name) =>
                body.add(ChirStmtSpec.Let(name,
                    ChirExprSpec.EnumField(ChirExprSpec.Ref(selName), fieldIdx + 1), isVar: false))
                prefixed = true
            case None => ()
        }
        fieldIdx++
    }
    if (!prefixed) {
        return arm.body
    }
    for (s in arm.body) {
        body.add(s)
    }
    return body
}

// Build the OR-combined equality condition for an arm's literal values. The compared left-hand side is:
//   - `useHeap`:    the buffer's tag slot load `EnumField($sel, 0)` (heap-represented enum);
//   - `useTagMask`: the packed selector's decoded tag `($sel & ENUM_TAG_MASK)` (single-Int64 enum);
//   - otherwise:    the whole selector value `$sel` (payload-less enum / Int64-literal match, unchanged).
// `useHeap` and `useTagMask` are mutually exclusive. Requires at least one literal.
private func literalCond(selName: String, literals: ArrayList<Int64>, useTagMask: Bool,
    useHeap: Bool): Option<ChirExprSpec> {
    if (literals.isEmpty()) {
        return None
    }
    var acc: Option<ChirExprSpec> = None
    for (lit in literals) {
        let lhs = if (useHeap) {
            ChirExprSpec.EnumField(ChirExprSpec.Ref(selName), 0)
        } else if (useTagMask) {
            enumTagDecode(ChirExprSpec.Ref(selName))
        } else {
            ChirExprSpec.Ref(selName)
        }
        let eq = ChirExprSpec.Binary(ChirExprKind.EQUAL, lhs, ChirExprSpec.Literal(lit))
        acc = match (acc) {
            case Some(prev) => Some(ChirExprSpec.Binary(ChirExprKind.OR, prev, eq))
            case None => Some(eq)
        }
    }
    return acc
}

// A value-position match desugar result: the prelude statements to emit before the use site (the
// selector temp, the result-var declaration, and the if/else-if chain that assigns the result), and
// `resultRef`, a REF expr that reads the result var. The caller binds `resultRef` into its `let`/
// `return`/`print` (e.g. `let r = <resultRef>`).
private class MatchValue {
    let prelude: ArrayList<ChirStmtSpec>
    let resultRef: ChirExprSpec
    init(prelude: ArrayList<ChirStmtSpec>, resultRef: ChirExprSpec) {
        this.prelude = prelude
        this.resultRef = resultRef
    }
}

// Desugar a value-position `match (sel) { case L => <expr> ... }` into a fresh `var $res` plus the
// selector temp + if/else-if chain where each arm assigns its single value-expression to `$res`.
// Each arm body must be a block whose single statement is an expression (the yielded value). Returns
// None on any unsupported shape (multi-statement arm, non-expression arm, non-Int64-literal patterns,
// etc.) so the enclosing decl/return falls back. The result var is Int64-typed (the common type of
// the Int64-valued arms).
private func adaptMatchValue(matchExpr: ParseMatchExpr, scope: AdaptScope): Option<MatchValue> {
    // Validate the match shape and turn each arm's single value-expression into an assignment to the
    // result var. We reuse normalizeMatchArms' validation by re-walking the cases here because the
    // arm bodies in value position must each be a single expression (not arbitrary statements).
    if (!matchExpr.matchMode || matchExpr.selector.isNone()) {
        return None
    }
    if (!matchExpr.matchCaseOthers.isEmpty() || matchExpr.matchCases.isEmpty()) {
        return None
    }
    let resName = scope.freshTemp("match_res")
    scope.locals.add(resName)
    let arms = ArrayList<MatchArm>()
    var idx = 0
    for (matchCase in matchExpr.matchCases) {
        idx++
        if (matchCase.patternGuard.isSome()) {
            return None
        }
        let armBlock = match (matchCase.exprOrDecls) {
            case Some(b) => b
            case None => return None
        }
        let literals = ArrayList<Int64>()
        var isCatchAll = false
        var bindingName: Option<String> = None
        var payloadBindingName: Option<String> = None
        let heapFieldBindings = ArrayList<Option<String>>()
        for (pattern in matchCase.patterns) {
            if (let Some(constPat) <- (pattern as ParseConstPattern)) {
                let lit = match (constPat.literal) {
                    case Some(e) => e
                    case None => return None
                }
                match (intLiteralValue(lit)) {
                    case Some(v) => literals.add(v)
                    case None => return None
                }
            } else if (let Some(_) <- (pattern as ParseWildcardPattern)) {
                isCatchAll = true
            } else if (let Some((tag, fieldBindings)) <- heapEnumPatternMatch(pattern, scope)) {
                // A destructuring enum-constructor pattern over a heap enum `case Add(a, b) => <expr>`:
                // match the tag and bind each payload field (per-slot load) for use in the value expr.
                literals.add(tag)
                if (matchCase.patterns.size != 1) {
                    return None
                }
                for (b in fieldBindings) {
                    heapFieldBindings.add(b)
                }
            } else if (let Some((tag, payloadName)) <- enumPatternMatch(pattern, scope)) {
                // A destructuring enum-constructor pattern `case Ctor(n) => <expr>`: match the tag and
                // bind the decoded payload to `n` for use in the yielded value expression.
                literals.add(tag)
                if (matchCase.patterns.size != 1) {
                    return None
                }
                payloadBindingName = payloadName
            } else if (let Some(varPat) <- (pattern as ParseVarPattern)) {
                let n = varPat.identifier.Val()
                if (n.isEmpty()) {
                    return None
                }
                // A bare payload-less enum-variant pattern matches the variant's tag (see the
                // statement-form normalizer); otherwise it is a catch-all binding.
                if (let Some(tag) <- enumVariantPatternTag(varPat, scope)) {
                    literals.add(tag)
                } else {
                    isCatchAll = true
                    bindingName = Some(n)
                }
            } else {
                return None
            }
        }
        if (isCatchAll && (!literals.isEmpty() || matchCase.patterns.size != 1)) {
            return None
        }
        if (isCatchAll && idx != matchExpr.matchCases.size) {
            return None
        }
        // The arm body must be exactly one expression statement (the yielded value). Seed a var
        // binding name first so `case n => n + 1` resolves the binding inside the value expression,
        // and the payload binding for a destructuring `case Ctor(n) => ... n ...`.
        if (let Some(name) <- bindingName) {
            scope.locals.add(name)
        }
        if (let Some(name) <- payloadBindingName) {
            scope.locals.add(name)
        }
        for (b in heapFieldBindings) {
            if (let Some(name) <- b) {
                scope.locals.add(name)
            }
        }
        if (armBlock.body.size != 1) {
            return None
        }
        let valueParseExpr = match (armBlock.body[0] as ParseExpr) {
            case Some(e) => e
            case None => return None
        }
        // A String/Bool arm value is out of the Int64 value-match grammar.
        if (exprIsString(valueParseExpr, scope) || exprIsBool(valueParseExpr, scope)) {
            return None
        }
        let valueSpec = match (adaptExpr(valueParseExpr, scope)) {
            case Some(e) => e
            case None => return None
        }
        let armStmts = ArrayList<ChirStmtSpec>()
        armStmts.add(ChirStmtSpec.Assign(resName, valueSpec))
        let arm = MatchArm(literals, isCatchAll, bindingName, armStmts)
        arm.payloadBindingName = payloadBindingName
        for (b in heapFieldBindings) {
            arm.heapFieldBindings.add(b)
        }
        arms.add(arm)
    }
    // Declare the result var (initialized to 0; every reachable path assigns it) before the chain.
    let resInit = ChirStmtSpec.Let(resName, ChirExprSpec.Literal(0), isVar: true)
    let fold = matchIsExhaustiveEnum(matchExpr, arms, scope)
    let prelude = match (buildMatchChain(matchExpr, arms, Some(resInit), scope, foldLastAsElse: fold)) {
        case Some(p) => p
        case None => return None
    }
    return Some(MatchValue(prelude, ChirExprSpec.Ref(resName)))
}

// Adapt `for (name in start..end)` / `for (name in start..=end)`. Only a simple `VarPattern` loop
// variable iterating a literal `RangeExpr` (`..` exclusive or `..=` inclusive) over Int64 bound
// expressions is supported; anything else fails the match (fallback). The loop variable is added to
// scope for the body. A `where` guard is rejected.
private func adaptForIn(forInExpr: ParseForInExpr, scope: AdaptScope): Option<ChirStmtSpec> {
    if (forInExpr.patternGuard.isSome()) {
        return None
    }
    let pattern = match (forInExpr.pattern) {
        case Some(p) => p
        case None => return None
    }
    let varPattern = match (pattern as ParseVarPattern) {
        case Some(vp) => vp
        case None => return None
    }
    let varName = varPattern.identifier.Val()
    if (varName.isEmpty()) {
        return None
    }
    let inExpr = match (forInExpr.inExpr) {
        case Some(e) => e
        case None => return None
    }
    // `for (x in a)` over an Int64 array local: iterate its elements.
    if (let Some(arrayName) <- arrayRefName(inExpr, scope)) {
        let body = match (forInExpr.body) {
            case Some(b) => b
            case None => return None
        }
        scope.locals.add(varName)
        scope.loopDepth++
        let bodyStmts = match (adaptStatements(body, scope)) {
            case Some(s) =>
                scope.loopDepth--
                s
            case None =>
                scope.loopDepth--
                return None
        }
        scope.needsRuntime = true
        return Some(ChirStmtSpec.ArrayFor(varName, arrayName, bodyStmts))
    }
    let rangeExpr = match (inExpr as ParseRangeExpr) {
        case Some(r) => r
        case None => return None
    }
    let inclusive = match (rangeExpr.op.kind) {
        case TokenKind.RANGEOP => false
        case TokenKind.CLOSEDRANGEOP => true
        case _ => return None
    }
    let startExpr = match (rangeExpr.leftExpr) {
        case Some(e) => e
        case None => return None
    }
    let endExpr = match (rangeExpr.rightExpr) {
        case Some(e) => e
        case None => return None
    }
    let startSpec = match (adaptExpr(startExpr, scope)) {
        case Some(e) => e
        case None => return None
    }
    let endSpec = match (adaptExpr(endExpr, scope)) {
        case Some(e) => e
        case None => return None
    }
    let body = match (forInExpr.body) {
        case Some(b) => b
        case None => return None
    }
    // The loop variable is an Int64 local in scope for the body.
    scope.locals.add(varName)
    scope.loopDepth++
    let bodyStmts = match (adaptStatements(body, scope)) {
        case Some(s) =>
            scope.loopDepth--
            s
        case None =>
            scope.loopDepth--
            return None
    }
    scope.needsRuntime = true
    return Some(ChirStmtSpec.For(varName, startSpec, endSpec, inclusive, bodyStmts))
}

// Adapt a `break` / `continue` jump. Only accepted inside a loop (loopDepth > 0); otherwise fall
// back. A loop body is genuine runtime computation, so these mark needsRuntime.
private func adaptJump(jumpExpr: ParseJumpExpr, scope: AdaptScope): Option<ChirStmtSpec> {
    if (scope.loopDepth <= 0) {
        return None
    }
    return match (jumpExpr.token.kind) {
        case TokenKind.BREAK =>
            scope.needsRuntime = true
            Some(ChirStmtSpec.Break())
        case TokenKind.CONTINUE =>
            scope.needsRuntime = true
            Some(ChirStmtSpec.Continue())
        case _ => None
    }
}

// Adapt a parse expression into a CHIR expression spec. Supports Int64 literals, references to
// known locals, parenthesized expressions, and arithmetic/relational binary ops. A binary op over
// any sub-expression marks the body as needing runtime computation.
private func adaptExpr(expr: ParseExpr, scope: AdaptScope): Option<ChirExprSpec> {
    if (let Some(litValue) <- intLiteralValue(expr)) {
        return Some(ChirExprSpec.Literal(litValue))
    }
    if (let Some(boolValue) <- boolLiteralValue(expr)) {
        return Some(ChirExprSpec.BoolLit(boolValue))
    }
    // A plain string literal lowers to a CString (i8*) String value.
    if (let Some(text) <- plainStringLiteralValue(expr)) {
        return Some(ChirExprSpec.StrLit(text))
    }
    // A string-interpolation literal (`"a=${x} b=${y+1}"`): lower to a concat of the literal text
    // parts and the stringified interpolated expressions, in order.
    if (let Some(spec) <- adaptInterpolation(expr, scope)) {
        return Some(spec)
    }
    // A bare reference to a payload-less variant of a HEAP-represented enum (`Z` in an enum that also
    // has multi-field variants) must build the {tag} buffer form (a 1-slot buffer) so it shares the
    // uniform heap value representation -- not a plain tag literal. Checked before the packed path.
    if (let Some(spec) <- adaptHeapBareVariant(expr, scope)) {
        return Some(spec)
    }
    // A bare reference to a payload-less enum variant (`Green`, `N`) is the variant's value: its
    // Int64 tag constant. Checked before the local-ref path so a variant name never mis-resolves
    // (variants are not locals). Constructing a variant is genuine runtime computation -> promote.
    if (let Some(tag) <- enumVariantTag(expr, scope)) {
        scope.needsRuntime = true
        return Some(ChirExprSpec.Literal(tag))
    }
    // Constructing a payload-carrying variant `Ctor(<payload>)`: encode the value as a single Int64
    // = (payload << ENUM_TAG_BITS) | tag. The Int64 ABI then carries it through params/returns/locals.
    if (let Some(spec) <- adaptEnumConstruction(expr, scope)) {
        return Some(spec)
    }
    if (let Some(refName) <- localRefName(expr, scope)) {
        return Some(ChirExprSpec.Ref(refName))
    }
    // a[i]: a subscript over an Int64 array local with a single Int64 index expression.
    if (let Some(subscript) <- (expr as ParseSubscriptExpr)) {
        return adaptSubscript(subscript, scope)
    }
    // a.size: the element count of an Int64 array local (statically known at adapt time).
    if (let Some(member) <- (expr as ParseMemberAccess)) {
        return adaptArraySize(member, scope)
    }
    if (let Some(unary) <- (expr as ParseUnaryExpr)) {
        let op = match (toChirUnaryOp(unary.op.kind)) {
            case Some(o) => o
            case None => return None
        }
        let operandExpr = match (unary.expr) {
            case Some(e) => e
            case None => return None
        }
        let operandSpec = match (adaptExpr(operandExpr, scope)) {
            case Some(e) => e
            case None => return None
        }
        scope.needsRuntime = true
        return Some(ChirExprSpec.Unary(op, operandSpec))
    }
    if (let Some(paren) <- (expr as ParseParenExpr)) {
        let inner = match (paren.expr) {
            case Some(e) => e
            case None => return None
        }
        return adaptExpr(inner, scope)
    }
    if (let Some(call) <- (expr as ParseCallExpr)) {
        return adaptCall(call, scope)
    }
    // AssignExpr is also a BinaryExpr; exclude it (handled only as a statement).
    if (let Some(_) <- (expr as ParseAssignExpr)) {
        return None
    }
    if (let Some(binary) <- (expr as ParseBinaryExpr)) {
        let op = match (toChirBinaryOp(binary.op.kind)) {
            case Some(o) => o
            case None => return None
        }
        let leftExpr = match (binary.leftExpr) {
            case Some(e) => e
            case None => return None
        }
        let rightExpr = match (binary.rightExpr) {
            case Some(e) => e
            case None => return None
        }
        let lhsSpec = match (adaptExpr(leftExpr, scope)) {
            case Some(e) => e
            case None => return None
        }
        let rhsSpec = match (adaptExpr(rightExpr, scope)) {
            case Some(e) => e
            case None => return None
        }
        scope.needsRuntime = true
        return Some(ChirExprSpec.Binary(op, lhsSpec, rhsSpec))
    }
    return None
}

// Adapt a string-interpolation literal into a CHIR String concat spec. The parser stores the parsed
// interpolation on `LitConstExpr.siExpr` as a `StrInterpolationExpr` whose `strParts` (a literal-text
// STR part or an interpolated EXPR part) run parallel to `strPartExprs` (the matching parse Expr; a
// `LitConstExpr` for STR parts, an `InterpolationExpr` for EXPR parts). We lower it to a left-folded
// concat of: each STR part as a `StrLit`, and each EXPR part as `ToStringConv(<adapted expr>)`
// (Int64/Bool stringified at runtime; a String expr passes through). Any unsupported shape (escapes
// in a literal part, a non-simple interpolated expression, a multi-statement interpolation block)
// returns None so the whole body falls back -- plain strings never regress. Building any concat marks
// the body as needing runtime computation.
private func adaptInterpolation(expr: ParseExpr, scope: AdaptScope): Option<ChirExprSpec> {
    let lit = match (expr as ParseLitConstExpr) {
        case Some(l) => l
        case None => return None
    }
    if (lit.kind != ParseLitConstKind.STRING) {
        return None
    }
    let si = match (lit.siExpr) {
        case Some(s) => s
        case None => return None
    }
    // strParts and strPartExprs are built in lock-step by the parser; bail if they ever diverge.
    if (si.strParts.size != si.strPartExprs.size || si.strParts.isEmpty()) {
        return None
    }
    var acc: Option<ChirExprSpec> = None
    var idx = 0
    while (idx < si.strParts.size) {
        let part = si.strParts[idx]
        let partExpr = si.strPartExprs[idx]
        let pieceSpec = if (part.strKind == StringPartKind.STR) {
            // A literal text segment. Reject any backslash escape so escape handling never diverges.
            match (plainInterpolationText(part.value)) {
                case Some(text) => ChirExprSpec.StrLit(text)
                case None => return None
            }
        } else {
            // An interpolated `${...}` segment: extract the inner expression and stringify it.
            let inner = match (interpolationInnerExpr(partExpr)) {
                case Some(e) => e
                case None => return None
            }
            let innerSpec = match (adaptExpr(inner, scope)) {
                case Some(e) => e
                case None => return None
            }
            // A String interpolated expr passes through; Int64/Bool are stringified at runtime.
            if (exprIsString(inner, scope)) {
                innerSpec
            } else {
                ChirExprSpec.ToStringConv(innerSpec)
            }
        }
        acc = match (acc) {
            case Some(prev) => Some(ChirExprSpec.Binary(ChirExprKind.ADD, prev, pieceSpec))
            case None => Some(pieceSpec)
        }
        idx++
    }
    match (acc) {
        case Some(result) =>
            scope.needsRuntime = true
            return Some(result)
        case None => return None
    }
}

// Extract the single inner expression of an interpolation segment. The parser stores it as an
// `InterpolationExpr` whose `block` is the parsed `${...}` body (parsed as a function-body block).
// Only a block with exactly one statement that is itself an expression is supported; anything else
// (empty/broken interpolation, a multi-statement block, a declaration) returns None (fallback).
private func interpolationInnerExpr(partExpr: ParseExpr): Option<ParseExpr> {
    let interp = match (partExpr as ParseInterpolationExpr) {
        case Some(i) => i
        case None => return None
    }
    let block = match (interp.block) {
        case Some(b) => b
        case None => return None
    }
    if (block.body.size != 1) {
        return None
    }
    return block.body[0] as ParseExpr
}

// A literal interpolation text segment with no backslash escapes (return None on any `\` so escape
// handling stays on the fallback path, mirroring plainStringLiteralValue).
private func plainInterpolationText(text: String): Option<String> {
    var idx = 0
    while (idx < text.size) {
        if (text[idx] == b'\\') {
            return None
        }
        idx++
    }
    return Some(text)
}

// Adapt a statement-level `println(<expr>)` / `print(<expr>)` into a runtime PRINT stmt spec.
// Only the print built-ins with exactly one positional argument are recognized; the argument must be
// a supported runtime Int64 expression. A bare integer or string literal argument is deliberately
// rejected (returns None) so it stays on the already-verified summary print path for byte-for-byte
// parity; this path handles only genuine runtime values (var refs, user calls, arithmetic).
private func adaptPrint(call: ParseCallExpr, scope: AdaptScope): Option<ChirStmtSpec> {
    let base = match (call.baseFunc) {
        case Some(b) => b
        case None => return None
    }
    let calleeRef = match (base as ParseRefExpr) {
        case Some(r) => r
        case None => return None
    }
    if (!calleeRef.typeArguments.isEmpty()) {
        return None
    }
    let calleeName = calleeRef.identifier.Val()
    if (calleeName != "println" && calleeName != "print") {
        return None
    }
    // A local/param named `print`/`println` shadows the built-in: do not treat as a print.
    if (scope.locals.contains(calleeName)) {
        return None
    }
    let newline = calleeName == "println"
    if (call.args.size != 1) {
        return None
    }
    let funcArg = call.args[0]
    if (!funcArg.name.Empty() || funcArg.withInout) {
        return None
    }
    let argExpr = match (funcArg.expr) {
        case Some(e) => e
        case None => return None
    }
    // A pure integer-literal argument lowers as a runtime PRINT of a constant value (the real body
    // emits a Constant and a printf("%ld[\n]") of it). Crucially this does NOT set needsRuntime: a
    // body whose only statements are literal prints will not promote and stays on the byte-for-byte
    // summary path. But once any sibling statement is genuinely runtime (binary op, var, call, ...),
    // the whole body promotes and these literal prints lower in-body too -- in source order.
    if (let Some(litValue) <- intLiteralValue(argExpr)) {
        return Some(ChirStmtSpec.Print(ChirExprSpec.Literal(litValue), newline: newline))
    }
    // A pure string-literal argument (no escape sequences) lowers as an in-body literal-string print.
    // Same gating as integer literals: it does not by itself set needsRuntime.
    if (let Some(text) <- plainStringLiteralValue(argExpr)) {
        return Some(ChirStmtSpec.PrintStr(text, newline: newline))
    }
    let argSpec = match (adaptExpr(argExpr, scope)) {
        case Some(e) => e
        case None => return None
    }
    // Require genuine runtime computation for the printed value (a bare let-bound literal ref does
    // not set needsRuntime via adaptExpr, so it would not promote -- which is fine: such a case
    // stays on the summary int path). adaptExpr already sets needsRuntime for var/param refs,
    // binary ops, and calls; reflect that the body needs the real path.
    scope.needsRuntime = true
    return Some(ChirStmtSpec.Print(argSpec, newline: newline))
}

// Adapt a call `f(arg0, arg1, ...)` over a simple top-level function name into a CHIR CALL expr
// spec. Only direct calls whose callee is a bare RefExpr naming a known top-level function and whose
// arguments are positional Int64 expressions are accepted; anything else fails the match (fallback).
private func adaptCall(call: ParseCallExpr, scope: AdaptScope): Option<ChirExprSpec> {
    let base = match (call.baseFunc) {
        case Some(b) => b
        case None => return None
    }
    let calleeRef = match (base as ParseRefExpr) {
        case Some(r) => r
        case None => return None
    }
    // Reject generic call type arguments.
    if (!calleeRef.typeArguments.isEmpty()) {
        return None
    }
    let calleeName = calleeRef.identifier.Val()
    // Must name a known top-level function, and must not be shadowed by a local.
    if (calleeName.isEmpty() || scope.locals.contains(calleeName) || !scope.funcNames.contains(calleeName)) {
        return None
    }
    let argSpecs = ArrayList<ChirExprSpec>()
    for (funcArg in call.args) {
        // No named or inout arguments in the supported grammar.
        if (!funcArg.name.Empty() || funcArg.withInout) {
            return None
        }
        let argExpr = match (funcArg.expr) {
            case Some(e) => e
            case None => return None
        }
        let argSpec = match (adaptExpr(argExpr, scope)) {
            case Some(e) => e
            case None => return None
        }
        argSpecs.add(argSpec)
    }
    scope.needsRuntime = true
    return Some(ChirExprSpec.Call(calleeName, argSpecs))
}

// Adapt a sized array constructor `Array<Int64>(n, repeat: v)` / `Array<Int64>(n, item: v)` with a
// literal size `n` into an ARRAY_LET of n copies of the (pure Int64) fill expression. The callee must
// be a bare RefExpr `Array` (not shadowed by a local) with a single Int64 type argument; the first
// argument is a positional int literal (the size) and the second is named `repeat`/`item`. Anything
// else returns None so the body falls back. Marks the new array local in scope.
private func adaptArrayCtor(initExpr: ParseExpr, scope: AdaptScope, name: String): Option<ChirStmtSpec> {
    let call = match (initExpr as ParseCallExpr) {
        case Some(c) => c
        case None => return None
    }
    let base = match (call.baseFunc) {
        case Some(b) => b
        case None => return None
    }
    let calleeRef = match (base as ParseRefExpr) {
        case Some(r) => r
        case None => return None
    }
    if (calleeRef.identifier.Val() != "Array" || scope.locals.contains("Array")) {
        return None
    }
    // Require exactly one type argument and that it be the Int64 element type.
    if (calleeRef.typeArguments.size != 1 || calleeRef.typeArguments[0].ToString() != "Int64") {
        return None
    }
    if (call.args.size != 2) {
        return None
    }
    // First argument: positional literal size.
    let sizeArg = call.args[0]
    if (!sizeArg.name.Empty() || sizeArg.withInout) {
        return None
    }
    let sizeExpr = match (sizeArg.expr) {
        case Some(e) => e
        case None => return None
    }
    let size = match (intLiteralValue(sizeExpr)) {
        case Some(n) => n
        case None => return None
    }
    if (size < 0) {
        return None
    }
    // Second argument: named `repeat:` or `item:` fill value (a pure Int64 expression).
    let fillArg = call.args[1]
    let fillLabel = fillArg.name.Val()
    if (fillLabel != "repeat" && fillLabel != "item") {
        return None
    }
    if (fillArg.withInout) {
        return None
    }
    let fillExpr = match (fillArg.expr) {
        case Some(e) => e
        case None => return None
    }
    // Only an Int64 fill value is supported (the array is VArray<Int64>).
    if (exprIsString(fillExpr, scope) || exprIsBool(fillExpr, scope)) {
        return None
    }
    let fillSpec = match (adaptExpr(fillExpr, scope)) {
        case Some(e) => e
        case None => return None
    }
    // Replicate the (pure) fill expression `size` times. Safe for the Int64 grammar (literals, local
    // refs, arithmetic) which has no observable side effects.
    let elems = ArrayList<ChirExprSpec>()
    var i: Int64 = 0
    while (i < size) {
        elems.add(fillSpec)
        i++
    }
    scope.locals.add(name)
    scope.arrayNames.add(name)
    scope.arrayLengths[name] = size
    scope.needsRuntime = true
    return Some(ChirStmtSpec.ArrayLet(name, elems))
}

// Adapt `a[i]` over an Int64 array local: the base must be a RefExpr naming a known array local and
// there must be exactly one index expression (an Int64 expr). Anything else fails the match (fallback).
private func adaptSubscript(subscript: ParseSubscriptExpr, scope: AdaptScope): Option<ChirExprSpec> {
    let base = match (subscript.baseExpr) {
        case Some(b) => b
        case None => return None
    }
    let arrayName = match (arrayRefName(base, scope)) {
        case Some(n) => n
        case None => return None
    }
    if (subscript.indexExprs.size != 1) {
        return None
    }
    let indexSpec = match (adaptExpr(subscript.indexExprs[0], scope)) {
        case Some(e) => e
        case None => return None
    }
    scope.needsRuntime = true
    return Some(ChirExprSpec.ArrayIndex(ChirExprSpec.Ref(arrayName), indexSpec))
}

// Adapt `a.size` over an Int64 array local: the base must be a RefExpr naming a known array local and
// the member field must be `size`. The element count is statically known and emitted as a constant.
private func adaptArraySize(member: ParseMemberAccess, scope: AdaptScope): Option<ChirExprSpec> {
    if (member.field.GetRawText() != "size") {
        return None
    }
    if (!member.typeArguments.isEmpty()) {
        return None
    }
    let base = match (member.baseExpr) {
        case Some(b) => b
        case None => return None
    }
    let arrayName = match (arrayRefName(base, scope)) {
        case Some(n) => n
        case None => return None
    }
    let len = match (scope.arrayLengths.get(arrayName)) {
        case Some(l) => l
        case None => return None
    }
    scope.needsRuntime = true
    return Some(ChirExprSpec.ArraySize(len))
}

// If `expr` is a bare RefExpr naming a known array local, return that name; otherwise None.
private func arrayRefName(expr: ParseExpr, scope: AdaptScope): Option<String> {
    if (let Some(refExpr) <- (expr as ParseRefExpr)) {
        let name = refExpr.identifier.Val()
        if (scope.arrayNames.contains(name)) {
            return Some(name)
        }
    }
    return None
}

// Map a parse binary-op token to a CHIR ExprKind. Only the Int64 arithmetic and relational ops
// modeled by the lowering path are accepted; anything else fails the match (fallback).
private func toChirBinaryOp(kind: TokenKind): Option<ChirExprKind> {
    return match (kind) {
        case TokenKind.ADD => Some(ChirExprKind.ADD)
        case TokenKind.SUB => Some(ChirExprKind.SUB)
        case TokenKind.MUL => Some(ChirExprKind.MUL)
        case TokenKind.DIV => Some(ChirExprKind.DIV)
        case TokenKind.MOD => Some(ChirExprKind.MOD)
        case TokenKind.LT => Some(ChirExprKind.LT)
        case TokenKind.GT => Some(ChirExprKind.GT)
        case TokenKind.LE => Some(ChirExprKind.LE)
        case TokenKind.GE => Some(ChirExprKind.GE)
        case TokenKind.EQUAL => Some(ChirExprKind.EQUAL)
        case TokenKind.NOTEQ => Some(ChirExprKind.NOTEQUAL)
        case TokenKind.AND => Some(ChirExprKind.AND)
        case TokenKind.OR => Some(ChirExprKind.OR)
        case _ => None
    }
}

// Map a parse unary-op token to a CHIR ExprKind. `!` -> NOT (Bool), `-` -> NEG (Int64); anything
// else fails the match (fallback).
private func toChirUnaryOp(kind: TokenKind): Option<ChirExprKind> {
    return match (kind) {
        case TokenKind.NOT => Some(ChirExprKind.NOT)
        case TokenKind.SUB => Some(ChirExprKind.NEG)
        case _ => None
    }
}

// Decide (syntactically) whether `expr` produces a Bool value: a bool literal, a reference to a
// known Bool local/param, a parenthesized bool expression, a `!` unary, or a relational/logical
// binary op (`<`, `>`, `<=`, `>=`, `==`, `!=`, `&&`, `||`). Used only to classify a value for the
// Bool-print promotion; unknown shapes return false (fall back conservatively).
private func exprIsBool(expr: ParseExpr, scope: AdaptScope): Bool {
    if (boolLiteralValue(expr).isSome()) {
        return true
    }
    if (let Some(refExpr) <- (expr as ParseRefExpr)) {
        return scope.boolNames.contains(refExpr.identifier.Val())
    }
    if (let Some(paren) <- (expr as ParseParenExpr)) {
        if (let Some(inner) <- paren.expr) {
            return exprIsBool(inner, scope)
        }
        return false
    }
    if (let Some(unary) <- (expr as ParseUnaryExpr)) {
        return unary.op.kind == TokenKind.NOT
    }
    // AssignExpr is also a BinaryExpr; never treat it as a bool-producing value here.
    if (let Some(_) <- (expr as ParseAssignExpr)) {
        return false
    }
    if (let Some(binary) <- (expr as ParseBinaryExpr)) {
        return match (binary.op.kind) {
            case TokenKind.LT => true
            case TokenKind.GT => true
            case TokenKind.LE => true
            case TokenKind.GE => true
            case TokenKind.EQUAL => true
            case TokenKind.NOTEQ => true
            case TokenKind.AND => true
            case TokenKind.OR => true
            case _ => false
        }
    }
    return false
}

// Decide (syntactically) whether `expr` produces a String value: a plain string literal, a reference
// to a known String local/param, a parenthesized String expression, a call to a String-returning
// top-level function, or a `+` concatenation where at least one side is a String. Used to classify a
// value for String let/var tracking and concat/print promotion; unknown shapes return false.
private func exprIsString(expr: ParseExpr, scope: AdaptScope): Bool {
    if (plainStringLiteralValue(expr).isSome()) {
        return true
    }
    // A string-interpolation literal is a String value (it lowers to a String concat).
    if (let Some(lit) <- (expr as ParseLitConstExpr)) {
        if (lit.kind == ParseLitConstKind.STRING && lit.siExpr.isSome()) {
            return true
        }
    }
    if (let Some(refExpr) <- (expr as ParseRefExpr)) {
        return scope.strNames.contains(refExpr.identifier.Val())
    }
    if (let Some(paren) <- (expr as ParseParenExpr)) {
        if (let Some(inner) <- paren.expr) {
            return exprIsString(inner, scope)
        }
        return false
    }
    // A call to a String-returning top-level function (and not shadowed by a local).
    if (let Some(call) <- (expr as ParseCallExpr)) {
        if (let Some(base) <- call.baseFunc) {
            if (let Some(calleeRef) <- (base as ParseRefExpr)) {
                let cn = calleeRef.identifier.Val()
                if (!scope.locals.contains(cn) && scope.strReturningFuncs.contains(cn)) {
                    return true
                }
            }
        }
        return false
    }
    // AssignExpr is also a BinaryExpr; never treat it as a String-producing value here.
    if (let Some(_) <- (expr as ParseAssignExpr)) {
        return false
    }
    // `a + b` is a String concat when either operand is a String.
    if (let Some(binary) <- (expr as ParseBinaryExpr)) {
        if (binary.op.kind != TokenKind.ADD) {
            return false
        }
        let leftIsStr = match (binary.leftExpr) {
            case Some(e) => exprIsString(e, scope)
            case None => false
        }
        let rightIsStr = match (binary.rightExpr) {
            case Some(e) => exprIsString(e, scope)
            case None => false
        }
        return leftIsStr || rightIsStr
    }
    return false
}

// Extract a Bool literal value from a `true`/`false` BOOL literal expression; None otherwise.
private func boolLiteralValue(expr: ParseExpr): Option<Bool> {
    if (let Some(lit) <- (expr as ParseLitConstExpr)) {
        if (lit.kind == ParseLitConstKind.BOOL) {
            if (lit.stringValue == "true") {
                return Some(true)
            }
            if (lit.stringValue == "false") {
                return Some(false)
            }
        }
    }
    return None
}

// If `varPat`'s identifier names a payload-less enum variant in scope, return its Int64 tag; else
// None (then the VarPattern is a normal catch-all binding).
private func enumVariantPatternTag(varPat: ParseVarPattern, scope: AdaptScope): Option<Int64> {
    let name = varPat.identifier.Val()
    if (scope.isEnumVariant(name)) {
        return scope.enums.tagOf(name)
    }
    return None
}

// If `expr` is a bare RefExpr naming a payload-LESS enum variant in scope (and not shadowed by a
// local), return that variant's encoded Int64 value; otherwise None. A payload-less variant -- whether
// in an all-payload-less enum (`Green`) or a payload-carrying enum (`None`) -- encodes as just its tag
// (the tag occupies the low ENUM_TAG_BITS bits with a zero payload), so the encoded value equals the
// tag. A bare reference to a payload-CARRYING variant (`Some` with no args) is a partial application,
// not a value, and is rejected. A variant reference with type arguments (`Green<...>`) is rejected.
private func enumVariantTag(expr: ParseExpr, scope: AdaptScope): Option<Int64> {
    if (let Some(refExpr) <- (expr as ParseRefExpr)) {
        if (!refExpr.typeArguments.isEmpty()) {
            return None
        }
        let name = refExpr.identifier.Val()
        if (scope.isEnumVariant(name) && !scope.enums.hasPayload(name)) {
            return scope.enums.tagOf(name)
        }
    }
    return None
}

// If `expr` is a bare RefExpr naming a payload-less variant of a HEAP-represented enum, build its
// {tag} buffer value (a 1-slot heap buffer) so it shares the enum's uniform heap representation.
// Otherwise None (the variant is in a non-heap enum, or this is not a bare variant reference).
private func adaptHeapBareVariant(expr: ParseExpr, scope: AdaptScope): Option<ChirExprSpec> {
    if (let Some(refExpr) <- (expr as ParseRefExpr)) {
        if (!refExpr.typeArguments.isEmpty()) {
            return None
        }
        let name = refExpr.identifier.Val()
        if (scope.isEnumVariant(name) && scope.enums.isHeap(name) && !scope.enums.hasPayload(name)) {
            if (let Some(tag) <- scope.enums.tagOf(name)) {
                scope.needsRuntime = true
                return Some(ChirExprSpec.EnumMake(tag, ArrayList<ChirExprSpec>()))
            }
        }
    }
    return None
}

// Construct a payload-carrying variant `Ctor(<payload>)`: encode the value as a single Int64 =
// (payload << ENUM_TAG_BITS) | tag, lowered as `(<payload-expr> LSHIFT bits) BITOR tag`. The callee
// must be a bare RefExpr naming a single-payload variant in scope (not shadowed by a local, no type
// arguments) called with exactly one positional argument whose classified value matches the variant's
// payload type (Int64 vs String). Anything else returns None (fall back). Constructing a value is
// genuine runtime computation -> promote. Returns None for CUT 3 (String payload) until that cut.
private func adaptEnumConstruction(expr: ParseExpr, scope: AdaptScope): Option<ChirExprSpec> {
    let call = match (expr as ParseCallExpr) {
        case Some(c) => c
        case None => return None
    }
    let base = match (call.baseFunc) {
        case Some(b) => b
        case None => return None
    }
    let calleeRef = match (base as ParseRefExpr) {
        case Some(r) => r
        case None => return None
    }
    if (!calleeRef.typeArguments.isEmpty()) {
        return None
    }
    let name = calleeRef.identifier.Val()
    if (!scope.isEnumVariant(name)) {
        return None
    }
    let payloadKind = match (scope.enums.payloadKindOf(name)) {
        case Some(k) => k
        case None => return None
    }
    // A heap-represented enum: `Ctor(a, b, ...)` stores each field in its OWN Int64 slot of a
    // {tag, f0, f1, ...} buffer (no bit-packing). Accept exactly the variant's declared number of
    // positional Int64 args. A payload-less variant in a heap enum (`Z`) is built as a bare reference
    // (handled in enumVariantTag), not a call, so it is not reached here.
    if (scope.enums.isHeap(name)) {
        return adaptHeapEnumConstruction(name, call, scope)
    }
    if (payloadKind == ENUM_PAYLOAD_NONE) {
        return None // payload-less variant cannot be applied to an argument
    }
    let tag = match (scope.enums.tagOf(name)) {
        case Some(t) => t
        case None => return None
    }
    if (call.args.size != 1) {
        return None
    }
    let arg = call.args[0]
    if (!arg.name.Empty() || arg.withInout) {
        return None
    }
    let argExpr = match (arg.expr) {
        case Some(e) => e
        case None => return None
    }
    // Gate the argument against the declared payload type so a value never mis-encodes.
    if (payloadKind == ENUM_PAYLOAD_INT) {
        if (exprIsString(argExpr, scope) || exprIsBool(argExpr, scope)) {
            return None
        }
        let payloadSpec = match (adaptExpr(argExpr, scope)) {
            case Some(e) => e
            case None => return None
        }
        scope.needsRuntime = true
        // (payload << ENUM_TAG_BITS) | tag
        let shifted = ChirExprSpec.Binary(ChirExprKind.LSHIFT, payloadSpec,
            ChirExprSpec.Literal(ENUM_TAG_BITS))
        return Some(ChirExprSpec.Binary(ChirExprKind.BITOR, shifted, ChirExprSpec.Literal(tag)))
    }
    // ENUM_PAYLOAD_STRING is handled in CUT 3 (a String payload cannot be packed into the Int64
    // encoding); leave it on the existing path for now.
    return None
}

// Construct a heap-represented enum variant `Ctor(a, b, ...)`: each field is stored in its OWN Int64
// slot of a {tag, f0, f1, ...} buffer (NOT bit-packed), so large field values round-trip losslessly.
// Accepts exactly the variant's declared field count of positional Int64 arguments; any named arg,
// inout, arity mismatch, or non-Int64 (String/Bool) argument returns None (fall back). The materialized
// value is the buffer address as an Int64 so it crosses the Int64 enum ABI.
private func adaptHeapEnumConstruction(name: String, call: ParseCallExpr,
    scope: AdaptScope): Option<ChirExprSpec> {
    let tag = match (scope.enums.tagOf(name)) {
        case Some(t) => t
        case None => return None
    }
    let fieldCount = match (scope.enums.fieldCountOf(name)) {
        case Some(n) => n
        case None => return None
    }
    if (call.args.size != fieldCount) {
        return None
    }
    let fields = ArrayList<ChirExprSpec>()
    for (arg in call.args) {
        if (!arg.name.Empty() || arg.withInout) {
            return None
        }
        let argExpr = match (arg.expr) {
            case Some(e) => e
            case None => return None
        }
        // Each field must be an Int64 value (the heap buffer stores Int64 slots only).
        if (exprIsString(argExpr, scope) || exprIsBool(argExpr, scope)) {
            return None
        }
        let fieldSpec = match (adaptExpr(argExpr, scope)) {
            case Some(e) => e
            case None => return None
        }
        fields.add(fieldSpec)
    }
    scope.needsRuntime = true
    return Some(ChirExprSpec.EnumMake(tag, fields))
}

// Decode the payload Int64 out of an enum value reference: `<enumRef> RSHIFT ENUM_TAG_BITS`. RSHIFT
// over a signed Int64 emits an arithmetic shift, so the payload sign-extends. Used to bind `case
// Ctor(n) => ... n ...` to the variant's stored payload.
private func enumPayloadDecode(enumRef: ChirExprSpec): ChirExprSpec {
    return ChirExprSpec.Binary(ChirExprKind.RSHIFT, enumRef, ChirExprSpec.Literal(ENUM_TAG_BITS))
}

// Decode the tag Int64 out of an enum value reference: `<enumRef> BITAND ENUM_TAG_MASK`. Used to test
// which variant a value is when matching.
private func enumTagDecode(enumRef: ChirExprSpec): ChirExprSpec {
    return ChirExprSpec.Binary(ChirExprKind.BITAND, enumRef, ChirExprSpec.Literal(ENUM_TAG_MASK))
}

private func localRefName(expr: ParseExpr, scope: AdaptScope): Option<String> {
    if (let Some(refExpr) <- (expr as ParseRefExpr)) {
        let name = refExpr.identifier.Val()
        if (scope.locals.contains(name)) {
            // A parameter reference is genuine runtime computation (cannot be folded); promote.
            if (scope.params.contains(name)) {
                scope.needsRuntime = true
            }
            return Some(name)
        }
    }
    return None
}

private func intLiteralValue(expr: ParseExpr): Option<Int64> {
    if (let Some(lit) <- (expr as ParseLitConstExpr)) {
        if (lit.kind == ParseLitConstKind.INTEGER) {
            return parseIntText(lit.stringValue)
        }
    }
    return None
}

// Extract a plain string-literal value (a `"..."` STRING literal whose raw text contains no escape
// sequences and no string interpolation). The parse lexer already strips the surrounding quotes from
// `stringValue`, so the raw slice equals the intended text only when no `\` escape is present; if a
// backslash appears we return None and fall back so escape handling never diverges from the summary
// path. Multiline / raw / interpolated string kinds are also rejected (return None).
private func plainStringLiteralValue(expr: ParseExpr): Option<String> {
    if (let Some(lit) <- (expr as ParseLitConstExpr)) {
        // An interpolated string literal carries a parsed `siExpr`; it is not a plain literal.
        if (lit.kind == ParseLitConstKind.STRING && lit.siExpr.isNone()) {
            let text = lit.stringValue
            var idx = 0
            while (idx < text.size) {
                if (text[idx] == b'\\') {
                    return None
                }
                idx++
            }
            return Some(text)
        }
    }
    return None
}

private func parseIntText(value: String): Option<Int64> {
    let normalized = value.replace("_", "")
    try {
        return Some(Int64.parse(normalized))
    } catch (e: Exception) {
        return None
    }
}
