package cangjie_compiler::macro_pkg

import std.collection.*
import std.sort.*
import cangjie_compiler::ast.AnnotationKind as RealAnnotationKind
import cangjie_compiler::ast.ExprKind as ParsedAstExprKind
import cangjie_compiler::ast.Node as ParsedAstNode
import cangjie_compiler::ast.ScopeKind as ParsedAstScopeKind
import cangjie_compiler::ast.VarDecl as ParsedAstVarDecl
import cangjie_compiler::basic.DiagCategory as ParsedDiagCategory
import cangjie_compiler::basic.DiagnosticEngine as ParsedDiagnosticEngine
import cangjie_compiler::parse.Annotation as ParsedAnnotation
import cangjie_compiler::parse.Decl as ParsedDecl
import cangjie_compiler::parse.Expr as ParsedExpr
import cangjie_compiler::parse.EnumPattern as ParsedEnumPattern
import cangjie_compiler::parse.FuncArg as ParsedFuncArg
import cangjie_compiler::parse.FuncBody as ParsedFuncBody
import cangjie_compiler::parse.FuncDecl as ParsedFuncDecl
import cangjie_compiler::parse.FuncParam as ParsedFuncParam
import cangjie_compiler::parse.FuncParamList as ParsedFuncParamList
import cangjie_compiler::parse.LitConstExpr as ParsedLitConstExpr
import cangjie_compiler::parse.LitConstKind as ParsedLitConstKind
import cangjie_compiler::parse.MacroInvocation as ParsedMacroInvocation
import cangjie_compiler::parse.MatchCase as ParsedMatchCase
import cangjie_compiler::parse.MatchCaseOther as ParsedMatchCaseOther
import cangjie_compiler::parse.Modifier as ParsedModifier
import cangjie_compiler::parse.Node as ParsedNode
import cangjie_compiler::parse.Parser as GeneratedParser
import cangjie_compiler::parse.Pattern as ParsedPattern
import cangjie_compiler::parse.ScopeKind as ParsedScopeKind
import cangjie_compiler::parse.StringKind as ParsedStringKind
import cangjie_compiler::parse.Type as ParsedType

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
        if (let Some(funcBody) <- funcDecl.funcBody) {
            for (list in funcBody.paramLists) {
                walkNode(list, visit)
            }
            if (let Some(body) <- funcBody.body) {
                walkNode(body, visit)
            }
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
    match (anno.kind) {
        case WHEN => return true
        case _ => ()
    }
    return anno.identifier.Val() == "When"
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

private func parseGeneratedNodes(tokens: ArrayList<Token>, macroNode: MacroCall, ci: MacroHost): ArrayList<Node> {
    let out = ArrayList<Node>()
    if (tokens.isEmpty()) {
        return out
    }
    if (ASTKindEquals(macroNode.RequireNode().astKind, ASTKind.MACRO_EXPAND_PARAM)) {
        let firstParamToken = tokens[0]
        let paramNode = FuncParam()
        paramNode.identifier = SrcIdentifier(firstParamToken.Value(), firstParamToken.Begin(), firstParamToken.End(), false)
        paramNode.begin = firstParamToken.Begin()
        paramNode.end = tokens[tokens.size - 1].End()
        paramNode.curFile = macroNode.RequireNode().curFile
        out.add(paramNode)
        return out
    }
    let parserDiag = ParsedDiagnosticEngine()
    let generatedParser = GeneratedParser(tokens.toArray(), parserDiag, ci.GetDiag().GetSourceManager(),
        attachComment: ci.GetGlobalOptions().enableAddCommentToAst,
        parseDeclFile: ci.GetGlobalOptions().compileCjd)
    generatedParser.SetCompileOptions(ci.GetGlobalOptions())
    generatedParser.SetPrimaryDecl(macroNode.RequireInvocation().outerDeclIdent)
    generatedParser.EnableCustomAnno()
    let parsedCurrentMacroCall = makeParsedCurrentMacroCall(macroNode.RequireNode())
    let parsedScope = if (ASTKindEquals(macroNode.RequireNode().astKind, ASTKind.MACRO_EXPAND_EXPR)) {
        ParsedScopeKind.FUNC_BODY
    } else {
        toParsedScopeKind(macroNode.RequireInvocation().scopeKind)
    }
    let parsedNodes = generatedParser.ParseNodes(parsedScope, parsedCurrentMacroCall)
    let hasParseError = parserDiag.GetErrorCount() > 0u64
    forwardParserDiagnostics(parserDiag, ci.GetDiag())
    if (hasParseError) {
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
            fd.identifier = SrcIdentifier(findFollowingIdentifier(tokens, 1))
            fd.begin = first.Begin()
            fd.end = tokens[tokens.size - 1].End()
            fd.curFile = macroNode.RequireNode().curFile
            out.add(fd)
            return out
        }
        if (first.kind == TokenKind.VAR || first.kind == TokenKind.LET || first.kind == TokenKind.CONST) {
            let varDecl = VarDecl()
            varDecl.identifier = SrcIdentifier(findFollowingIdentifier(tokens, 1))
            varDecl.begin = first.Begin()
            varDecl.end = tokens[tokens.size - 1].End()
            varDecl.curFile = macroNode.RequireNode().curFile
            out.add(varDecl)
            return out
        }
        let decl = Decl(ASTKind.DECL)
        decl.identifier = SrcIdentifier(findFollowingIdentifier(tokens, 0))
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
    for (diagnostic in parserDiag.GetCategoryDiagnostic(ParsedDiagCategory.LEX)) {
        diag.HandleDiagnostic(diagnostic)
    }
    for (diagnostic in parserDiag.GetCategoryDiagnostic(ParsedDiagCategory.PARSE)) {
        diag.HandleDiagnostic(diagnostic)
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
    }
}

private func toMacroScopeKind(scope: ParsedAstScopeKind): ScopeKind {
    return match (scope) {
        case ParsedAstScopeKind.TOPLEVEL => ScopeKind.TOPLEVEL
        case ParsedAstScopeKind.CLASS_BODY => ScopeKind.CLASS_BODY
        case ParsedAstScopeKind.INTERFACE_BODY => ScopeKind.INTERFACE_BODY
        case ParsedAstScopeKind.STRUCT_BODY => ScopeKind.STRUCT_BODY
        case ParsedAstScopeKind.EXTEND_BODY => ScopeKind.EXTEND_BODY
        case ParsedAstScopeKind.FUNC_BODY => ScopeKind.FUNC_BODY
        case ParsedAstScopeKind.MACRO_BODY => ScopeKind.MACRO_BODY
        case ParsedAstScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS => ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
        case ParsedAstScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT => ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
        case ParsedAstScopeKind.PROP_MEMBER_SETTER_BODY => ScopeKind.PROP_MEMBER_SETTER_BODY
        case ParsedAstScopeKind.PROP_MEMBER_GETTER_BODY => ScopeKind.PROP_MEMBER_GETTER_BODY
        case ParsedAstScopeKind.ENUM_BODY => ScopeKind.ENUM_BODY
        case ParsedAstScopeKind.ENUM_CONSTRUCTOR => ScopeKind.ENUM_CONSTRUCTOR
        case ParsedAstScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM => ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM
        case ParsedAstScopeKind.MAIN_BODY => ScopeKind.MAIN_BODY
        case ParsedAstScopeKind.UNKNOWN_SCOPE => ScopeKind.UNKNOWN_SCOPE
    }
}

private func toMacroExprKind(kind: ParsedAstExprKind): ExprKind {
    return match (kind) {
        case ParsedAstExprKind.ALL => ExprKind.ALL
        case ParsedAstExprKind.VAR_INIT => ExprKind.VAR_INIT
        case ParsedAstExprKind.INDEX_EXPR => ExprKind.INDEX_EXPR
        case ParsedAstExprKind.IF_COND_EXPR => ExprKind.IF_COND_EXPR
        case ParsedAstExprKind.WHILE_COND_EXPR => ExprKind.WHILE_COND_EXPR
        case ParsedAstExprKind.LET_PATTERN => ExprKind.LET_PATTERN
        case ParsedAstExprKind.LEFT_EXPR => ExprKind.LEFT_EXPR
        case ParsedAstExprKind.EXPR_IN_TUPLE => ExprKind.EXPR_IN_TUPLE
        case ParsedAstExprKind.EXPR_IN_IF_COND_TUPLE => ExprKind.EXPR_IN_IF_COND_TUPLE
        case ParsedAstExprKind.EXPR_IN_WHILE_COND_TUPLE => ExprKind.EXPR_IN_WHILE_COND_TUPLE
        case ParsedAstExprKind.EXPR_IN_ARRAY => ExprKind.EXPR_IN_ARRAY
        case ParsedAstExprKind.EXPR_IN_CALLSUFFIX => ExprKind.EXPR_IN_CALLSUFFIX
        case ParsedAstExprKind.EXPR_IN_ANNOTATION => ExprKind.EXPR_IN_ANNOTATION
        case ParsedAstExprKind.UNKNOWN_EXPR => ExprKind.UNKNOWN_EXPR
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

private func copyParsedAstNodeBase(parsedNode: ParsedAstNode, targetNode: Node, fallbackFile: Option<File>): Unit {
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
    return parsedModifier
}

private func convertParsedAnnotation(parsedAnnotation: ParsedAnnotation, fallbackFile: Option<File>): Annotation {
    return parsedAnnotation
}

private func copyParsedDeclBase(parsedDecl: ParsedDecl, targetDecl: Decl, fallbackFile: Option<File>): Unit {
    copyParsedNodeBase(parsedDecl, targetDecl, fallbackFile)
    targetDecl.identifier = parsedDecl.identifier
    for (parsedModifier in parsedDecl.modifiers) {
        targetDecl.modifiers.add(convertParsedModifier(parsedModifier))
    }
    for (parsedAnnotation in parsedDecl.annotations) {
        targetDecl.annotations.add(convertParsedAnnotation(parsedAnnotation, fallbackFile))
    }
    targetDecl.CopyAttrs(parsedDecl.GetAttrs())
}

private func convertParsedFuncBody(parsedBody: ParsedFuncBody, fallbackFile: Option<File>): FuncBody {
    return parsedBody
}

private func convertParsedFuncParamList(parsedList: ParsedFuncParamList, fallbackFile: Option<File>): FuncParamList {
    return parsedList
}

private func convertParsedFuncParam(parsedParam: ParsedFuncParam, fallbackFile: Option<File>): FuncParam {
    return parsedParam
}

private func convertParsedAstVarDecl(parsedVarDecl: ParsedAstVarDecl, fallbackFile: Option<File>): VarDecl {
    return parsedVarDecl
}

private func convertParsedFuncDecl(parsedFuncDecl: ParsedFuncDecl, fallbackFile: Option<File>): FuncDecl {
    return parsedFuncDecl
}

private func convertParsedDecl(parsedDecl: ParsedDecl, fallbackFile: Option<File>): Decl {
    return parsedDecl
}

private func convertParsedFuncArg(parsedArg: ParsedFuncArg, fallbackFile: Option<File>): FuncArg {
    return parsedArg
}

private func convertParsedMatchCase(parsedCase: ParsedMatchCase, fallbackFile: Option<File>): MatchCase {
    return parsedCase
}

private func convertParsedMatchCaseOther(
    parsedCaseOther: ParsedMatchCaseOther,
    fallbackFile: Option<File>
): MatchCaseOther {
    return parsedCaseOther
}

private func convertParsedExpr(parsedExpr: ParsedExpr, fallbackFile: Option<File>): Expr {
    return parsedExpr
}

private func parsedLitTokenKind(lit: ParsedLitConstExpr): TokenKind {
    return match (lit.kind) {
        case ParsedLitConstKind.INTEGER => TokenKind.INTEGER_LITERAL
        case ParsedLitConstKind.RUNE_BYTE => TokenKind.RUNE_BYTE_LITERAL
        case ParsedLitConstKind.FLOAT => TokenKind.FLOAT_LITERAL
        case ParsedLitConstKind.RUNE => TokenKind.RUNE_LITERAL
        case ParsedLitConstKind.STRING => match (lit.stringKind) {
            case ParsedStringKind.MULTILINE => TokenKind.MULTILINE_STRING
            case ParsedStringKind.MULTILINE_RAW => TokenKind.MULTILINE_RAW_STRING
            case _ => TokenKind.STRING_LITERAL
        }
        case ParsedLitConstKind.JSTRING => TokenKind.JSTRING_LITERAL
        case ParsedLitConstKind.BOOL => TokenKind.BOOL_LITERAL
        case ParsedLitConstKind.UNIT => TokenKind.UNIT_LITERAL
        case ParsedLitConstKind.NONE => TokenKind.ILLEGAL
    }
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
    return parsedType
}

private func parsedEnumPatternConstructorName(parsedEnumPattern: ParsedEnumPattern): String {
    if (let Some(constructor) <- parsedEnumPattern.constructor) {
        return constructor.ToString()
    }
    return ""
}

private func convertParsedPattern(parsedPattern: ParsedPattern, fallbackFile: Option<File>): Pattern {
    return parsedPattern
}

private func convertParsedMacroInvocation(
    parsedInvocation: ParsedMacroInvocation,
    fallbackFile: Option<File>
): MacroInvocation {
    return parsedInvocation
}

private func convertParsedNode(parsedNode: ParsedNode, fallbackFile: Option<File>): Node {
    return parsedNode
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
            }
        } else {
            for (decl in newDecls) {
                if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    emitMacroDiagArg(diag, decl.begin, DiagKind.macro_expect_decl_not_enum_constructor,
                        decl.identifier.GetRawText())
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
    var ci: MacroHost
    var macroCollector: MacroCollector = MacroCollector()
    public let tokensEvalInMacro: ArrayList<String> = ArrayList<String>()

    public init(ci: MacroHost) {
        this.ci = ci
    }

    public func Execute(pkg: Package): Unit {
        curPackage = Some(pkg)
        CollectMacros(pkg)
        if (hasNoMacros(macroCollector) || macroCollector.macCalls.isEmpty() ||
            hasDefAndCallInSamePkg(macroCollector, ci.GetDiag()) || ci.GetDiag().GetErrorCount() > 0) {
            return
        }
        EvaluateMacros()
        ProcessPackageMacros(this, pkg)
        ReplaceAST(pkg)
    }

    public func Execute(packages: ArrayList<Package>): Unit {
        if (ci.GetGlobalOptions().enableCompileTest) {
            TestEntryConstructor(ci.GetDiag()).CheckTestSuite(packages)
        }
        for (pkg in packages) {
            Execute(pkg)
        }
        if (ci.GetGlobalOptions().enableCompileTest && ci.GetGlobalOptions().CompileExecutable()) {
            TestEntryConstructor.ConstructTestSuite(ci.GetGlobalOptions().moduleName, packages,
                ci.importManager.GetAllImportedPackages(true), ci.GetGlobalOptions().compileTestsOnly,
                ci.GetGlobalOptions().mock == MockMode.ON)
        }
        for (pkg in packages) {
            AddCurFile(pkg)
            checkUnhandledMacroCall(pkg, ci.GetDiag())
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
        let evaluator = MacroEvaluation(ci, localCollector, ci.GetGlobalOptions().enableMacroInLSP)
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
        let evaluator = MacroEvaluation(ci, macroCollector, ci.GetGlobalOptions().enableMacroInLSP)
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
            if (hasMacroCallInNode(node, ci.GetDiag())) {
                return
            }
            checkWhenAfterMacroExpand(node, ci.GetDiag())
        }
        ReplaceEachMacroHelper(macCall, nodes)
    }

    public func ReplaceEachMacroHelper(macroNode: MacroCall, newNodes: ArrayList<Node>): Unit {
        let target = macroNode.replaceLoc
        if (target.kind == ReplaceTargetKind.EXPR_BOX) {
            if (newNodes.isEmpty()) {
                emitMacroDiag(ci.GetDiag(), macroNode.GetBeginPos(), DiagKind.macro_unexpect_no_expr)
            } else if (newNodes.size == 1) {
                if (let Some(replacementExpr) <- (newNodes[0] as Expr)) {
                    if (AssignExprReplacement(target, replacementExpr)) {
                        if (let Some(file) <- macroNode.RequireNode().curFile) {
                            file.originalMacroCallNodes.add(macroNode.RequireNode())
                        }
                    }
                } else {
                    emitMacroDiag(ci.GetDiag(), newNodes[0].begin, DiagKind.macro_expect_one_expr)
                }
            } else {
                emitMacroDiag(ci.GetDiag(), newNodes[newNodes.size - 1].begin, DiagKind.macro_expect_one_expr)
            }
        } else if (target.kind == ReplaceTargetKind.NODE_VECTOR) {
            if (let Some(nodes) <- target.nodes) {
                preserveOriginalMacroNode(macroNode, macroNode.RequireNode().curFile)
                replaceNodeVector(nodes, target.loc, newNodes)
            }
        } else if (target.kind == ReplaceTargetKind.EXPR_VECTOR) {
            if (let Some(exprs) <- target.exprs) {
                replaceExprVector(exprs, target.loc, newNodes, macroNode, ci.GetDiag())
            }
        } else if (target.kind == ReplaceTargetKind.DECL_VECTOR) {
            if (let Some(decls) <- target.decls) {
                replaceDeclVector(decls, target.loc, newNodes, macroNode, ci.GetDiag())
            }
        } else if (target.kind == ReplaceTargetKind.PARAM_VECTOR) {
            if (let Some(params) <- target.params) {
                replaceParamVector(params, target.loc, newNodes, macroNode, ci.GetDiag())
            }
        } else {
            emitMacroDiag(ci.GetDiag(), macroNode.GetBeginPos(), DiagKind.macro_expand_invalid_node_replace)
        }
    }
}
