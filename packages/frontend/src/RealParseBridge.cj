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
import cangjie_compiler::parse.RefExpr as ParseRefExpr
import cangjie_compiler::parse.LitConstExpr as ParseLitConstExpr
import cangjie_compiler::parse.ReturnExpr as ParseReturnExpr
import cangjie_compiler::parse.LitConstKind as ParseLitConstKind

// Statement-kind tags mirrored by FuncBody.realStmtKind. Kept in sync with the CHIR-side
// AST2CHIRStmtSpec tags in CodeGenBridge.cj.
let REAL_STMT_LET_LITERAL: Int64 = 0
let REAL_STMT_LET_BINARY: Int64 = 1
let REAL_STMT_RETURN: Int64 = 2

// Binary-op tags mirrored by FuncBody.realStmtOp.
let REAL_OP_ADD: Int64 = 0

// First real-expression slice adapter. Runs the real recursive-descent parser over the same
// source the frontend already summarized, and for any function whose body matches the small
// supported grammar (Int64 `let` literals, a single ADD over locals, and a return of a local),
// fills the ordered real-body statement model on the frontend FuncBody and sets hasRealBody.
//
// Only functions that genuinely need runtime computation are promoted: the body must contain at
// least one `let` binding consumed by the returned expression. This deliberately leaves the
// already-verified summary slices (literal returns, let-folded returns, pure-literal arithmetic
// folds, println/print) on their existing path, so they cannot regress. Anything outside the
// grammar simply leaves hasRealBody == false (silent fallback).
public func AdaptRealBodies(file: File, fileID: UInt64, sourceCode: String, sm: SourceManager): Unit {
    let parseDiag = ParseDiagnosticEngine()
    let parser = RealParser(fileID, sourceCode, parseDiag, sm)
    let parsedFile = parser.ParseTopLevel()
    if (parseDiag.HasError()) {
        return
    }
    for (decl in file.decls) {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            tryAdaptFunction(funcDecl, parsedFile)
        }
    }
}

private func tryAdaptFunction(funcDecl: FuncDecl, parsedFile: ParseFile): Unit {
    // Leave print bodies entirely to the summary path.
    if (!funcDecl.funcBody.printStrings.isEmpty()) {
        return
    }
    // Note: a body whose returned expression folds to a literal in the summary path
    // (e.g. `let a=2; let b=3; return a+b`) still arrives here with hasLiteralReturn == true.
    // We only override that fold when the body genuinely needs runtime computation (the returned
    // expression depends on a local binding); see adaptParsedFunc / CommitTo, which clears the
    // stale literal-return summary so the real CHIR body wins. Pure-literal folds such as
    // `return 2 + 3 * 4` use no locals and are therefore never promoted (no regression).
    let name = funcDecl.identifier.Val()
    let matched = findParsedFunc(parsedFile, name, funcDecl.begin.line)
    if (let Some(parsedFunc) <- matched) {
        adaptParsedFunc(funcDecl, parsedFunc)
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

private func adaptParsedFunc(funcDecl: FuncDecl, parsedFunc: ParseFuncDecl): Unit {
    let body = match (parsedFunc.funcBody) {
        case Some(fb) => fb
        case None => return
    }
    let block = match (body.body) {
        case Some(b) => b
        case None => return
    }
    // Build the statement model into a staging collection of parallel arrays. Only commit
    // (and set hasRealBody) if the whole body matches the grammar AND it contains a genuine
    // runtime arithmetic op (an ADD). Bodies the summary path already folds to a single literal
    // -- e.g. `return 42`, `let x = 9; return x`, `return 2 + 3 * 4` -- contain no real ADD here
    // and are therefore left byte-for-byte on their existing literal/fold path (no regression).
    let staging = RealBodyStaging()
    let locals = HashSet<String>()
    var sawReturn = false
    for (node in block.body) {
        if (sawReturn) {
            // Statements after a return are outside this minimal grammar.
            return
        }
        if (let Some(varDecl) <- (node as ParseVarDecl)) {
            if (!adaptVarDecl(varDecl, staging, locals)) {
                return
            }
            continue
        }
        if (let Some(returnExpr) <- (node as ParseReturnExpr)) {
            if (!adaptReturn(returnExpr, staging, locals)) {
                return
            }
            sawReturn = true
            continue
        }
        // Any other statement kind: unsupported -> fall back.
        return
    }
    // Require a real runtime ADD; otherwise leave the summary/literal path untouched.
    if (!sawReturn || !staging.HasBinary()) {
        return
    }
    staging.CommitTo(funcDecl.funcBody)
}

// Returns true when the VarDecl matched the grammar and was staged.
private func adaptVarDecl(varDecl: ParseVarDecl, staging: RealBodyStaging, locals: HashSet<String>): Bool {
    if (varDecl.isVar || varDecl.isConst) {
        return false
    }
    let name = varDecl.identifier.Val()
    if (name.isEmpty()) {
        return false
    }
    let initExpr = match (varDecl.initializer) {
        case Some(e) => e
        case None => return false
    }
    if (let Some(litValue) <- intLiteralValue(initExpr)) {
        staging.AddLetLiteral(name, litValue)
        locals.add(name)
        return true
    }
    if (let Some(binary) <- (initExpr as ParseBinaryExpr)) {
        if (binary.op.kind != TokenKind.ADD) {
            return false
        }
        let lhs = operandOf(binary.leftExpr, locals)
        let rhs = operandOf(binary.rightExpr, locals)
        if (let (Some(l), Some(r)) <- (lhs, rhs)) {
            staging.AddLetBinary(name, REAL_OP_ADD, l, r)
            locals.add(name)
            return true
        }
        return false
    }
    return false
}

// Returns true when the return matched the grammar, false on a grammar miss.
private func adaptReturn(returnExpr: ParseReturnExpr, staging: RealBodyStaging,
    locals: HashSet<String>): Bool {
    let expr = match (returnExpr.expr) {
        case Some(e) => e
        case None => return false
    }
    if (let Some(litValue) <- intLiteralValue(expr)) {
        staging.AddReturnLiteral(litValue)
        return true
    }
    if (let Some(refName) <- localRefName(expr, locals)) {
        staging.AddReturnRef(refName)
        return true
    }
    // `return a + b`: lower the binary into an implicit temp local, then return that local.
    if (let Some(binary) <- (expr as ParseBinaryExpr)) {
        if (binary.op.kind != TokenKind.ADD) {
            return false
        }
        let lhs = operandOf(binary.leftExpr, locals)
        let rhs = operandOf(binary.rightExpr, locals)
        if (let (Some(l), Some(r)) <- (lhs, rhs)) {
            // Only ref+ref ADD is modeled by the CHIR LetBinaryRefRef builder; require locals.
            if (l.isLiteral || r.isLiteral) {
                return false
            }
            let tempName = staging.FreshTempName()
            staging.AddLetBinary(tempName, REAL_OP_ADD, l, r)
            locals.add(tempName)
            staging.AddReturnRef(tempName)
            return true
        }
        return false
    }
    return false
}

// An operand of a binary op: either a reference to a known local or an Int64 literal.
private struct RealOperand {
    let isLiteral: Bool
    let name: String
    let literal: Int64
    init(isLiteral: Bool, name: String, literal: Int64) {
        this.isLiteral = isLiteral
        this.name = name
        this.literal = literal
    }
}

private func operandOf(maybeExpr: Option<ParseExpr>, locals: HashSet<String>): Option<RealOperand> {
    let expr = match (maybeExpr) {
        case Some(e) => e
        case None => return None
    }
    if (let Some(litValue) <- intLiteralValue(expr)) {
        return Some(RealOperand(true, "", litValue))
    }
    if (let Some(refName) <- localRefName(expr, locals)) {
        return Some(RealOperand(false, refName, 0))
    }
    return None
}

private func localRefName(expr: ParseExpr, locals: HashSet<String>): Option<String> {
    if (let Some(refExpr) <- (expr as ParseRefExpr)) {
        let name = refExpr.identifier.Val()
        if (locals.contains(name)) {
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

private func parseIntText(value: String): Option<Int64> {
    let normalized = value.replace("_", "")
    try {
        return Some(Int64.parse(normalized))
    } catch (e: Exception) {
        return None
    }
}

// Stages the ordered statement model so it is committed atomically only when the whole body
// matched the grammar.
private class RealBodyStaging {
    let kinds = ArrayList<Int64>()
    let names = ArrayList<String>()
    let literals = ArrayList<Int64>()
    let ops = ArrayList<Int64>()
    let lhsIsLiteral = ArrayList<Bool>()
    let lhsName = ArrayList<String>()
    let lhsLiteral = ArrayList<Int64>()
    let rhsIsLiteral = ArrayList<Bool>()
    let rhsName = ArrayList<String>()
    let rhsLiteral = ArrayList<Int64>()
    var tempCounter = 0
    var hasBinary = false

    func HasBinary(): Bool { return hasBinary }

    func FreshTempName(): String {
        let name = "$ret${tempCounter}"
        tempCounter++
        return name
    }

    func AddLetLiteral(name: String, value: Int64): Unit {
        kinds.add(REAL_STMT_LET_LITERAL)
        names.add(name)
        literals.add(value)
        ops.add(REAL_OP_ADD)
        lhsIsLiteral.add(true); lhsName.add(""); lhsLiteral.add(0)
        rhsIsLiteral.add(true); rhsName.add(""); rhsLiteral.add(0)
    }

    func AddLetBinary(name: String, op: Int64, lhs: RealOperand, rhs: RealOperand): Unit {
        hasBinary = true
        kinds.add(REAL_STMT_LET_BINARY)
        names.add(name)
        literals.add(0)
        ops.add(op)
        lhsIsLiteral.add(lhs.isLiteral); lhsName.add(lhs.name); lhsLiteral.add(lhs.literal)
        rhsIsLiteral.add(rhs.isLiteral); rhsName.add(rhs.name); rhsLiteral.add(rhs.literal)
    }

    func AddReturnRef(name: String): Unit {
        kinds.add(REAL_STMT_RETURN)
        names.add("")
        literals.add(0)
        ops.add(REAL_OP_ADD)
        lhsIsLiteral.add(false); lhsName.add(name); lhsLiteral.add(0)
        rhsIsLiteral.add(true); rhsName.add(""); rhsLiteral.add(0)
    }

    func AddReturnLiteral(value: Int64): Unit {
        kinds.add(REAL_STMT_RETURN)
        names.add("")
        literals.add(0)
        ops.add(REAL_OP_ADD)
        lhsIsLiteral.add(true); lhsName.add(""); lhsLiteral.add(value)
        rhsIsLiteral.add(true); rhsName.add(""); rhsLiteral.add(0)
    }

    func CommitTo(funcBody: FuncBody): Unit {
        // Clear any stale literal-return summary so the real CHIR body path wins in the bridge.
        funcBody.hasLiteralReturn = false
        funcBody.hasRealBody = true
        funcBody.realStmtKind = kinds
        funcBody.realStmtName = names
        funcBody.realStmtLiteral = literals
        funcBody.realStmtOp = ops
        funcBody.realStmtLhsIsLiteral = lhsIsLiteral
        funcBody.realStmtLhsName = lhsName
        funcBody.realStmtLhsLiteral = lhsLiteral
        funcBody.realStmtRhsIsLiteral = rhsIsLiteral
        funcBody.realStmtRhsName = rhsName
        funcBody.realStmtRhsLiteral = rhsLiteral
    }
}
