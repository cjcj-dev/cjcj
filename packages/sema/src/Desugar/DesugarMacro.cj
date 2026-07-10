package cjcj::sema.Desugar

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.StringConvertor
import cjcj::sema.*
import cjcj::utils.{CLASS_ERROR, CLASS_EXCEPTION, GetMacroFuncName, MACRO_OBJECT_NAME, MC_EXCEPTION}

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

private let UNSAFE_POINTER_CAST: String = "unsafePointerCastFromUint8Array"

// Create the type 'CPointer<UInt8>' as a fresh node (each param/return needs its own instance,
// mirrors the ASTCloner::Clone the C++ CreateCallParam does to avoid sharing type nodes).
private func CreateUInt8PointerType(pos: Position): RefType {
    let args = ArrayList<Type>()
    args.add(PrimitiveType(TypeKind.TYPE_UINT8))
    let ptrType = CreateRefType("CPointer", args)
    ptrType.begin = pos
    ptrType.end = pos
    return ptrType
}

// Create the type 'CPointer<Unit>' as a fresh node.
private func CreateUnitPointerType(pos: Position): RefType {
    let args = ArrayList<Type>()
    args.add(PrimitiveType(TypeKind.TYPE_UNIT))
    let ptrType = CreateRefType("CPointer", args)
    ptrType.begin = pos
    ptrType.end = pos
    return ptrType
}

// Create var decl, like : let bufParam: Array<UInt8> = Array<UInt8>(paramSize, repeat: 0).
private func CreateReadingVarDecl(newPos: Position, declName: String, argSize: String): VarDecl {
    let arrElemType = ArrayList<Type>()
    arrElemType.add(PrimitiveType(TypeKind.TYPE_UINT8))
    let arrType = CreateRefType("Array", arrElemType)
    arrType.EnableAttr(Attribute.IN_CORE)
    let baseTypeArgs = ArrayList<Type>()
    baseTypeArgs.add(PrimitiveType(TypeKind.TYPE_UINT8))
    let baseF = CreateRefExpr(SrcIdentifier("Array"), None, newPos, baseTypeArgs)
    baseF.EnableAttr(Attribute.IN_CORE)
    let funcVector = ArrayList<FuncArg>()
    funcVector.add(CreateFuncArg(CreateRefExpr(argSize)))
    let litConst = CreateLitConstExpr(LitConstKind.INTEGER, "0", Ty.GetInitialTy())
    funcVector.add(CreateFuncArg(litConst, "repeat"))
    let callExpr = CreateCallExpr(baseF, funcVector)
    return CreateVarDecl(declName, callExpr, arrType)
}

// Create forIn expression, like : for (i in 0..argSize) { declName[i] = unsafe { argPtr.read(i) } }.
private func CreateReadingForInExpr(declName: String, argPtr: String, argSize: String): ForInExpr {
    let varPattern = CreateVarPattern("i")
    let start = CreateLitConstExpr(LitConstKind.INTEGER, "0", Ty.GetInitialTy())
    let end = CreateRefExpr(argSize)
    let rangeExpr = RangeExpr()
    rangeExpr.startExpr = start
    rangeExpr.stopExpr = end
    rangeExpr.isClosed = false
    rangeExpr.EnableAttr(Attribute.COMPILER_ADD)

    let callBase = CreateMemberAccess(CreateRefExpr(declName), "[]")
    let funcArg1 = CreateFuncArg(CreateRefExpr("i"))

    let readCallBase = CreateMemberAccess(CreateRefExpr(argPtr), "read")
    let readVector = ArrayList<FuncArg>()
    readVector.add(CreateFuncArg(CreateRefExpr("i")))
    let readCall = CreateCallExpr(readCallBase, readVector)
    readCall.EnableAttr(Attribute.UNSAFE)

    let funcVector = ArrayList<FuncArg>()
    funcVector.add(funcArg1)
    funcVector.add(CreateFuncArg(readCall, "value"))
    let callExpr = CreateCallExpr(callBase, funcVector)
    let nodes = ArrayList<Node>()
    nodes.add(callExpr)
    let forInBody = CreateBlock(nodes)
    return CreateForInExpr(varPattern, rangeExpr, forInBody)
}

// Create var decl, like : let argName: Tokens = Tokens().
private func CreateTokensParamDecl(argName: String, pos: Position): VarDecl {
    let refExpr = CreateRefExprInAST(OPTION_TOKENS)
    refExpr.begin = pos
    refExpr.end = pos
    let tokensCall = CreateCallExpr(refExpr, ArrayList<FuncArg>())
    return CreateVarDecl(argName, tokensCall, None)
}

// Create assign expr, like : argName = argName + refreshPos(Token(TokenKind.ILLEGAL), fileID, line, column).
private func CreateIllegalTokensDecl(argName: String, pos: Position): AssignExpr {
    let tokenKind = CreateRefExprInAST("TokenKind")
    let tok = CreateFuncArg(CreateMemberAccess(tokenKind, "ILLEGAL"))
    tok.begin = pos
    tok.end = pos
    let tokensAttrArgs = ArrayList<FuncArg>()
    tokensAttrArgs.add(tok)

    let uint32Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT32)
    let int32Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT32)
    let fileID = CreateFuncArg(CreateLitConstExpr(LitConstKind.INTEGER, "${pos.fileID}", uint32Ty))
    let line = CreateFuncArg(CreateLitConstExpr(LitConstKind.INTEGER, "${pos.line}", int32Ty))
    let column = CreateFuncArg(CreateLitConstExpr(LitConstKind.INTEGER, "${pos.column}", int32Ty))
    let tokenRef = CreateRefExprInAST(TOKEN_TYPE_NAME)
    tokenRef.begin = pos
    tokenRef.end = pos
    let tokenCall = CreateCallExpr(tokenRef, tokensAttrArgs)
    let arguments = ArrayList<FuncArg>()
    arguments.add(CreateFuncArg(tokenCall))
    arguments.add(fileID)
    arguments.add(line)
    arguments.add(column)
    let refreshExpr = CreateRefExprInAST(REFRESH_POS)
    refreshExpr.begin = pos
    refreshExpr.end = pos
    let callExpr = CreateCallExpr(refreshExpr, arguments)
    let binExpr = CreateBinaryExpr(CreateRefExpr(argName), callExpr, TokenKind.ADD)
    return CreateAssignExpr(CreateRefExpr(argName), binExpr)
}

// Create attribute macro call, like : ident(attr, params).
private func CreateAttrCall(ident: String, pos: Position): CallExpr {
    let retAttrArgs = ArrayList<FuncArg>()
    retAttrArgs.add(CreateFuncArg(CreateRefExpr("attr", pos)))
    retAttrArgs.add(CreateFuncArg(CreateRefExpr("params", pos)))
    return CreateCallExpr(CreateRefExpr(ident, pos), retAttrArgs)
}

// Create common macro call, like : ident(params).
private func CreateCommonCall(ident: String, pos: Position): CallExpr {
    let retCommonArgs = ArrayList<FuncArg>()
    retCommonArgs.add(CreateFuncArg(CreateRefExpr("params", pos)))
    return CreateCallExpr(CreateRefExpr(ident, pos), retCommonArgs)
}

// Create var decl, like : let tBuffer = refName.toBytes().
private func CreateToBytesVar(refName: String, pos: Position): VarDecl {
    let toBytesCall = CreateCallExpr(CreateMemberAccess(CreateRefExpr(refName, pos), "toBytes"), ArrayList<FuncArg>())
    return CreateVarDecl("tBuffer", toBytesCall, None)
}

// Create return expression, like : return unsafePointerCastFromUint8Array(tBuffer).
private func CreateReturnExpr(pos: Position): CallExpr {
    let retExprArgs = ArrayList<FuncArg>()
    retExprArgs.add(CreateFuncArg(CreateRefExpr("tBuffer", pos)))
    let baseExpr = CreateRefExprInAST(UNSAFE_POINTER_CAST)
    baseExpr.begin = pos
    baseExpr.end = pos
    return CreateCallExpr(baseExpr, retExprArgs)
}

// Create catch block, like : { [e.printStackTrace()] var tokVar = Tokens(); tokVar = tokVar + Token(ILLEGAL);
//     let tBuffer = tokVar.toBytes(); return unsafePointerCastFromUint8Array(tBuffer) }.
private func CreateCatchBlock(tryExpr: TryExpr, pos: Position, printStack: Bool): Unit {
    let nodes = ArrayList<Node>()
    if (printStack) {
        nodes.add(CreateCallExpr(CreateMemberAccess(CreateRefExpr("e"), "printStackTrace"), ArrayList<FuncArg>()))
    }
    let tokVar = CreateTokensParamDecl("tokVar", pos)
    tokVar.isVar = true
    nodes.add(tokVar)
    nodes.add(CreateIllegalTokensDecl("tokVar", pos))
    nodes.add(CreateToBytesVar("tokVar", pos))
    nodes.add(CreateReturnExpr(pos))
    tryExpr.catchPosVector.add(INVALID_POSITION)
    tryExpr.catchBlocks.add(CreateBlock(nodes))
}

// Create ExceptTypePattern, like : 'catch (e: Exception)' or 'catch (e: MacroContextException)'.
private func CreateCatchPattern(tryExpr: TryExpr, exceptionTypeStr: String): Unit {
    let exceptTypePattern = ExceptTypePattern()
    let varPattern = VarPattern()
    let eDecl = CreateVarDecl("e")
    varPattern.varDecl = eDecl
    eDecl.parentPattern = varPattern

    let exceptionType = if (exceptionTypeStr == CLASS_EXCEPTION) {
        CreateRefTypeInCore(CLASS_EXCEPTION)
    } else if (exceptionTypeStr == CLASS_ERROR) {
        CreateRefTypeInCore(CLASS_ERROR)
    } else {
        let ty = CreateRefType(exceptionTypeStr)
        ty.EnableAttr(Attribute.IN_MACRO)
        ty
    }
    let tryBlockBegin = tryExpr.tryBlock.getOrThrow().begin
    exceptionType.begin = tryBlockBegin
    exceptionType.end = tryBlockBegin
    exceptionType.EnableAttr(Attribute.COMPILER_ADD)
    exceptTypePattern.types.add(exceptionType)
    exceptTypePattern.pattern = varPattern
    tryExpr.catchPatterns.add(exceptTypePattern)
}

// Create thread_local assign expr, like : MACRO_OBJECT.set(refName).
private func CreateTLAssignExpr(refName: String, newPos: Position): Expr {
    let baseRef = CreateRefExpr(MACRO_OBJECT_NAME)
    baseRef.EnableAttr(Attribute.IN_MACRO)
    baseRef.begin = newPos
    baseRef.end = newPos
    let tlBase = CreateMemberAccess(baseRef, "set")
    let funcArgVector = ArrayList<FuncArg>()
    funcArgVector.add(CreateFuncArg(CreateRefExpr(refName)))
    let assignCall = CreateCallExpr(tlBase, funcArgVector)
    assignCall.EnableAttr(Attribute.COMPILER_ADD)
    assignCall.begin = newPos
    assignCall.end = newPos
    return assignCall
}

// Create finally block, like : { MACRO_OBJECT.set(None) }.
private func CreateFinallyBlock(tryExpr: TryExpr, pos: Position): Unit {
    let nodes = ArrayList<Node>()
    nodes.add(CreateTLAssignExpr("None", pos))
    tryExpr.finallyBlock = CreateBlock(nodes)
}

// Create try expression: try { ... } catch (e: MacroContextException) { ... } catch (e: Exception) { ... }
// catch (e: Error) { ... } finally { MACRO_OBJECT.set(None) }.
private func CreateWrapperTryExpr(tryBlock: Block): TryExpr {
    let tryExpr = TryExpr()
    tryExpr.tryBlock = tryBlock
    CreateCatchPattern(tryExpr, MC_EXCEPTION)
    CreateCatchBlock(tryExpr, tryBlock.begin, false)
    CreateCatchPattern(tryExpr, CLASS_EXCEPTION)
    CreateCatchBlock(tryExpr, tryBlock.begin, true)
    // For oom, catch error is required because oom inherits from error rather than exception.
    CreateCatchPattern(tryExpr, CLASS_ERROR)
    CreateCatchBlock(tryExpr, tryBlock.begin, true)
    CreateFinallyBlock(tryExpr, tryBlock.begin)
    return tryExpr
}

// Create if expression, like : if (argSize > 0) { argName = Tokens(argBuf) }.
private func CreateWrapperIfExpr(argName: String, argBuf: String, argSize: String, pos: Position): IfExpr {
    let argSizeExpr = CreateRefExpr(argSize)
    let litConst = CreateLitConstExpr(LitConstKind.INTEGER, "0", Ty.GetInitialTy())
    let cond = CreateBinaryExpr(argSizeExpr, litConst, TokenKind.GT)

    let thenExprBlock = Block()
    let tokensAttrArgs = ArrayList<FuncArg>()
    tokensAttrArgs.add(CreateFuncArg(CreateRefExpr(argBuf)))
    let refExpr = CreateRefExprInAST(OPTION_TOKENS)
    refExpr.begin = pos
    refExpr.end = pos
    let callExpr = CreateCallExpr(refExpr, tokensAttrArgs)
    let assignExpr = CreateAssignExpr(CreateRefExpr(argName), callExpr)
    thenExprBlock.body.add(assignExpr)

    let elseExprBlock = Block()
    let ifExpr = CreateIfExpr(cond, thenExprBlock, elseExprBlock, None)
    ifExpr.hasElse = false
    ifExpr.EnableAttr(Attribute.COMPILER_ADD)
    return ifExpr
}

// Create the try-block body of the macro wrapper (deserialize the token buffers, invoke the macro, serialize).
private func CreateWrapperTryBlock(pos: Position, ident: String, isAttr: Bool): Block {
    // Pos after 'pos' to lookup field.
    let newPos = pos + BEGIN_POSITION
    let tlAssignCall = CreateTLAssignExpr("callMacroCallPtr", newPos)
    let bufAttrVar = CreateReadingVarDecl(newPos, "bufAttr", "attrSize")
    let bufAttrForIn = CreateReadingForInExpr("bufAttr", "attrPtr", "attrSize")
    let bufParamVar = CreateReadingVarDecl(newPos, "bufParam", "paramSize")
    let bufParamForIn = CreateReadingForInExpr("bufParam", "paramPtr", "paramSize")

    let attrVar = CreateTokensParamDecl("attr", pos)
    attrVar.isVar = true
    let attrIfExpr = CreateWrapperIfExpr("attr", "bufAttr", "attrSize", pos)
    let paramsVar = CreateTokensParamDecl("params", pos)
    paramsVar.isVar = true
    let argsIfExpr = CreateWrapperIfExpr("params", "bufParam", "paramSize", pos)

    let callExpr = if (isAttr) {
        CreateAttrCall(ident, newPos)
    } else {
        CreateCommonCall(ident, newPos)
    }
    if (let Some(baseFunc) <- callExpr.baseFunc) {
        baseFunc.EnableAttr(Attribute.MACRO_INVOKE_BODY)
    }
    callExpr.EnableAttr(Attribute.MACRO_INVOKE_BODY)
    let retVar = CreateVarDecl("ret", callExpr, None)
    retVar.isVar = true
    let tBufferVar = CreateToBytesVar("ret", newPos)
    let retExpr = CreateReturnExpr(newPos)

    let nodes = ArrayList<Node>()
    nodes.add(tlAssignCall)
    if (isAttr) {
        nodes.add(bufAttrVar)
        nodes.add(bufAttrForIn)
        nodes.add(attrVar)
        nodes.add(attrIfExpr)
    }
    nodes.add(bufParamVar)
    nodes.add(bufParamForIn)
    nodes.add(paramsVar)
    nodes.add(argsIfExpr)
    nodes.add(retVar)
    nodes.add(tBufferVar)
    nodes.add(retExpr)
    return CreateBlock(nodes)
}

// Create the wrapper function:
// external func macroCall_a_ident(attrPtr: CPointer<UInt8>, attrSize: Int64, paramPtr: CPointer<UInt8>,
//     paramSize: Int64, callMacroCallPtr: CPointer<Unit>): CPointer<UInt8>.
private func CreateWrapperFuncDecl(funcName: String, pos: Position, body: Block, params: ArrayList<FuncParam>,
    retType: RefType): FuncDecl {
    let paramList = CreateFuncParamList(params)
    let funcParamLists = ArrayList<FuncParamList>()
    funcParamLists.add(paramList)
    let funcBody = CreateFuncBody(funcParamLists, retType, body, None)
    funcBody.EnableAttr(Attribute.C)
    funcBody.EnableAttr(Attribute.MACRO_INVOKE_BODY)
    funcBody.EnableAttr(Attribute.PUBLIC)
    let funcDecl = CreateFuncDecl(funcName, funcBody, None)
    funcDecl.toBeCompiled = true // For incremental compilation.
    funcDecl.identifier.SetPos(pos, pos)
    funcDecl.begin = pos
    funcDecl.end = pos
    funcDecl.modifiers.add(Modifier(TokenKind.PUBLIC, pos))
    funcDecl.EnableAttr(Attribute.NO_MANGLE)
    funcDecl.EnableAttr(Attribute.C)
    funcDecl.EnableAttr(Attribute.MACRO_INVOKE_FUNC)
    funcDecl.EnableAttr(Attribute.PUBLIC)
    return funcDecl
}

// Synthesize and append the macroCall_c_<ident>/macroCall_a_<ident> C-ABI wrapper function that the
// compiler dlsyms to invoke a compiled macro. Mirrors C++ DesugarMacro.cpp AddMacroFuncDecl.
private func AddMacroFuncDecl(curFile: File, pos: Position, ident: String, isAttr: Bool): Unit {
    let tryBlock = CreateWrapperTryBlock(pos, ident, isAttr)
    tryBlock.begin = pos
    tryBlock.end = pos
    let tryExpr = CreateWrapperTryExpr(tryBlock)
    tryExpr.EnableAttr(Attribute.MACRO_INVOKE_BODY)
    let body = Block()
    body.begin = pos
    body.end = pos
    body.body.add(tryExpr)

    // Create params: (attrPtr: CPointer<UInt8>, attrSize: Int64, paramPtr: CPointer<UInt8>,
    //     paramSize: Int64, callMacroCallPtr: CPointer<Unit>). Non-attr macros drop the first two.
    let attrPtrParam = CreateFuncParam("attrPtr", CreateUInt8PointerType(pos), None, None)
    attrPtrParam.begin = pos
    attrPtrParam.end = pos
    let attrSizeParam = CreateFuncParam("attrSize", PrimitiveType(TypeKind.TYPE_INT64), None, None)
    attrSizeParam.begin = pos
    attrSizeParam.end = pos
    let paramPtrParam = CreateFuncParam("paramPtr", CreateUInt8PointerType(pos), None, None)
    paramPtrParam.begin = pos
    paramPtrParam.end = pos
    let paramSizeParam = CreateFuncParam("paramSize", PrimitiveType(TypeKind.TYPE_INT64), None, None)
    paramSizeParam.begin = pos
    paramSizeParam.end = pos
    let callMacroCallPtr = CreateFuncParam("callMacroCallPtr", CreateUnitPointerType(pos), None, None)

    let params = ArrayList<FuncParam>()
    if (isAttr) {
        params.add(attrPtrParam)
        params.add(attrSizeParam)
    }
    params.add(paramPtrParam)
    params.add(paramSizeParam)
    params.add(callMacroCallPtr)

    var packageName = ""
    if (let Some(pkg) <- curFile.curPackage) {
        packageName = pkg.fullPackageName
    }
    let funcName = GetMacroFuncName(packageName, isAttr, ident)
    let funcDecl = CreateWrapperFuncDecl(funcName, pos, body, params, CreateUInt8PointerType(pos))
    funcDecl.EnableAttr(Attribute.GLOBAL)
    curFile.decls.add(funcDecl)
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
    var isAttr = false
    if (let Some(body) <- macroDecl.funcBody) {
        funcDecl.funcBody = body
        body.funcDecl = funcDecl
        funcDecl.end = body.end
        // The attr macro has 2 params (attr, input); the common macro has 1 (input).
        if (!body.paramLists.isEmpty()) {
            isAttr = body.paramLists[0].params.size == 2
        }
        macroDecl.funcBody = None
    }
    macroDecl.desugarDecl = funcDecl
    AddMacroFuncDecl(file, macroDecl.end, macroDecl.identifier.Val(), isAttr)
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
