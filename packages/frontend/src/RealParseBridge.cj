package cangjie_compiler::frontend

import std.collection.*
import std.convert.*
import cangjie_compiler::basic.SourceManager
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
import cangjie_compiler::parse.Block as ParseBlock
import cangjie_compiler::parse.LitConstKind as ParseLitConstKind
import cangjie_compiler::parse.InterpolationExpr as ParseInterpolationExpr
import cangjie_compiler::parse.ArrayLit as ParseArrayLit
import cangjie_compiler::parse.SubscriptExpr as ParseSubscriptExpr
import cangjie_compiler::parse.MemberAccess as ParseMemberAccess
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
            tryAdaptFunction(funcDecl, parsedFile, funcNames, strReturningFuncs)
        }
    }
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
    strReturningFuncs: HashSet<String>): Unit {
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
        adaptParsedFunc(funcDecl, parsedFunc, funcNames, strReturningFuncs)
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
    var needsRuntime: Bool = false
    // Depth of enclosing `for`/`while` loops currently being adapted. A `break`/`continue` is only
    // accepted (promotable) when loopDepth > 0; otherwise the body falls back to the summary path.
    var loopDepth: Int64 = 0

    init(funcNames: HashSet<String>, strReturningFuncs: HashSet<String>) {
        this.funcNames = funcNames
        for (n in strReturningFuncs) {
            this.strReturningFuncs.add(n)
        }
    }
}

private func adaptParsedFunc(funcDecl: FuncDecl, parsedFunc: ParseFuncDecl, funcNames: HashSet<String>,
    strReturningFuncs: HashSet<String>): Unit {
    let body = match (parsedFunc.funcBody) {
        case Some(fb) => fb
        case None => return
    }
    let block = match (body.body) {
        case Some(b) => b
        case None => return
    }
    let scope = AdaptScope(funcNames, strReturningFuncs)
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
            match (adaptVarDecl(varDecl, scope)) {
                case Some(stmt) => out.add(stmt)
                case None => return None
            }
            continue
        }
        if (let Some(returnExpr) <- (node as ParseReturnExpr)) {
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
