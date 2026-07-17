package cjcj::ast

import std.collection.*

public func DefaultVisitFunc(source: Node, target: Node): Unit {
    let _ = source
    let _ = target
}

public func SetIsClonedSourceCode(source: Node, target: Node): Unit {
    let _ = source
    target.EnableAttr(Attribute.IS_CLONED_SOURCE_CODE)
}

private func cloneIdentifier(source: Identifier): Identifier {
    return Identifier(source.Val(), source.Begin(), source.End())
}

private func cloneSrcIdentifier(source: SrcIdentifier): SrcIdentifier {
    return SrcIdentifier(source.Val(), source.Begin(), source.End(), source.IsRaw())
}

private func cloneComment(source: Comment): Comment {
    return Comment(source.style, source.kind, source.info)
}

private func cloneCommentGroup(source: CommentGroup): CommentGroup {
    let target = CommentGroup()
    for (comment in source.cms) {
        target.cms.add(cloneComment(comment))
    }
    return target
}

private func cloneCommentGroups(source: CommentGroups): CommentGroups {
    let target = CommentGroups()
    for (group in source.leadingComments) {
        target.leadingComments.add(cloneCommentGroup(group))
    }
    for (group in source.innerComments) {
        target.innerComments.add(cloneCommentGroup(group))
    }
    for (group in source.trailingComments) {
        target.trailingComments.add(cloneCommentGroup(group))
    }
    return target
}

public func CopyBasicInfo(source: Node, target: Node): Unit {
    target.begin = source.begin
    target.end = source.end
    target.curMacroCall = source.curMacroCall
    target.isInMacroCall = source.isInMacroCall
    target.comments = cloneCommentGroups(source.comments)
    CopyNodeScopeInfo(target, source)
}

// This function should be called in each node which inherit Node directly (the AST clone path).
// Unlike CopyBasicInfo it also carries the sema type and attributes, mirroring C++ AST/Clone.cpp:86-95
// CopyNodeField (private to the cloner).
func CopyNodeField(source: Node, target: Node): Unit {
    target.begin = source.begin
    target.end = source.end
    target.SetTy(source.GetTy().getOrThrow())
    target.curMacroCall = source.curMacroCall
    target.isInMacroCall = source.isInMacroCall
    target.comments = cloneCommentGroups(source.comments)
    CopyNodeScopeInfo(target, source)
    target.CopyAttrs(source.GetAttrs())
}

public func CloneMacroInvocation(source: MacroInvocation): MacroInvocation {
    let target = MacroInvocation()
    target.macroCallDiagInfo.fullName = source.macroCallDiagInfo.fullName
    for (pos in source.fullNameDotPos) { target.fullNameDotPos.add(pos) }
    target.macroCallDiagInfo.identifier = source.macroCallDiagInfo.identifier
    target.macroCallDiagInfo.identifierPos = source.macroCallDiagInfo.identifierPos
    target.leftSquarePos = source.leftSquarePos
    for (token in source.attrs) { target.attrs.add(token) }
    target.rightSquarePos = source.rightSquarePos
    target.leftParenPos = source.leftParenPos
    for (token in source.args) { target.args.add(token) }
    target.rightParenPos = source.rightParenPos
    for (token in source.newTokens) { target.newTokens.add(token) }
    target.newTokensStr = source.newTokensStr
    target.parent = source.parent
    target.scopeKind = source.scopeKind
    target.exprKind = source.exprKind
    return target
}

public func CloneGeneric(source: Generic): Generic {
    return CloneGeneric(source, DefaultVisitFunc)
}

public func CloneGeneric(source: Generic, visitFunc: (Node, Node) -> Unit): Generic {
    let target = Generic()
    for (typeParameter in source.typeParameters) {
        if (let Some(cloned) <- (ASTCloner.Clone(typeParameter, visitFunc) as GenericParamDecl)) {
            target.typeParameters.add(cloned)
        }
    }
    for (genericConstraint in source.genericConstraints) {
        if (let Some(cloned) <- (ASTCloner.Clone(genericConstraint, visitFunc) as GenericConstraint)) {
            target.genericConstraints.add(cloned)
        }
    }
    target.leftAnglePos = source.leftAnglePos
    target.rightAnglePos = source.rightAnglePos
    return target
}

public class ASTCloner {
    private var targetAddr2targetAddr: ArrayList<(Node, (Node) -> Unit)> = ArrayList<(Node, (Node) -> Unit)>()
    private var source2cloned: HashMap<Node, Node> = HashMap<Node, Node>()

    public init() {}

    public static func Clone(node: Node): Node {
        return ASTCloner().CloneWithRearrange(node, DefaultVisitFunc)
    }

    public static func Clone(node: Node, visitFunc: (Node, Node) -> Unit): Node {
        return ASTCloner().CloneWithRearrange(node, visitFunc)
    }

    private func TargetAddrMapInsert(from: Option<Node>, target: (Node) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, target))
        }
    }

    private func TargetAddrMapInsert(from: Option<Decl>, target: (Decl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as Decl).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Decl, target: (Decl) -> Unit): Unit {
        targetAddr2targetAddr.add((from, { cloned: Node => target((cloned as Decl).getOrThrow()) }))
    }

    private func TargetAddrMapInsert(from: Option<FuncDecl>, target: (FuncDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as FuncDecl).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<PropDecl>, target: (PropDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as PropDecl).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<Expr>, target: (Expr) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as Expr).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<Pattern>, target: (Pattern) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as Pattern).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<FuncBody>, target: (FuncBody) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as FuncBody).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<ClassLikeDecl>, target: (ClassLikeDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as ClassLikeDecl).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<StructDecl>, target: (StructDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as StructDecl).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<EnumDecl>, target: (EnumDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as EnumDecl).getOrThrow()) }))
        }
    }

    private static func CloneNode(node: Node, visitFunc: (Node, Node) -> Unit): Node {
        if (let Some(typeNode) <- (node as Type)) {
            let target = CloneType(typeNode, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(expr) <- (node as Expr)) {
            let target = CloneExpr(expr, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(decl) <- (node as Decl)) {
            let target = CloneDecl(decl, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(pattern) <- (node as Pattern)) {
            let target = ClonePattern(pattern, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(classBody) <- (node as ClassBody)) {
            let target = CloneClassBody(classBody, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(structBody) <- (node as StructBody)) {
            let target = CloneStructBody(structBody, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(interfaceBody) <- (node as InterfaceBody)) {
            let target = CloneInterfaceBody(interfaceBody, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(genericConstraint) <- (node as GenericConstraint)) {
            let target = CloneGenericConstraint(genericConstraint, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(funcBody) <- (node as FuncBody)) {
            let target = CloneFuncBody(funcBody, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(funcParamList) <- (node as FuncParamList)) {
            let target = CloneFuncParamList(funcParamList, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(funcArg) <- (node as FuncArg)) {
            let target = CloneFuncArg(funcArg, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(matchCase) <- (node as MatchCase)) {
            let target = CloneMatchCase(matchCase, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(matchCaseOther) <- (node as MatchCaseOther)) {
            let target = CloneMatchCaseOther(matchCaseOther, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(annotation) <- (node as Annotation)) {
            let target = CloneAnnotation(annotation, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        if (let Some(importSpec) <- (node as ImportSpec)) {
            let target = CloneImportSpec(importSpec, visitFunc)
            visitFunc(node, target)
            target.EnableAttr(Attribute.COMPILER_ADD)
            return target
        }
        let target = makeNode(node)
        CopyNodeField(node, target)
        copyCommon(node, target, visitFunc)
        copySpecific(node, target, visitFunc)
        visitFunc(node, target)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private func CloneWithRearrange(node: Node, visitFunc: (Node, Node) -> Unit): Node {
        let collectMap = { from: Node, target: Node =>
            if (let Some(sourceDecl) <- (from as Decl)) {
                if (let Some(targetDecl) <- (target as Decl)) {
                    source2cloned[sourceDecl] = targetDecl
                    TargetAddrMapInsert(sourceDecl.outerDecl, { value: Decl => targetDecl.outerDecl = value })
                    TargetAddrMapInsert(sourceDecl.genericDecl, { value: Decl => targetDecl.genericDecl = value })
                }
            }
            if (let Some(sourceExpr) <- (from as Expr)) {
                if (let Some(targetExpr) <- (target as Expr)) {
                    source2cloned[sourceExpr] = targetExpr
                    TargetAddrMapInsert(sourceExpr.sourceExpr, { value: Expr => targetExpr.sourceExpr = value })
                    TargetAddrMapInsert(sourceExpr.mapExpr, { value: Expr => targetExpr.mapExpr = value })
                }
            }
            if (let Some(sourceBody) <- (from as FuncBody)) {
                if (let Some(targetBody) <- (target as FuncBody)) {
                    source2cloned[sourceBody] = targetBody
                    TargetAddrMapInsert(sourceBody.funcDecl, { value: FuncDecl => targetBody.funcDecl = value })
                    TargetAddrMapInsert(sourceBody.outerFunc, { value: FuncBody => targetBody.outerFunc = value })
                    TargetAddrMapInsert(sourceBody.parentClassLike,
                        { value: ClassLikeDecl => targetBody.parentClassLike = value })
                    TargetAddrMapInsert(sourceBody.parentStruct, { value: StructDecl => targetBody.parentStruct = value })
                    TargetAddrMapInsert(sourceBody.parentEnum, { value: EnumDecl => targetBody.parentEnum = value })
                }
            }
            if (let Some(sourcePattern) <- (from as Pattern)) {
                if (let Some(targetPattern) <- (target as Pattern)) {
                    source2cloned[sourcePattern] = targetPattern
                    TargetAddrMapInsert(sourcePattern.ctxExpr, { value: Expr => targetPattern.ctxExpr = value })
                }
            }
            match (from.astKind) {
                case ASTKind.REF_EXPR =>
                let sourceRefExpr = (from as RefExpr).getOrThrow()
                let targetRefExpr = (target as RefExpr).getOrThrow()
                TargetAddrMapInsert(sourceRefExpr.ref.target, { value: Decl => targetRefExpr.ref.target = value })
                TargetAddrMapInsert(sourceRefExpr.callOrPattern,
                    { value: Node => targetRefExpr.callOrPattern = value })
            case ASTKind.ARRAY_EXPR =>
                let sourceArrayExpr = (from as ArrayExpr).getOrThrow()
                let targetArrayExpr = (target as ArrayExpr).getOrThrow()
                TargetAddrMapInsert(sourceArrayExpr.initFunc,
                    { value: FuncDecl => targetArrayExpr.initFunc = value })
            case ASTKind.ARRAY_LIT =>
                let sourceArrayLit = (from as ArrayLit).getOrThrow()
                let targetArrayLit = (target as ArrayLit).getOrThrow()
                TargetAddrMapInsert(sourceArrayLit.initFunc, { value: FuncDecl => targetArrayLit.initFunc = value })
            case ASTKind.MEMBER_ACCESS =>
                let sourceMember = (from as MemberAccess).getOrThrow()
                if (let Some(baseExpr) <- sourceMember.baseExpr) {
                    if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                        if (refExpr.isThis) {
                            let targetMember = (target as MemberAccess).getOrThrow()
                            TargetAddrMapInsert(sourceMember.target,
                                { value: Decl => targetMember.target = value })
                            TargetAddrMapInsert(sourceMember.callOrPattern,
                                { value: Node => targetMember.callOrPattern = value })
                            var idx: Int64 = 0
                            while (idx < sourceMember.targets.size) {
                                let targetIdx = idx
                                TargetAddrMapInsert(sourceMember.targets[targetIdx],
                                    { value: FuncDecl => targetMember.targets[targetIdx] = Some(value) })
                                idx++
                            }
                        }
                    }
                }
            case ASTKind.FOR_IN_EXPR =>
                let sourceForIn = (from as ForInExpr).getOrThrow()
                let targetForIn = (target as ForInExpr).getOrThrow()
                TargetAddrMapInsert(sourceForIn.patternInDesugarExpr,
                    { value: Pattern => targetForIn.patternInDesugarExpr = value })
            case ASTKind.CALL_EXPR =>
                let sourceCall = (from as CallExpr).getOrThrow()
                var targetNeedsRearrange = true
                if (let Some(baseFunc) <- sourceCall.baseFunc) {
                    if (let Some(member) <- (baseFunc as MemberAccess)) {
                        targetNeedsRearrange = false
                        if (let Some(baseExpr) <- member.baseExpr) {
                            if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                                targetNeedsRearrange = refExpr.isThis
                            }
                        }
                    }
                }
                if (targetNeedsRearrange) {
                    let targetCall = (target as CallExpr).getOrThrow()
                    TargetAddrMapInsert(sourceCall.resolvedFunction,
                        { value: FuncDecl => targetCall.resolvedFunction = value })
                }
            case ASTKind.RETURN_EXPR =>
                let sourceReturn = (from as ReturnExpr).getOrThrow()
                let targetReturn = (target as ReturnExpr).getOrThrow()
                TargetAddrMapInsert(sourceReturn.refFuncBody,
                    { value: FuncBody => targetReturn.refFuncBody = value })
            case ASTKind.JUMP_EXPR =>
                let sourceJump = (from as JumpExpr).getOrThrow()
                let targetJump = (target as JumpExpr).getOrThrow()
                TargetAddrMapInsert(sourceJump.refLoop, { value: Expr => targetJump.refLoop = value })
            case ASTKind.REF_TYPE =>
                let sourceRefType = (from as RefType).getOrThrow()
                let targetRefType = (target as RefType).getOrThrow()
                TargetAddrMapInsert(sourceRefType.ref.target, { value: Decl => targetRefType.ref.target = value })
            case ASTKind.QUALIFIED_TYPE =>
                let sourceQualified = (from as QualifiedType).getOrThrow()
                let targetQualified = (target as QualifiedType).getOrThrow()
                TargetAddrMapInsert(sourceQualified.target, { value: Decl => targetQualified.target = value })
            case ASTKind.FUNC_DECL =>
                let sourceFuncDecl = (from as FuncDecl).getOrThrow()
                let targetFuncDecl = (target as FuncDecl).getOrThrow()
                TargetAddrMapInsert(sourceFuncDecl.ownerFunc,
                    { value: FuncDecl => targetFuncDecl.ownerFunc = value })
                TargetAddrMapInsert(sourceFuncDecl.propDecl, { value: PropDecl => targetFuncDecl.propDecl = value })
            case ASTKind.VAR_DECL =>
                let sourceVarDecl = (from as VarDecl).getOrThrow()
                let targetVarDecl = (target as VarDecl).getOrThrow()
                TargetAddrMapInsert(sourceVarDecl.parentPattern,
                    { value: Pattern => targetVarDecl.parentPattern = value })
            case _ => ()
        }
            visitFunc(from, target)
        }
        let targetNode = ASTCloner.CloneNode(node, collectMap)
        for ((source, targetAddr) in targetAddr2targetAddr) {
            if (let Some(cloned) <- source2cloned.get(source)) {
                targetAddr(cloned)
            }
        }
        return targetNode
    }

    private static func cloneExpr(node: Option<Expr>, visitFunc: (Node, Node) -> Unit): Option<Expr> {
        if (let Some(value) <- node) {
            return CloneExpr(value, visitFunc)
        }
        return None
    }

    private static func cloneType(node: Option<Type>, visitFunc: (Node, Node) -> Unit): Option<Type> {
        if (let Some(value) <- node) {
            return CloneNode(value, visitFunc) as Type
        }
        return None
    }

    private static func clonePattern(node: Option<Pattern>, visitFunc: (Node, Node) -> Unit): Option<Pattern> {
        if (let Some(value) <- node) {
            return CloneNode(value, visitFunc) as Pattern
        }
        return None
    }

    private static func cloneBlock(node: Option<Block>, visitFunc: (Node, Node) -> Unit): Option<Block> {
        if (let Some(value) <- node) {
            return CloneNode(value, visitFunc) as Block
        }
        return None
    }

    private static func cloneFuncBody(node: Option<FuncBody>, visitFunc: (Node, Node) -> Unit): Option<FuncBody> {
        if (let Some(value) <- node) {
            return CloneNode(value, visitFunc) as FuncBody
        }
        return None
    }

    private static func cloneRefType(node: Option<RefType>, visitFunc: (Node, Node) -> Unit): Option<RefType> {
        if (let Some(value) <- node) {
            return CloneNode(value, visitFunc) as RefType
        }
        return None
    }

    private static func cloneFuncArg(node: Option<FuncArg>, visitFunc: (Node, Node) -> Unit): Option<FuncArg> {
        if (let Some(value) <- node) {
            return CloneNode(value, visitFunc) as FuncArg
        }
        return None
    }

    private static func CloneExpr(node: Option<Expr>, visitFunc: (Node, Node) -> Unit): Option<Expr> {
        if (let Some(value) <- node) {
            return CloneExpr(value, visitFunc)
        }
        return None
    }

    private static func CloneType(node: Option<Type>, visitFunc: (Node, Node) -> Unit): Option<Type> {
        if (let Some(value) <- node) {
            return CloneType(value, visitFunc)
        }
        return None
    }

    private static func CloneType(source: Type, visitFunc: (Node, Node) -> Unit): Type {
        let target: Type = match (source.astKind) {
            case ASTKind.REF_TYPE => CloneRefType((source as RefType).getOrThrow(), visitFunc)
            case ASTKind.PRIMITIVE_TYPE => PrimitiveType()
            case ASTKind.PAREN_TYPE => CloneParenType((source as ParenType).getOrThrow(), visitFunc)
            case ASTKind.QUALIFIED_TYPE => CloneQualifiedType((source as QualifiedType).getOrThrow(), visitFunc)
            case ASTKind.OPTION_TYPE => CloneOptionType((source as OptionType).getOrThrow(), visitFunc)
            case ASTKind.FUNC_TYPE => CloneFuncType((source as FuncType).getOrThrow(), visitFunc)
            case ASTKind.TUPLE_TYPE => CloneTupleType((source as TupleType).getOrThrow(), visitFunc)
            case ASTKind.CONSTANT_TYPE => CloneConstantType((source as ConstantType).getOrThrow(), visitFunc)
            case ASTKind.VARRAY_TYPE => CloneVArrayType((source as VArrayType).getOrThrow(), visitFunc)
            case ASTKind.THIS_TYPE => ThisType(source.begin)
            case ASTKind.INVALID_TYPE => InvalidType(source.begin)
            case _ => Type()
        }
        if (let Some(primitiveSource) <- (source as PrimitiveType)) {
            if (let Some(primitiveTarget) <- (target as PrimitiveType)) {
                primitiveTarget.str = primitiveSource.str
                primitiveTarget.kind = primitiveSource.kind
            }
        }
        target.commaPos = source.commaPos
        target.bitAndPos = source.bitAndPos
        target.typeParameterName = source.typeParameterName
        target.typeParameterNameIsRawId = source.typeParameterNameIsRawId
        target.typePos = source.typePos
        target.colonPos = source.colonPos
        target.aliasTy = source.aliasTy
        CopyNodeField(source, target)
        visitFunc(source, target)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func ClonePattern(node: Option<Pattern>, visitFunc: (Node, Node) -> Unit): Option<Pattern> {
        if (let Some(value) <- node) {
            return ClonePattern(value, visitFunc)
        }
        return None
    }

    private static func ClonePattern(source: Pattern, visitFunc: (Node, Node) -> Unit): Pattern {
        let target: Pattern = match (source.astKind) {
            case ASTKind.CONST_PATTERN => CloneConstPattern((source as ConstPattern).getOrThrow(), visitFunc)
            case ASTKind.WILDCARD_PATTERN => WildcardPattern()
            case ASTKind.VAR_PATTERN => CloneVarPattern((source as VarPattern).getOrThrow(), visitFunc)
            case ASTKind.TUPLE_PATTERN => CloneTuplePattern((source as TuplePattern).getOrThrow(), visitFunc)
            case ASTKind.TYPE_PATTERN => CloneTypePattern((source as TypePattern).getOrThrow(), visitFunc)
            case ASTKind.ENUM_PATTERN => CloneEnumPattern((source as EnumPattern).getOrThrow(), visitFunc)
            case ASTKind.EXCEPT_TYPE_PATTERN =>
                CloneExceptTypePattern((source as ExceptTypePattern).getOrThrow(), visitFunc)
            case ASTKind.COMMAND_TYPE_PATTERN =>
                CloneCommandTypePattern((source as CommandTypePattern).getOrThrow(), visitFunc)
            case ASTKind.VAR_OR_ENUM_PATTERN =>
                CloneVarOrEnumPattern((source as VarOrEnumPattern).getOrThrow(), visitFunc)
            case ASTKind.INVALID_PATTERN => InvalidPattern(source.begin)
            case _ => InvalidPattern()
        }
        CopyNodeField(source, target)
        copyCommon(source, target, visitFunc)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        visitFunc(source, target)
        return target
    }

    private static func CloneDecl(source: Decl, visitFunc: (Node, Node) -> Unit): Decl {
        let target: Decl = match (source.astKind) {
            case ASTKind.GENERIC_PARAM_DECL =>
                CloneGenericParamDecl((source as GenericParamDecl).getOrThrow())
            case ASTKind.PROP_DECL => ClonePropDecl((source as PropDecl).getOrThrow(), visitFunc)
            case ASTKind.VAR_DECL => CloneVarDecl((source as VarDecl).getOrThrow(), visitFunc)
            case ASTKind.FUNC_PARAM => CloneVarDecl((source as VarDecl).getOrThrow(), visitFunc)
            case ASTKind.FUNC_DECL => CloneFuncDecl((source as FuncDecl).getOrThrow(), visitFunc)
            case ASTKind.STRUCT_DECL => CloneStructDecl((source as StructDecl).getOrThrow(), visitFunc)
            case ASTKind.CLASS_DECL => CloneClassDecl((source as ClassDecl).getOrThrow(), visitFunc)
            case ASTKind.INTERFACE_DECL => CloneInterfaceDecl((source as InterfaceDecl).getOrThrow(), visitFunc)
            case ASTKind.ENUM_DECL => CloneEnumDecl((source as EnumDecl).getOrThrow(), visitFunc)
            case ASTKind.PRIMARY_CTOR_DECL => ClonePrimaryCtorDecl((source as PrimaryCtorDecl).getOrThrow(), visitFunc)
            case ASTKind.EXTEND_DECL => CloneExtendDecl((source as ExtendDecl).getOrThrow(), visitFunc)
            case ASTKind.MACRO_EXPAND_DECL => CloneMacroExpandDecl((source as MacroExpandDecl).getOrThrow())
            case ASTKind.VAR_WITH_PATTERN_DECL =>
                CloneVarWithPatternDecl((source as VarWithPatternDecl).getOrThrow(), visitFunc)
            case ASTKind.TYPE_ALIAS_DECL => CloneTypeAliasDecl((source as TypeAliasDecl).getOrThrow(), visitFunc)
            case ASTKind.MACRO_DECL => InvalidDecl(source.begin)
            case ASTKind.MAIN_DECL => InvalidDecl(source.begin)
            case ASTKind.INVALID_DECL => InvalidDecl(source.begin)
            case _ => InvalidDecl(source.begin)
        }
        CopyNodeField(source, target)
        copyCommon(source, target, visitFunc)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        visitFunc(source, target)
        return target
    }

    private static func CloneFuncBody(source: FuncBody, visitFunc: (Node, Node) -> Unit): FuncBody {
        let target = FuncBody()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneBlock(node: Option<Block>, visitFunc: (Node, Node) -> Unit): Option<Block> {
        if (let Some(value) <- node) {
            return CloneBlock(value, visitFunc)
        }
        return None
    }

    private static func CloneFuncArg(source: FuncArg, visitFunc: (Node, Node) -> Unit): FuncArg {
        let target = FuncArg()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneGenericParamDecl(source: GenericParamDecl): Decl {
        let target = GenericParamDecl()
        target.outerDecl = source.outerDecl
        target.commaPos = source.commaPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneFuncParam(source: FuncParam, visitFunc: (Node, Node) -> Unit): VarDecl {
        let _ = source
        let _ = visitFunc
        let target = FuncParam()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneVarWithPatternDecl(source: VarWithPatternDecl, visitFunc: (Node, Node) -> Unit): Decl {
        let _ = source
        let _ = visitFunc
        return VarWithPatternDecl()
    }

    private static func CloneVarDecl(source: VarDecl, visitFunc: (Node, Node) -> Unit): Decl {
        if (let Some(param) <- (source as FuncParam)) {
            return CloneFuncParam(param, visitFunc)
        }
        let _ = visitFunc
        let target = VarDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneFuncDecl(source: FuncDecl, visitFunc: (Node, Node) -> Unit): Decl {
        let _ = source
        let _ = visitFunc
        let target = FuncDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func ClonePrimaryCtorDecl(source: PrimaryCtorDecl, visitFunc: (Node, Node) -> Unit): Decl {
        let _ = source
        let _ = visitFunc
        let target = PrimaryCtorDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func ClonePropDecl(source: PropDecl, visitFunc: (Node, Node) -> Unit): Decl {
        let _ = source
        let _ = visitFunc
        let target = PropDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneExtendDecl(source: ExtendDecl, visitFunc: (Node, Node) -> Unit): Decl {
        let _ = source
        let _ = visitFunc
        let target = ExtendDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneMacroExpandDecl(source: MacroExpandDecl): Decl {
        let _ = source
        let target = MacroExpandDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneStructDecl(source: StructDecl, visitFunc: (Node, Node) -> Unit): Decl {
        let _ = source
        let _ = visitFunc
        let target = StructDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneClassDecl(source: ClassDecl, visitFunc: (Node, Node) -> Unit): Decl {
        let _ = source
        let _ = visitFunc
        let target = ClassDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneInterfaceDecl(source: InterfaceDecl, visitFunc: (Node, Node) -> Unit): Decl {
        let _ = source
        let _ = visitFunc
        let target = InterfaceDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneEnumDecl(source: EnumDecl, visitFunc: (Node, Node) -> Unit): Decl {
        let _ = source
        let _ = visitFunc
        let target = EnumDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneTypeAliasDecl(source: TypeAliasDecl, visitFunc: (Node, Node) -> Unit): Decl {
        let _ = source
        let _ = visitFunc
        let target = TypeAliasDecl()
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneConstPattern(source: ConstPattern, visitFunc: (Node, Node) -> Unit): ConstPattern {
        let _ = source
        let _ = visitFunc
        return ConstPattern()
    }

    private static func CloneVarPattern(source: VarPattern, visitFunc: (Node, Node) -> Unit): VarPattern {
        let _ = source
        let _ = visitFunc
        return VarPattern()
    }

    private static func CloneTuplePattern(source: TuplePattern, visitFunc: (Node, Node) -> Unit): TuplePattern {
        let _ = source
        let _ = visitFunc
        return TuplePattern()
    }

    private static func CloneTypePattern(source: TypePattern, visitFunc: (Node, Node) -> Unit): TypePattern {
        let _ = source
        let _ = visitFunc
        return TypePattern()
    }

    private static func CloneEnumPattern(source: EnumPattern, visitFunc: (Node, Node) -> Unit): EnumPattern {
        let _ = source
        let _ = visitFunc
        return EnumPattern()
    }

    private static func CloneExceptTypePattern(
        source: ExceptTypePattern, visitFunc: (Node, Node) -> Unit): ExceptTypePattern {
        let _ = source
        let _ = visitFunc
        return ExceptTypePattern()
    }

    private static func CloneCommandTypePattern(
        source: CommandTypePattern, visitFunc: (Node, Node) -> Unit): CommandTypePattern {
        let _ = source
        let _ = visitFunc
        return CommandTypePattern()
    }

    private static func CloneVarOrEnumPattern(
        source: VarOrEnumPattern, visitFunc: (Node, Node) -> Unit): VarOrEnumPattern {
        let _ = visitFunc
        let target = VarOrEnumPattern(source.identifier)
        return target
    }

    private static func CloneClassBody(source: ClassBody, visitFunc: (Node, Node) -> Unit): ClassBody {
        let target = ClassBody()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneStructBody(source: StructBody, visitFunc: (Node, Node) -> Unit): StructBody {
        let target = StructBody()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneInterfaceBody(source: InterfaceBody, visitFunc: (Node, Node) -> Unit): InterfaceBody {
        let target = InterfaceBody()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneGenericConstraint(
        source: GenericConstraint, visitFunc: (Node, Node) -> Unit): GenericConstraint {
        let target = GenericConstraint()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneFuncParamList(source: FuncParamList, visitFunc: (Node, Node) -> Unit): FuncParamList {
        let target = FuncParamList()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneAnnotation(source: Annotation, visitFunc: (Node, Node) -> Unit): Annotation {
        let target = Annotation()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        return target
    }

    private static func CloneImportSpec(source: ImportSpec, visitFunc: (Node, Node) -> Unit): ImportSpec {
        let target = ImportSpec()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        return target
    }

    private static func CloneMatchCase(source: MatchCase, visitFunc: (Node, Node) -> Unit): MatchCase {
        let target = MatchCase()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneMatchCaseOther(
        source: MatchCaseOther, visitFunc: (Node, Node) -> Unit): MatchCaseOther {
        let target = MatchCaseOther()
        CopyNodeField(source, target)
        copySpecific(source, target, visitFunc)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneRefType(source: RefType, visitFunc: (Node, Node) -> Unit): RefType {
        let target = RefType()
        CopyNodeField(source, target)
        target.ref = cloneReference(source.ref)
        target.leftAnglePos = source.leftAnglePos
        for (typeArg in source.typeArguments) {
            target.typeArguments.add(CloneType(typeArg, visitFunc))
        }
        target.rightAnglePos = source.rightAnglePos
        target.commaPos = source.commaPos
        target.bitAndPos = source.bitAndPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneQualifiedType(source: QualifiedType, visitFunc: (Node, Node) -> Unit): QualifiedType {
        let target = QualifiedType()
        target.baseType = CloneType(source.baseType, visitFunc)
        target.field = cloneSrcIdentifier(source.field)
        target.target = source.target
        for (typeArg in source.typeArguments) {
            target.typeArguments.add(CloneType(typeArg, visitFunc))
        }
        return target
    }

    private static func CloneParenType(source: ParenType, visitFunc: (Node, Node) -> Unit): ParenType {
        let target = ParenType()
        target.innerType = CloneType(source.innerType, visitFunc)
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func CloneOptionType(source: OptionType, visitFunc: (Node, Node) -> Unit): OptionType {
        let target = OptionType()
        target.componentType = CloneType(source.componentType, visitFunc)
        target.questNum = source.questNum
        for (pos in source.questVector) { target.questVector.add(pos) }
        target.desugarType = if (let Some(desugarType) <- source.desugarType) {
            CloneRefType(desugarType, visitFunc)
        } else {
            None
        }
        return target
    }

    private static func CloneFuncType(source: FuncType, visitFunc: (Node, Node) -> Unit): FuncType {
        let target = FuncType()
        for (paramType in source.paramTypes) {
            target.paramTypes.add(CloneType(paramType, visitFunc))
        }
        target.retType = CloneType(source.retType, visitFunc)
        target.isC = source.isC
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        target.arrowPos = source.arrowPos
        return target
    }

    private static func CloneTupleType(source: TupleType, visitFunc: (Node, Node) -> Unit): TupleType {
        let target = TupleType()
        for (fieldType in source.fieldTypes) {
            target.fieldTypes.add(CloneType(fieldType, visitFunc))
        }
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        for (pos in source.commaPosVector) { target.commaPosVector.add(pos) }
        return target
    }

    private static func CloneConstantType(source: ConstantType, visitFunc: (Node, Node) -> Unit): ConstantType {
        let target = ConstantType()
        target.constantExpr = CloneExpr(source.constantExpr, visitFunc)
        target.dollarPos = source.dollarPos
        return target
    }

    private static func CloneVArrayType(source: VArrayType, visitFunc: (Node, Node) -> Unit): VArrayType {
        let target = VArrayType()
        target.leftAnglePos = source.leftAnglePos
        target.typeArgument = CloneType(source.typeArgument, visitFunc)
        target.constantType = CloneType(source.constantType, visitFunc)
        target.rightAnglePos = source.rightAnglePos
        return target
    }

    private static func CloneIfExpr(source: IfExpr, visitFunc: (Node, Node) -> Unit): IfExpr {
        let target = IfExpr()
        target.ifPos = source.ifPos
        target.leftParenPos = source.leftParenPos
        target.condExpr = CloneExpr(source.condExpr, visitFunc)
        target.rightParenPos = source.rightParenPos
        if (let Some(thenBody) <- source.thenBody) {
            target.thenBody = CloneExpr(thenBody, visitFunc) as Block
        }
        target.hasElse = source.hasElse
        target.isElseIf = source.isElseIf
        target.elsePos = source.elsePos
        target.elseBody = CloneExpr(source.elseBody, visitFunc)
        return target
    }

    private static func CloneMacroExpandExpr(source: MacroExpandExpr, visitFunc: (Node, Node) -> Unit): MacroExpandExpr {
        let target = MacroExpandExpr()
        target.identifier = cloneIdentifier(source.identifier)
        target.invocation = CloneMacroInvocation(source.invocation)
        for (annotation in source.annotations) {
            if (let Some(cloned) <- (CloneNode(annotation, visitFunc) as Annotation)) { target.annotations.add(cloned) }
        }
        for (modifier in source.modifiers) {
            if (let Some(cloned) <- (CloneNode(modifier, visitFunc) as Modifier)) { target.modifiers.add(cloned) }
        }
        return target
    }

    private static func CloneTokenPart(source: TokenPart, visitFunc: (Node, Node) -> Unit): TokenPart {
        let _ = visitFunc
        let target = TokenPart()
        for (token in source.tokens) { target.tokens.add(token) }
        return target
    }

    private static func CloneQuoteExpr(source: QuoteExpr, visitFunc: (Node, Node) -> Unit): QuoteExpr {
        let target = QuoteExpr()
        for (expr in source.exprs) {
            target.exprs.add(CloneExpr(expr, visitFunc))
        }
        target.quotePos = source.quotePos
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func CloneTryExpr(source: TryExpr, visitFunc: (Node, Node) -> Unit): TryExpr {
        let target = TryExpr()
        target.tryPos = source.tryPos
        target.lParen = source.lParen
        for (resource in source.resourceSpec) {
            if (let Some(cloned) <- (CloneNode(resource, visitFunc) as VarDecl)) { target.resourceSpec.add(cloned) }
        }
        target.isDesugaredFromSyncBlock = source.isDesugaredFromSyncBlock
        target.isDesugaredFromTryWithResources = source.isDesugaredFromTryWithResources
        target.isIllegalResourceSpec = source.isIllegalResourceSpec
        target.tryBlock = CloneBlock(source.tryBlock, visitFunc)
        for (pos in source.catchPosVector) { target.catchPosVector.add(pos) }
        for (block in source.catchBlocks) {
            target.catchBlocks.add(CloneBlock(block, visitFunc))
        }
        for (pattern in source.catchPatterns) {
            target.catchPatterns.add(ClonePattern(pattern, visitFunc))
        }
        for (handler in source.handlers) { target.handlers.add(cloneHandler(handler, visitFunc)) }
        target.finallyPos = source.finallyPos
        target.finallyBlock = CloneBlock(source.finallyBlock, visitFunc)
        for (pos in source.resourceSpecCommaPos) { target.resourceSpecCommaPos.add(pos) }
        target.rParen = source.rParen
        for (pos in source.catchLParenPosVector) { target.catchLParenPosVector.add(pos) }
        for (pos in source.catchRParenPosVector) { target.catchRParenPosVector.add(pos) }
        if (let Some(lambda) <- source.tryLambda) {
            if (let Some(cloned) <- (CloneExpr(lambda, visitFunc) as LambdaExpr)) { target.tryLambda = cloned }
        }
        if (let Some(lambda) <- source.finallyLambda) {
            if (let Some(cloned) <- (CloneExpr(lambda, visitFunc) as LambdaExpr)) { target.finallyLambda = cloned }
        }
        return target
    }

    private static func CloneThrowExpr(source: ThrowExpr, visitFunc: (Node, Node) -> Unit): ThrowExpr {
        let target = ThrowExpr()
        target.throwPos = source.throwPos
        target.expr = CloneExpr(source.expr, visitFunc)
        return target
    }

    private static func ClonePerformExpr(source: PerformExpr, visitFunc: (Node, Node) -> Unit): PerformExpr {
        let target = PerformExpr()
        target.performPos = source.performPos
        target.expr = CloneExpr(source.expr, visitFunc)
        return target
    }

    private static func CloneResumeExpr(source: ResumeExpr, visitFunc: (Node, Node) -> Unit): ResumeExpr {
        let target = ResumeExpr()
        target.resumePos = source.resumePos
        target.withPos = source.withPos
        target.withExpr = CloneExpr(source.withExpr, visitFunc)
        target.throwingPos = source.throwingPos
        target.throwingExpr = CloneExpr(source.throwingExpr, visitFunc)
        return target
    }

    private static func CloneReturnExpr(source: ReturnExpr, visitFunc: (Node, Node) -> Unit): ReturnExpr {
        let target = ReturnExpr()
        target.returnPos = source.returnPos
        target.expr = CloneExpr(source.expr, visitFunc)
        target.refFuncBody = source.refFuncBody
        return target
    }

    private static func CloneWhileExpr(source: WhileExpr, visitFunc: (Node, Node) -> Unit): WhileExpr {
        let target = WhileExpr()
        target.whilePos = source.whilePos
        target.leftParenPos = source.leftParenPos
        target.condExpr = CloneExpr(source.condExpr, visitFunc)
        target.body = CloneBlock(source.body, visitFunc)
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func CloneDoWhileExpr(source: DoWhileExpr, visitFunc: (Node, Node) -> Unit): DoWhileExpr {
        let target = DoWhileExpr()
        target.doPos = source.doPos
        target.body = CloneBlock(source.body, visitFunc)
        target.whilePos = source.whilePos
        target.leftParenPos = source.leftParenPos
        target.condExpr = CloneExpr(source.condExpr, visitFunc)
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func CloneAssignExpr(source: AssignExpr, visitFunc: (Node, Node) -> Unit): AssignExpr {
        let target = AssignExpr()
        target.leftValue = CloneExpr(source.leftValue, visitFunc)
        target.op = source.op
        target.rightExpr = CloneExpr(source.rightExpr, visitFunc)
        target.isCompound = source.isCompound
        target.assignPos = source.assignPos
        return target
    }

    private static func CloneIncOrDecExpr(source: IncOrDecExpr, visitFunc: (Node, Node) -> Unit): IncOrDecExpr {
        let target = IncOrDecExpr()
        target.op = source.op
        target.operatorPos = source.operatorPos
        target.expr = CloneExpr(source.expr, visitFunc)
        return target
    }

    private static func CloneUnaryExpr(source: UnaryExpr, visitFunc: (Node, Node) -> Unit): UnaryExpr {
        let target = UnaryExpr()
        target.op = source.op
        target.expr = CloneExpr(source.expr, visitFunc)
        target.operatorPos = source.operatorPos
        return target
    }

    private static func CloneBinaryExpr(source: BinaryExpr, visitFunc: (Node, Node) -> Unit): BinaryExpr {
        let target = BinaryExpr()
        target.op = source.op
        target.leftExpr = CloneExpr(source.leftExpr, visitFunc)
        target.rightExpr = CloneExpr(source.rightExpr, visitFunc)
        target.operatorPos = source.operatorPos
        return target
    }

    private static func CloneRangeExpr(source: RangeExpr, visitFunc: (Node, Node) -> Unit): RangeExpr {
        let target = RangeExpr()
        target.startExpr = CloneExpr(source.startExpr, visitFunc)
        target.rangePos = source.rangePos
        target.stopExpr = CloneExpr(source.stopExpr, visitFunc)
        target.colonPos = source.colonPos
        target.stepExpr = CloneExpr(source.stepExpr, visitFunc)
        target.isClosed = source.isClosed
        target.decl = source.decl
        return target
    }

    private static func CloneSubscriptExpr(source: SubscriptExpr, visitFunc: (Node, Node) -> Unit): SubscriptExpr {
        let target = SubscriptExpr()
        target.baseExpr = CloneExpr(source.baseExpr, visitFunc)
        target.leftParenPos = source.leftParenPos
        for (expr in source.indexExprs) {
            target.indexExprs.add(CloneExpr(expr, visitFunc))
        }
        for (pos in source.commaPos) { target.commaPos.add(pos) }
        target.rightParenPos = source.rightParenPos
        target.isTupleAccess = source.isTupleAccess
        return target
    }

    private static func CloneMemberAccess(source: MemberAccess, visitFunc: (Node, Node) -> Unit): MemberAccess {
        let target = MemberAccess()
        target.baseExpr = CloneExpr(source.baseExpr, visitFunc)
        target.dotPos = source.dotPos
        target.field = cloneSrcIdentifier(source.field)
        target.target = source.target
        for (decl in source.targets) { target.targets.add(decl) }
        target.isPattern = source.isPattern
        target.isAlone = source.isAlone
        for (ty in source.instTys) { target.instTys.add(ty) }
        target.matchedParentTy = source.matchedParentTy
        target.callOrPattern = source.callOrPattern
        for (entry in source.foundUpperBoundMap) { target.foundUpperBoundMap.add(entry) }
        target.isExposedAccess = source.isExposedAccess
        for (ty in source.typeArguments) {
            target.typeArguments.add(CloneType(ty, visitFunc))
        }
        return target
    }

    private static func CloneCallExpr(source: CallExpr, visitFunc: (Node, Node) -> Unit): CallExpr {
        let target = CallExpr()
        target.baseFunc = CloneExpr(source.baseFunc, visitFunc)
        target.leftParenPos = source.leftParenPos
        target.needCheckToTokens = source.needCheckToTokens
        let cloneTable = HashMap<Node, FuncArg>()
        for (arg in source.args) {
            let cloned = (CloneNode(arg, visitFunc) as FuncArg).getOrThrow()
            target.args.add(cloned)
            cloneTable[arg] = cloned
        }
        if (let Some(sourceDesugarArgs) <- source.desugarArgs) {
            for (arg in source.defaultArgs) {
                let cloned = (CloneNode(arg, visitFunc) as FuncArg).getOrThrow()
                target.defaultArgs.add(cloned)
                cloneTable[arg] = cloned
            }
            let clonedDesugarArgs = ArrayList<FuncArg>()
            for (sourceArg in sourceDesugarArgs) {
                clonedDesugarArgs.add(cloneTable.get(sourceArg).getOrThrow())
            }
            target.desugarArgs = Some(clonedDesugarArgs)
        }
        target.rightParenPos = source.rightParenPos
        target.resolvedFunction = source.resolvedFunction
        target.callKind = source.callKind
        target.sugarKind = source.sugarKind
        if (let Some(baseFunc) <- target.baseFunc) {
            if (let Some(member) <- (baseFunc as MemberAccess)) { member.callOrPattern = target }
        }
        return target
    }

    private static func CloneParenExpr(source: ParenExpr, visitFunc: (Node, Node) -> Unit): ParenExpr {
        let target = ParenExpr()
        target.leftParenPos = source.leftParenPos
        target.expr = CloneExpr(source.expr, visitFunc)
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func CloneLambdaExpr(source: LambdaExpr, visitFunc: (Node, Node) -> Unit): LambdaExpr {
        let target = if (let Some(body) <- source.funcBody) {
            LambdaExpr((CloneNode(body, visitFunc) as FuncBody).getOrThrow())
        } else {
            LambdaExpr()
        }
        if (source.TestAttr(Attribute.MOCK_SUPPORTED)) { target.EnableAttr(Attribute.MOCK_SUPPORTED) }
        return target
    }

    private static func CloneLitConstExpr(source: LitConstExpr, visitFunc: (Node, Node) -> Unit): LitConstExpr {
        let target = LitConstExpr(source.kind, source.stringValue)
        for (code in source.codepoint) { target.codepoint.add(code) }
        target.delimiterNum = source.delimiterNum
        target.stringKind = source.stringKind
        target.rawString = source.rawString
        if (let Some(refType) <- source.ref) {
            target.ref = CloneRefType(refType, visitFunc)
            if (let Some(clonedRef) <- target.ref) { visitFunc(refType, clonedRef) }
        }
        target.siExpr = if (let Some(expr) <- source.siExpr) { CloneExpr(expr, visitFunc) as StrInterpolationExpr } else { None }
        return target
    }

    private static func CloneInterpolationExpr(source: InterpolationExpr, visitFunc: (Node, Node) -> Unit): InterpolationExpr {
        let target = InterpolationExpr()
        target.rawString = source.rawString
        target.dollarPos = source.dollarPos
        target.block = CloneBlock(source.block, visitFunc)
        return target
    }

    private static func CloneStrInterpolationExpr(
        source: StrInterpolationExpr, visitFunc: (Node, Node) -> Unit): StrInterpolationExpr {
        let target = StrInterpolationExpr()
        target.rawString = source.rawString
        for (part in source.strParts) { target.strParts.add(part) }
        for (expr in source.strPartExprs) {
            target.strPartExprs.add(CloneExpr(expr, visitFunc))
        }
        return target
    }

    private static func CloneArrayLit(source: ArrayLit, visitFunc: (Node, Node) -> Unit): ArrayLit {
        let target = ArrayLit()
        target.leftSquarePos = source.leftSquarePos
        for (expr in source.children) {
            target.children.add(CloneExpr(expr, visitFunc))
        }
        for (pos in source.commaPosVector) { target.commaPosVector.add(pos) }
        target.rightSquarePos = source.rightSquarePos
        target.initFunc = source.initFunc
        return target
    }

    private static func CloneArrayExpr(source: ArrayExpr, visitFunc: (Node, Node) -> Unit): ArrayExpr {
        let target = ArrayExpr()
        target.typeNode = CloneType(source.typeNode, visitFunc)
        target.leftParenPos = source.leftParenPos
        for (arg in source.args) { target.args.add((CloneNode(arg, visitFunc) as FuncArg).getOrThrow()) }
        for (pos in source.commaPosVector) { target.commaPosVector.add(pos) }
        target.rightParenPos = source.rightParenPos
        target.initFunc = source.initFunc
        target.isValueArray = source.isValueArray
        return target
    }

    private static func ClonePointerExpr(source: PointerExpr, visitFunc: (Node, Node) -> Unit): PointerExpr {
        let target = PointerExpr()
        target.typeNode = CloneType(source.typeNode, visitFunc)
        target.arg = if (let Some(arg) <- source.arg) { CloneNode(arg, visitFunc) as FuncArg } else { None }
        return target
    }

    private static func CloneTupleLit(source: TupleLit, visitFunc: (Node, Node) -> Unit): TupleLit {
        let target = TupleLit()
        target.leftParenPos = source.leftParenPos
        for (expr in source.children) {
            target.children.add(CloneExpr(expr, visitFunc))
        }
        for (pos in source.commaPosVector) { target.commaPosVector.add(pos) }
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func CloneRefExpr(source: RefExpr, visitFunc: (Node, Node) -> Unit): RefExpr {
        let target = RefExpr(cloneSrcIdentifier(source.ref.identifier))
        target.leftAnglePos = source.leftAnglePos
        target.ref.target = source.ref.target
        for (decl in source.ref.targets) { target.ref.targets.add(decl) }
        for (ty in source.typeArguments) {
            target.typeArguments.add(CloneType(ty, visitFunc))
        }
        target.rightAnglePos = source.rightAnglePos
        target.isSuper = source.isSuper
        target.isThis = source.isThis
        target.isAlone = source.isAlone
        for (ty in source.instTys) { target.instTys.add(ty) }
        target.matchedParentTy = source.matchedParentTy
        target.callOrPattern = source.callOrPattern
        return target
    }

    private static func CloneForInExpr(source: ForInExpr, visitFunc: (Node, Node) -> Unit): ForInExpr {
        let target = ForInExpr()
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        target.pattern = ClonePattern(source.pattern, visitFunc)
        target.inPos = source.inPos
        target.inExpression = CloneExpr(source.inExpression, visitFunc)
        target.wherePos = source.wherePos
        target.patternGuard = CloneExpr(source.patternGuard, visitFunc)
        target.patternInDesugarExpr = source.patternInDesugarExpr
        target.body = CloneBlock(source.body, visitFunc)
        target.forInKind = source.forInKind
        return target
    }

    private static func CloneMatchExpr(source: MatchExpr, visitFunc: (Node, Node) -> Unit): MatchExpr {
        let target = MatchExpr()
        target.matchMode = source.matchMode
        target.sugarKind = source.sugarKind
        target.selector = CloneExpr(source.selector, visitFunc)
        for (matchCase in source.matchCases) {
            if (let Some(cloned) <- (CloneNode(matchCase, visitFunc) as MatchCase)) { target.matchCases.add(cloned) }
        }
        for (other in source.matchCaseOthers) {
            if (let Some(cloned) <- (CloneNode(other, visitFunc) as MatchCaseOther)) { target.matchCaseOthers.add(cloned) }
        }
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        target.leftCurlPos = source.leftCurlPos
        target.rightCurlPos = source.rightCurlPos
        return target
    }

    private static func CloneJumpExpr(source: JumpExpr): JumpExpr {
        let target = JumpExpr()
        target.isBreak = source.isBreak
        target.refLoop = source.refLoop
        return target
    }

    private static func CloneTypeConvExpr(source: TypeConvExpr, visitFunc: (Node, Node) -> Unit): TypeConvExpr {
        let target = TypeConvExpr()
        target.typeNode = CloneType(source.typeNode, visitFunc)
        target.expr = CloneExpr(source.expr, visitFunc)
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func CloneSpawnExpr(source: SpawnExpr, visitFunc: (Node, Node) -> Unit): SpawnExpr {
        let target = SpawnExpr()
        target.task = CloneExpr(source.task, visitFunc)
        target.arg = CloneExpr(source.arg, visitFunc)
        target.futureObj = if (let Some(decl) <- source.futureObj) { CloneDecl(decl, visitFunc) as VarDecl } else { None }
        target.spawnPos = source.spawnPos
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func CloneSynchronizedExpr(
        source: SynchronizedExpr, visitFunc: (Node, Node) -> Unit): SynchronizedExpr {
        let target = SynchronizedExpr()
        target.mutex = CloneExpr(source.mutex, visitFunc)
        target.body = CloneBlock(source.body, visitFunc)
        target.syncPos = source.syncPos
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func CloneInvalidExpr(source: InvalidExpr): InvalidExpr {
        let target = InvalidExpr(source.begin)
        target.value = source.value
        return target
    }

    private static func CloneBlock(source: Block, visitFunc: (Node, Node) -> Unit): Block {
        let target = Block()
        CopyNodeField(source, target)
        target.unsafePos = source.unsafePos
        target.leftCurlPos = source.leftCurlPos
        for (node in source.body) { target.body.add(CloneNode(node, visitFunc)) }
        target.rightCurlPos = source.rightCurlPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func CloneTrailingClosureExpr(
        source: TrailingClosureExpr, visitFunc: (Node, Node) -> Unit): TrailingClosureExpr {
        let target = TrailingClosureExpr()
        target.leftLambda = source.leftLambda
        target.rightLambda = source.rightLambda
        target.expr = CloneExpr(source.expr, visitFunc)
        target.lambda = if (let Some(lambda) <- source.lambda) { CloneExpr(lambda, visitFunc) as LambdaExpr } else { None }
        return target
    }

    private static func CloneIsExpr(source: IsExpr, visitFunc: (Node, Node) -> Unit): IsExpr {
        let target = IsExpr()
        target.leftExpr = CloneExpr(source.leftExpr, visitFunc)
        target.isType = CloneType(source.isType, visitFunc)
        target.isPos = source.isPos
        return target
    }

    private static func CloneAsExpr(source: AsExpr, visitFunc: (Node, Node) -> Unit): AsExpr {
        let target = AsExpr()
        target.leftExpr = CloneExpr(source.leftExpr, visitFunc)
        target.asType = CloneType(source.asType, visitFunc)
        target.asPos = source.asPos
        return target
    }

    private static func CloneOptionalExpr(source: OptionalExpr, visitFunc: (Node, Node) -> Unit): OptionalExpr {
        let target = OptionalExpr()
        target.baseExpr = CloneExpr(source.baseExpr, visitFunc)
        target.questPos = source.questPos
        return target
    }

    private static func CloneOptionalChainExpr(
        source: OptionalChainExpr, visitFunc: (Node, Node) -> Unit): OptionalChainExpr {
        let target = OptionalChainExpr()
        target.expr = CloneExpr(source.expr, visitFunc)
        return target
    }

    private static func CloneLetPatternDestructor(
        source: LetPatternDestructor, visitFunc: (Node, Node) -> Unit): LetPatternDestructor {
        let target = LetPatternDestructor()
        target.backarrowPos = source.backarrowPos
        for (pattern in source.patterns) {
            target.patterns.add(ClonePattern(pattern, visitFunc))
        }
        for (pos in source.orPos) { target.orPos.add(pos) }
        target.initializer = CloneExpr(source.initializer, visitFunc)
        return target
    }

    private static func CloneIfAvailableExpr(
        source: IfAvailableExpr, visitFunc: (Node, Node) -> Unit): IfAvailableExpr {
        let arg = CloneFuncArg(source.GetArg().getOrThrow(), visitFunc)
        let lambda1 = CloneLambdaExpr(source.GetLambda1().getOrThrow(), visitFunc)
        let lambda2 = CloneLambdaExpr(source.GetLambda2().getOrThrow(), visitFunc)
        return IfAvailableExpr(arg, lambda1, lambda2)
    }

    private static func CloneExpr(source: Expr, visitFunc: (Node, Node) -> Unit): Expr {
        let clonedExpr: Expr = match (source.astKind) {
            case ASTKind.IF_EXPR => CloneIfExpr((source as IfExpr).getOrThrow(), visitFunc)
            case ASTKind.PRIMITIVE_TYPE_EXPR =>
                PrimitiveTypeExpr((source as PrimitiveTypeExpr).getOrThrow().typeKind)
            case ASTKind.MACRO_EXPAND_EXPR => CloneMacroExpandExpr((source as MacroExpandExpr).getOrThrow(), visitFunc)
            case ASTKind.TOKEN_PART => CloneTokenPart((source as TokenPart).getOrThrow(), visitFunc)
            case ASTKind.QUOTE_EXPR => CloneQuoteExpr((source as QuoteExpr).getOrThrow(), visitFunc)
            case ASTKind.TRY_EXPR => CloneTryExpr((source as TryExpr).getOrThrow(), visitFunc)
            case ASTKind.THROW_EXPR => CloneThrowExpr((source as ThrowExpr).getOrThrow(), visitFunc)
            case ASTKind.PERFORM_EXPR => ClonePerformExpr((source as PerformExpr).getOrThrow(), visitFunc)
            case ASTKind.RESUME_EXPR => CloneResumeExpr((source as ResumeExpr).getOrThrow(), visitFunc)
            case ASTKind.RETURN_EXPR => CloneReturnExpr((source as ReturnExpr).getOrThrow(), visitFunc)
            case ASTKind.WHILE_EXPR => CloneWhileExpr((source as WhileExpr).getOrThrow(), visitFunc)
            case ASTKind.DO_WHILE_EXPR => CloneDoWhileExpr((source as DoWhileExpr).getOrThrow(), visitFunc)
            case ASTKind.ASSIGN_EXPR => CloneAssignExpr((source as AssignExpr).getOrThrow(), visitFunc)
            case ASTKind.INC_OR_DEC_EXPR => CloneIncOrDecExpr((source as IncOrDecExpr).getOrThrow(), visitFunc)
            case ASTKind.UNARY_EXPR => CloneUnaryExpr((source as UnaryExpr).getOrThrow(), visitFunc)
            case ASTKind.BINARY_EXPR => CloneBinaryExpr((source as BinaryExpr).getOrThrow(), visitFunc)
            case ASTKind.RANGE_EXPR => CloneRangeExpr((source as RangeExpr).getOrThrow(), visitFunc)
            case ASTKind.SUBSCRIPT_EXPR => CloneSubscriptExpr((source as SubscriptExpr).getOrThrow(), visitFunc)
            case ASTKind.MEMBER_ACCESS => CloneMemberAccess((source as MemberAccess).getOrThrow(), visitFunc)
            case ASTKind.CALL_EXPR => CloneCallExpr((source as CallExpr).getOrThrow(), visitFunc)
            case ASTKind.PAREN_EXPR => CloneParenExpr((source as ParenExpr).getOrThrow(), visitFunc)
            case ASTKind.LAMBDA_EXPR => CloneLambdaExpr((source as LambdaExpr).getOrThrow(), visitFunc)
            case ASTKind.LIT_CONST_EXPR => CloneLitConstExpr((source as LitConstExpr).getOrThrow(), visitFunc)
            case ASTKind.ARRAY_LIT => CloneArrayLit((source as ArrayLit).getOrThrow(), visitFunc)
            case ASTKind.ARRAY_EXPR => CloneArrayExpr((source as ArrayExpr).getOrThrow(), visitFunc)
            case ASTKind.POINTER_EXPR => ClonePointerExpr((source as PointerExpr).getOrThrow(), visitFunc)
            case ASTKind.TUPLE_LIT => CloneTupleLit((source as TupleLit).getOrThrow(), visitFunc)
            case ASTKind.REF_EXPR => CloneRefExpr((source as RefExpr).getOrThrow(), visitFunc)
            case ASTKind.FOR_IN_EXPR => CloneForInExpr((source as ForInExpr).getOrThrow(), visitFunc)
            case ASTKind.MATCH_EXPR => CloneMatchExpr((source as MatchExpr).getOrThrow(), visitFunc)
            case ASTKind.JUMP_EXPR => CloneJumpExpr((source as JumpExpr).getOrThrow())
            case ASTKind.TYPE_CONV_EXPR => CloneTypeConvExpr((source as TypeConvExpr).getOrThrow(), visitFunc)
            case ASTKind.SPAWN_EXPR => CloneSpawnExpr((source as SpawnExpr).getOrThrow(), visitFunc)
            case ASTKind.SYNCHRONIZED_EXPR => CloneSynchronizedExpr((source as SynchronizedExpr).getOrThrow(), visitFunc)
            case ASTKind.INVALID_EXPR => CloneInvalidExpr((source as InvalidExpr).getOrThrow())
            case ASTKind.BLOCK => CloneBlock((source as Block).getOrThrow(), visitFunc)
            case ASTKind.INTERPOLATION_EXPR => CloneInterpolationExpr((source as InterpolationExpr).getOrThrow(), visitFunc)
            case ASTKind.STR_INTERPOLATION_EXPR =>
                CloneStrInterpolationExpr((source as StrInterpolationExpr).getOrThrow(), visitFunc)
            case ASTKind.TRAIL_CLOSURE_EXPR =>
                CloneTrailingClosureExpr((source as TrailingClosureExpr).getOrThrow(), visitFunc)
            case ASTKind.IS_EXPR => CloneIsExpr((source as IsExpr).getOrThrow(), visitFunc)
            case ASTKind.AS_EXPR => CloneAsExpr((source as AsExpr).getOrThrow(), visitFunc)
            case ASTKind.OPTIONAL_EXPR => CloneOptionalExpr((source as OptionalExpr).getOrThrow(), visitFunc)
            case ASTKind.OPTIONAL_CHAIN_EXPR =>
                CloneOptionalChainExpr((source as OptionalChainExpr).getOrThrow(), visitFunc)
            case ASTKind.WILDCARD_EXPR => WildcardExpr()
            case ASTKind.LET_PATTERN_DESTRUCTOR =>
                CloneLetPatternDestructor((source as LetPatternDestructor).getOrThrow(), visitFunc)
            case ASTKind.IF_AVAILABLE_EXPR => CloneIfAvailableExpr((source as IfAvailableExpr).getOrThrow(), visitFunc)
            case _ => InvalidExpr(source.begin)
        }
        if (clonedExpr.astKind != ASTKind.INVALID_EXPR) {
            CopyNodeField(source, clonedExpr)
            clonedExpr.isConst = source.isConst
            clonedExpr.isBaseFunc = source.isBaseFunc
            clonedExpr.isInFlowExpr = source.isInFlowExpr
            clonedExpr.constNumValue.asInt.Assign(source.constNumValue.asInt)
            clonedExpr.constNumValue.asFloat.value = source.constNumValue.asFloat.value
            clonedExpr.constNumValue.asFloat.flowStatus = source.constNumValue.asFloat.flowStatus
            clonedExpr.constNumValue.asBoolean = source.constNumValue.asBoolean
            clonedExpr.hasSemi = source.hasSemi
            clonedExpr.mapExpr = if (let Some(mapExpr) <- source.mapExpr) {
                if (mapExpr == source) { clonedExpr } else { mapExpr }
            } else {
                None
            }
            clonedExpr.sourceExpr = source.sourceExpr
            clonedExpr.overflowStrategy = source.overflowStrategy
            if (source.desugarExpr.isSome() && clonedExpr.desugarExpr.isNone()) {
                clonedExpr.desugarExpr = CloneExpr(source.desugarExpr, visitFunc)
            }
            clonedExpr.EnableAttr(Attribute.COMPILER_ADD)
            visitFunc(source, clonedExpr)
        }
        return clonedExpr
    }

    private static func makeNode(node: Node): Node {
        return match (node.astKind) {
            case ASTKind.FEATURE_ID => FeatureId()
            case ASTKind.FEATURES_SET => FeaturesSet()
            case ASTKind.FEATURES_DIRECTIVE => FeaturesDirective()
            case ASTKind.IMPORT_CONTENT => ImportContent()
            case ASTKind.IMPORT_SPEC => ImportSpec()
            case ASTKind.PACKAGE_SPEC => PackageSpec()
            case ASTKind.FILE => File()
            case ASTKind.PACKAGE => Package()
            case ASTKind.PACKAGE_DECL => PackageDecl(Package())
            case ASTKind.MODIFIER => Modifier()
            case ASTKind.ANNOTATION => Annotation()
            case ASTKind.BUILTIN_DECL => BuiltInDecl(BuiltInType.ARRAY)
            case ASTKind.GENERIC_PARAM_DECL => GenericParamDecl()
            case ASTKind.VAR_DECL => VarDecl()
            case ASTKind.VAR_WITH_PATTERN_DECL => VarWithPatternDecl()
            case ASTKind.FUNC_PARAM => FuncParam()
            case ASTKind.DUMMY_BODY => DummyBody()
            case ASTKind.ENUM_DECL => EnumDecl()
            case ASTKind.TYPE_ALIAS_DECL => TypeAliasDecl()
            case ASTKind.FUNC_PARAM_LIST => FuncParamList()
            case ASTKind.FUNC_BODY => FuncBody()
            case ASTKind.FUNC_DECL => FuncDecl()
            case ASTKind.MACRO_DECL => MacroDecl()
            case ASTKind.MAIN_DECL => MainDecl()
            case ASTKind.PRIMARY_CTOR_DECL => PrimaryCtorDecl()
            case ASTKind.PROP_DECL => PropDecl()
            case ASTKind.STRUCT_BODY => StructBody()
            case ASTKind.STRUCT_DECL => StructDecl()
            case ASTKind.INTERFACE_BODY => InterfaceBody()
            case ASTKind.INTERFACE_DECL => InterfaceDecl()
            case ASTKind.CLASS_BODY => ClassBody()
            case ASTKind.CLASS_DECL => ClassDecl()
            case ASTKind.EXTEND_DECL => ExtendDecl()
            case ASTKind.INVALID_DECL => InvalidDecl(node.begin)
            case ASTKind.INVALID_PATTERN => InvalidPattern(node.begin)
            case ASTKind.CONST_PATTERN => ConstPattern()
            case ASTKind.WILDCARD_PATTERN => WildcardPattern()
            case ASTKind.VAR_PATTERN => VarPattern()
            case ASTKind.TUPLE_PATTERN => TuplePattern()
            case ASTKind.TYPE_PATTERN => TypePattern()
            case ASTKind.ENUM_PATTERN => EnumPattern()
            case ASTKind.VAR_OR_ENUM_PATTERN => VarOrEnumPattern(SrcIdentifier())
            case ASTKind.EXCEPT_TYPE_PATTERN => ExceptTypePattern()
            case ASTKind.COMMAND_TYPE_PATTERN => CommandTypePattern()
            case ASTKind.INVALID_TYPE => InvalidType(node.begin)
            case ASTKind.REF_TYPE => RefType()
            case ASTKind.THIS_TYPE => ThisType(node.begin)
            case ASTKind.PRIMITIVE_TYPE => PrimitiveType()
            case ASTKind.PAREN_TYPE => ParenType()
            case ASTKind.QUALIFIED_TYPE => QualifiedType()
            case ASTKind.OPTION_TYPE => OptionType()
            case ASTKind.CONSTANT_TYPE => ConstantType()
            case ASTKind.VARRAY_TYPE => VArrayType()
            case ASTKind.FUNC_TYPE => FuncType()
            case ASTKind.TUPLE_TYPE => TupleType()
            case ASTKind.GENERIC_CONSTRAINT => GenericConstraint()
            case ASTKind.GENERIC => Generic()
            case ASTKind.WILDCARD_EXPR => WildcardExpr()
            case ASTKind.BLOCK => Block()
            case ASTKind.IF_EXPR => IfExpr()
            case ASTKind.LET_PATTERN_DESTRUCTOR => LetPatternDestructor()
            case ASTKind.TOKEN_PART => TokenPart()
            case ASTKind.QUOTE_EXPR => QuoteExpr()
            case ASTKind.MATCH_CASE => MatchCase()
            case ASTKind.MATCH_CASE_OTHER => MatchCaseOther()
            case ASTKind.MATCH_EXPR => MatchExpr()
            case ASTKind.TRY_EXPR => TryExpr()
            case ASTKind.THROW_EXPR => ThrowExpr()
            case ASTKind.PERFORM_EXPR => PerformExpr()
            case ASTKind.RESUME_EXPR => ResumeExpr()
            case ASTKind.RETURN_EXPR => ReturnExpr()
            case ASTKind.JUMP_EXPR => JumpExpr()
            case ASTKind.FOR_IN_EXPR => ForInExpr()
            case ASTKind.WHILE_EXPR => WhileExpr()
            case ASTKind.DO_WHILE_EXPR => DoWhileExpr()
            case ASTKind.ASSIGN_EXPR => AssignExpr()
            case ASTKind.INC_OR_DEC_EXPR => IncOrDecExpr()
            case ASTKind.UNARY_EXPR => UnaryExpr()
            case ASTKind.BINARY_EXPR => BinaryExpr()
            case ASTKind.IS_EXPR => IsExpr()
            case ASTKind.AS_EXPR => AsExpr()
            case ASTKind.RANGE_EXPR => RangeExpr()
            case ASTKind.SUBSCRIPT_EXPR => SubscriptExpr()
            case ASTKind.INTERPOLATION_EXPR => InterpolationExpr()
            case ASTKind.STR_INTERPOLATION_EXPR => StrInterpolationExpr()
            case ASTKind.LIT_CONST_EXPR => LitConstExpr()
            case ASTKind.FUNC_ARG => FuncArg()
            case ASTKind.CALL_EXPR => CallExpr()
            case ASTKind.MEMBER_ACCESS => MemberAccess()
            case ASTKind.PAREN_EXPR => ParenExpr()
            case ASTKind.LAMBDA_EXPR => LambdaExpr()
            case ASTKind.IF_AVAILABLE_EXPR => IfAvailableExpr()
            case ASTKind.TRAIL_CLOSURE_EXPR => TrailingClosureExpr()
            case ASTKind.OPTIONAL_EXPR => OptionalExpr()
            case ASTKind.OPTIONAL_CHAIN_EXPR => OptionalChainExpr()
            case ASTKind.ARRAY_LIT => ArrayLit()
            case ASTKind.ARRAY_EXPR => ArrayExpr()
            case ASTKind.POINTER_EXPR => PointerExpr()
            case ASTKind.TUPLE_LIT => TupleLit()
            case ASTKind.TYPE_CONV_EXPR => TypeConvExpr()
            case ASTKind.REF_EXPR => RefExpr()
            case ASTKind.PRIMITIVE_TYPE_EXPR => PrimitiveTypeExpr(TypeKind.TYPE_INVALID)
            case ASTKind.INVALID_EXPR => InvalidExpr(node.begin)
            case ASTKind.SPAWN_EXPR => SpawnExpr()
            case ASTKind.SYNCHRONIZED_EXPR => SynchronizedExpr()
            case ASTKind.MACRO_EXPAND_EXPR => MacroExpandExpr()
            case ASTKind.MACRO_EXPAND_DECL => MacroExpandDecl()
            case ASTKind.MACRO_EXPAND_PARAM => MacroExpandParam()
            case _ => InvalidExpr()
        }
    }

    private static func copyCommon(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(sourceExpr) <- (source as Expr)) {
            if (let Some(targetExpr) <- (target as Expr)) {
                targetExpr.desugarExpr = cloneExpr(sourceExpr.desugarExpr, visitFunc)
                targetExpr.sourceExpr = sourceExpr.sourceExpr
                targetExpr.mapExpr = sourceExpr.mapExpr
                targetExpr.semiPos = sourceExpr.semiPos
                targetExpr.overflowStrategy = sourceExpr.overflowStrategy
                targetExpr.isConst = sourceExpr.isConst
                targetExpr.isBaseFunc = sourceExpr.isBaseFunc
                targetExpr.isInFlowExpr = sourceExpr.isInFlowExpr
                targetExpr.hasSemi = sourceExpr.hasSemi
                targetExpr.hasQuestSuffix = sourceExpr.hasQuestSuffix
                targetExpr.constNumValue.asInt.Assign(sourceExpr.constNumValue.asInt)
                targetExpr.constNumValue.asFloat.value = sourceExpr.constNumValue.asFloat.value
                targetExpr.constNumValue.asFloat.flowStatus = sourceExpr.constNumValue.asFloat.flowStatus
                targetExpr.constNumValue.asBoolean = sourceExpr.constNumValue.asBoolean
            }
        }

        if (let Some(sourceDecl) <- (source as Decl)) {
            if (let Some(targetDecl) <- (target as Decl)) {
                for (modifier in sourceDecl.modifiers) {
                    if (let Some(cloned) <- (CloneNode(modifier, visitFunc) as Modifier)) { targetDecl.modifiers.add(cloned) }
                }
                for (annotation in sourceDecl.annotations) {
                    if (let Some(cloned) <- (CloneNode(annotation, visitFunc) as Annotation)) { targetDecl.annotations.add(cloned) }
                }
                if (let Some(array) <- sourceDecl.annotationsArray) {
                    targetDecl.annotationsArray = CloneNode(array, visitFunc) as ArrayLit
                }
                targetDecl.identifier = cloneSrcIdentifier(sourceDecl.identifier)
                targetDecl.generic = if (let Some(generic) <- sourceDecl.generic) {
                    CloneGeneric(generic, visitFunc)
                } else {
                    None
                }
                targetDecl.identifierForLsp = sourceDecl.identifierForLsp
                targetDecl.keywordPos = sourceDecl.keywordPos
                targetDecl.hash = sourceDecl.hash
                targetDecl.toBeCompiled = sourceDecl.toBeCompiled
                targetDecl.moduleName = sourceDecl.moduleName
                targetDecl.fullPackageName = sourceDecl.fullPackageName
                targetDecl.outerDecl = sourceDecl.outerDecl
                targetDecl.genericDecl = sourceDecl.genericDecl
                targetDecl.linkage = sourceDecl.linkage
                targetDecl.doNotExport = sourceDecl.doNotExport
                targetDecl.isUsedImports = sourceDecl.isUsedImports
                targetDecl.specificImplementation = sourceDecl.specificImplementation
                for (dependency in sourceDecl.dependencies) { targetDecl.dependencies.add(dependency) }
                targetDecl.checkFlag = sourceDecl.checkFlag
                targetDecl.captureIndex = sourceDecl.captureIndex
            }
        }

        if (let Some(sourcePattern) <- (source as Pattern)) {
            if (let Some(targetPattern) <- (target as Pattern)) {
                targetPattern.ctxExpr = sourcePattern.ctxExpr
            }
        }

        if (let Some(sourceType) <- (source as Type)) {
            if (let Some(targetType) <- (target as Type)) {
                targetType.commaPos = sourceType.commaPos
                targetType.bitAndPos = sourceType.bitAndPos
                targetType.colonPos = sourceType.colonPos
                targetType.typePos = sourceType.typePos
                targetType.typeParameterName = sourceType.typeParameterName
                targetType.typeParameterNameIsRawId = sourceType.typeParameterNameIsRawId
                targetType.aliasTy = sourceType.aliasTy
            }
        }
    }

    private static func copySpecific(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        copyImportAndPackage(source, target, visitFunc)
        copyDecl(source, target, visitFunc)
        copyPattern(source, target, visitFunc)
        copyType(source, target, visitFunc)
        copyExpr(source, target, visitFunc)
        copyMacro(source, target, visitFunc)
    }

    private static func copyImportAndPackage(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(src) <- (source as FeatureId)) {
            if (let Some(dst) <- (target as FeatureId)) {
                for (id in src.identifiers) { dst.identifiers.add(cloneIdentifier(id)) }
                for (pos in src.dotPoses) { dst.dotPoses.add(pos) }
            }
        }
        if (let Some(src) <- (source as FeaturesSet)) {
            if (let Some(dst) <- (target as FeaturesSet)) {
                dst.lCurlPos = src.lCurlPos
                for (item in src.content) { if (let Some(cloned) <- (CloneNode(item, visitFunc) as FeatureId)) { dst.content.add(cloned) } }
                for (pos in src.commaPoses) { dst.commaPoses.add(pos) }
                dst.rCurlPos = src.rCurlPos
            }
        }
        if (let Some(src) <- (source as FeaturesDirective)) {
            if (let Some(dst) <- (target as FeaturesDirective)) {
                for (annotation in src.annotations) { if (let Some(cloned) <- (CloneNode(annotation, visitFunc) as Annotation)) { dst.annotations.add(cloned) } }
                dst.featuresSet = if (let Some(set) <- src.featuresSet) { CloneNode(set, visitFunc) as FeaturesSet } else { None }
                dst.featuresPos = src.featuresPos
            }
        }
        if (let Some(src) <- (source as ImportContent)) {
            if (let Some(dst) <- (target as ImportContent)) {
                dst.kind = src.kind
                dst.hasDoubleColon = src.hasDoubleColon
                for (path in src.prefixPaths) { dst.prefixPaths.add(path) }
                for (pos in src.prefixPoses) { dst.prefixPoses.add(pos) }
                for (pos in src.prefixDotPoses) { dst.prefixDotPoses.add(pos) }
                dst.identifier = cloneIdentifier(src.identifier)
                dst.asPos = src.asPos
                dst.aliasName = cloneIdentifier(src.aliasName)
                dst.leftCurlPos = src.leftCurlPos
                for (item in src.items) { if (let Some(cloned) <- (CloneNode(item, visitFunc) as ImportContent)) { dst.items.add(cloned) } }
                for (pos in src.commaPoses) { dst.commaPoses.add(pos) }
                dst.rightCurlPos = src.rightCurlPos
                dst.isDecl = src.isDecl
            }
        }
        if (let Some(src) <- (source as ImportSpec)) {
            if (let Some(dst) <- (target as ImportSpec)) {
                dst.modifier = if (let Some(modifier) <- src.modifier) { CloneNode(modifier, visitFunc) as Modifier } else { None }
                dst.importPos = src.importPos
                if (let Some(content) <- (CloneNode(src.content, visitFunc) as ImportContent)) { dst.content = content }
                for (annotation in src.annotations) { if (let Some(cloned) <- (CloneNode(annotation, visitFunc) as Annotation)) { dst.annotations.add(cloned) } }
                dst.withImplicitExport = src.withImplicitExport
            }
        }
        if (let Some(src) <- (source as PackageSpec)) {
            if (let Some(dst) <- (target as PackageSpec)) {
                dst.modifier = if (let Some(modifier) <- src.modifier) { CloneNode(modifier, visitFunc) as Modifier } else { None }
                dst.macroPos = src.macroPos
                dst.packagePos = src.packagePos
                dst.hasDoubleColon = src.hasDoubleColon
                for (path in src.prefixPaths) { dst.prefixPaths.add(path) }
                for (pos in src.prefixPoses) { dst.prefixPoses.add(pos) }
                for (pos in src.prefixDotPoses) { dst.prefixDotPoses.add(pos) }
                dst.packageName = cloneIdentifier(src.packageName)
                dst.hasMacro = src.hasMacro
                dst.hasSpecific = src.hasSpecific
                dst.hasCommon = src.hasCommon
            }
        }
        if (let Some(src) <- (source as File)) {
            if (let Some(dst) <- (target as File)) {
                dst.fileName = src.fileName
                dst.filePath = src.filePath
                dst.fileHash = src.fileHash
                dst.feature = if (let Some(feature) <- src.feature) { CloneNode(feature, visitFunc) as FeaturesDirective } else { None }
                dst.packageSpec = if (let Some(pkgSpec) <- src.packageSpec) { CloneNode(pkgSpec, visitFunc) as PackageSpec } else { None }
                for (importSpec in src.imports) { if (let Some(cloned) <- (CloneNode(importSpec, visitFunc) as ImportSpec)) { dst.imports.add(cloned) } }
                for (decl in src.decls) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as Decl)) { dst.decls.add(cloned) } }
                for (node in src.trashBin) { dst.trashBin.add(CloneNode(node, visitFunc)) }
                dst.curPackage = src.curPackage
                dst.indexOfPackage = src.indexOfPackage
                dst.hasMacro = src.hasMacro
                dst.macroCallFilePath = src.macroCallFilePath
                dst.macroCallPosBase = src.macroCallPosBase
                for (node in src.originalMacroCallNodes) { dst.originalMacroCallNodes.add(CloneNode(node, visitFunc)) }
                for (decl in src.exportedInternalDecls) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as Decl)) { dst.exportedInternalDecls.add(cloned) } }
                dst.isCommon = src.isCommon
                dst.isSpecific = src.isSpecific
            }
        }
        if (let Some(src) <- (source as Package)) {
            if (let Some(dst) <- (target as Package)) {
                dst.fullPackageName = src.fullPackageName
                for (file in src.files) { if (let Some(cloned) <- (CloneNode(file, visitFunc) as File)) { dst.files.add(cloned) } }
                for (decl in src.genericInstantiatedDecls) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as Decl)) { dst.genericInstantiatedDecls.add(cloned) } }
                for (decl in src.srcImportedNonGenericDecls) { dst.srcImportedNonGenericDecls.add(decl) }
                for (decl in src.inlineFuncDecls) { dst.inlineFuncDecls.add(decl) }
                dst.accessible = src.accessible
                dst.hasSourceImportedDecl = src.hasSourceImportedDecl
                dst.isMacroPackage = src.isMacroPackage
                dst.noSubPkg = src.noSubPkg
                dst.needExported = src.needExported
                dst.interopCJApiStrategy = src.interopCJApiStrategy
                dst.interopCJGenericTypeStrategy = src.interopCJGenericTypeStrategy
                for (api in src.interopCJIncludedApis) { dst.interopCJIncludedApis.add(api) }
                for (api in src.interopCJExcludedApis) { dst.interopCJExcludedApis.add(api) }
                for (outerType in src.allowedInteropCJGenericInstantiations.keys()) {
                    if (let Some(innerMap) <- src.allowedInteropCJGenericInstantiations.get(outerType)) {
                        let copiedInnerMap = HashMap<String, GenericTypeArguments>()
                        for (innerType in innerMap.keys()) {
                            if (let Some(args) <- innerMap.get(innerType)) {
                                let copiedArgs = GenericTypeArguments()
                                for (symbol in args.symbols) { copiedArgs.symbols.add(symbol) }
                                copiedInnerMap[innerType] = copiedArgs
                            }
                        }
                        dst.allowedInteropCJGenericInstantiations[outerType] = copiedInnerMap
                    }
                }
                for (tuple in src.interopTuples) { dst.interopTuples.add(tuple) }
                dst.isInteropCJPackageConfig = src.isInteropCJPackageConfig
                for (lambdaPattern in src.lambdaPatterns) {
                    let copiedPattern = LambdaPattern(
                        lambdaPattern.signature, lambdaPattern.parameterTypes.toArray(), lambdaPattern.returnType)
                    for (classMapping in lambdaPattern.classMappings) {
                        copiedPattern.classMappings.add(ClassMapping(classMapping.name, classMapping.pkgPath))
                    }
                    copiedPattern.fullPackageName = lambdaPattern.fullPackageName
                    dst.lambdaPatterns.add(copiedPattern)
                }
                for (dep in src.GetAllDependentStdPkgs()) { dst.AddDependentStdPkg(dep) }
            }
        }
        if (let Some(src) <- (source as PackageDecl)) {
            if (let Some(dst) <- (target as PackageDecl)) {
                dst.srcPackage = src.srcPackage
            }
        }
    }

    private static func copyDecl(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(src) <- (source as InheritableDecl)) {
            if (let Some(dst) <- (target as InheritableDecl)) {
                dst.upperBoundPos = src.upperBoundPos
                for (ty in src.inheritedTypes) { if (let Some(cloned) <- (CloneNode(ty, visitFunc) as Type)) { dst.inheritedTypes.add(cloned) } }
            }
        }
        if (let Some(src) <- (source as BuiltInDecl)) {
            if (let Some(dst) <- (target as BuiltInDecl)) { dst.builtinType = src.builtinType }
        }
        if (let Some(src) <- (source as GenericParamDecl)) {
            if (let Some(dst) <- (target as GenericParamDecl)) { dst.commaPos = src.commaPos }
        }
        if (let Some(src) <- (source as VarDeclAbstract)) {
            if (let Some(dst) <- (target as VarDeclAbstract)) {
                dst.typeNode = cloneType(src.typeNode, visitFunc)
                dst.colonPos = src.colonPos
                dst.initializer = cloneExpr(src.initializer, visitFunc)
                dst.assignPos = src.assignPos
                dst.isVar = src.isVar
                dst.isConst = src.isConst
            }
        }
        if (let Some(src) <- (source as VarDecl)) {
            if (let Some(dst) <- (target as VarDecl)) {
                dst.parentPattern = src.parentPattern
                dst.isIdentifierCompilerAdd = src.isIdentifierCompilerAdd
                dst.isResourceVar = src.isResourceVar
                dst.isMemberParam = src.isMemberParam
            }
        }
        if (let Some(src) <- (source as VarWithPatternDecl)) {
            if (let Some(dst) <- (target as VarWithPatternDecl)) { dst.irrefutablePattern = clonePattern(src.irrefutablePattern, visitFunc) }
        }
        if (let Some(src) <- (source as FuncParam)) {
            if (let Some(dst) <- (target as FuncParam)) {
                dst.notMarkPos = src.notMarkPos
                dst.assignment = cloneExpr(src.assignment, visitFunc)
                dst.commaPos = src.commaPos
                dst.desugarDecl = if (let Some(decl) <- src.desugarDecl) { CloneNode(decl, visitFunc) as FuncDecl } else { None }
                dst.isNamedParam = src.isNamedParam
                dst.hasLetOrVar = src.hasLetOrVar
            }
        }
        if (let Some(src) <- (source as EnumDecl)) {
            if (let Some(dst) <- (target as EnumDecl)) {
                dst.leftCurlPos = src.leftCurlPos
                dst.bodyScope = if (let Some(bodyScope) <- src.bodyScope) { CloneNode(bodyScope, visitFunc) as DummyBody } else { None }
                for (decl in src.constructors) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as Decl)) { dst.constructors.add(cloned) } }
                for (pos in src.bitOrPosVector) { dst.bitOrPosVector.add(pos) }
                for (decl in src.members) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as Decl)) { dst.members.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
                dst.hasArguments = src.hasArguments
                dst.hasEllipsis = src.hasEllipsis
                dst.ellipsisPos = src.ellipsisPos
            }
        }
        if (let Some(src) <- (source as TypeAliasDecl)) {
            if (let Some(dst) <- (target as TypeAliasDecl)) {
                dst.assignPos = src.assignPos
                dst.typeNode = cloneType(src.typeNode, visitFunc)
            }
        }
        if (let Some(src) <- (source as FuncParamList)) {
            if (let Some(dst) <- (target as FuncParamList)) {
                dst.leftParenPos = src.leftParenPos
                for (param in src.params) { if (let Some(cloned) <- (CloneNode(param, visitFunc) as FuncParam)) { dst.params.add(cloned) } }
                dst.rightParenPos = src.rightParenPos
                dst.variadicArgIndex = src.variadicArgIndex
                dst.hasVariableLenArg = src.hasVariableLenArg
            }
        }
        if (let Some(src) <- (source as FuncBody)) {
            if (let Some(dst) <- (target as FuncBody)) {
                for (params in src.paramLists) { if (let Some(cloned) <- (CloneNode(params, visitFunc) as FuncParamList)) { dst.paramLists.add(cloned) } }
                dst.doubleArrowPos = src.doubleArrowPos
                dst.colonPos = src.colonPos
                dst.retType = cloneType(src.retType, visitFunc)
                dst.body = cloneBlock(src.body, visitFunc)
                dst.generic = if (let Some(generic) <- src.generic) {
                    CloneGeneric(generic, visitFunc)
                } else {
                    None
                }
                dst.funcDecl = src.funcDecl
                for (captured in src.capturedVars) { dst.capturedVars.add(captured) }
                dst.outerFunc = src.outerFunc
                dst.parentClassLike = src.parentClassLike
                dst.parentStruct = src.parentStruct
                dst.parentEnum = src.parentEnum
                dst.captureKind = src.captureKind
            }
        }
        if (let Some(src) <- (source as FuncDecl)) {
            if (let Some(dst) <- (target as FuncDecl)) {
                dst.leftParenPos = src.leftParenPos
                dst.rightParenPos = src.rightParenPos
                dst.funcBody = cloneFuncBody(src.funcBody, visitFunc)
                if (let Some(body) <- dst.funcBody) { body.funcDecl = dst }
                dst.ownerFunc = src.ownerFunc
                dst.propDecl = src.propDecl
                dst.overflowStrategy = src.overflowStrategy
                dst.constructorCall = src.constructorCall
                dst.op = src.op
                dst.variadicArgIndex = src.variadicArgIndex
                dst.hasVariableLenArg = src.hasVariableLenArg
                dst.isConst = src.isConst
                dst.isSetter = src.isSetter
                dst.isGetter = src.isGetter
                dst.isInline = src.isInline
                dst.isFastNative = src.isFastNative
                dst.isReExportedOrRenamed = src.isReExportedOrRenamed
                dst.isFrozen = src.isFrozen
            }
        }
        if (let Some(src) <- (source as MacroDecl)) {
            if (let Some(dst) <- (target as MacroDecl)) {
                dst.funcBody = cloneFuncBody(src.funcBody, visitFunc)
                dst.desugarDecl = if (let Some(decl) <- src.desugarDecl) { CloneNode(decl, visitFunc) as FuncDecl } else { None }
            }
        }
        if (let Some(src) <- (source as MainDecl)) {
            if (let Some(dst) <- (target as MainDecl)) {
                dst.funcBody = cloneFuncBody(src.funcBody, visitFunc)
                dst.desugarDecl = if (let Some(decl) <- src.desugarDecl) { CloneNode(decl, visitFunc) as FuncDecl } else { None }
                dst.overflowStrategy = src.overflowStrategy
                dst.isFastNative = src.isFastNative
            }
        }
        if (let Some(src) <- (source as PrimaryCtorDecl)) {
            if (let Some(dst) <- (target as PrimaryCtorDecl)) {
                dst.funcBody = cloneFuncBody(src.funcBody, visitFunc)
                dst.overflowStrategy = src.overflowStrategy
                dst.hasVariableLenArg = src.hasVariableLenArg
                dst.isFastNative = src.isFastNative
                dst.isConst = src.isConst
            }
        }
        if (let Some(src) <- (source as PropDecl)) {
            if (let Some(dst) <- (target as PropDecl)) {
                dst.leftCurlPos = src.leftCurlPos
                for (getter in src.getters) { if (let Some(cloned) <- (CloneNode(getter, visitFunc) as FuncDecl)) { dst.getters.add(cloned) } }
                for (setter in src.setters) { if (let Some(cloned) <- (CloneNode(setter, visitFunc) as FuncDecl)) { dst.setters.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
        if (let Some(src) <- (source as StructBody)) {
            if (let Some(dst) <- (target as StructBody)) {
                dst.leftCurlPos = src.leftCurlPos
                for (decl in src.decls) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as Decl)) { dst.decls.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
        if (let Some(src) <- (source as StructDecl)) {
            if (let Some(dst) <- (target as StructDecl)) { dst.body = if (let Some(body) <- src.body) { CloneNode(body, visitFunc) as StructBody } else { None } }
        }
        if (let Some(src) <- (source as InterfaceBody)) {
            if (let Some(dst) <- (target as InterfaceBody)) {
                dst.leftCurlPos = src.leftCurlPos
                for (decl in src.decls) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as Decl)) { dst.decls.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
        if (let Some(src) <- (source as ClassLikeDecl)) {
            if (let Some(dst) <- (target as ClassLikeDecl)) {
                for (decl in src.subDecls) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as Decl)) { dst.subDecls.add(cloned) } }
            }
        }
        if (let Some(src) <- (source as InterfaceDecl)) {
            if (let Some(dst) <- (target as InterfaceDecl)) { dst.body = if (let Some(body) <- src.body) { CloneNode(body, visitFunc) as InterfaceBody } else { None } }
        }
        if (let Some(src) <- (source as ClassBody)) {
            if (let Some(dst) <- (target as ClassBody)) {
                dst.leftCurlPos = src.leftCurlPos
                for (decl in src.decls) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as Decl)) { dst.decls.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
        if (let Some(src) <- (source as ClassDecl)) {
            if (let Some(dst) <- (target as ClassDecl)) { dst.body = if (let Some(body) <- src.body) { CloneNode(body, visitFunc) as ClassBody } else { None } }
        }
        if (let Some(src) <- (source as ExtendDecl)) {
            if (let Some(dst) <- (target as ExtendDecl)) {
                dst.extendedType = cloneType(src.extendedType, visitFunc)
                dst.wherePos = src.wherePos
                dst.bodyScope = if (let Some(bodyScope) <- src.bodyScope) { CloneNode(bodyScope, visitFunc) as DummyBody } else { None }
                dst.leftCurlPos = src.leftCurlPos
                for (decl in src.members) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as Decl)) { dst.members.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
    }

    private static func copyPattern(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(src) <- (source as ConstPattern)) {
            if (let Some(dst) <- (target as ConstPattern)) {
                dst.literal = cloneExpr(src.literal, visitFunc)
                dst.operatorCallExpr = if (let Some(call) <- src.operatorCallExpr) { CloneNode(call, visitFunc) as CallExpr } else { None }
            }
        }
        if (let Some(src) <- (source as VarPattern)) {
            if (let Some(dst) <- (target as VarPattern)) {
                dst.varDecl = if (let Some(decl) <- src.varDecl) { CloneNode(decl, visitFunc) as VarDecl } else { None }
                dst.desugarExpr = cloneExpr(src.desugarExpr, visitFunc)
            }
        }
        if (let Some(src) <- (source as TuplePattern)) {
            if (let Some(dst) <- (target as TuplePattern)) {
                dst.leftBracePos = src.leftBracePos
                for (pattern in src.patterns) { if (let Some(cloned) <- (CloneNode(pattern, visitFunc) as Pattern)) { dst.patterns.add(cloned) } }
                for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }
                dst.rightBracePos = src.rightBracePos
            }
        }
        if (let Some(src) <- (source as TypePattern)) {
            if (let Some(dst) <- (target as TypePattern)) {
                dst.pattern = clonePattern(src.pattern, visitFunc)
                dst.colonPos = src.colonPos
                dst.typeNode = cloneType(src.typeNode, visitFunc)
                dst.desugarExpr = cloneExpr(src.desugarExpr, visitFunc)
                dst.desugarVarPattern = if (let Some(pattern) <- src.desugarVarPattern) { CloneNode(pattern, visitFunc) as VarPattern } else { None }
                dst.needRuntimeTypeCheck = src.needRuntimeTypeCheck
                dst.matchBeforeRuntime = src.matchBeforeRuntime
            }
        }
        if (let Some(src) <- (source as EnumPattern)) {
            if (let Some(dst) <- (target as EnumPattern)) {
                dst.constructor = cloneExpr(src.constructor, visitFunc)
                for (pattern in src.patterns) { if (let Some(cloned) <- (CloneNode(pattern, visitFunc) as Pattern)) { dst.patterns.add(cloned) } }
                dst.leftParenPos = src.leftParenPos
                for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }
                dst.rightParenPos = src.rightParenPos
            }
        }
        if (let Some(src) <- (source as VarOrEnumPattern)) {
            if (let Some(dst) <- (target as VarOrEnumPattern)) {
                dst.identifier = cloneSrcIdentifier(src.identifier)
                dst.pattern = clonePattern(src.pattern, visitFunc)
            }
        }
        if (let Some(src) <- (source as ExceptTypePattern)) {
            if (let Some(dst) <- (target as ExceptTypePattern)) {
                dst.pattern = clonePattern(src.pattern, visitFunc)
                dst.patternPos = src.patternPos
                dst.colonPos = src.colonPos
                for (ty in src.types) { if (let Some(cloned) <- (CloneNode(ty, visitFunc) as Type)) { dst.types.add(cloned) } }
                for (pos in src.bitOrPosVector) { dst.bitOrPosVector.add(pos) }
            }
        }
        if (let Some(src) <- (source as CommandTypePattern)) {
            if (let Some(dst) <- (target as CommandTypePattern)) {
                dst.pattern = clonePattern(src.pattern, visitFunc)
                dst.patternPos = src.patternPos
                dst.colonPos = src.colonPos
                for (ty in src.types) { if (let Some(cloned) <- (CloneNode(ty, visitFunc) as Type)) { dst.types.add(cloned) } }
                for (pos in src.bitOrPosVector) { dst.bitOrPosVector.add(pos) }
            }
        }
    }

    private static func copyType(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(src) <- (source as RefType)) {
            if (let Some(dst) <- (target as RefType)) {
                dst.ref = cloneReference(src.ref)
                dst.leftAnglePos = src.leftAnglePos
                for (ty in src.typeArguments) { if (let Some(cloned) <- (CloneNode(ty, visitFunc) as Type)) { dst.typeArguments.add(cloned) } }
                dst.rightAnglePos = src.rightAnglePos
            }
        }
        if (let Some(src) <- (source as PrimitiveType)) {
            if (let Some(dst) <- (target as PrimitiveType)) {
                dst.str = src.str
                dst.kind = src.kind
            }
        }
        if (let Some(src) <- (source as ParenType)) {
            if (let Some(dst) <- (target as ParenType)) {
                dst.leftParenPos = src.leftParenPos
                dst.innerType = cloneType(src.innerType, visitFunc)
                dst.rightParenPos = src.rightParenPos
            }
        }
        if (let Some(src) <- (source as QualifiedType)) {
            if (let Some(dst) <- (target as QualifiedType)) {
                dst.baseType = cloneType(src.baseType, visitFunc)
                dst.dotPos = src.dotPos
                dst.field = cloneSrcIdentifier(src.field)
                dst.leftAnglePos = src.leftAnglePos
                for (ty in src.typeArguments) { if (let Some(cloned) <- (CloneNode(ty, visitFunc) as Type)) { dst.typeArguments.add(cloned) } }
                dst.rightAnglePos = src.rightAnglePos
                dst.target = src.target
            }
        }
        if (let Some(src) <- (source as OptionType)) {
            if (let Some(dst) <- (target as OptionType)) {
                dst.componentType = cloneType(src.componentType, visitFunc)
                dst.questNum = src.questNum
                for (pos in src.questVector) { dst.questVector.add(pos) }
                dst.desugarType = cloneRefType(src.desugarType, visitFunc)
            }
        }
        if (let Some(src) <- (source as ConstantType)) {
            if (let Some(dst) <- (target as ConstantType)) {
                dst.constantExpr = cloneExpr(src.constantExpr, visitFunc)
                dst.dollarPos = src.dollarPos
            }
        }
        if (let Some(src) <- (source as VArrayType)) {
            if (let Some(dst) <- (target as VArrayType)) {
                dst.varrayPos = src.varrayPos
                dst.leftAnglePos = src.leftAnglePos
                dst.typeArgument = cloneType(src.typeArgument, visitFunc)
                dst.constantType = cloneType(src.constantType, visitFunc)
                dst.rightAnglePos = src.rightAnglePos
            }
        }
        if (let Some(src) <- (source as FuncType)) {
            if (let Some(dst) <- (target as FuncType)) {
                dst.leftParenPos = src.leftParenPos
                for (ty in src.paramTypes) { if (let Some(cloned) <- (CloneNode(ty, visitFunc) as Type)) { dst.paramTypes.add(cloned) } }
                dst.rightParenPos = src.rightParenPos
                dst.arrowPos = src.arrowPos
                dst.retType = cloneType(src.retType, visitFunc)
                dst.isC = src.isC
            }
        }
        if (let Some(src) <- (source as TupleType)) {
            if (let Some(dst) <- (target as TupleType)) {
                dst.leftParenPos = src.leftParenPos
                dst.rightParenPos = src.rightParenPos
                for (ty in src.fieldTypes) { if (let Some(cloned) <- (CloneNode(ty, visitFunc) as Type)) { dst.fieldTypes.add(cloned) } }
                for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }
            }
        }
        if (let Some(src) <- (source as GenericConstraint)) {
            if (let Some(dst) <- (target as GenericConstraint)) {
                dst.wherePos = src.wherePos
                dst.refType = cloneRefType(src.refType, visitFunc)
                dst.operatorPos = src.operatorPos
                for (pos in src.bitAndPos) { dst.bitAndPos.add(pos) }
                for (ty in src.upperBounds) { if (let Some(cloned) <- (CloneNode(ty, visitFunc) as Type)) { dst.upperBounds.add(cloned) } }
                dst.commaPos = src.commaPos
                dst.isImplicitlyIntroduced = src.isImplicitlyIntroduced
            }
        }
        if (let Some(src) <- (source as Generic)) {
            if (let Some(dst) <- (target as Generic)) {
                dst.leftAnglePos = src.leftAnglePos
                for (param in src.typeParameters) { if (let Some(cloned) <- (CloneNode(param, visitFunc) as GenericParamDecl)) { dst.typeParameters.add(cloned) } }
                dst.rightAnglePos = src.rightAnglePos
                for (constraint in src.genericConstraints) { if (let Some(cloned) <- (CloneNode(constraint, visitFunc) as GenericConstraint)) { dst.genericConstraints.add(cloned) } }
            }
        }
    }

    private static func cloneReference(source: Reference): Reference {
        let target = Reference()
        target.identifier = cloneSrcIdentifier(source.identifier)
        target.target = source.target
        for (decl in source.targets) { target.targets.add(decl) }
        return target
    }

    private static func copyExpr(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(src) <- (source as Block)) {
            if (let Some(dst) <- (target as Block)) {
                dst.leftCurlPos = src.leftCurlPos
                for (node in src.body) { dst.body.add(CloneNode(node, visitFunc)) }
                dst.rightCurlPos = src.rightCurlPos
                dst.unsafePos = src.unsafePos
            }
        }
        if (let Some(src) <- (source as IfExpr)) {
            if (let Some(dst) <- (target as IfExpr)) {
                dst.ifPos = src.ifPos
                dst.leftParenPos = src.leftParenPos
                dst.condExpr = cloneExpr(src.condExpr, visitFunc)
                dst.rightParenPos = src.rightParenPos
                dst.thenBody = cloneBlock(src.thenBody, visitFunc)
                dst.elsePos = src.elsePos
                dst.elseBody = cloneExpr(src.elseBody, visitFunc)
                dst.isElseIf = src.isElseIf
                dst.hasElse = src.hasElse
                dst.sugarKind = src.sugarKind
            }
        }
        if (let Some(src) <- (source as LetPatternDestructor)) {
            if (let Some(dst) <- (target as LetPatternDestructor)) {
                for (pattern in src.patterns) { if (let Some(cloned) <- (CloneNode(pattern, visitFunc) as Pattern)) { dst.patterns.add(cloned) } }
                for (pos in src.orPos) { dst.orPos.add(pos) }
                dst.backarrowPos = src.backarrowPos
                dst.initializer = cloneExpr(src.initializer, visitFunc)
            }
        }
        if (let Some(src) <- (source as TokenPart)) {
            if (let Some(dst) <- (target as TokenPart)) { for (token in src.tokens) { dst.tokens.add(token) } }
        }
        if (let Some(src) <- (source as QuoteExpr)) {
            if (let Some(dst) <- (target as QuoteExpr)) {
                dst.quotePos = src.quotePos
                dst.leftParenPos = src.leftParenPos
                dst.rightParenPos = src.rightParenPos
                for (expr in src.exprs) { if (let Some(cloned) <- (CloneNode(expr, visitFunc) as Expr)) { dst.exprs.add(cloned) } }
            }
        }
        if (let Some(src) <- (source as MatchCase)) {
            if (let Some(dst) <- (target as MatchCase)) {
                for (pattern in src.patterns) { if (let Some(cloned) <- (CloneNode(pattern, visitFunc) as Pattern)) { dst.patterns.add(cloned) } }
                for (pos in src.bitOrPosVector) { dst.bitOrPosVector.add(pos) }
                dst.patternGuard = cloneExpr(src.patternGuard, visitFunc)
                dst.wherePos = src.wherePos
                dst.arrowPos = src.arrowPos
                dst.exprOrDecls = cloneBlock(src.exprOrDecls, visitFunc)
            }
        }
        if (let Some(src) <- (source as MatchCaseOther)) {
            if (let Some(dst) <- (target as MatchCaseOther)) {
                dst.matchExpr = cloneExpr(src.matchExpr, visitFunc)
                dst.arrowPos = src.arrowPos
                dst.exprOrDecls = cloneBlock(src.exprOrDecls, visitFunc)
            }
        }
        if (let Some(src) <- (source as MatchExpr)) {
            if (let Some(dst) <- (target as MatchExpr)) {
                dst.sugarKind = src.sugarKind
                dst.matchMode = src.matchMode
                dst.leftParenPos = src.leftParenPos
                dst.selector = cloneExpr(src.selector, visitFunc)
                dst.rightParenPos = src.rightParenPos
                dst.leftCurlPos = src.leftCurlPos
                for (matchCase in src.matchCases) { if (let Some(cloned) <- (CloneNode(matchCase, visitFunc) as MatchCase)) { dst.matchCases.add(cloned) } }
                for (other in src.matchCaseOthers) { if (let Some(cloned) <- (CloneNode(other, visitFunc) as MatchCaseOther)) { dst.matchCaseOthers.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
        copyControlExpr(source, target, visitFunc)
        copyOperatorExpr(source, target, visitFunc)
        copyLiteralAndCallExpr(source, target, visitFunc)
        copyReferenceExpr(source, target, visitFunc)
    }

    private static func copyControlExpr(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(src) <- (source as TryExpr)) {
            if (let Some(dst) <- (target as TryExpr)) {
                dst.tryPos = src.tryPos
                dst.lParen = src.lParen
                for (decl in src.resourceSpec) { if (let Some(cloned) <- (CloneNode(decl, visitFunc) as VarDecl)) { dst.resourceSpec.add(cloned) } }
                for (pos in src.resourceSpecCommaPos) { dst.resourceSpecCommaPos.add(pos) }
                dst.rParen = src.rParen
                dst.tryBlock = cloneBlock(src.tryBlock, visitFunc)
                for (pos in src.catchPosVector) { dst.catchPosVector.add(pos) }
                for (pos in src.catchLParenPosVector) { dst.catchLParenPosVector.add(pos) }
                for (pos in src.catchRParenPosVector) { dst.catchRParenPosVector.add(pos) }
                for (block in src.catchBlocks) { if (let Some(cloned) <- (CloneNode(block, visitFunc) as Block)) { dst.catchBlocks.add(cloned) } }
                for (pattern in src.catchPatterns) { if (let Some(cloned) <- (CloneNode(pattern, visitFunc) as Pattern)) { dst.catchPatterns.add(cloned) } }
                dst.finallyPos = src.finallyPos
                dst.finallyBlock = cloneBlock(src.finallyBlock, visitFunc)
                for (handler in src.handlers) { dst.handlers.add(cloneHandler(handler, visitFunc)) }
                dst.isIllegalResourceSpec = src.isIllegalResourceSpec
                dst.isDesugaredFromTryWithResources = src.isDesugaredFromTryWithResources
                dst.isDesugaredFromSyncBlock = src.isDesugaredFromSyncBlock
                dst.tryLambda = if (let Some(lambda) <- src.tryLambda) { CloneNode(lambda, visitFunc) as LambdaExpr } else { None }
                dst.finallyLambda = if (let Some(lambda) <- src.finallyLambda) { CloneNode(lambda, visitFunc) as LambdaExpr } else { None }
            }
        }
        if (let Some(src) <- (source as ThrowExpr)) { if (let Some(dst) <- (target as ThrowExpr)) { dst.throwPos = src.throwPos; dst.expr = cloneExpr(src.expr, visitFunc) } }
        if (let Some(src) <- (source as PerformExpr)) { if (let Some(dst) <- (target as PerformExpr)) { dst.performPos = src.performPos; dst.expr = cloneExpr(src.expr, visitFunc) } }
        if (let Some(src) <- (source as ResumeExpr)) {
            if (let Some(dst) <- (target as ResumeExpr)) {
                dst.resumePos = src.resumePos
                dst.withPos = src.withPos
                dst.withExpr = cloneExpr(src.withExpr, visitFunc)
                dst.throwingPos = src.throwingPos
                dst.throwingExpr = cloneExpr(src.throwingExpr, visitFunc)
                dst.enclosing = src.enclosing
            }
        }
        if (let Some(src) <- (source as ReturnExpr)) { if (let Some(dst) <- (target as ReturnExpr)) { dst.returnPos = src.returnPos; dst.expr = cloneExpr(src.expr, visitFunc); dst.refFuncBody = src.refFuncBody } }
        if (let Some(src) <- (source as JumpExpr)) { if (let Some(dst) <- (target as JumpExpr)) { dst.refLoop = src.refLoop; dst.isBreak = src.isBreak } }
        if (let Some(src) <- (source as ForInExpr)) {
            if (let Some(dst) <- (target as ForInExpr)) {
                dst.leftParenPos = src.leftParenPos
                dst.pattern = clonePattern(src.pattern, visitFunc)
                dst.patternInDesugarExpr = src.patternInDesugarExpr
                dst.inPos = src.inPos
                dst.inExpression = cloneExpr(src.inExpression, visitFunc)
                dst.rightParenPos = src.rightParenPos
                dst.wherePos = src.wherePos
                dst.patternGuard = cloneExpr(src.patternGuard, visitFunc)
                dst.body = cloneBlock(src.body, visitFunc)
                dst.forInKind = src.forInKind
            }
        }
        if (let Some(src) <- (source as WhileExpr)) { if (let Some(dst) <- (target as WhileExpr)) { dst.whilePos = src.whilePos; dst.leftParenPos = src.leftParenPos; dst.condExpr = cloneExpr(src.condExpr, visitFunc); dst.rightParenPos = src.rightParenPos; dst.body = cloneBlock(src.body, visitFunc); dst.sugarKind = src.sugarKind } }
        if (let Some(src) <- (source as DoWhileExpr)) { if (let Some(dst) <- (target as DoWhileExpr)) { dst.doPos = src.doPos; dst.body = cloneBlock(src.body, visitFunc); dst.whilePos = src.whilePos; dst.leftParenPos = src.leftParenPos; dst.condExpr = cloneExpr(src.condExpr, visitFunc); dst.rightParenPos = src.rightParenPos } }
    }

    private static func cloneHandler(source: Handler, visitFunc: (Node, Node) -> Unit): Handler {
        let target = Handler()
        target.pos = source.pos
        target.commandPattern = clonePattern(source.commandPattern, visitFunc)
        target.block = cloneBlock(source.block, visitFunc)
        target.desugaredLambda = if (let Some(lambda) <- source.desugaredLambda) { CloneNode(lambda, visitFunc) as LambdaExpr } else { None }
        target.commandResultTy = source.commandResultTy
        return target
    }

    private static func copyOperatorExpr(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(src) <- (source as OverloadableExpr)) { if (let Some(dst) <- (target as OverloadableExpr)) { dst.op = src.op } }
        if (let Some(src) <- (source as AssignExpr)) { if (let Some(dst) <- (target as AssignExpr)) { dst.leftValue = cloneExpr(src.leftValue, visitFunc); dst.assignPos = src.assignPos; dst.rightExpr = cloneExpr(src.rightExpr, visitFunc); dst.isCompound = src.isCompound } }
        if (let Some(src) <- (source as IncOrDecExpr)) { if (let Some(dst) <- (target as IncOrDecExpr)) { dst.operatorPos = src.operatorPos; dst.expr = cloneExpr(src.expr, visitFunc) } }
        if (let Some(src) <- (source as UnaryExpr)) { if (let Some(dst) <- (target as UnaryExpr)) { dst.expr = cloneExpr(src.expr, visitFunc); dst.operatorPos = src.operatorPos } }
        if (let Some(src) <- (source as BinaryExpr)) { if (let Some(dst) <- (target as BinaryExpr)) { dst.leftExpr = cloneExpr(src.leftExpr, visitFunc); dst.rightExpr = cloneExpr(src.rightExpr, visitFunc); dst.operatorPos = src.operatorPos } }
        if (let Some(src) <- (source as IsExpr)) { if (let Some(dst) <- (target as IsExpr)) { dst.leftExpr = cloneExpr(src.leftExpr, visitFunc); dst.isType = cloneType(src.isType, visitFunc); dst.isPos = src.isPos } }
        if (let Some(src) <- (source as AsExpr)) { if (let Some(dst) <- (target as AsExpr)) { dst.leftExpr = cloneExpr(src.leftExpr, visitFunc); dst.asType = cloneType(src.asType, visitFunc); dst.asPos = src.asPos } }
        if (let Some(src) <- (source as RangeExpr)) { if (let Some(dst) <- (target as RangeExpr)) { dst.startExpr = cloneExpr(src.startExpr, visitFunc); dst.rangePos = src.rangePos; dst.stopExpr = cloneExpr(src.stopExpr, visitFunc); dst.colonPos = src.colonPos; dst.stepExpr = cloneExpr(src.stepExpr, visitFunc); dst.decl = src.decl; dst.isClosed = src.isClosed } }
        if (let Some(src) <- (source as SubscriptExpr)) {
            if (let Some(dst) <- (target as SubscriptExpr)) {
                dst.baseExpr = cloneExpr(src.baseExpr, visitFunc)
                dst.leftParenPos = src.leftParenPos
                for (expr in src.indexExprs) { if (let Some(cloned) <- (CloneNode(expr, visitFunc) as Expr)) { dst.indexExprs.add(cloned) } }
                for (pos in src.commaPos) { dst.commaPos.add(pos) }
                dst.rightParenPos = src.rightParenPos
                dst.isTupleAccess = src.isTupleAccess
            }
        }
    }

    private static func copyLiteralAndCallExpr(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(src) <- (source as InterpolationExpr)) { if (let Some(dst) <- (target as InterpolationExpr)) { dst.rawString = src.rawString; dst.dollarPos = src.dollarPos; dst.block = cloneBlock(src.block, visitFunc) } }
        if (let Some(src) <- (source as StrInterpolationExpr)) {
            if (let Some(dst) <- (target as StrInterpolationExpr)) {
                dst.rawString = src.rawString
                for (part in src.strParts) { dst.strParts.add(part) }
                for (expr in src.strPartExprs) { if (let Some(cloned) <- (CloneNode(expr, visitFunc) as Expr)) { dst.strPartExprs.add(cloned) } }
            }
        }
        if (let Some(src) <- (source as LitConstExpr)) {
            if (let Some(dst) <- (target as LitConstExpr)) {
                dst.ref = cloneRefType(src.ref, visitFunc)
                dst.rawString = src.rawString
                dst.siExpr = if (let Some(expr) <- src.siExpr) { CloneNode(expr, visitFunc) as StrInterpolationExpr } else { None }
                dst.stringValue = src.stringValue
                for (code in src.codepoint) { dst.codepoint.add(code) }
                dst.kind = src.kind
                dst.stringKind = src.stringKind
                dst.isSingleQuote = src.isSingleQuote
                dst.delimiterNum = src.delimiterNum
            }
        }
        if (let Some(src) <- (source as FuncArg)) {
            if (let Some(dst) <- (target as FuncArg)) {
                dst.name = cloneSrcIdentifier(src.name)
                dst.colonPos = src.colonPos
                dst.expr = cloneExpr(src.expr, visitFunc)
                dst.commaPos = src.commaPos
                dst.withInout = src.withInout
                dst.inoutPos = src.inoutPos
            }
        }
        if (let Some(src) <- (source as CallExpr)) {
            if (let Some(dst) <- (target as CallExpr)) {
                dst.baseFunc = cloneExpr(src.baseFunc, visitFunc)
                if (let Some(baseFunc) <- dst.baseFunc) {
                    if (let Some(member) <- (baseFunc as MemberAccess)) {
                        member.callOrPattern = dst
                    }
                }
                dst.leftParenPos = src.leftParenPos
                let cloneTable = HashMap<Node, FuncArg>()
                for (arg in src.args) {
                    if (let Some(cloned) <- (CloneNode(arg, visitFunc) as FuncArg)) {
                        dst.args.add(cloned)
                        cloneTable[arg] = cloned
                    }
                }
                dst.rightParenPos = src.rightParenPos
                dst.resolvedFunction = src.resolvedFunction
                dst.callKind = src.callKind
                if (let Some(sourceDesugarArgs) <- src.desugarArgs) {
                    for (arg in src.defaultArgs) {
                        if (let Some(cloned) <- (CloneNode(arg, visitFunc) as FuncArg)) {
                            dst.defaultArgs.add(cloned)
                            cloneTable[arg] = cloned
                        }
                    }
                    let clonedDesugarArgs = ArrayList<FuncArg>()
                    for (sourceArg in sourceDesugarArgs) {
                        clonedDesugarArgs.add(cloneTable.get(sourceArg).getOrThrow())
                    }
                    dst.desugarArgs = Some(clonedDesugarArgs)
                }
                dst.needCheckToTokens = src.needCheckToTokens
                dst.sugarKind = src.sugarKind
            }
        }
    }

    private static func copyReferenceExpr(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(src) <- (source as NameReferenceExpr)) {
            if (let Some(dst) <- (target as NameReferenceExpr)) {
                dst.leftAnglePos = src.leftAnglePos
                for (ty in src.typeArguments) { if (let Some(cloned) <- (CloneNode(ty, visitFunc) as Type)) { dst.typeArguments.add(cloned) } }
                dst.rightAnglePos = src.rightAnglePos
                for (ty in src.instTys) { dst.instTys.add(ty) }
                dst.callOrPattern = src.callOrPattern
                dst.matchedParentTy = src.matchedParentTy
                dst.aliasTarget = src.aliasTarget
                dst.isAlone = src.isAlone
                dst.compilerAddedTyArgs = src.compilerAddedTyArgs
            }
        }
        if (let Some(src) <- (source as MemberAccess)) {
            if (let Some(dst) <- (target as MemberAccess)) {
                dst.baseExpr = cloneExpr(src.baseExpr, visitFunc)
                dst.dotPos = src.dotPos
                dst.field = cloneSrcIdentifier(src.field)
                for (decl in src.targets) { dst.targets.add(decl) }
                dst.target = src.target
                for (entry in src.foundUpperBoundMap) { dst.foundUpperBoundMap.add(entry) }
                dst.isExposedAccess = src.isExposedAccess
                dst.isPattern = src.isPattern
            }
        }
        if (let Some(src) <- (source as ParenExpr)) { if (let Some(dst) <- (target as ParenExpr)) { dst.leftParenPos = src.leftParenPos; dst.expr = cloneExpr(src.expr, visitFunc); dst.rightParenPos = src.rightParenPos } }
        if (let Some(src) <- (source as LambdaExpr)) { if (let Some(dst) <- (target as LambdaExpr)) { dst.funcBody = cloneFuncBody(src.funcBody, visitFunc); dst.mangledName = src.mangledName } }
        if (let Some(src) <- (source as IfAvailableExpr)) {
            if (let Some(dst) <- (target as IfAvailableExpr)) {
                if (let Some(arg) <- src.GetArg()) {
                    if (let Some(cloned) <- (CloneNode(arg, visitFunc) as FuncArg)) {
                        dst.SetArg(cloned)
                    }
                }
                if (let Some(lambda) <- src.GetLambda1()) {
                    if (let Some(cloned) <- (CloneNode(lambda, visitFunc) as LambdaExpr)) {
                        dst.SetLambda1(cloned)
                    }
                }
                if (let Some(lambda) <- src.GetLambda2()) {
                    if (let Some(cloned) <- (CloneNode(lambda, visitFunc) as LambdaExpr)) {
                        dst.SetLambda2(cloned)
                    }
                }
            }
        }
        if (let Some(src) <- (source as TrailingClosureExpr)) { if (let Some(dst) <- (target as TrailingClosureExpr)) { dst.leftLambda = src.leftLambda; dst.expr = cloneExpr(src.expr, visitFunc); dst.lambda = if (let Some(lambda) <- src.lambda) { CloneNode(lambda, visitFunc) as LambdaExpr } else { None }; dst.rightLambda = src.rightLambda } }
        if (let Some(src) <- (source as OptionalExpr)) { if (let Some(dst) <- (target as OptionalExpr)) { dst.baseExpr = cloneExpr(src.baseExpr, visitFunc); dst.questPos = src.questPos } }
        if (let Some(src) <- (source as OptionalChainExpr)) { if (let Some(dst) <- (target as OptionalChainExpr)) { dst.expr = cloneExpr(src.expr, visitFunc) } }
        if (let Some(src) <- (source as ArrayLit)) { if (let Some(dst) <- (target as ArrayLit)) { dst.leftSquarePos = src.leftSquarePos; for (expr in src.children) { if (let Some(cloned) <- (CloneNode(expr, visitFunc) as Expr)) { dst.children.add(cloned) } }; for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }; dst.rightSquarePos = src.rightSquarePos; dst.initFunc = src.initFunc } }
        if (let Some(src) <- (source as ArrayExpr)) { if (let Some(dst) <- (target as ArrayExpr)) { dst.typeNode = cloneType(src.typeNode, visitFunc); dst.leftParenPos = src.leftParenPos; for (arg in src.args) { if (let Some(cloned) <- (CloneNode(arg, visitFunc) as FuncArg)) { dst.args.add(cloned) } }; for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }; dst.rightParenPos = src.rightParenPos; dst.initFunc = src.initFunc; dst.isValueArray = src.isValueArray } }
        if (let Some(src) <- (source as PointerExpr)) { if (let Some(dst) <- (target as PointerExpr)) { dst.typeNode = cloneType(src.typeNode, visitFunc); dst.arg = cloneFuncArg(src.arg, visitFunc) } }
        if (let Some(src) <- (source as TupleLit)) { if (let Some(dst) <- (target as TupleLit)) { dst.leftParenPos = src.leftParenPos; for (expr in src.children) { if (let Some(cloned) <- (CloneNode(expr, visitFunc) as Expr)) { dst.children.add(cloned) } }; for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }; dst.rightParenPos = src.rightParenPos } }
        if (let Some(src) <- (source as TypeConvExpr)) { if (let Some(dst) <- (target as TypeConvExpr)) { dst.typeNode = cloneType(src.typeNode, visitFunc); dst.leftParenPos = src.leftParenPos; dst.expr = cloneExpr(src.expr, visitFunc); dst.rightParenPos = src.rightParenPos } }
        if (let Some(src) <- (source as RefExpr)) { if (let Some(dst) <- (target as RefExpr)) { dst.ref = cloneReference(src.ref); dst.isThis = src.isThis; dst.isSuper = src.isSuper; dst.isQuoteDollar = src.isQuoteDollar } }
        if (let Some(src) <- (source as PrimitiveTypeExpr)) { if (let Some(dst) <- (target as PrimitiveTypeExpr)) { dst.typeKind = src.typeKind } }
        if (let Some(src) <- (source as InvalidExpr)) { if (let Some(dst) <- (target as InvalidExpr)) { dst.value = src.value } }
        if (let Some(src) <- (source as SpawnExpr)) { if (let Some(dst) <- (target as SpawnExpr)) { dst.spawnPos = src.spawnPos; dst.futureObj = if (let Some(decl) <- src.futureObj) { CloneNode(decl, visitFunc) as VarDecl } else { None }; dst.task = cloneExpr(src.task, visitFunc); dst.arg = cloneExpr(src.arg, visitFunc); dst.leftParenPos = src.leftParenPos; dst.rightParenPos = src.rightParenPos } }
        if (let Some(src) <- (source as SynchronizedExpr)) { if (let Some(dst) <- (target as SynchronizedExpr)) { dst.syncPos = src.syncPos; dst.leftParenPos = src.leftParenPos; dst.mutex = cloneExpr(src.mutex, visitFunc); dst.rightParenPos = src.rightParenPos; dst.body = cloneBlock(src.body, visitFunc) } }
    }

    private static func copyMacro(source: Node, target: Node, visitFunc: (Node, Node) -> Unit): Unit {
        if (let Some(src) <- (source as MacroExpandExpr)) {
            if (let Some(dst) <- (target as MacroExpandExpr)) {
                dst.invocation = CloneMacroInvocation(src.invocation)
                dst.identifier = cloneIdentifier(src.identifier)
                for (annotation in src.annotations) { if (let Some(cloned) <- (CloneNode(annotation, visitFunc) as Annotation)) { dst.annotations.add(cloned) } }
                for (modifier in src.modifiers) { if (let Some(cloned) <- (CloneNode(modifier, visitFunc) as Modifier)) { dst.modifiers.add(cloned) } }
            }
        }
        if (let Some(src) <- (source as MacroExpandDecl)) {
            if (let Some(dst) <- (target as MacroExpandDecl)) { dst.invocation = CloneMacroInvocation(src.invocation) }
        }
        if (let Some(src) <- (source as MacroExpandParam)) {
            if (let Some(dst) <- (target as MacroExpandParam)) { dst.invocation = CloneMacroInvocation(src.invocation) }
        }
        if (let Some(src) <- (source as Modifier)) {
            if (let Some(dst) <- (target as Modifier)) {
                dst.modifier = src.modifier
                dst.isExplicit = src.isExplicit
            }
        }
        if (let Some(src) <- (source as Annotation)) {
            if (let Some(dst) <- (target as Annotation)) {
                dst.isCompileTimeVisible = src.isCompileTimeVisible
                dst.kind = src.kind
                dst.identifier = cloneIdentifier(src.identifier)
                dst.lsquarePos = src.lsquarePos
                for (arg in src.args) { if (let Some(cloned) <- (CloneNode(arg, visitFunc) as FuncArg)) { dst.args.add(cloned) } }
                dst.rsquarePos = src.rsquarePos
                dst.overflowStrategy = src.overflowStrategy
                for (token in src.attrs) { dst.attrs.add(token) }
                for (pos in src.attrCommas) { dst.attrCommas.add(pos) }
                dst.definedPackage = src.definedPackage
                dst.condExpr = cloneExpr(src.condExpr, visitFunc)
                dst.target = src.target
                dst.runtimeVisible = src.runtimeVisible
                dst.baseExpr = cloneExpr(src.baseExpr, visitFunc)
            }
        }
    }
}
