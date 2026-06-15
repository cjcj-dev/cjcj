package cangjie_compiler::ast

public func DefaultVisitFunc(source: Node, target: Node): Unit {
    if (source.begin == target.begin) {
        return
    }
}

public func SetIsClonedSourceCode(source: Node, target: Node): Unit {
    if (source.TestAttr(Attribute.IS_CLONED_SOURCE_CODE)) {
        target.EnableAttr(Attribute.IS_CLONED_SOURCE_CODE)
        return
    }
    target.EnableAttr(Attribute.IS_CLONED_SOURCE_CODE)
}

public func CopyBasicInfo(source: Node, target: Node): Unit {
    target.begin = source.begin
    target.end = source.end
    target.curMacroCall = source.curMacroCall
    target.isInMacroCall = source.isInMacroCall
    target.comments = source.comments
    target.CopyAttrs(source.GetAttrs())
    CopyNodeScopeInfo(target, source)
    if (let Some(ty) <- source.GetTy()) {
        target.SetTy(ty)
    }
}

public func CloneMacroInvocation(source: MacroInvocation): MacroInvocation {
    let target = MacroInvocation()
    target.macroCallDiagInfo = source.macroCallDiagInfo
    for (pos in source.fullNameDotPos) { target.fullNameDotPos.add(pos) }
    target.leftSquarePos = source.leftSquarePos
    target.rightSquarePos = source.rightSquarePos
    target.leftParenPos = source.leftParenPos
    target.rightParenPos = source.rightParenPos
    target.atPos = source.atPos
    target.macroNamePos = source.macroNamePos
    for (token in source.attrs) { target.attrs.add(token) }
    for (token in source.args) { target.args.add(token) }
    target.decl = source.decl
    target.parent = source.parent
    target.target = source.target
    target.outerDeclIdent = source.outerDeclIdent
    for (node in source.nodes) { target.nodes.add(node) }
    for (token in source.newTokens) { target.newTokens.add(token) }
    target.newTokensStr = source.newTokensStr
    target.scopeKind = source.scopeKind
    target.exprKind = source.exprKind
    target.hasParenthesis = source.hasParenthesis
    target.hasAttr = source.hasAttr
    target.isFuncParam = source.isFuncParam
    target.isCompileTimeVisible = source.isCompileTimeVisible
    return target
}

public func CloneGeneric(source: Generic): Generic {
    let target = Generic()
    CopyBasicInfo(source, target)
    target.leftAnglePos = source.leftAnglePos
    target.rightAnglePos = source.rightAnglePos
    for (param in source.typeParameters) {
        if (let Some(cloned) <- (ASTCloner.Clone(param) as GenericParamDecl)) {
            target.typeParameters.add(cloned)
        }
    }
    for (constraint in source.genericConstraints) {
        if (let Some(cloned) <- (ASTCloner.Clone(constraint) as GenericConstraint)) {
            target.genericConstraints.add(cloned)
        }
    }
    return target
}

public class ASTCloner {
    public init() {}

    public static func Clone(node: Node): Node {
        // TODO(selfhost:AST): port the full C++ Clone.cpp deep-copy matrix for every ASTKind.
        let cloned = match (node.astKind) {
            case ASTKind.REF_TYPE => RefType()
            case ASTKind.QUALIFIED_TYPE => QualifiedType()
            case ASTKind.PRIMITIVE_TYPE => PrimitiveType()
            case ASTKind.FUNC_TYPE => FuncType()
            case ASTKind.TUPLE_TYPE => TupleType()
            case ASTKind.REF_EXPR => RefExpr()
            case ASTKind.MEMBER_ACCESS => MemberAccess()
            case ASTKind.CALL_EXPR => CallExpr()
            case ASTKind.LIT_CONST_EXPR => LitConstExpr()
            case ASTKind.BLOCK => Block()
            case ASTKind.VAR_DECL => VarDecl()
            case ASTKind.FUNC_PARAM => FuncParam()
            case ASTKind.FUNC_DECL => FuncDecl()
            case ASTKind.GENERIC => Generic()
            case ASTKind.GENERIC_CONSTRAINT => GenericConstraint()
            case _ => Node(node.astKind)
        }
        CopyBasicInfo(node, cloned)
        return cloned
    }
}
