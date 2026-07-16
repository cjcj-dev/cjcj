package cjcj::macro_pkg

import std.collection.*
import std.sort.*
import cjcj::ast.{Diagnose, DiagnoseRefactor}
import cjcj::ast.AnnotationKind as RealAnnotationKind
import cjcj::ast.ExprKind as ParsedAstExprKind
import cjcj::ast.Node as ParsedAstNode
import cjcj::ast.ScopeKind as ParsedAstScopeKind
import cjcj::ast.VarDecl as ParsedAstVarDecl
import cjcj::ast.VisitAction
import cjcj::ast.Walker
import cjcj::parse.Annotation as ParsedAnnotation
import cjcj::parse.Decl as ParsedDecl
import cjcj::parse.Expr as ParsedExpr
import cjcj::parse.EnumPattern as ParsedEnumPattern
import cjcj::parse.FuncArg as ParsedFuncArg
import cjcj::parse.FuncBody as ParsedFuncBody
import cjcj::parse.FuncDecl as ParsedFuncDecl
import cjcj::parse.FuncParam as ParsedFuncParam
import cjcj::parse.FuncParamList as ParsedFuncParamList
import cjcj::parse.LitConstExpr as ParsedLitConstExpr
import cjcj::parse.LitConstKind as ParsedLitConstKind
import cjcj::parse.MacroInvocation as ParsedMacroInvocation
import cjcj::parse.MatchCase as ParsedMatchCase
import cjcj::parse.MatchCaseOther as ParsedMatchCaseOther
import cjcj::parse.Modifier as ParsedModifier
import cjcj::parse.Node as ParsedNode
import cjcj::parse.Parser as GeneratedParser
import cjcj::parse.Pattern as ParsedPattern
import cjcj::parse.ExprKind as ParsedExprKind
import cjcj::parse.ScopeKind as ParsedScopeKind
import cjcj::parse.StringKind as ParsedStringKind
import cjcj::parse.Type as ParsedType

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
    let walker = Walker(node, visitPre: { curNode: Node =>
        if (visit(curNode)) { VisitAction.WALK_CHILDREN } else { VisitAction.SKIP_CHILDREN }
    })
    let _ = walker.Walk()
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

private func HasMacroCallInNode(node: Node, diag: DiagnosticEngine): Bool {
    let hasMacroCall = Box<Bool>(false)
    walkNode(node, { curNode: Node =>
        if (curNode.IsMacroCallNode()) {
            hasMacroCall.value = true
            if (let Some(invocation) <- curNode.GetInvocation()) {
                Diagnose(diag, node, invocation.macroCallDiagInfo.identifierPos,
                    DiagKind.macro_undeclared_identifier,
                    args: [DiagArgument(invocation.macroCallDiagInfo.identifier)]).Emit()
            }
            return false
        }
        return true
    })
    return hasMacroCall.value
}

private func CheckWhenAfterMacroExpand(node: Node, diag: DiagnosticEngine): Unit {
    walkNode(node, { curNode: Node =>
        if (let Some(decl) <- (curNode as Decl)) {
            for (anno in decl.annotations) {
                if (anno.kind == RealAnnotationKind.WHEN) {
                    DiagnoseRefactor(diag,
                        DiagKindRefactor.conditional_compilation_unexpected_after_macro, anno).Emit()
                }
            }
        }
        return true
    })
}

private func CheckUnhandledMacroCall(pkg: Package, diag: DiagnosticEngine): Unit {
    if (diag.GetErrorCount() > 0) {
        return
    }
    for (file in pkg.files) {
        if (!file.hasMacro) {
            continue
        }
        walkNode(file, { curNode: Node =>
            if (let Some(macroExpr) <- (curNode as MacroExpandExpr)) {
                if (macroExpr.invocation.IsIfAvailable()) {
                    return true
                }
            }
            if (curNode.IsMacroCallNode()) {
                if (let Some(invocation) <- curNode.GetInvocation()) {
                    Diagnose(diag, curNode, invocation.macroCallDiagInfo.identifierPos,
                        DiagKind.macro_undeclared_identifier,
                        args: [DiagArgument(invocation.macroCallDiagInfo.identifier)]).Emit()
                }
                return false
            }
            return true
        })
    }
}

private func ReplaceEachMacroImpl(tokens: ArrayList<Token>, macroNode: MacroCall, ci: MacroHost): ArrayList<Node> {
    let out = ArrayList<Node>()
    if (tokens.isEmpty()) {
        return out
    }
    let generatedParser = GeneratedParser(tokens.toArray(), ci.GetDiag(), ci.GetDiag().GetSourceManager(),
        attachComment: ci.GetGlobalOptions().enableAddCommentToAst,
        parseDeclFile: ci.GetGlobalOptions().compileCjd)
    generatedParser.SetCompileOptions(ci.GetGlobalOptions())
    generatedParser.SetPrimaryDecl(macroNode.RequireInvocation().outerDeclIdent)
    generatedParser.EnableCustomAnno()
    let invocation = macroNode.RequireInvocation()
    let parsedNodes = if (let Some(scopeKind) <- invocation.scopeKind) {
        generatedParser.ParseNodes(toParsedScopeKind(scopeKind), macroNode.RequireNode(),
            modifiers: macroNode.GetModifiers(), annos: macroNode.GetAnnotations())
    } else {
        let parsedExprKind = match (invocation.exprKind.getOrThrow()) {
            case ExprKind.ALL => ParsedExprKind.ALL
            case ExprKind.VAR_INIT => ParsedExprKind.VAR_INIT
            case ExprKind.INDEX_EXPR => ParsedExprKind.INDEX_EXPR
            case ExprKind.IF_COND_EXPR => ParsedExprKind.IF_COND_EXPR
            case ExprKind.WHILE_COND_EXPR => ParsedExprKind.WHILE_COND_EXPR
            case ExprKind.LET_PATTERN => ParsedExprKind.LET_PATTERN
            case ExprKind.LEFT_EXPR => ParsedExprKind.LEFT_EXPR
            case ExprKind.EXPR_IN_TUPLE => ParsedExprKind.EXPR_IN_TUPLE
            case ExprKind.EXPR_IN_IF_COND_TUPLE => ParsedExprKind.EXPR_IN_IF_COND_TUPLE
            case ExprKind.EXPR_IN_WHILE_COND_TUPLE => ParsedExprKind.EXPR_IN_WHILE_COND_TUPLE
            case ExprKind.EXPR_IN_ARRAY => ParsedExprKind.EXPR_IN_ARRAY
            case ExprKind.EXPR_IN_CALLSUFFIX => ParsedExprKind.EXPR_IN_CALLSUFFIX
            case ExprKind.EXPR_IN_ANNOTATION => ParsedExprKind.EXPR_IN_ANNOTATION
            case ExprKind.UNKNOWN_EXPR => ParsedExprKind.UNKNOWN_EXPR
        }
        generatedParser.ParseNodes(parsedExprKind, macroNode.RequireNode(), modifiers: macroNode.GetModifiers(),
            annos: macroNode.GetAnnotations())
    }
    for (parsedNode in parsedNodes) {
        out.add(parsedNode)
    }
    return out
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
    Diagnose(diag, newNodes[newNodes.size - 1], DiagKind.macro_expect_one_expr).Emit()
}

private func checkReplacedEnumCaseMember(macroNode: MacroCall, newDecls: ArrayList<Decl>, diag: DiagnosticEngine): Unit {
    let invocation = macroNode.RequireInvocation()
    if (let Some(parent) <- invocation.parent) {
        if (!ASTKindEquals(parent.astKind, ASTKind.ENUM_DECL)) {
            return
        }
        if (macroNode.RequireNode().TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            if (!newDecls.isEmpty() && !newDecls[0].TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                Diagnose(diag, newDecls[0], DiagKind.macro_expect_enum_constructor).Emit()
            }
            if (newDecls.size > 1) {
                Diagnose(diag, newDecls[1], DiagKind.macro_expect_one_enum_constructor).Emit()
            }
            if (let Some(enumDecl) <- (parent as EnumDecl)) {
                if (ASTKindEquals(newDecls[0].astKind, ASTKind.FUNC_DECL)) {
                    enumDecl.hasArguments = true
                }
            }
        } else {
            for (decl in newDecls) {
                if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    Diagnose(diag, decl, DiagKind.macro_expect_decl_not_enum_constructor,
                        args: [DiagArgument(decl.identifier.GetRawText())]).Emit()
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
            Diagnose(diag, node, DiagKind.macro_expect_declaration).Emit()
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
                Diagnose(diag, param, DiagKind.macro_named_parameter_after_unnamed).Emit()
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
            Diagnose(diag, node, DiagKind.macro_expect_declaration).Emit()
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
            CheckUnhandledMacroCall(pkg, ci.GetDiag())
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
        if (ci.GetDiag().GetErrorCount() != 0u64) {
            ci.GetDiag().EmitCategoryGroup()
        }
    }

    public func ReplaceEachMacro(macCall: MacroCall): Unit {
        let invocation = macCall.RequireInvocation()
        if (MacroExpandFailed(invocation.newTokens) || macCall.status == MacroEvalStatus.FAIL) {
            return
        }
        let nodes = ReplaceEachMacroImpl(invocation.newTokens, macCall, ci)
        for (node in nodes) {
            if (node.IsInvalid()) {
                return
            }
            if (HasMacroCallInNode(node, ci.GetDiag())) {
                return
            }
            CheckWhenAfterMacroExpand(node, ci.GetDiag())
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
                    Diagnose(ci.GetDiag(), newNodes[0], DiagKind.macro_expect_one_expr).Emit()
                }
            } else {
                Diagnose(ci.GetDiag(), newNodes[newNodes.size - 1], DiagKind.macro_expect_one_expr).Emit()
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
