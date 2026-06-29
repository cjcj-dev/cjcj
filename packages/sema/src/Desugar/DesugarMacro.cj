package cangjie_compiler::sema.Desugar

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::basic.StringConvertor
import cangjie_compiler::sema.*

private let OPTION_TOKENS: String = "Tokens"
private let TRANSFORM_TOKENS: String = "transformTokens"
private let REFRESH_POS: String = "refreshPos"
private let REFRESH_TOKENS_POSITION: String = "refreshTokensPosition"
private let TOKEN_TYPE_NAME: String = "Token"
private let TO_TOKENS: String = "toTokens"
private let CONCAT: String = "concat"

private func AppendUInt16(out: ArrayList<UInt8>, value: UInt16): Unit {
    out.add(UInt8(UInt64(value) & 0xff))
    out.add(UInt8((UInt64(value) >> 8) & 0xff))
}

private func AppendUInt32(out: ArrayList<UInt8>, value: UInt32): Unit {
    out.add(UInt8(UInt64(value) & 0xff))
    out.add(UInt8((UInt64(value) >> 8) & 0xff))
    out.add(UInt8((UInt64(value) >> 16) & 0xff))
    out.add(UInt8((UInt64(value) >> 24) & 0xff))
}

private func AppendInt32(out: ArrayList<UInt8>, value: Int64): Unit {
    AppendUInt32(out, UInt32(value))
}

private func IsEscapedTokenKind(kind: TokenKind): Bool {
    return kind == TokenKind.STRING_LITERAL || kind == TokenKind.JSTRING_LITERAL ||
        kind == TokenKind.RUNE_LITERAL || kind == TokenKind.MULTILINE_STRING ||
        kind == TokenKind.MULTILINE_RAW_STRING
}

private func NormalizeQuoteTokens(tokens: ArrayList<Token>): Unit {
    var idx: Int64 = 0
    while (idx < tokens.size) {
        var token = tokens[idx]
        if (token.kind == TokenKind.MULTILINE_RAW_STRING) {
            token.SetValue(StringConvertor.Normalize(token.Value(), isRawString: true))
            tokens[idx] = token
        }
        idx++
    }
}

private func SerializeQuoteTokens(tokens: ArrayList<Token>): ArrayList<UInt8> {
    NormalizeQuoteTokens(tokens)
    let out = ArrayList<UInt8>()
    if (tokens.isEmpty()) {
        return out
    }
    AppendUInt32(out, UInt32(tokens.size))
    for (token in tokens) {
        AppendUInt16(out, UInt16(TokenKindIndex(token.kind)))
        let valueBytes = token.Value().toArray()
        AppendUInt32(out, UInt32(valueBytes.size))
        for (byte in valueBytes) {
            out.add(byte)
        }
        let begin = token.Begin()
        AppendUInt32(out, UInt32(begin.fileID))
        AppendInt32(out, begin.line)
        var column = begin.column
        if (IsEscapedTokenKind(token.kind) && column + 1 + token.Value().size == token.End().column) {
            column++
        }
        AppendInt32(out, column)
        AppendUInt16(out, if (token.isSingleQuote) { 1u16 } else { 0u16 })
        if (token.kind == TokenKind.MULTILINE_RAW_STRING) {
            AppendUInt16(out, UInt16(token.delimiterNum))
        }
    }
    return out
}

private func DesugarTokensToArrayLiteral(tokens: ArrayList<Token>): ArrayLit {
    let buffers = SerializeQuoteTokens(tokens)
    let elements = ArrayList<Expr>()
    for (byte in buffers) {
        elements.add(CreateLitConstExpr(LitConstKind.INTEGER, "${byte}", Ty.GetInitialTy()))
    }
    return CreateArrayLit(elements, Ty.GetInitialTy())
}

private func CreateQuoteDesugarExpr(qexpr: QuoteExpr): Expr {
    let tokensRef = CreateRefExprInAST(OPTION_TOKENS)
    tokensRef.begin = qexpr.begin
    tokensRef.end = qexpr.end
    let tokensExpr = CreateCallExpr(tokensRef, ArrayList<FuncArg>())
    tokensExpr.EnableAttr(Attribute.COMPILER_ADD)
    tokensExpr.begin = qexpr.begin
    tokensExpr.end = qexpr.end
    return tokensExpr
}

private func CloneExpr(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

private func CreateRefreshPosCall(callExpr: CallExpr): Option<Expr> {
    if (let Some(clonedCall) <- CloneExpr(callExpr)) {
        let uint32Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT32)
        let int32Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT32)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(clonedCall))
        args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.INTEGER, "${callExpr.begin.fileID}", uint32Ty)))
        args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.INTEGER, "${callExpr.begin.line}", int32Ty)))
        args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.INTEGER, "${callExpr.begin.column}", int32Ty)))
        let refreshExpr = CreateRefExprInAST(REFRESH_POS)
        refreshExpr.begin = callExpr.begin
        refreshExpr.end = callExpr.end
        return CreateCallExpr(refreshExpr, args)
    }
    return None
}

public func CreateToTokensMethod(expr: Expr): MemberAccess {
    let walker = Walker(expr, visitPre: { node: Node =>
        if (let Some(callExpr) <- (node as CallExpr)) {
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                if (let Some(refExpr) <- (baseFunc as RefExpr)) {
                    if (refExpr.ref.identifier.Val() == TOKEN_TYPE_NAME) {
                        if (let Some(refreshCall) <- CreateRefreshPosCall(callExpr)) {
                            callExpr.desugarExpr = refreshCall
                            return VisitAction.SKIP_CHILDREN
                        }
                    }
                }
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    if (let Some(desugarExpr) <- expr.desugarExpr) {
        return CreateMemberAccess(desugarExpr, TO_TOKENS)
    }
    if (let Some(cloned) <- CloneExpr(expr)) {
        cloned.EnableAttr(Attribute.IS_CLONED_SOURCE_CODE)
        return CreateMemberAccess(cloned, TO_TOKENS)
    }
    return CreateMemberAccess(expr, TO_TOKENS)
}

private func CreateTokensCallFromTokenPart(tokenPart: TokenPart): Expr {
    let arrayLit = DesugarTokensToArrayLiteral(tokenPart.tokens)
    CopyBasicInfo(tokenPart, arrayLit)
    let args = ArrayList<FuncArg>()
    args.add(CreateFuncArg(arrayLit))
    let tokensRef = CreateRefExprInAST(OPTION_TOKENS)
    tokensRef.begin = tokenPart.begin
    tokensRef.end = tokenPart.end
    let tokensCall = CreateCallExpr(tokensRef, args)
    let refreshArgs = ArrayList<FuncArg>()
    refreshArgs.add(CreateFuncArg(tokensCall))
    let refreshExpr = CreateRefExprInAST(REFRESH_TOKENS_POSITION)
    refreshExpr.begin = tokenPart.begin
    refreshExpr.end = tokenPart.end
    return CreateCallExpr(refreshExpr, refreshArgs)
}

private func CreateTransformTokensExpr(expr: Expr, tokensExpr: Expr): Expr {
    let transformRef = CreateRefExprInAST(TRANSFORM_TOKENS)
    transformRef.begin = expr.begin
    transformRef.end = expr.end
    let args = ArrayList<FuncArg>()
    if (let Some(clonedExpr) <- CloneExpr(expr)) {
        clonedExpr.EnableAttr(Attribute.IS_CLONED_SOURCE_CODE)
        args.add(CreateFuncArg(clonedExpr))
    } else {
        args.add(CreateFuncArg(expr))
    }
    args.add(CreateFuncArg(tokensExpr))
    let transform = CreateCallExpr(transformRef, args)
    transform.EnableAttr(Attribute.COMPILER_ADD)
    return transform
}

private func ConcatQuoteTokens(existing: Expr, next: Expr): Expr {
    let base = if (let Some(cloned) <- CloneExpr(existing)) {
        cloned
    } else {
        existing
    }
    let concatAccess = CreateMemberAccess(base, CONCAT)
    concatAccess.begin = next.begin
    concatAccess.end = next.end
    let args = ArrayList<FuncArg>()
    args.add(CreateFuncArg(next))
    let callExpr = CreateCallExpr(concatAccess, args)
    callExpr.EnableAttr(Attribute.COMPILER_ADD)
    return callExpr
}

private func BuildQuotePartExpr(expr: Expr): Option<Expr> {
    if (let Some(tokenPart) <- (expr as TokenPart)) {
        return CreateTokensCallFromTokenPart(tokenPart)
    }
    if (let Some(quoteExpr) <- (expr as QuoteExpr)) {
        DesugarQuoteExpr(quoteExpr)
        return quoteExpr.desugarExpr
    }
    let memberAccess = CreateToTokensMethod(expr)
    let callExpr = CreateCallExpr(memberAccess, ArrayList<FuncArg>())
    callExpr.needCheckToTokens = true
    return callExpr
}

public func DesugarQuoteExpr(qe: QuoteExpr): Unit {
    if (qe.exprs.isEmpty()) {
        qe.desugarExpr = CreateQuoteDesugarExpr(qe)
    }
    for (expr in qe.exprs) {
        if (let Some(tokensExpr) <- BuildQuotePartExpr(expr)) {
            tokensExpr.EnableAttr(Attribute.COMPILER_ADD)
            CopyBasicInfo(expr, tokensExpr)
            if (let Some(existing) <- qe.desugarExpr) {
                qe.desugarExpr = ConcatQuoteTokens(existing, tokensExpr)
            } else if (expr.astKind == ASTKind.QUOTE_EXPR || expr.astKind == ASTKind.TOKEN_PART) {
                qe.desugarExpr = tokensExpr
            } else {
                qe.desugarExpr = CreateTransformTokensExpr(expr, tokensExpr)
            }
            if (let Some(desugarExpr) <- qe.desugarExpr) {
                desugarExpr.EnableAttr(Attribute.COMPILER_ADD)
            }
        }
    }
    if (let Some(desugarExpr) <- qe.desugarExpr) {
        AddCurFile(desugarExpr, file: qe.curFile)
    }
}

private func CloneModifier(modifier: Modifier): Option<Modifier> {
    return ASTCloner.Clone(modifier) as Modifier
}

private func CloneAnnotation(annotation: Annotation): Option<Annotation> {
    return ASTCloner.Clone(annotation) as Annotation
}

private func DesugarSingleMacroDecl(file: File, macroDecl: MacroDecl): Unit {
    if (macroDecl.TestAttr(Attribute.HAS_BROKEN) || macroDecl.desugarDecl.isSome()) {
        return
    }
    let funcDecl = FuncDecl()
    CopyBasicInfo(macroDecl, funcDecl)
    funcDecl.curFile = macroDecl.curFile
    if (let Some(pkg) <- file.curPackage) {
        funcDecl.fullPackageName = pkg.fullPackageName
    }
    funcDecl.begin = macroDecl.begin
    funcDecl.end = macroDecl.end
    funcDecl.keywordPos = macroDecl.keywordPos
    funcDecl.identifier = macroDecl.identifier
    funcDecl.CloneAttrs(macroDecl)
    funcDecl.rawMangleName = macroDecl.rawMangleName
    funcDecl.toBeCompiled = macroDecl.toBeCompiled
    for (modifier in macroDecl.modifiers) {
        if (let Some(clonedModifier) <- CloneModifier(modifier)) {
            funcDecl.modifiers.add(clonedModifier)
        }
    }
    for (annotation in macroDecl.annotations) {
        if (annotation.kind == AstAnnotationKind.DEPRECATED) {
            if (let Some(clonedAnnotation) <- CloneAnnotation(annotation)) {
                funcDecl.annotations.add(clonedAnnotation)
            }
        }
    }
    if (let Some(body) <- macroDecl.funcBody) {
        funcDecl.funcBody = body
        body.funcDecl = funcDecl
        funcDecl.end = body.end
        macroDecl.funcBody = None
    }
    macroDecl.desugarDecl = funcDecl
}

public func DesugarMacroDecl(file: File): Unit {
    let originalSize = file.decls.size
    var idx: Int64 = 0
    while (idx < originalSize) {
        if (let Some(macroDecl) <- (file.decls[idx] as MacroDecl)) {
            DesugarSingleMacroDecl(file, macroDecl)
        }
        idx++
    }
}
