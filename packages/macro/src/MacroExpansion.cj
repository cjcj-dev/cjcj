package cangjie_compiler::macro_pkg

import std.collection.*
import std.sort.*
import cangjie_compiler::ast.AnnotationKind as RealAnnotationKind
import cangjie_compiler::parse.Annotation as ParsedAnnotation
import cangjie_compiler::parse.ArrayExpr as ParsedArrayExpr
import cangjie_compiler::parse.ArrayLit as ParsedArrayLit
import cangjie_compiler::parse.AsExpr as ParsedAsExpr
import cangjie_compiler::parse.BinaryExpr as ParsedBinaryExpr
import cangjie_compiler::parse.Block as ParsedBlock
import cangjie_compiler::parse.CallExpr as ParsedCallExpr
import cangjie_compiler::parse.ClassDecl as ParsedClassDecl
import cangjie_compiler::parse.CommandTypePattern as ParsedCommandTypePattern
import cangjie_compiler::parse.ConstPattern as ParsedConstPattern
import cangjie_compiler::parse.Decl as ParsedDecl
import cangjie_compiler::parse.DiagSeverity as ParsedDiagSeverity
import cangjie_compiler::parse.DiagnosticEngine as ParsedDiagnosticEngine
import cangjie_compiler::parse.Expr as ParsedExpr
import cangjie_compiler::parse.ExprKind as ParsedExprKind
import cangjie_compiler::parse.EnumDecl as ParsedEnumDecl
import cangjie_compiler::parse.EnumPattern as ParsedEnumPattern
import cangjie_compiler::parse.ExceptTypePattern as ParsedExceptTypePattern
import cangjie_compiler::parse.ExtendDecl as ParsedExtendDecl
import cangjie_compiler::parse.DoWhileExpr as ParsedDoWhileExpr
import cangjie_compiler::parse.ForInExpr as ParsedForInExpr
import cangjie_compiler::parse.FuncArg as ParsedFuncArg
import cangjie_compiler::parse.FuncBody as ParsedFuncBody
import cangjie_compiler::parse.FuncDecl as ParsedFuncDecl
import cangjie_compiler::parse.FuncParam as ParsedFuncParam
import cangjie_compiler::parse.FuncParamList as ParsedFuncParamList
import cangjie_compiler::parse.IfExpr as ParsedIfExpr
import cangjie_compiler::parse.IncOrDecExpr as ParsedIncOrDecExpr
import cangjie_compiler::parse.InterpolationExpr as ParsedInterpolationExpr
import cangjie_compiler::parse.IsExpr as ParsedIsExpr
import cangjie_compiler::parse.JumpExpr as ParsedJumpExpr
import cangjie_compiler::parse.LambdaExpr as ParsedLambdaExpr
import cangjie_compiler::parse.LetPatternDestructor as ParsedLetPatternDestructor
import cangjie_compiler::parse.InterfaceDecl as ParsedInterfaceDecl
import cangjie_compiler::parse.LitConstExpr as ParsedLitConstExpr
import cangjie_compiler::parse.MacroDecl as ParsedMacroDecl
import cangjie_compiler::parse.MacroExpandDecl as ParsedMacroExpandDecl
import cangjie_compiler::parse.MacroExpandExpr as ParsedMacroExpandExpr
import cangjie_compiler::parse.MacroInvocation as ParsedMacroInvocation
import cangjie_compiler::parse.MatchCase as ParsedMatchCase
import cangjie_compiler::parse.MatchCaseOther as ParsedMatchCaseOther
import cangjie_compiler::parse.MatchExpr as ParsedMatchExpr
import cangjie_compiler::parse.MemberAccess as ParsedMemberAccess
import cangjie_compiler::parse.Modifier as ParsedModifier
import cangjie_compiler::parse.Node as ParsedNode
import cangjie_compiler::parse.OptionalChainExpr as ParsedOptionalChainExpr
import cangjie_compiler::parse.OptionalExpr as ParsedOptionalExpr
import cangjie_compiler::parse.ParenExpr as ParsedParenExpr
import cangjie_compiler::parse.Parser as GeneratedParser
import cangjie_compiler::parse.Pattern as ParsedPattern
import cangjie_compiler::parse.PerformExpr as ParsedPerformExpr
import cangjie_compiler::parse.PrimitiveType as ParsedPrimitiveType
import cangjie_compiler::parse.PrimitiveTypeExpr as ParsedPrimitiveTypeExpr
import cangjie_compiler::parse.QuoteExpr as ParsedQuoteExpr
import cangjie_compiler::parse.RangeExpr as ParsedRangeExpr
import cangjie_compiler::parse.RefExpr as ParsedRefExpr
import cangjie_compiler::parse.RefType as ParsedRefType
import cangjie_compiler::parse.ResumeExpr as ParsedResumeExpr
import cangjie_compiler::parse.ReturnExpr as ParsedReturnExpr
import cangjie_compiler::parse.ScopeKind as ParsedScopeKind
import cangjie_compiler::parse.SpawnExpr as ParsedSpawnExpr
import cangjie_compiler::parse.StrInterpolationExpr as ParsedStrInterpolationExpr
import cangjie_compiler::parse.StructDecl as ParsedStructDecl
import cangjie_compiler::parse.SubscriptExpr as ParsedSubscriptExpr
import cangjie_compiler::parse.SynchronizedExpr as ParsedSynchronizedExpr
import cangjie_compiler::parse.ThrowExpr as ParsedThrowExpr
import cangjie_compiler::parse.TokenPart as ParsedTokenPart
import cangjie_compiler::parse.TrailingClosureExpr as ParsedTrailingClosureExpr
import cangjie_compiler::parse.TryExpr as ParsedTryExpr
import cangjie_compiler::parse.TupleLit as ParsedTupleLit
import cangjie_compiler::parse.Type as ParsedType
import cangjie_compiler::parse.TypeConvExpr as ParsedTypeConvExpr
import cangjie_compiler::parse.TuplePattern as ParsedTuplePattern
import cangjie_compiler::parse.TypePattern as ParsedTypePattern
import cangjie_compiler::parse.UnaryExpr as ParsedUnaryExpr
import cangjie_compiler::parse.VarDecl as ParsedVarDecl
import cangjie_compiler::parse.VarOrEnumPattern as ParsedVarOrEnumPattern
import cangjie_compiler::parse.VarPattern as ParsedVarPattern
import cangjie_compiler::parse.VarWithPatternDecl as ParsedVarWithPatternDecl
import cangjie_compiler::parse.WildcardExpr as ParsedWildcardExpr
import cangjie_compiler::parse.WildcardPattern as ParsedWildcardPattern
import cangjie_compiler::parse.WhileExpr as ParsedWhileExpr

private func hasNoMacros(mc: MacroCollector): Bool {
    return mc.macroDefFuncs.isEmpty() && mc.macCalls.isEmpty()
}

private func hasDefAndCallInSamePkg(macroCollector: MacroCollector, diag: DiagnosticEngine): Bool {
    var ret = false
    for (fd in macroCollector.macroDefFuncs) {
        for (call in macroCollector.macCalls) {
            if (fd.identifier == call.GetFullName()) {
                ret = true
                diag.Diagnose(call.GetBeginPos(), DiagKind.macro_unexpect_def_and_call_in_same_pkg).Emit()
            }
        }
    }
    return ret
}

private func emitMacroDiag(diag: DiagnosticEngine, pos: Position, kind: DiagKind): Unit {
    diag.Diagnose(pos, kind).Emit()
}

private func emitMacroDiagArg(diag: DiagnosticEngine, pos: Position, kind: DiagKind, arg: String): Unit {
    diag.Diagnose(pos, kind, args: [DiagArgument(arg)]).Emit()
}

private func walkNode(node: Node, visit: (Node) -> Bool): Unit {
    if (!visit(node)) {
        return
    }
    for (child in node.Children()) {
        walkNode(child, visit)
    }
    if (let Some(decl) <- (node as Decl)) {
        for (anno in decl.annotations) {
            walkNode(anno, visit)
        }
        for (member in decl.GetMemberDecls()) {
            walkNode(member, visit)
        }
    }
    if (let Some(funcDecl) <- (node as FuncDecl)) {
        for (list in funcDecl.funcBody.paramLists) {
            walkNode(list, visit)
        }
        if (let Some(body) <- funcDecl.funcBody.body) {
            walkNode(body, visit)
        }
    }
}

private func collectMacroEachFile(file: File, collector: MacroCollector): Unit {
    walkNode(file, { curNode: Node =>
        if (let Some(macroDecl) <- (curNode as MacroDecl)) {
            collector.macroDefFuncs.add(macroDecl)
        }
        UpdateMacroInfo(curNode, collector)
        return !curNode.IsMacroCallNode()
    })
}

private func sortMacroCalls(calls: ArrayList<MacroCall>): Unit {
    sort(calls, by: { left: MacroCall, right: MacroCall =>
        let leftPos = left.GetBeginPos()
        let rightPos = right.GetBeginPos()
        if (leftPos.fileID < rightPos.fileID) {
            Ordering.LT
        } else if (leftPos.fileID > rightPos.fileID) {
            Ordering.GT
        } else if (leftPos < rightPos) {
            Ordering.LT
        } else if (rightPos < leftPos) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)
}

private func hasMacroCallInNode(node: Node, diag: DiagnosticEngine, skipIfAvailable!: Bool = false): Bool {
    let hasMacroCall = Box<Bool>(false)
    walkNode(node, { curNode: Node =>
        if (curNode.IsMacroCallNode()) {
            if (skipIfAvailable) {
                if (let Some(invocation) <- curNode.GetInvocation()) {
                    if (invocation.IsIfAvailable()) {
                        return true
                    }
                }
            }
            hasMacroCall.value = true
            if (let Some(invocation) <- curNode.GetInvocation()) {
                emitMacroDiagArg(diag, invocation.macroCallDiagInfo.identifierPos,
                    DiagKind.macro_undeclared_identifier, invocation.macroCallDiagInfo.identifier)
            }
            return false
        }
        return true
    })
    return hasMacroCall.value
}

private func isWhenAnnotation(anno: Annotation): Bool {
    return anno.kind == "WHEN" || anno.kind == "When" || anno.identifier.Val() == "When"
}

private func checkWhenAfterMacroExpand(node: Node, diag: DiagnosticEngine): Unit {
    walkNode(node, { curNode: Node =>
        if (let Some(decl) <- (curNode as Decl)) {
            for (anno in decl.annotations) {
                if (isWhenAnnotation(anno)) {
                    diag.DiagnoseRefactor(DiagKindRefactor.conditional_compilation_unexpected_after_macro,
                        anno.begin).Emit()
                }
            }
        }
        return true
    })
}

private func checkUnhandledMacroCall(pkg: Package, diag: DiagnosticEngine): Unit {
    if (diag.GetErrorCount() > 0) {
        return
    }
    for (file in pkg.files) {
        if (!file.hasMacro) {
            continue
        }
        let _ = hasMacroCallInNode(file, diag, skipIfAvailable: true)
    }
}

private func parseGeneratedNodes(tokens: ArrayList<Token>, macroNode: MacroCall, ci: CompilerInstance): ArrayList<Node> {
    let out = ArrayList<Node>()
    if (tokens.isEmpty()) {
        return out
    }
    if (ASTKindEquals(macroNode.RequireNode().astKind, ASTKind.MACRO_EXPAND_PARAM)) {
        let firstParamToken = tokens[0]
        let paramNode = FuncParam()
        paramNode.identifier = firstParamToken.Value()
        paramNode.begin = firstParamToken.Begin()
        paramNode.end = tokens[tokens.size - 1].End()
        paramNode.curFile = macroNode.RequireNode().curFile
        out.add(paramNode)
        return out
    }
    let parserDiag = ParsedDiagnosticEngine()
    let generatedParser = GeneratedParser(tokens.toArray(), parserDiag, ci.diag.GetSourceManager(),
        attachComment: ci.invocation.globalOptions.enableAddCommentToAst,
        parseDeclFile: ci.invocation.globalOptions.compileCjd)
    generatedParser.SetCompileOptions(ci.invocation.globalOptions)
    generatedParser.SetPrimaryDecl(macroNode.RequireInvocation().outerDeclIdent)
    generatedParser.EnableCustomAnno()
    let parsedCurrentMacroCall = makeParsedCurrentMacroCall(macroNode.RequireNode())
    let parsedScope = if (ASTKindEquals(macroNode.RequireNode().astKind, ASTKind.MACRO_EXPAND_EXPR)) {
        ParsedScopeKind.FUNC_BODY
    } else {
        toParsedScopeKind(macroNode.RequireInvocation().scopeKind)
    }
    let parsedNodes = generatedParser.ParseNodes(parsedScope, parsedCurrentMacroCall)
    forwardParserDiagnostics(parserDiag, ci.diag)
    if (parserDiag.HasError()) {
        out.add(makeInvalidGeneratedNode(tokens))
        return out
    }
    let fallbackFile = macroNode.RequireNode().curFile
    for (parsedNode in parsedNodes) {
        out.add(convertParsedNode(parsedNode, fallbackFile))
    }
    if (!out.isEmpty()) {
        return out
    }

    // Fallback for bridge-only gaps while the sibling parser AST and Macro's local compatibility AST still differ.
    let first = tokens[0]
    if (ASTKindEquals(macroNode.RequireNode().astKind, ASTKind.MACRO_EXPAND_DECL)) {
        if (first.kind == TokenKind.FUNC || first.kind == TokenKind.MACRO) {
            let fd = FuncDecl()
            fd.identifier = findFollowingIdentifier(tokens, 1)
            fd.begin = first.Begin()
            fd.end = tokens[tokens.size - 1].End()
            fd.curFile = macroNode.RequireNode().curFile
            out.add(fd)
            return out
        }
        if (first.kind == TokenKind.VAR || first.kind == TokenKind.LET || first.kind == TokenKind.CONST) {
            let varDecl = VarDecl()
            varDecl.identifier = findFollowingIdentifier(tokens, 1)
            varDecl.begin = first.Begin()
            varDecl.end = tokens[tokens.size - 1].End()
            varDecl.curFile = macroNode.RequireNode().curFile
            out.add(varDecl)
            return out
        }
        let decl = Decl(ASTKind.DECL)
        decl.identifier = findFollowingIdentifier(tokens, 0)
        decl.begin = first.Begin()
        decl.end = tokens[tokens.size - 1].End()
        decl.curFile = macroNode.RequireNode().curFile
        out.add(decl)
        return out
    }
    let tokenPart = TokenPart(tokens)
    tokenPart.begin = first.Begin()
    tokenPart.end = tokens[tokens.size - 1].End()
    tokenPart.curFile = macroNode.RequireNode().curFile
    out.add(tokenPart)
    return out
}

private func makeParsedCurrentMacroCall(macroNode: Node): ParsedNode {
    let parsedNode = ParsedNode()
    parsedNode.begin = macroNode.begin
    parsedNode.end = macroNode.end
    return parsedNode
}

private func makeInvalidGeneratedNode(tokens: ArrayList<Token>): Node {
    let invalidNode = Node()
    if (!tokens.isEmpty()) {
        invalidNode.begin = tokens[0].Begin()
        invalidNode.end = tokens[tokens.size - 1].End()
    }
    invalidNode.EnableAttr(Attribute.IS_BROKEN)
    return invalidNode
}

private func forwardParserDiagnostics(parserDiag: ParsedDiagnosticEngine, diag: DiagnosticEngine): Unit {
    for (diagnostic in parserDiag.Diagnostics()) {
        if (diagnostic.severity == ParsedDiagSeverity.WARNING) {
            diag.Warn(MakeRange(diagnostic.pos, diagnostic.pos), diagnostic.message)
        } else {
            diag.Diagnose(diagnostic.pos, diagnostic.message)
        }
    }
}

private func toParsedScopeKind(scope: ScopeKind): ParsedScopeKind {
    return match (scope) {
        case ScopeKind.TOPLEVEL => ParsedScopeKind.TOPLEVEL
        case ScopeKind.CLASS_BODY => ParsedScopeKind.CLASS_BODY
        case ScopeKind.INTERFACE_BODY => ParsedScopeKind.INTERFACE_BODY
        case ScopeKind.STRUCT_BODY => ParsedScopeKind.STRUCT_BODY
        case ScopeKind.EXTEND_BODY => ParsedScopeKind.EXTEND_BODY
        case ScopeKind.FUNC_BODY => ParsedScopeKind.FUNC_BODY
        case ScopeKind.MACRO_BODY => ParsedScopeKind.MACRO_BODY
        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS => ParsedScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT => ParsedScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
        case ScopeKind.PROP_MEMBER_SETTER_BODY => ParsedScopeKind.PROP_MEMBER_SETTER_BODY
        case ScopeKind.PROP_MEMBER_GETTER_BODY => ParsedScopeKind.PROP_MEMBER_GETTER_BODY
        case ScopeKind.ENUM_BODY => ParsedScopeKind.ENUM_BODY
        case ScopeKind.ENUM_CONSTRUCTOR => ParsedScopeKind.ENUM_CONSTRUCTOR
        case ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM => ParsedScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM
        case ScopeKind.MAIN_BODY => ParsedScopeKind.MAIN_BODY
        case ScopeKind.UNKNOWN_SCOPE => ParsedScopeKind.UNKNOWN_SCOPE
        case ScopeKind.UNKNOWN => ParsedScopeKind.UNKNOWN_SCOPE
    }
}

private func toMacroScopeKind(scope: ParsedScopeKind): ScopeKind {
    return match (scope) {
        case ParsedScopeKind.TOPLEVEL => ScopeKind.TOPLEVEL
        case ParsedScopeKind.CLASS_BODY => ScopeKind.CLASS_BODY
        case ParsedScopeKind.INTERFACE_BODY => ScopeKind.INTERFACE_BODY
        case ParsedScopeKind.STRUCT_BODY => ScopeKind.STRUCT_BODY
        case ParsedScopeKind.EXTEND_BODY => ScopeKind.EXTEND_BODY
        case ParsedScopeKind.FUNC_BODY => ScopeKind.FUNC_BODY
        case ParsedScopeKind.MACRO_BODY => ScopeKind.MACRO_BODY
        case ParsedScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS => ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
        case ParsedScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT => ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
        case ParsedScopeKind.PROP_MEMBER_SETTER_BODY => ScopeKind.PROP_MEMBER_SETTER_BODY
        case ParsedScopeKind.PROP_MEMBER_GETTER_BODY => ScopeKind.PROP_MEMBER_GETTER_BODY
        case ParsedScopeKind.ENUM_BODY => ScopeKind.ENUM_BODY
        case ParsedScopeKind.ENUM_CONSTRUCTOR => ScopeKind.ENUM_CONSTRUCTOR
        case ParsedScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM => ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM
        case ParsedScopeKind.MAIN_BODY => ScopeKind.MAIN_BODY
        case ParsedScopeKind.UNKNOWN_SCOPE => ScopeKind.UNKNOWN_SCOPE
    }
}

private func toMacroExprKind(kind: ParsedExprKind): ExprKind {
    return match (kind) {
        case ParsedExprKind.ALL => ExprKind.ALL
        case ParsedExprKind.VAR_INIT => ExprKind.VAR_INIT
        case ParsedExprKind.INDEX_EXPR => ExprKind.INDEX_EXPR
        case ParsedExprKind.IF_COND_EXPR => ExprKind.IF_COND_EXPR
        case ParsedExprKind.WHILE_COND_EXPR => ExprKind.WHILE_COND_EXPR
        case ParsedExprKind.LET_PATTERN => ExprKind.LET_PATTERN
        case ParsedExprKind.LEFT_EXPR => ExprKind.LEFT_EXPR
        case ParsedExprKind.EXPR_IN_TUPLE => ExprKind.EXPR_IN_TUPLE
        case ParsedExprKind.EXPR_IN_IF_COND_TUPLE => ExprKind.EXPR_IN_IF_COND_TUPLE
        case ParsedExprKind.EXPR_IN_WHILE_COND_TUPLE => ExprKind.EXPR_IN_WHILE_COND_TUPLE
        case ParsedExprKind.EXPR_IN_ARRAY => ExprKind.EXPR_IN_ARRAY
        case ParsedExprKind.EXPR_IN_CALLSUFFIX => ExprKind.EXPR_IN_CALLSUFFIX
        case ParsedExprKind.EXPR_IN_ANNOTATION => ExprKind.EXPR_IN_ANNOTATION
        case ParsedExprKind.UNKNOWN_EXPR => ExprKind.UNKNOWN_EXPR
    }
}

private func copyParsedNodeBase(parsedNode: ParsedNode, targetNode: Node, fallbackFile: Option<File>): Unit {
    targetNode.begin = parsedNode.begin
    targetNode.end = parsedNode.end
    targetNode.curFile = fallbackFile
    if (parsedNode.isBroken || ASTKindEquals(parsedNode.astKind, ASTKind.INVALID_DECL) ||
        ASTKindEquals(parsedNode.astKind, ASTKind.INVALID_EXPR) ||
        ASTKindEquals(parsedNode.astKind, ASTKind.INVALID_TYPE) ||
        ASTKindEquals(parsedNode.astKind, ASTKind.INVALID_PATTERN)) {
        targetNode.EnableAttr(Attribute.IS_BROKEN)
    }
}

private func convertParsedModifier(parsedModifier: ParsedModifier): Modifier {
    return Modifier(parsedModifier.tokenKind, parsedModifier.begin)
}

private func convertParsedAnnotation(parsedAnnotation: ParsedAnnotation, fallbackFile: Option<File>): Annotation {
    let targetAnnotation = Annotation()
    copyParsedNodeBase(parsedAnnotation, targetAnnotation, fallbackFile)
    targetAnnotation.kind = if (parsedAnnotation.kind == RealAnnotationKind.WHEN) { "WHEN" } else {
        parsedAnnotation.identifier.Val()
    }
    targetAnnotation.identifier = Identifier(parsedAnnotation.identifier.Val(), parsedAnnotation.identifier.Begin(),
        parsedAnnotation.identifier.End())
    targetAnnotation.isCompileTimeVisible = parsedAnnotation.isCompileTimeVisible
    for (attrToken in parsedAnnotation.attrs) {
        targetAnnotation.attrs.add(attrToken.Value())
    }
    for (parsedArg in parsedAnnotation.args) {
        targetAnnotation.args.add(convertParsedFuncArg(parsedArg, fallbackFile))
    }
    return targetAnnotation
}

private func copyParsedDeclBase(parsedDecl: ParsedDecl, targetDecl: Decl, fallbackFile: Option<File>): Unit {
    copyParsedNodeBase(parsedDecl, targetDecl, fallbackFile)
    targetDecl.identifier = parsedDecl.identifier.Val()
    for (parsedModifier in parsedDecl.modifiers) {
        targetDecl.modifiers.add(convertParsedModifier(parsedModifier))
    }
    for (parsedAnnotation in parsedDecl.annotations) {
        targetDecl.annotations.add(convertParsedAnnotation(parsedAnnotation, fallbackFile))
    }
    for (parsedAttr in parsedDecl.GetAttrs()) {
        targetDecl.EnableAttr(parsedAttr)
    }
}

private func convertParsedFuncBody(parsedBody: ParsedFuncBody, fallbackFile: Option<File>): FuncBody {
    let targetBody = FuncBody()
    copyParsedNodeBase(parsedBody, targetBody, fallbackFile)
    for (parsedList in parsedBody.paramLists) {
        targetBody.paramLists.add(convertParsedFuncParamList(parsedList, fallbackFile))
    }
    if (let Some(parsedReturnType) <- parsedBody.retType) {
        targetBody.retType = Some(convertParsedType(parsedReturnType, fallbackFile))
    }
    if (let Some(parsedBlockValue) <- parsedBody.body) {
        if (let Some(convertedBlock) <- (convertParsedExpr(parsedBlockValue, fallbackFile) as Block)) {
            targetBody.body = Some(convertedBlock)
        }
    }
    return targetBody
}

private func convertParsedFuncParamList(parsedList: ParsedFuncParamList, fallbackFile: Option<File>): FuncParamList {
    let targetList = FuncParamList()
    copyParsedNodeBase(parsedList, targetList, fallbackFile)
    for (parsedParam in parsedList.params) {
        targetList.params.add(convertParsedFuncParam(parsedParam, fallbackFile))
    }
    return targetList
}

private func convertParsedFuncParam(parsedParam: ParsedFuncParam, fallbackFile: Option<File>): FuncParam {
    let targetParam = FuncParam()
    copyParsedDeclBase(parsedParam, targetParam, fallbackFile)
    targetParam.isNamedParam = parsedParam.isNamedParam
    targetParam.isMemberParam = parsedParam.isMemberParam
    if (let Some(parsedAssignment) <- parsedParam.assignment) {
        targetParam.assignment = Some(convertParsedExpr(parsedAssignment, fallbackFile))
    }
    return targetParam
}

private func convertParsedFuncDecl(parsedFuncDecl: ParsedFuncDecl, fallbackFile: Option<File>): FuncDecl {
    let targetFuncDecl = if (let Some(_) <- (parsedFuncDecl as ParsedMacroDecl)) { MacroDecl() } else { FuncDecl() }
    copyParsedDeclBase(parsedFuncDecl, targetFuncDecl, fallbackFile)
    if (let Some(parsedBody) <- parsedFuncDecl.funcBody) {
        targetFuncDecl.funcBody = convertParsedFuncBody(parsedBody, fallbackFile)
        targetFuncDecl.funcBody.funcDecl = Some(targetFuncDecl)
    }
    return targetFuncDecl
}

private func convertParsedDecl(parsedDecl: ParsedDecl, fallbackFile: Option<File>): Decl {
    if (let Some(parsedMacroDecl) <- (parsedDecl as ParsedMacroExpandDecl)) {
        let targetMacroDecl = MacroExpandDecl()
        copyParsedDeclBase(parsedMacroDecl, targetMacroDecl, fallbackFile)
        targetMacroDecl.invocation = convertParsedMacroInvocation(parsedMacroDecl.invocation, fallbackFile)
        return targetMacroDecl
    }
    if (let Some(parsedParamDecl) <- (parsedDecl as ParsedFuncParam)) {
        return convertParsedFuncParam(parsedParamDecl, fallbackFile)
    }
    if (let Some(parsedFunctionDecl) <- (parsedDecl as ParsedFuncDecl)) {
        return convertParsedFuncDecl(parsedFunctionDecl, fallbackFile)
    }
    if (let Some(parsedPatternVariableDecl) <- (parsedDecl as ParsedVarWithPatternDecl)) {
        let targetPatternVariableDecl = VarWithPatternDecl()
        copyParsedDeclBase(parsedPatternVariableDecl, targetPatternVariableDecl, fallbackFile)
        targetPatternVariableDecl.isVar = parsedPatternVariableDecl.isVar
        if (let Some(parsedPatternTypeNode) <- parsedPatternVariableDecl.typeNode) {
            targetPatternVariableDecl.declType = Some(convertParsedType(parsedPatternTypeNode, fallbackFile))
        }
        if (let Some(parsedPatternInitializer) <- parsedPatternVariableDecl.initializer) {
            targetPatternVariableDecl.initializer = Some(convertParsedExpr(parsedPatternInitializer, fallbackFile))
        }
        if (let Some(parsedIrrefutablePattern) <- parsedPatternVariableDecl.irrefutablePattern) {
            targetPatternVariableDecl.irrefutablePattern = Some(convertParsedPattern(parsedIrrefutablePattern,
                fallbackFile))
        }
        return targetPatternVariableDecl
    }
    if (let Some(parsedVariableDecl) <- (parsedDecl as ParsedVarDecl)) {
        let targetVariableDecl = VarDecl()
        copyParsedDeclBase(parsedVariableDecl, targetVariableDecl, fallbackFile)
        if (let Some(parsedTypeNode) <- parsedVariableDecl.typeNode) {
            targetVariableDecl.declType = Some(convertParsedType(parsedTypeNode, fallbackFile))
        }
        if (let Some(parsedInitializer) <- parsedVariableDecl.initializer) {
            targetVariableDecl.initializer = Some(convertParsedExpr(parsedInitializer, fallbackFile))
        }
        for (constructorType in parsedVariableDecl.constructorTypes) {
            targetVariableDecl.constructorTypes.add(convertParsedType(constructorType, fallbackFile))
        }
        return targetVariableDecl
    }
    if (let Some(parsedClassDecl) <- (parsedDecl as ParsedClassDecl)) {
        let targetClassDecl = ClassDecl()
        copyParsedDeclBase(parsedClassDecl, targetClassDecl, fallbackFile)
        for (parsedMemberDecl in parsedClassDecl.bodyDecls) {
            let convertedMemberDecl = convertParsedDecl(parsedMemberDecl, fallbackFile)
            convertedMemberDecl.outerDecl = Some(targetClassDecl)
            targetClassDecl.members.add(convertedMemberDecl)
        }
        return targetClassDecl
    }
    if (let Some(parsedStructDecl) <- (parsedDecl as ParsedStructDecl)) {
        let targetStructDecl = StructDecl()
        copyParsedDeclBase(parsedStructDecl, targetStructDecl, fallbackFile)
        for (parsedStructMemberDecl in parsedStructDecl.bodyDecls) {
            let convertedStructMemberDecl = convertParsedDecl(parsedStructMemberDecl, fallbackFile)
            convertedStructMemberDecl.outerDecl = Some(targetStructDecl)
            targetStructDecl.members.add(convertedStructMemberDecl)
        }
        return targetStructDecl
    }
    if (let Some(parsedInterfaceDecl) <- (parsedDecl as ParsedInterfaceDecl)) {
        let targetInterfaceDecl = InterfaceDecl()
        copyParsedDeclBase(parsedInterfaceDecl, targetInterfaceDecl, fallbackFile)
        for (parsedInterfaceMemberDecl in parsedInterfaceDecl.bodyDecls) {
            let convertedInterfaceMemberDecl = convertParsedDecl(parsedInterfaceMemberDecl, fallbackFile)
            convertedInterfaceMemberDecl.outerDecl = Some(targetInterfaceDecl)
            targetInterfaceDecl.members.add(convertedInterfaceMemberDecl)
        }
        return targetInterfaceDecl
    }
    if (let Some(parsedEnumDecl) <- (parsedDecl as ParsedEnumDecl)) {
        let targetEnumDecl = EnumDecl()
        copyParsedDeclBase(parsedEnumDecl, targetEnumDecl, fallbackFile)
        targetEnumDecl.hasArguments = false
        for (parsedEnumConstructorDecl in parsedEnumDecl.constructors) {
            let convertedEnumConstructorDecl = convertParsedDecl(parsedEnumConstructorDecl, fallbackFile)
            convertedEnumConstructorDecl.outerDecl = Some(targetEnumDecl)
            if (let Some(convertedEnumVarDecl) <- (convertedEnumConstructorDecl as VarDecl)) {
                if (!convertedEnumVarDecl.constructorTypes.isEmpty()) {
                    targetEnumDecl.hasArguments = true
                }
            }
            if (let Some(convertedEnumFuncDecl) <- (convertedEnumConstructorDecl as FuncDecl)) {
                if (convertedEnumFuncDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    targetEnumDecl.hasArguments = true
                }
            }
            targetEnumDecl.constructors.add(convertedEnumConstructorDecl)
        }
        for (parsedEnumMemberDecl in parsedEnumDecl.bodyDecls) {
            let convertedEnumMemberDecl = convertParsedDecl(parsedEnumMemberDecl, fallbackFile)
            convertedEnumMemberDecl.outerDecl = Some(targetEnumDecl)
            targetEnumDecl.members.add(convertedEnumMemberDecl)
        }
        return targetEnumDecl
    }
    if (let Some(parsedExtendDecl) <- (parsedDecl as ParsedExtendDecl)) {
        let targetExtendDecl = ExtendDecl()
        copyParsedDeclBase(parsedExtendDecl, targetExtendDecl, fallbackFile)
        for (parsedExtendMemberDecl in parsedExtendDecl.bodyDecls) {
            let convertedExtendMemberDecl = convertParsedDecl(parsedExtendMemberDecl, fallbackFile)
            convertedExtendMemberDecl.outerDecl = Some(targetExtendDecl)
            targetExtendDecl.members.add(convertedExtendMemberDecl)
        }
        return targetExtendDecl
    }
    let targetDecl = Decl(parsedDecl.astKind)
    copyParsedDeclBase(parsedDecl, targetDecl, fallbackFile)
    return targetDecl
}

private func convertParsedFuncArg(parsedArg: ParsedFuncArg, fallbackFile: Option<File>): FuncArg {
    let targetArg = FuncArg()
    copyParsedNodeBase(parsedArg, targetArg, fallbackFile)
    targetArg.name = Identifier(parsedArg.name.Val(), parsedArg.name.Begin(), parsedArg.name.End())
    if (let Some(parsedArgExpr) <- parsedArg.expr) {
        targetArg.expr = Some(convertParsedExpr(parsedArgExpr, fallbackFile))
    }
    return targetArg
}

private func convertParsedMatchCase(parsedCase: ParsedMatchCase, fallbackFile: Option<File>): MatchCase {
    let targetCase = MatchCase()
    copyParsedNodeBase(parsedCase, targetCase, fallbackFile)
    for (parsedPatternNode in parsedCase.patterns) {
        targetCase.patterns.add(convertParsedPattern(parsedPatternNode, fallbackFile))
    }
    if (let Some(parsedGuardExpr) <- parsedCase.patternGuard) {
        targetCase.patternGuard = Some(convertParsedExpr(parsedGuardExpr, fallbackFile))
    }
    if (let Some(parsedCaseBody) <- parsedCase.exprOrDecls) {
        if (let Some(convertedCaseBody) <- (convertParsedExpr(parsedCaseBody, fallbackFile) as Block)) {
            targetCase.exprOrDecls = Some(convertedCaseBody)
        }
    }
    return targetCase
}

private func convertParsedMatchCaseOther(
    parsedCaseOther: ParsedMatchCaseOther,
    fallbackFile: Option<File>
): MatchCaseOther {
    let targetCaseOther = MatchCaseOther()
    copyParsedNodeBase(parsedCaseOther, targetCaseOther, fallbackFile)
    if (let Some(parsedOtherExpr) <- parsedCaseOther.matchExpr) {
        targetCaseOther.matchExpr = Some(convertParsedExpr(parsedOtherExpr, fallbackFile))
    }
    if (let Some(parsedOtherBody) <- parsedCaseOther.exprOrDecls) {
        if (let Some(convertedOtherBody) <- (convertParsedExpr(parsedOtherBody, fallbackFile) as Block)) {
            targetCaseOther.exprOrDecls = Some(convertedOtherBody)
        }
    }
    return targetCaseOther
}

private func convertParsedExpr(parsedExpr: ParsedExpr, fallbackFile: Option<File>): Expr {
    if (let Some(parsedMacroExpr) <- (parsedExpr as ParsedMacroExpandExpr)) {
        let targetMacroExpr = MacroExpandExpr()
        copyParsedNodeBase(parsedMacroExpr, targetMacroExpr, fallbackFile)
        targetMacroExpr.identifier = Identifier(parsedMacroExpr.identifier.Val(), parsedMacroExpr.identifier.Begin(),
            parsedMacroExpr.identifier.End())
        targetMacroExpr.invocation = convertParsedMacroInvocation(parsedMacroExpr.invocation, fallbackFile)
        return targetMacroExpr
    }
    if (let Some(parsedBlockExpr) <- (parsedExpr as ParsedBlock)) {
        let targetBlock = Block()
        copyParsedNodeBase(parsedBlockExpr, targetBlock, fallbackFile)
        for (parsedBodyNode in parsedBlockExpr.body) {
            targetBlock.body.add(convertParsedNode(parsedBodyNode, fallbackFile))
        }
        return targetBlock
    }
    if (let Some(parsedTokenPartExpr) <- (parsedExpr as ParsedTokenPart)) {
        let targetTokenPart = TokenPart(parsedTokenPartExpr.tokens)
        copyParsedNodeBase(parsedTokenPartExpr, targetTokenPart, fallbackFile)
        return targetTokenPart
    }
    if (let Some(parsedWildcardExpr) <- (parsedExpr as ParsedWildcardExpr)) {
        let targetWildcardExpr = WildcardExpr()
        copyParsedNodeBase(parsedWildcardExpr, targetWildcardExpr, fallbackFile)
        return targetWildcardExpr
    }
    if (let Some(parsedTupleExpr) <- (parsedExpr as ParsedTupleLit)) {
        let targetTupleExpr = TupleLit()
        copyParsedNodeBase(parsedTupleExpr, targetTupleExpr, fallbackFile)
        for (parsedChildExpr in parsedTupleExpr.children) {
            targetTupleExpr.children.add(convertParsedExpr(parsedChildExpr, fallbackFile))
        }
        return targetTupleExpr
    }
    if (let Some(parsedArrayLitExpr) <- (parsedExpr as ParsedArrayLit)) {
        let targetArrayLitExpr = ArrayLit()
        copyParsedNodeBase(parsedArrayLitExpr, targetArrayLitExpr, fallbackFile)
        for (parsedArrayChildExpr in parsedArrayLitExpr.children) {
            targetArrayLitExpr.children.add(convertParsedExpr(parsedArrayChildExpr, fallbackFile))
        }
        return targetArrayLitExpr
    }
    if (let Some(parsedQuoteExpr) <- (parsedExpr as ParsedQuoteExpr)) {
        let targetQuoteExpr = QuoteExpr()
        copyParsedNodeBase(parsedQuoteExpr, targetQuoteExpr, fallbackFile)
        for (parsedQuoteToken in parsedQuoteExpr.tokens) {
            targetQuoteExpr.tokens.add(parsedQuoteToken)
        }
        for (parsedQuotedExpr in parsedQuoteExpr.exprs) {
            targetQuoteExpr.exprs.add(convertParsedExpr(parsedQuotedExpr, fallbackFile))
        }
        return targetQuoteExpr
    }
    if (let Some(parsedRefExpr) <- (parsedExpr as ParsedRefExpr)) {
        let targetRefExpr = RefExpr(parsedRefExpr.identifier.GetRawText())
        copyParsedNodeBase(parsedRefExpr, targetRefExpr, fallbackFile)
        return targetRefExpr
    }
    if (let Some(parsedLitExpr) <- (parsedExpr as ParsedLitConstExpr)) {
        let targetLitExpr = LitConstExpr()
        copyParsedNodeBase(parsedLitExpr, targetLitExpr, fallbackFile)
        targetLitExpr.rawString = parsedLitExpr.rawString
        targetLitExpr.kind = parsedLitExpr.tokenKind
        return targetLitExpr
    }
    if (let Some(parsedPrimitiveTypeExpr) <- (parsedExpr as ParsedPrimitiveTypeExpr)) {
        let targetPrimitiveTypeExpr = PrimitiveTypeExpr(primitiveTypeKindFromName(parsedPrimitiveTypeExpr.name))
        copyParsedNodeBase(parsedPrimitiveTypeExpr, targetPrimitiveTypeExpr, fallbackFile)
        return targetPrimitiveTypeExpr
    }
    if (let Some(parsedMemberExpr) <- (parsedExpr as ParsedMemberAccess)) {
        let targetMemberExpr = MemberAccess()
        copyParsedNodeBase(parsedMemberExpr, targetMemberExpr, fallbackFile)
        targetMemberExpr.field = parsedMemberExpr.field.GetRawText()
        if (let Some(parsedBaseExpr) <- parsedMemberExpr.baseExpr) {
            targetMemberExpr.baseExpr = Some(convertParsedExpr(parsedBaseExpr, fallbackFile))
        }
        return targetMemberExpr
    }
    if (let Some(parsedCallExpr) <- (parsedExpr as ParsedCallExpr)) {
        let targetCallExpr = CallExpr()
        copyParsedNodeBase(parsedCallExpr, targetCallExpr, fallbackFile)
        if (let Some(parsedBaseFunc) <- parsedCallExpr.baseFunc) {
            targetCallExpr.baseFunc = Some(convertParsedExpr(parsedBaseFunc, fallbackFile))
        }
        for (parsedCallArg in parsedCallExpr.args) {
            targetCallExpr.args.add(convertParsedFuncArg(parsedCallArg, fallbackFile))
        }
        return targetCallExpr
    }
    if (let Some(parsedArrayExpr) <- (parsedExpr as ParsedArrayExpr)) {
        let targetArrayExpr = ArrayExpr()
        copyParsedNodeBase(parsedArrayExpr, targetArrayExpr, fallbackFile)
        if (let Some(parsedArrayTypeNode) <- parsedArrayExpr.typeNode) {
            targetArrayExpr.typeNode = Some(convertParsedType(parsedArrayTypeNode, fallbackFile))
        }
        for (parsedArrayArg in parsedArrayExpr.args) {
            targetArrayExpr.args.add(convertParsedFuncArg(parsedArrayArg, fallbackFile))
        }
        return targetArrayExpr
    }
    if (let Some(parsedSubscriptExpr) <- (parsedExpr as ParsedSubscriptExpr)) {
        let targetSubscriptExpr = SubscriptExpr()
        copyParsedNodeBase(parsedSubscriptExpr, targetSubscriptExpr, fallbackFile)
        if (let Some(parsedSubscriptBase) <- parsedSubscriptExpr.baseExpr) {
            targetSubscriptExpr.baseExpr = Some(convertParsedExpr(parsedSubscriptBase, fallbackFile))
        }
        for (parsedIndexExpr in parsedSubscriptExpr.indexExprs) {
            targetSubscriptExpr.indexExprs.add(convertParsedExpr(parsedIndexExpr, fallbackFile))
        }
        return targetSubscriptExpr
    }
    if (let Some(parsedOptionalExpr) <- (parsedExpr as ParsedOptionalExpr)) {
        let targetOptionalExpr = OptionalExpr()
        copyParsedNodeBase(parsedOptionalExpr, targetOptionalExpr, fallbackFile)
        if (let Some(parsedOptionalBaseExpr) <- parsedOptionalExpr.baseExpr) {
            targetOptionalExpr.baseExpr = Some(convertParsedExpr(parsedOptionalBaseExpr, fallbackFile))
        }
        return targetOptionalExpr
    }
    if (let Some(parsedOptionalChainExpr) <- (parsedExpr as ParsedOptionalChainExpr)) {
        let targetOptionalChainExpr = OptionalChainExpr()
        copyParsedNodeBase(parsedOptionalChainExpr, targetOptionalChainExpr, fallbackFile)
        if (let Some(parsedOptionalChainInner) <- parsedOptionalChainExpr.expr) {
            targetOptionalChainExpr.expr = Some(convertParsedExpr(parsedOptionalChainInner, fallbackFile))
        }
        return targetOptionalChainExpr
    }
    if (let Some(parsedParenExpr) <- (parsedExpr as ParsedParenExpr)) {
        let targetParenExpr = ParenExpr()
        copyParsedNodeBase(parsedParenExpr, targetParenExpr, fallbackFile)
        if (let Some(parsedInnerExpr) <- parsedParenExpr.expr) {
            targetParenExpr.expr = Some(convertParsedExpr(parsedInnerExpr, fallbackFile))
        }
        return targetParenExpr
    }
    if (let Some(parsedUnaryExpr) <- (parsedExpr as ParsedUnaryExpr)) {
        let targetUnaryExpr = UnaryExpr(parsedUnaryExpr.astKind)
        copyParsedNodeBase(parsedUnaryExpr, targetUnaryExpr, fallbackFile)
        targetUnaryExpr.op = parsedUnaryExpr.op.kind
        if (let Some(parsedUnaryInnerExpr) <- parsedUnaryExpr.expr) {
            targetUnaryExpr.expr = Some(convertParsedExpr(parsedUnaryInnerExpr, fallbackFile))
        }
        return targetUnaryExpr
    }
    if (let Some(parsedIncOrDecExpr) <- (parsedExpr as ParsedIncOrDecExpr)) {
        let targetIncOrDecExpr = IncOrDecExpr()
        copyParsedNodeBase(parsedIncOrDecExpr, targetIncOrDecExpr, fallbackFile)
        targetIncOrDecExpr.op = parsedIncOrDecExpr.op
        if (let Some(parsedIncOrDecInnerExpr) <- parsedIncOrDecExpr.expr) {
            targetIncOrDecExpr.expr = Some(convertParsedExpr(parsedIncOrDecInnerExpr, fallbackFile))
        }
        return targetIncOrDecExpr
    }
    if (let Some(parsedTypeConvExpr) <- (parsedExpr as ParsedTypeConvExpr)) {
        let targetTypeConvExpr = TypeConvExpr()
        copyParsedNodeBase(parsedTypeConvExpr, targetTypeConvExpr, fallbackFile)
        if (let Some(parsedConvTypeNode) <- parsedTypeConvExpr.typeNode) {
            targetTypeConvExpr.typeNode = Some(convertParsedType(parsedConvTypeNode, fallbackFile))
        }
        if (let Some(parsedConvExpr) <- parsedTypeConvExpr.expr) {
            targetTypeConvExpr.expr = Some(convertParsedExpr(parsedConvExpr, fallbackFile))
        }
        return targetTypeConvExpr
    }
    if (let Some(parsedLetPatternExpr) <- (parsedExpr as ParsedLetPatternDestructor)) {
        let targetLetPatternExpr = LetPatternDestructor()
        copyParsedNodeBase(parsedLetPatternExpr, targetLetPatternExpr, fallbackFile)
        for (parsedLetPattern in parsedLetPatternExpr.patterns) {
            targetLetPatternExpr.patterns.add(convertParsedPattern(parsedLetPattern, fallbackFile))
        }
        if (let Some(parsedLetInitializer) <- parsedLetPatternExpr.initializer) {
            targetLetPatternExpr.initializer = Some(convertParsedExpr(parsedLetInitializer, fallbackFile))
        }
        return targetLetPatternExpr
    }
    if (let Some(parsedReturnExpr) <- (parsedExpr as ParsedReturnExpr)) {
        let targetReturnExpr = ReturnExpr()
        copyParsedNodeBase(parsedReturnExpr, targetReturnExpr, fallbackFile)
        if (let Some(parsedReturnValue) <- parsedReturnExpr.expr) {
            targetReturnExpr.expr = Some(convertParsedExpr(parsedReturnValue, fallbackFile))
        }
        return targetReturnExpr
    }
    if (let Some(parsedJumpExpr) <- (parsedExpr as ParsedJumpExpr)) {
        let targetJumpExpr = JumpExpr()
        copyParsedNodeBase(parsedJumpExpr, targetJumpExpr, fallbackFile)
        targetJumpExpr.isBreak = parsedJumpExpr.token.kind == TokenKind.BREAK
        return targetJumpExpr
    }
    if (let Some(parsedIfExpr) <- (parsedExpr as ParsedIfExpr)) {
        let targetIfExpr = IfExpr()
        copyParsedNodeBase(parsedIfExpr, targetIfExpr, fallbackFile)
        targetIfExpr.hasElse = parsedIfExpr.hasElse
        if (let Some(parsedCondExpr) <- parsedIfExpr.condExpr) {
            targetIfExpr.condExpr = Some(convertParsedExpr(parsedCondExpr, fallbackFile))
        }
        if (let Some(parsedThenBody) <- parsedIfExpr.thenBody) {
            if (let Some(convertedThenBody) <- (convertParsedExpr(parsedThenBody, fallbackFile) as Block)) {
                targetIfExpr.thenBody = Some(convertedThenBody)
            }
        }
        if (let Some(parsedElseBody) <- parsedIfExpr.elseBody) {
            targetIfExpr.elseBody = Some(convertParsedExpr(parsedElseBody, fallbackFile))
        }
        return targetIfExpr
    }
    if (let Some(parsedMatchExpr) <- (parsedExpr as ParsedMatchExpr)) {
        let targetMatchExpr = MatchExpr()
        copyParsedNodeBase(parsedMatchExpr, targetMatchExpr, fallbackFile)
        if (let Some(parsedSelectorExpr) <- parsedMatchExpr.selector) {
            targetMatchExpr.selector = Some(convertParsedExpr(parsedSelectorExpr, fallbackFile))
        }
        for (parsedCaseNode in parsedMatchExpr.matchCases) {
            targetMatchExpr.matchCases.add(convertParsedMatchCase(parsedCaseNode, fallbackFile))
        }
        for (parsedOtherNode in parsedMatchExpr.matchCaseOthers) {
            targetMatchExpr.matchCaseOthers.add(convertParsedMatchCaseOther(parsedOtherNode, fallbackFile))
        }
        return targetMatchExpr
    }
    if (let Some(parsedTryExpr) <- (parsedExpr as ParsedTryExpr)) {
        let targetTryExpr = TryExpr()
        copyParsedNodeBase(parsedTryExpr, targetTryExpr, fallbackFile)
        for (parsedResourceDecl in parsedTryExpr.resourceSpec) {
            if (let Some(convertedResourceDecl) <- (convertParsedDecl(parsedResourceDecl, fallbackFile) as VarDecl)) {
                targetTryExpr.resourceSpec.add(convertedResourceDecl)
            }
        }
        if (let Some(parsedTryBlock) <- parsedTryExpr.tryBlock) {
            if (let Some(convertedTryBlock) <- (convertParsedExpr(parsedTryBlock, fallbackFile) as Block)) {
                targetTryExpr.tryBlock = Some(convertedTryBlock)
            }
        }
        for (parsedCatchPattern in parsedTryExpr.catchPatterns) {
            targetTryExpr.catchPatterns.add(convertParsedPattern(parsedCatchPattern, fallbackFile))
        }
        for (parsedCatchBlock in parsedTryExpr.catchBlocks) {
            if (let Some(convertedCatchBlock) <- (convertParsedExpr(parsedCatchBlock, fallbackFile) as Block)) {
                targetTryExpr.catchBlocks.add(convertedCatchBlock)
            }
        }
        if (let Some(parsedFinallyBlock) <- parsedTryExpr.finallyBlock) {
            if (let Some(convertedFinallyBlock) <- (convertParsedExpr(parsedFinallyBlock, fallbackFile) as Block)) {
                targetTryExpr.finallyBlock = Some(convertedFinallyBlock)
            }
        }
        for (parsedHandler in parsedTryExpr.handlers) {
            let targetHandler = Handler()
            if (let Some(parsedCommandPattern) <- parsedHandler.commandPattern) {
                targetHandler.commandPattern = Some(convertParsedPattern(parsedCommandPattern, fallbackFile))
            }
            if (let Some(parsedHandlerBlock) <- parsedHandler.block) {
                if (let Some(convertedHandlerBlock) <- (convertParsedExpr(parsedHandlerBlock, fallbackFile) as Block)) {
                    targetHandler.block = Some(convertedHandlerBlock)
                }
            }
            targetTryExpr.handlers.add(targetHandler)
        }
        return targetTryExpr
    }
    if (let Some(parsedWhileExpr) <- (parsedExpr as ParsedWhileExpr)) {
        let targetWhileExpr = WhileExpr()
        copyParsedNodeBase(parsedWhileExpr, targetWhileExpr, fallbackFile)
        if (let Some(parsedWhileCond) <- parsedWhileExpr.condExpr) {
            targetWhileExpr.condExpr = Some(convertParsedExpr(parsedWhileCond, fallbackFile))
        }
        if (let Some(parsedWhileBody) <- parsedWhileExpr.body) {
            if (let Some(convertedWhileBody) <- (convertParsedExpr(parsedWhileBody, fallbackFile) as Block)) {
                targetWhileExpr.body = Some(convertedWhileBody)
            }
        }
        return targetWhileExpr
    }
    if (let Some(parsedDoWhileExpr) <- (parsedExpr as ParsedDoWhileExpr)) {
        let targetDoWhileExpr = DoWhileExpr()
        copyParsedNodeBase(parsedDoWhileExpr, targetDoWhileExpr, fallbackFile)
        if (let Some(parsedDoBody) <- parsedDoWhileExpr.body) {
            if (let Some(convertedDoBody) <- (convertParsedExpr(parsedDoBody, fallbackFile) as Block)) {
                targetDoWhileExpr.body = Some(convertedDoBody)
            }
        }
        if (let Some(parsedDoCond) <- parsedDoWhileExpr.condExpr) {
            targetDoWhileExpr.condExpr = Some(convertParsedExpr(parsedDoCond, fallbackFile))
        }
        return targetDoWhileExpr
    }
    if (let Some(parsedForInExpr) <- (parsedExpr as ParsedForInExpr)) {
        let targetForInExpr = ForInExpr()
        copyParsedNodeBase(parsedForInExpr, targetForInExpr, fallbackFile)
        if (let Some(parsedForPattern) <- parsedForInExpr.pattern) {
            targetForInExpr.pattern = Some(convertParsedPattern(parsedForPattern, fallbackFile))
        }
        if (let Some(parsedForInSource) <- parsedForInExpr.inExpr) {
            targetForInExpr.inExpr = Some(convertParsedExpr(parsedForInSource, fallbackFile))
        }
        if (let Some(parsedForGuard) <- parsedForInExpr.patternGuard) {
            targetForInExpr.patternGuard = Some(convertParsedExpr(parsedForGuard, fallbackFile))
        }
        if (let Some(parsedForBody) <- parsedForInExpr.body) {
            if (let Some(convertedForBody) <- (convertParsedExpr(parsedForBody, fallbackFile) as Block)) {
                targetForInExpr.body = Some(convertedForBody)
            }
        }
        return targetForInExpr
    }
    if (let Some(parsedLambdaExpr) <- (parsedExpr as ParsedLambdaExpr)) {
        let targetLambdaExpr = LambdaExpr()
        copyParsedNodeBase(parsedLambdaExpr, targetLambdaExpr, fallbackFile)
        for (parsedLambdaAnno in parsedLambdaExpr.annotations) {
            targetLambdaExpr.annotations.add(convertParsedAnnotation(parsedLambdaAnno, fallbackFile))
        }
        if (let Some(parsedLambdaBody) <- parsedLambdaExpr.funcBody) {
            targetLambdaExpr.funcBody = Some(convertParsedFuncBody(parsedLambdaBody, fallbackFile))
        }
        return targetLambdaExpr
    }
    if (let Some(parsedThrowExpr) <- (parsedExpr as ParsedThrowExpr)) {
        let targetThrowExpr = ThrowExpr(parsedThrowExpr.astKind)
        copyParsedNodeBase(parsedThrowExpr, targetThrowExpr, fallbackFile)
        if (let Some(parsedThrownExpr) <- parsedThrowExpr.expr) {
            targetThrowExpr.expr = Some(convertParsedExpr(parsedThrownExpr, fallbackFile))
        }
        return targetThrowExpr
    }
    if (let Some(parsedPerformExpr) <- (parsedExpr as ParsedPerformExpr)) {
        let targetPerformExpr = PerformExpr()
        copyParsedNodeBase(parsedPerformExpr, targetPerformExpr, fallbackFile)
        if (let Some(parsedPerformedExpr) <- parsedPerformExpr.expr) {
            targetPerformExpr.expr = Some(convertParsedExpr(parsedPerformedExpr, fallbackFile))
        }
        return targetPerformExpr
    }
    if (let Some(parsedResumeExpr) <- (parsedExpr as ParsedResumeExpr)) {
        let targetResumeExpr = ResumeExpr()
        copyParsedNodeBase(parsedResumeExpr, targetResumeExpr, fallbackFile)
        if (let Some(parsedResumeWithExpr) <- parsedResumeExpr.withExpr) {
            targetResumeExpr.withExpr = Some(convertParsedExpr(parsedResumeWithExpr, fallbackFile))
        }
        if (let Some(parsedResumeThrowExpr) <- parsedResumeExpr.throwingExpr) {
            targetResumeExpr.throwingExpr = Some(convertParsedExpr(parsedResumeThrowExpr, fallbackFile))
        }
        return targetResumeExpr
    }
    if (let Some(parsedSpawnExpr) <- (parsedExpr as ParsedSpawnExpr)) {
        let targetSpawnExpr = SpawnExpr()
        copyParsedNodeBase(parsedSpawnExpr, targetSpawnExpr, fallbackFile)
        if (let Some(parsedSpawnArgExpr) <- parsedSpawnExpr.arg) {
            targetSpawnExpr.arg = Some(convertParsedExpr(parsedSpawnArgExpr, fallbackFile))
        }
        if (let Some(parsedSpawnTaskExpr) <- parsedSpawnExpr.task) {
            targetSpawnExpr.task = Some(convertParsedExpr(parsedSpawnTaskExpr, fallbackFile))
        }
        return targetSpawnExpr
    }
    if (let Some(parsedSynchronizedExpr) <- (parsedExpr as ParsedSynchronizedExpr)) {
        let targetSynchronizedExpr = SynchronizedExpr()
        copyParsedNodeBase(parsedSynchronizedExpr, targetSynchronizedExpr, fallbackFile)
        if (let Some(parsedMutexExpr) <- parsedSynchronizedExpr.mutex) {
            targetSynchronizedExpr.mutex = Some(convertParsedExpr(parsedMutexExpr, fallbackFile))
        }
        if (let Some(parsedSyncBody) <- parsedSynchronizedExpr.body) {
            if (let Some(convertedSyncBody) <- (convertParsedExpr(parsedSyncBody, fallbackFile) as Block)) {
                targetSynchronizedExpr.body = Some(convertedSyncBody)
            }
        }
        return targetSynchronizedExpr
    }
    if (let Some(parsedTrailingClosureExpr) <- (parsedExpr as ParsedTrailingClosureExpr)) {
        let targetTrailingClosureExpr = TrailingClosureExpr()
        copyParsedNodeBase(parsedTrailingClosureExpr, targetTrailingClosureExpr, fallbackFile)
        if (let Some(parsedTrailingBaseExpr) <- parsedTrailingClosureExpr.expr) {
            targetTrailingClosureExpr.expr = Some(convertParsedExpr(parsedTrailingBaseExpr, fallbackFile))
        }
        if (let Some(parsedTrailingLambda) <- parsedTrailingClosureExpr.lambda) {
            if (let Some(convertedTrailingLambda) <- (convertParsedExpr(parsedTrailingLambda, fallbackFile) as LambdaExpr)) {
                targetTrailingClosureExpr.lambda = Some(convertedTrailingLambda)
            }
        }
        return targetTrailingClosureExpr
    }
    if (let Some(parsedInterpolationExpr) <- (parsedExpr as ParsedInterpolationExpr)) {
        let targetInterpolationExpr = InterpolationExpr()
        copyParsedNodeBase(parsedInterpolationExpr, targetInterpolationExpr, fallbackFile)
        if (let Some(parsedInterpolationBlock) <- parsedInterpolationExpr.block) {
            if (let Some(convertedInterpolationBlock) <- (convertParsedExpr(parsedInterpolationBlock, fallbackFile) as Block)) {
                targetInterpolationExpr.block = Some(convertedInterpolationBlock)
            }
        }
        return targetInterpolationExpr
    }
    if (let Some(parsedStringInterpolationExpr) <- (parsedExpr as ParsedStrInterpolationExpr)) {
        let targetStringInterpolationExpr = StrInterpolationExpr()
        copyParsedNodeBase(parsedStringInterpolationExpr, targetStringInterpolationExpr, fallbackFile)
        for (parsedPartExpr in parsedStringInterpolationExpr.strPartExprs) {
            targetStringInterpolationExpr.strPartExprs.add(convertParsedExpr(parsedPartExpr, fallbackFile))
        }
        return targetStringInterpolationExpr
    }
    if (let Some(parsedIsExpr) <- (parsedExpr as ParsedIsExpr)) {
        let targetIsExpr = IsExpr()
        copyParsedNodeBase(parsedIsExpr, targetIsExpr, fallbackFile)
        if (let Some(parsedIsLeftExpr) <- parsedIsExpr.leftExpr) {
            targetIsExpr.leftExpr = Some(convertParsedExpr(parsedIsLeftExpr, fallbackFile))
        }
        if (let Some(parsedIsTypeNode) <- parsedIsExpr.typeNode) {
            targetIsExpr.isType = Some(convertParsedType(parsedIsTypeNode, fallbackFile))
        }
        return targetIsExpr
    }
    if (let Some(parsedAsExpr) <- (parsedExpr as ParsedAsExpr)) {
        let targetAsExpr = AsExpr()
        copyParsedNodeBase(parsedAsExpr, targetAsExpr, fallbackFile)
        if (let Some(parsedAsLeftExpr) <- parsedAsExpr.leftExpr) {
            targetAsExpr.leftExpr = Some(convertParsedExpr(parsedAsLeftExpr, fallbackFile))
        }
        if (let Some(parsedAsTypeNode) <- parsedAsExpr.typeNode) {
            targetAsExpr.asType = Some(convertParsedType(parsedAsTypeNode, fallbackFile))
        }
        return targetAsExpr
    }
    if (let Some(parsedRangeExpr) <- (parsedExpr as ParsedRangeExpr)) {
        let targetRangeExpr = RangeExpr()
        copyParsedNodeBase(parsedRangeExpr, targetRangeExpr, fallbackFile)
        targetRangeExpr.isClosed = parsedRangeExpr.op.kind == TokenKind.CLOSEDRANGEOP
        if (let Some(parsedRangeStartExpr) <- parsedRangeExpr.leftExpr) {
            targetRangeExpr.startExpr = Some(convertParsedExpr(parsedRangeStartExpr, fallbackFile))
        }
        if (let Some(parsedRangeStopExpr) <- parsedRangeExpr.rightExpr) {
            targetRangeExpr.stopExpr = Some(convertParsedExpr(parsedRangeStopExpr, fallbackFile))
        }
        return targetRangeExpr
    }
    if (let Some(parsedBinaryExpr) <- (parsedExpr as ParsedBinaryExpr)) {
        let targetBinaryExpr = BinaryExpr(parsedBinaryExpr.astKind)
        copyParsedNodeBase(parsedBinaryExpr, targetBinaryExpr, fallbackFile)
        targetBinaryExpr.op = parsedBinaryExpr.op.kind
        if (let Some(parsedLeftExpr) <- parsedBinaryExpr.leftExpr) {
            targetBinaryExpr.leftExpr = Some(convertParsedExpr(parsedLeftExpr, fallbackFile))
        }
        if (let Some(parsedRightExpr) <- parsedBinaryExpr.rightExpr) {
            targetBinaryExpr.rightExpr = Some(convertParsedExpr(parsedRightExpr, fallbackFile))
        }
        return targetBinaryExpr
    }
    let targetExpr = Expr(parsedExpr.astKind)
    copyParsedNodeBase(parsedExpr, targetExpr, fallbackFile)
    return targetExpr
}

private func primitiveTypeKindFromName(typeName: String): TypeKind {
    if (typeName == "Unit") { return TypeKind.TYPE_UNIT }
    if (typeName == "Int8") { return TypeKind.TYPE_INT8 }
    if (typeName == "Int16") { return TypeKind.TYPE_INT16 }
    if (typeName == "Int32") { return TypeKind.TYPE_INT32 }
    if (typeName == "Int64") { return TypeKind.TYPE_INT64 }
    if (typeName == "IntNative") { return TypeKind.TYPE_INT_NATIVE }
    if (typeName == "Int") { return TypeKind.TYPE_IDEAL_INT }
    if (typeName == "UInt8") { return TypeKind.TYPE_UINT8 }
    if (typeName == "UInt16") { return TypeKind.TYPE_UINT16 }
    if (typeName == "UInt32") { return TypeKind.TYPE_UINT32 }
    if (typeName == "UInt64") { return TypeKind.TYPE_UINT64 }
    if (typeName == "UIntNative") { return TypeKind.TYPE_UINT_NATIVE }
    if (typeName == "Float16") { return TypeKind.TYPE_FLOAT16 }
    if (typeName == "Float32") { return TypeKind.TYPE_FLOAT32 }
    if (typeName == "Float64") { return TypeKind.TYPE_FLOAT64 }
    if (typeName == "Float") { return TypeKind.TYPE_IDEAL_FLOAT }
    if (typeName == "Rune") { return TypeKind.TYPE_RUNE }
    if (typeName == "Nothing") { return TypeKind.TYPE_NOTHING }
    if (typeName == "Bool") { return TypeKind.TYPE_BOOLEAN }
    if (typeName == "CString") { return TypeKind.TYPE_CSTRING }
    return TypeKind.TYPE_INVALID
}

private func convertParsedType(parsedType: ParsedType, fallbackFile: Option<File>): Type {
    if (let Some(parsedPrimitive) <- (parsedType as ParsedPrimitiveType)) {
        let targetPrimitive = PrimitiveType(primitiveTypeKindFromName(parsedPrimitive.name))
        copyParsedNodeBase(parsedPrimitive, targetPrimitive, fallbackFile)
        if (TypeKindEquals(targetPrimitive.kind, TypeKind.TYPE_INVALID)) {
            targetPrimitive.name = parsedPrimitive.name
        }
        return targetPrimitive
    }
    if (let Some(parsedReference) <- (parsedType as ParsedRefType)) {
        let targetReference = RefType(parsedReference.identifier.GetRawText())
        copyParsedNodeBase(parsedReference, targetReference, fallbackFile)
        return targetReference
    }
    let targetType = Type()
    copyParsedNodeBase(parsedType, targetType, fallbackFile)
    targetType.name = parsedType.ToString()
    return targetType
}

private func parsedEnumPatternConstructorName(parsedEnumPattern: ParsedEnumPattern): String {
    if (parsedEnumPattern.constructorParts.isEmpty()) {
        return parsedEnumPattern.constructor.GetRawText()
    }
    let builder = StringBuilder()
    var partIdx: Int64 = 0
    while (partIdx < parsedEnumPattern.constructorParts.size) {
        if (partIdx > 0) {
            builder.append(".")
        }
        builder.append(parsedEnumPattern.constructorParts[partIdx].GetRawText())
        partIdx++
    }
    return builder.toString()
}

private func fillTypeListPattern(
    parsedPattern: ParsedPattern,
    targetPattern: TypeListPattern,
    fallbackFile: Option<File>
): Unit {
    if (let Some(parsedExceptPattern) <- (parsedPattern as ParsedExceptTypePattern)) {
        if (let Some(innerPattern) <- parsedExceptPattern.pattern) {
            targetPattern.pattern = Some(convertParsedPattern(innerPattern, fallbackFile))
        }
        for (patternType in parsedExceptPattern.types) {
            targetPattern.types.add(convertParsedType(patternType, fallbackFile))
        }
    } else if (let Some(parsedCommandPattern) <- (parsedPattern as ParsedCommandTypePattern)) {
        if (let Some(innerCommandPattern) <- parsedCommandPattern.pattern) {
            targetPattern.pattern = Some(convertParsedPattern(innerCommandPattern, fallbackFile))
        }
        for (commandType in parsedCommandPattern.types) {
            targetPattern.types.add(convertParsedType(commandType, fallbackFile))
        }
    }
}

private func convertParsedPattern(parsedPattern: ParsedPattern, fallbackFile: Option<File>): Pattern {
    if (let Some(parsedWildcardPattern) <- (parsedPattern as ParsedWildcardPattern)) {
        let targetWildcardPattern = WildcardPattern()
        copyParsedNodeBase(parsedWildcardPattern, targetWildcardPattern, fallbackFile)
        return targetWildcardPattern
    }
    if (let Some(parsedConstPattern) <- (parsedPattern as ParsedConstPattern)) {
        let targetConstPattern = ConstPattern()
        copyParsedNodeBase(parsedConstPattern, targetConstPattern, fallbackFile)
        if (let Some(parsedLiteral) <- parsedConstPattern.literal) {
            targetConstPattern.literal = Some(convertParsedExpr(parsedLiteral, fallbackFile))
        }
        return targetConstPattern
    }
    if (let Some(parsedVarPattern) <- (parsedPattern as ParsedVarPattern)) {
        let targetVarPattern = VarPattern()
        copyParsedNodeBase(parsedVarPattern, targetVarPattern, fallbackFile)
        targetVarPattern.identifier = parsedVarPattern.identifier.GetRawText()
        targetVarPattern.isVar = parsedVarPattern.isVar
        return targetVarPattern
    }
    if (let Some(parsedTuplePattern) <- (parsedPattern as ParsedTuplePattern)) {
        let targetTuplePattern = TuplePattern()
        copyParsedNodeBase(parsedTuplePattern, targetTuplePattern, fallbackFile)
        for (tuplePattern in parsedTuplePattern.patterns) {
            targetTuplePattern.patterns.add(convertParsedPattern(tuplePattern, fallbackFile))
        }
        return targetTuplePattern
    }
    if (let Some(parsedEnumPattern) <- (parsedPattern as ParsedEnumPattern)) {
        let targetEnumPattern = EnumPattern()
        copyParsedNodeBase(parsedEnumPattern, targetEnumPattern, fallbackFile)
        targetEnumPattern.constructor = parsedEnumPatternConstructorName(parsedEnumPattern)
        for (typeArgument in parsedEnumPattern.typeArguments) {
            targetEnumPattern.typeArguments.add(convertParsedType(typeArgument, fallbackFile))
        }
        for (enumInnerPattern in parsedEnumPattern.patterns) {
            targetEnumPattern.patterns.add(convertParsedPattern(enumInnerPattern, fallbackFile))
        }
        return targetEnumPattern
    }
    if (let Some(parsedVarOrEnumPattern) <- (parsedPattern as ParsedVarOrEnumPattern)) {
        let targetVarOrEnumPattern = VarOrEnumPattern()
        copyParsedNodeBase(parsedVarOrEnumPattern, targetVarOrEnumPattern, fallbackFile)
        targetVarOrEnumPattern.identifier = parsedVarOrEnumPattern.identifier.GetRawText()
        return targetVarOrEnumPattern
    }
    if (let Some(parsedTypePattern) <- (parsedPattern as ParsedTypePattern)) {
        let targetTypePattern = TypePattern()
        copyParsedNodeBase(parsedTypePattern, targetTypePattern, fallbackFile)
        if (let Some(innerTypePattern) <- parsedTypePattern.pattern) {
            targetTypePattern.pattern = Some(convertParsedPattern(innerTypePattern, fallbackFile))
        }
        if (let Some(typePatternType) <- parsedTypePattern.typeNode) {
            targetTypePattern.typeNode = Some(convertParsedType(typePatternType, fallbackFile))
        }
        return targetTypePattern
    }
    if (let Some(parsedExceptPattern) <- (parsedPattern as ParsedExceptTypePattern)) {
        let targetExceptPattern = ExceptTypePattern()
        copyParsedNodeBase(parsedExceptPattern, targetExceptPattern, fallbackFile)
        fillTypeListPattern(parsedExceptPattern, targetExceptPattern, fallbackFile)
        return targetExceptPattern
    }
    if (let Some(parsedCommandPattern) <- (parsedPattern as ParsedCommandTypePattern)) {
        let targetCommandPattern = CommandTypePattern()
        copyParsedNodeBase(parsedCommandPattern, targetCommandPattern, fallbackFile)
        fillTypeListPattern(parsedCommandPattern, targetCommandPattern, fallbackFile)
        return targetCommandPattern
    }
    let targetPattern = Pattern()
    copyParsedNodeBase(parsedPattern, targetPattern, fallbackFile)
    return targetPattern
}

private func convertParsedMacroInvocation(
    parsedInvocation: ParsedMacroInvocation,
    fallbackFile: Option<File>
): MacroInvocation {
    let targetInvocation = MacroInvocation()
    targetInvocation.macroCallDiagInfo = parsedInvocation.macroCallDiagInfo
    for (dotPos in parsedInvocation.fullNameDotPos) { targetInvocation.fullNameDotPos.add(dotPos) }
    targetInvocation.leftSquarePos = parsedInvocation.leftSquarePos
    targetInvocation.rightSquarePos = parsedInvocation.rightSquarePos
    targetInvocation.leftParenPos = parsedInvocation.leftParenPos
    targetInvocation.rightParenPos = parsedInvocation.rightParenPos
    targetInvocation.atPos = parsedInvocation.atPos
    targetInvocation.macroNamePos = parsedInvocation.macroNamePos
    for (attrToken in parsedInvocation.attrs) { targetInvocation.attrs.add(attrToken) }
    for (argToken in parsedInvocation.args) { targetInvocation.args.add(argToken) }
    if (let Some(parsedDeclNode) <- parsedInvocation.decl) {
        targetInvocation.decl = Some(convertParsedDecl(parsedDeclNode, fallbackFile))
    }
    if (let Some(parsedTargetDecl) <- parsedInvocation.target) {
        targetInvocation.target = Some(convertParsedDecl(parsedTargetDecl, fallbackFile))
    }
    targetInvocation.outerDeclIdent = parsedInvocation.outerDeclIdent
    for (parsedInvocationNode in parsedInvocation.nodes) {
        targetInvocation.nodes.add(convertParsedNode(parsedInvocationNode, fallbackFile))
    }
    for (macroAtPos in parsedInvocation.macroAtPosition) { targetInvocation.macroAtPosition.add(macroAtPos) }
    for (newToken in parsedInvocation.newTokens) { targetInvocation.newTokens.add(newToken) }
    targetInvocation.newTokensStr = parsedInvocation.newTokensStr
    targetInvocation.scopeKind = toMacroScopeKind(parsedInvocation.scopeKind)
    targetInvocation.exprKind = toMacroExprKind(parsedInvocation.exprKind)
    targetInvocation.hasParenthesis = parsedInvocation.hasParenthesis
    targetInvocation.hasAttr = parsedInvocation.hasAttr
    targetInvocation.isFuncParam = parsedInvocation.isFuncParam
    targetInvocation.isCompileTimeVisible = parsedInvocation.isCompileTimeVisible
    for (debugPair in parsedInvocation.macroDebugMap) { targetInvocation.macroDebugMap.add(debugPair) }
    for (originPair in parsedInvocation.origin2newPosMap) { targetInvocation.origin2newPosMap.add(originPair) }
    return targetInvocation
}

private func convertParsedNode(parsedNode: ParsedNode, fallbackFile: Option<File>): Node {
    if (let Some(parsedDeclNode) <- (parsedNode as ParsedDecl)) {
        return convertParsedDecl(parsedDeclNode, fallbackFile)
    }
    if (let Some(parsedExprNode) <- (parsedNode as ParsedExpr)) {
        return convertParsedExpr(parsedExprNode, fallbackFile)
    }
    if (let Some(parsedTypeNode) <- (parsedNode as ParsedType)) {
        return convertParsedType(parsedTypeNode, fallbackFile)
    }
    if (let Some(parsedPatternNode) <- (parsedNode as ParsedPattern)) {
        return convertParsedPattern(parsedPatternNode, fallbackFile)
    }
    if (let Some(parsedAnnotationNode) <- (parsedNode as ParsedAnnotation)) {
        return convertParsedAnnotation(parsedAnnotationNode, fallbackFile)
    }
    let targetNode = Node(parsedNode.astKind)
    copyParsedNodeBase(parsedNode, targetNode, fallbackFile)
    return targetNode
}

private func findFollowingIdentifier(tokens: ArrayList<Token>, start: Int64): String {
    var idx = start
    while (idx < tokens.size) {
        if (IsIdentifierOrContextualKeyword(tokens[idx].kind)) {
            return tokens[idx].Value()
        }
        idx++
    }
    return ""
}

private func replaceNodeVector(container: ArrayList<Node>, loc: Int64, newNodes: ArrayList<Node>): Unit {
    if (loc < 0 || loc >= container.size) {
        return
    }
    let rebuilt = ArrayList<Node>()
    var idx: Int64 = 0
    while (idx < container.size) {
        if (idx == loc) {
            for (node in newNodes) {
                rebuilt.add(node)
            }
        } else {
            rebuilt.add(container[idx])
        }
        idx++
    }
    container.clear()
    for (node in rebuilt) {
        container.add(node)
    }
}

private func replaceExprVectorWith(container: ArrayList<Expr>, loc: Int64, expr: Expr): Unit {
    let rebuilt = ArrayList<Expr>()
    var idx: Int64 = 0
    while (idx < container.size) {
        if (idx == loc) {
            rebuilt.add(expr)
        } else {
            rebuilt.add(container[idx])
        }
        idx++
    }
    container.clear()
    for (item in rebuilt) {
        container.add(item)
    }
}

private func replaceExprVector(
    container: ArrayList<Expr>,
    loc: Int64,
    newNodes: ArrayList<Node>,
    macroNode: MacroCall,
    diag: DiagnosticEngine
): Unit {
    if (loc < 0 || loc >= container.size) {
        return
    }
    if (newNodes.isEmpty()) {
        emitMacroDiag(diag, macroNode.GetBeginPos(), DiagKind.macro_unexpect_no_expr)
        return
    }
    if (newNodes.size == 1) {
        if (let Some(replacementExpr) <- (newNodes[0] as Expr)) {
            preserveOriginalMacroNode(macroNode, container[loc].curFile)
            replaceExprVectorWith(container, loc, replacementExpr)
            return
        }
    }
    emitMacroDiag(diag, newNodes[newNodes.size - 1].begin, DiagKind.macro_expect_one_expr)
}

private func checkReplacedEnumCaseMember(macroNode: MacroCall, newDecls: ArrayList<Decl>, diag: DiagnosticEngine): Unit {
    let invocation = macroNode.RequireInvocation()
    if (let Some(parent) <- invocation.parent) {
        if (!ASTKindEquals(parent.astKind, ASTKind.ENUM_DECL)) {
            return
        }
        if (macroNode.RequireNode().TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            if (!newDecls.isEmpty() && !newDecls[0].TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                emitMacroDiag(diag, newDecls[0].begin, DiagKind.macro_expect_enum_constructor)
            }
            if (newDecls.size > 1) {
                emitMacroDiag(diag, newDecls[1].begin, DiagKind.macro_expect_one_enum_constructor)
            }
            if (let Some(enumDecl) <- (parent as EnumDecl)) {
                if (ASTKindEquals(newDecls[0].astKind, ASTKind.FUNC_DECL)) {
                    enumDecl.hasArguments = true
                }
                if (let Some(newVarDecl) <- (newDecls[0] as VarDecl)) {
                    if (!newVarDecl.constructorTypes.isEmpty()) {
                        enumDecl.hasArguments = true
                    }
                }
            }
        } else {
            for (decl in newDecls) {
                if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    emitMacroDiagArg(diag, decl.begin, DiagKind.macro_expect_decl_not_enum_constructor,
                        decl.identifier)
                }
            }
        }
    }
}

private func replacementFile(macroNode: MacroCall, fallback: Option<File>): Option<File> {
    if (let Some(file) <- macroNode.RequireNode().curFile) {
        return Some(file)
    }
    return fallback
}

private func preserveOriginalMacroNode(macroNode: MacroCall, fallback: Option<File>): Unit {
    if (let Some(file) <- replacementFile(macroNode, fallback)) {
        file.originalMacroCallNodes.add(macroNode.RequireNode())
    }
}

private func replaceDeclVector(
    container: ArrayList<Decl>,
    loc: Int64,
    newNodes: ArrayList<Node>,
    macroNode: MacroCall,
    diag: DiagnosticEngine
): Unit {
    if (loc < 0 || loc >= container.size) {
        return
    }
    let original = container[loc]
    if (newNodes.isEmpty()) {
        preserveOriginalMacroNode(macroNode, original.curFile)
        replaceDeclVectorWith(container, loc, ArrayList<Decl>())
        return
    }
    let replacements = ArrayList<Decl>()
    for (node in newNodes) {
        if (let Some(decl) <- (node as Decl)) {
            decl.outerDecl = original.outerDecl
            if (decl.curFile.isNone()) {
                decl.curFile = original.curFile
            }
            replacements.add(decl)
        } else {
            emitMacroDiag(diag, node.begin, DiagKind.macro_expect_declaration)
        }
    }
    if (replacements.isEmpty()) {
        return
    }
    checkReplacedEnumCaseMember(macroNode, replacements, diag)
    preserveOriginalMacroNode(macroNode, original.curFile)
    replaceDeclVectorWith(container, loc, replacements)
}

private func replaceDeclVectorWith(container: ArrayList<Decl>, loc: Int64, newDecls: ArrayList<Decl>): Unit {
    let rebuilt = ArrayList<Decl>()
    var idx: Int64 = 0
    while (idx < container.size) {
        if (idx == loc) {
            for (decl in newDecls) {
                rebuilt.add(decl)
            }
        } else {
            rebuilt.add(container[idx])
        }
        idx++
    }
    container.clear()
    for (decl in rebuilt) {
        container.add(decl)
    }
}

private func checkReplacedFuncParamList(
    macroNode: MacroCall,
    params: ArrayList<FuncParam>,
    diag: DiagnosticEngine
): Unit {
    let invocation = macroNode.RequireInvocation()
    if (let Some(parent) <- invocation.parent) {
        if (!ASTKindEquals(parent.astKind, ASTKind.FUNC_PARAM_LIST)) {
            return
        }
        var meetNamedParameter = false
        for (param in params) {
            if (!meetNamedParameter && param.isNamedParam) {
                meetNamedParameter = true
            } else if (meetNamedParameter && !param.isNamedParam) {
                emitMacroDiag(diag, param.begin, DiagKind.macro_named_parameter_after_unnamed)
            }
        }
    }
}

private func replaceParamVector(
    container: ArrayList<FuncParam>,
    loc: Int64,
    newNodes: ArrayList<Node>,
    macroNode: MacroCall,
    diag: DiagnosticEngine
): Unit {
    if (loc < 0 || loc >= container.size) {
        return
    }
    if (newNodes.isEmpty()) {
        emitMacroDiag(diag, macroNode.GetBeginPos(), DiagKind.macro_unexpected_empty_parameter)
        return
    }
    let original = container[loc]
    let replacements = ArrayList<FuncParam>()
    for (node in newNodes) {
        if (let Some(param) <- (node as FuncParam)) {
            param.outerDecl = original.outerDecl
            if (param.curFile.isNone()) {
                param.curFile = original.curFile
            }
            replacements.add(param)
        } else {
            emitMacroDiag(diag, node.begin, DiagKind.macro_expect_declaration)
        }
    }
    if (replacements.isEmpty()) {
        return
    }
    preserveOriginalMacroNode(macroNode, original.curFile)
    replaceParamVectorWith(container, loc, replacements)
    checkReplacedFuncParamList(macroNode, container, diag)
}

private func replaceParamVectorWith(container: ArrayList<FuncParam>, loc: Int64, newParams: ArrayList<FuncParam>): Unit {
    let rebuilt = ArrayList<FuncParam>()
    var idx: Int64 = 0
    while (idx < container.size) {
        if (idx == loc) {
            for (param in newParams) {
                rebuilt.add(param)
            }
        } else {
            rebuilt.add(container[idx])
        }
        idx++
    }
    container.clear()
    for (param in rebuilt) {
        container.add(param)
    }
}

public class MacroExpansion {
    var curPackage: Option<Package> = None
    var ci: CompilerInstance
    var macroCollector: MacroCollector = MacroCollector()
    public let tokensEvalInMacro: ArrayList<String> = ArrayList<String>()

    public init(ci: CompilerInstance) {
        this.ci = ci
    }

    public func Execute(pkg: Package): Unit {
        curPackage = Some(pkg)
        CollectMacros(pkg)
        if (hasNoMacros(macroCollector) || macroCollector.macCalls.isEmpty() ||
            hasDefAndCallInSamePkg(macroCollector, ci.diag) || ci.diag.GetErrorCount() > 0) {
            return
        }
        EvaluateMacros()
        ProcessPackageMacros(this, pkg)
        ReplaceAST(pkg)
    }

    public func Execute(packages: ArrayList<Package>): Unit {
        if (ci.invocation.globalOptions.enableCompileTest) {
            TestEntryConstructor(ci.diag).CheckTestSuite(packages)
        }
        for (pkg in packages) {
            Execute(pkg)
        }
        if (ci.invocation.globalOptions.enableCompileTest && ci.invocation.globalOptions.CompileExecutable()) {
            TestEntryConstructor.ConstructTestSuite(ci.invocation.globalOptions.moduleName, packages,
                ci.importManager.GetAllImportedPackages(), ci.invocation.globalOptions.compileTestsOnly,
                ci.invocation.globalOptions.mock == MockMode.ON)
        }
        for (pkg in packages) {
            AddCurFile(pkg)
            checkUnhandledMacroCall(pkg, ci.diag)
        }
    }

    public func ExpandDecl(decl: Decl): ArrayList<Decl> {
        let result = ArrayList<Decl>()
        if (decl.IsMemberDecl()) {
            return result
        }
        let currentDecls = ArrayList<Decl>()
        currentDecls.add(decl)
        let localCollector = MacroCollector()
        CollectMacroCallsInDecls(currentDecls, localCollector)
        if (localCollector.macCalls.isEmpty()) {
            return currentDecls
        }
        let evaluator = MacroEvaluation(ci, localCollector, ci.invocation.globalOptions.enableMacroInLSP)
        evaluator.Evaluate()
        ProcessMacroCallList(this, localCollector.macCalls)
        ReplaceMacroCallsInDecls(localCollector.macCalls)
        for (currentDecl in currentDecls) {
            result.add(currentDecl)
        }
        return result
    }

    private func CollectMacros(pkg: Package): Unit {
        macroCollector.clear()
        macroCollector.curPkg = Some(pkg)
        for (file in pkg.files) {
            if (!file.hasMacro) {
                continue
            }
            collectMacroEachFile(file, macroCollector)
        }
        sortMacroCalls(macroCollector.macCalls)
        for (pkg in ci.importManager.GetImportedPkgsForMacro()) {
            macroCollector.importedMacroPkgs.add(pkg)
        }
    }

    public func CollectMacroCallsInDecls(currentDecls: ArrayList<Decl>, collector: MacroCollector): Unit {
        var idx: Int64 = 0
        while (idx < currentDecls.size) {
            let currentDecl = currentDecls[idx]
            if (currentDecl.IsMacroCallNode()) {
                let call = MacroCall(currentDecl)
                call.replaceLoc.kind = ReplaceTargetKind.DECL_VECTOR
                call.replaceLoc.loc = idx
                call.replaceLoc.decls = Some(currentDecls)
                call.isOuterMost = true
                collector.macCalls.add(call)
            } else {
                walkNode(currentDecl, { curNode: Node =>
                    UpdateMacroInfo(curNode, collector)
                    return true
                })
            }
            idx++
        }
        sortMacroCalls(collector.macCalls)
    }

    public func ReplaceMacroCallsInDecls(macroCalls: ArrayList<MacroCall>): Unit {
        var idx = macroCalls.size - 1
        while (idx >= 0) {
            ReplaceEachMacro(macroCalls[idx])
            if (idx == 0) {
                break
            }
            idx--
        }
    }

    private func EvaluateMacros(): Unit {
        let evaluator = MacroEvaluation(ci, macroCollector, ci.invocation.globalOptions.enableMacroInLSP)
        evaluator.Evaluate()
        tokensEvalInMacro.clear()
        for (code in evaluator.GetVecOfGeneratedCodes()) {
            tokensEvalInMacro.add(code)
        }
    }

    public func ReplaceAST(pkg: Package): Unit {
        let _ = pkg
        var idx = macroCollector.macCalls.size - 1
        while (idx >= 0) {
            ReplaceEachMacro(macroCollector.macCalls[idx])
            if (idx == 0) {
                break
            }
            idx--
        }
    }

    public func ReplaceEachMacro(macCall: MacroCall): Unit {
        let invocation = macCall.RequireInvocation()
        if (MacroExpandFailed(invocation.newTokens) || macCall.status == MacroEvalStatus.FAIL) {
            return
        }
        let nodes = parseGeneratedNodes(invocation.newTokens, macCall, ci)
        for (node in nodes) {
            if (node.IsInvalid()) {
                return
            }
            if (hasMacroCallInNode(node, ci.diag)) {
                return
            }
            checkWhenAfterMacroExpand(node, ci.diag)
        }
        ReplaceEachMacroHelper(macCall, nodes)
    }

    public func ReplaceEachMacroHelper(macroNode: MacroCall, newNodes: ArrayList<Node>): Unit {
        let target = macroNode.replaceLoc
        if (target.kind == ReplaceTargetKind.EXPR_BOX) {
            if (newNodes.isEmpty()) {
                emitMacroDiag(ci.diag, macroNode.GetBeginPos(), DiagKind.macro_unexpect_no_expr)
            } else if (newNodes.size == 1) {
                if (let Some(replacementExpr) <- (newNodes[0] as Expr)) {
                    if (AssignExprReplacement(target, replacementExpr)) {
                        if (let Some(file) <- macroNode.RequireNode().curFile) {
                            file.originalMacroCallNodes.add(macroNode.RequireNode())
                        }
                    }
                } else {
                    emitMacroDiag(ci.diag, newNodes[0].begin, DiagKind.macro_expect_one_expr)
                }
            } else {
                emitMacroDiag(ci.diag, newNodes[newNodes.size - 1].begin, DiagKind.macro_expect_one_expr)
            }
        } else if (target.kind == ReplaceTargetKind.NODE_VECTOR) {
            if (let Some(nodes) <- target.nodes) {
                preserveOriginalMacroNode(macroNode, macroNode.RequireNode().curFile)
                replaceNodeVector(nodes, target.loc, newNodes)
            }
        } else if (target.kind == ReplaceTargetKind.EXPR_VECTOR) {
            if (let Some(exprs) <- target.exprs) {
                replaceExprVector(exprs, target.loc, newNodes, macroNode, ci.diag)
            }
        } else if (target.kind == ReplaceTargetKind.DECL_VECTOR) {
            if (let Some(decls) <- target.decls) {
                replaceDeclVector(decls, target.loc, newNodes, macroNode, ci.diag)
            }
        } else if (target.kind == ReplaceTargetKind.PARAM_VECTOR) {
            if (let Some(params) <- target.params) {
                replaceParamVector(params, target.loc, newNodes, macroNode, ci.diag)
            }
        } else {
            emitMacroDiag(ci.diag, macroNode.GetBeginPos(), DiagKind.macro_expand_invalid_node_replace)
        }
    }
}
