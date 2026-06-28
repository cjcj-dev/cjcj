package cangjie_compiler::ast

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
    if (let Some(ty) <- source.GetTy()) {
        target.SetTy(ty)
    }
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
    if (let Some(cloned) <- (ASTCloner.Clone(source) as Generic)) {
        return cloned
    }
    return Generic()
}

public func CloneGeneric(source: Generic, visitFunc: (Node, Node) -> Unit): Generic {
    if (let Some(cloned) <- (ASTCloner.Clone(source, visitFunc) as Generic)) {
        return cloned
    }
    return Generic()
}

public class ASTCloner {
    private static var cloneDepth: Int64 = 0
    private static var targetAddr2targetAddr: ArrayList<(Node, (Node) -> Unit)> = ArrayList<(Node, (Node) -> Unit)>()
    private static var source2cloned: HashMap<Node, Node> = HashMap<Node, Node>()
    private static var visitor: (Node, Node) -> Unit = DefaultVisitFunc

    public init() {}

    public static func Clone(node: Node): Node {
        return CloneWithRearrange(node, DefaultVisitFunc)
    }

    public static func Clone(node: Node, visitFunc: (Node, Node) -> Unit): Node {
        return CloneWithRearrange(node, visitFunc)
    }

    private static func TargetAddrMapInsert(from: Option<Node>, target: (Node) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, target))
        }
    }

    private static func TargetAddrMapInsert(from: Option<Decl>, target: (Decl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as Decl).getOrThrow()) }))
        }
    }

    private static func TargetAddrMapInsert(from: Decl, target: (Decl) -> Unit): Unit {
        targetAddr2targetAddr.add((from, { cloned: Node => target((cloned as Decl).getOrThrow()) }))
    }

    private static func TargetAddrMapInsert(from: Option<FuncDecl>, target: (FuncDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as FuncDecl).getOrThrow()) }))
        }
    }

    private static func TargetAddrMapInsert(from: Option<PropDecl>, target: (PropDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as PropDecl).getOrThrow()) }))
        }
    }

    private static func TargetAddrMapInsert(from: Option<Expr>, target: (Expr) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as Expr).getOrThrow()) }))
        }
    }

    private static func TargetAddrMapInsert(from: Option<Pattern>, target: (Pattern) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as Pattern).getOrThrow()) }))
        }
    }

    private static func TargetAddrMapInsert(from: Option<FuncBody>, target: (FuncBody) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as FuncBody).getOrThrow()) }))
        }
    }

    private static func TargetAddrMapInsert(from: Option<ClassLikeDecl>, target: (ClassLikeDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as ClassLikeDecl).getOrThrow()) }))
        }
    }

    private static func TargetAddrMapInsert(from: Option<StructDecl>, target: (StructDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as StructDecl).getOrThrow()) }))
        }
    }

    private static func TargetAddrMapInsert(from: Option<EnumDecl>, target: (EnumDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as EnumDecl).getOrThrow()) }))
        }
    }

    private static func CloneWithRearrange(node: Node, visitFunc: (Node, Node) -> Unit): Node {
        let isRoot = cloneDepth == 0
        if (isRoot) {
            targetAddr2targetAddr.clear()
            source2cloned.clear()
            visitor = visitFunc
        }
        cloneDepth++
        let target = makeNode(node)
        CopyNodeField(node, target)
        copyCommon(node, target)
        copySpecific(node, target)
        if (let Some(sourceDecl) <- (node as Decl)) {
            if (let Some(targetDecl) <- (target as Decl)) {
                source2cloned[sourceDecl] = targetDecl
                TargetAddrMapInsert(sourceDecl.outerDecl, { value: Decl => targetDecl.outerDecl = value })
                TargetAddrMapInsert(sourceDecl.genericDecl, { value: Decl => targetDecl.genericDecl = value })
            }
        }
        if (let Some(sourceExpr) <- (node as Expr)) {
            if (let Some(targetExpr) <- (target as Expr)) {
                source2cloned[sourceExpr] = targetExpr
                TargetAddrMapInsert(sourceExpr.sourceExpr, { value: Expr => targetExpr.sourceExpr = value })
                TargetAddrMapInsert(sourceExpr.mapExpr, { value: Expr => targetExpr.mapExpr = value })
            }
        }
        if (let Some(sourceBody) <- (node as FuncBody)) {
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
        if (let Some(sourcePattern) <- (node as Pattern)) {
            if (let Some(targetPattern) <- (target as Pattern)) {
                source2cloned[sourcePattern] = targetPattern
                TargetAddrMapInsert(sourcePattern.ctxExpr, { value: Expr => targetPattern.ctxExpr = value })
            }
        }
        match (node.astKind) {
            case ASTKind.REF_EXPR =>
                let sourceRefExpr = (node as RefExpr).getOrThrow()
                let targetRefExpr = (target as RefExpr).getOrThrow()
                TargetAddrMapInsert(sourceRefExpr.ref.target, { value: Decl => targetRefExpr.ref.target = value })
                TargetAddrMapInsert(sourceRefExpr.callOrPattern,
                    { value: Node => targetRefExpr.callOrPattern = value })
            case ASTKind.ARRAY_EXPR =>
                let sourceArrayExpr = (node as ArrayExpr).getOrThrow()
                let targetArrayExpr = (target as ArrayExpr).getOrThrow()
                TargetAddrMapInsert(sourceArrayExpr.initFunc,
                    { value: FuncDecl => targetArrayExpr.initFunc = value })
            case ASTKind.ARRAY_LIT =>
                let sourceArrayLit = (node as ArrayLit).getOrThrow()
                let targetArrayLit = (target as ArrayLit).getOrThrow()
                TargetAddrMapInsert(sourceArrayLit.initFunc, { value: FuncDecl => targetArrayLit.initFunc = value })
            case ASTKind.MEMBER_ACCESS =>
                let sourceMember = (node as MemberAccess).getOrThrow()
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
                                    { value: Decl => targetMember.targets[targetIdx] = value })
                                idx++
                            }
                        }
                    }
                }
            case ASTKind.FOR_IN_EXPR =>
                let sourceForIn = (node as ForInExpr).getOrThrow()
                let targetForIn = (target as ForInExpr).getOrThrow()
                TargetAddrMapInsert(sourceForIn.patternInDesugarExpr,
                    { value: Pattern => targetForIn.patternInDesugarExpr = value })
            case ASTKind.CALL_EXPR =>
                let sourceCall = (node as CallExpr).getOrThrow()
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
                let sourceReturn = (node as ReturnExpr).getOrThrow()
                let targetReturn = (target as ReturnExpr).getOrThrow()
                TargetAddrMapInsert(sourceReturn.refFuncBody,
                    { value: FuncBody => targetReturn.refFuncBody = value })
            case ASTKind.JUMP_EXPR =>
                let sourceJump = (node as JumpExpr).getOrThrow()
                let targetJump = (target as JumpExpr).getOrThrow()
                TargetAddrMapInsert(sourceJump.refLoop, { value: Expr => targetJump.refLoop = value })
            case ASTKind.REF_TYPE =>
                let sourceRefType = (node as RefType).getOrThrow()
                let targetRefType = (target as RefType).getOrThrow()
                TargetAddrMapInsert(sourceRefType.ref.target, { value: Decl => targetRefType.ref.target = value })
            case ASTKind.QUALIFIED_TYPE =>
                let sourceQualified = (node as QualifiedType).getOrThrow()
                let targetQualified = (target as QualifiedType).getOrThrow()
                TargetAddrMapInsert(sourceQualified.target, { value: Decl => targetQualified.target = value })
            case ASTKind.FUNC_DECL =>
                let sourceFuncDecl = (node as FuncDecl).getOrThrow()
                let targetFuncDecl = (target as FuncDecl).getOrThrow()
                TargetAddrMapInsert(sourceFuncDecl.ownerFunc,
                    { value: FuncDecl => targetFuncDecl.ownerFunc = value })
                TargetAddrMapInsert(sourceFuncDecl.propDecl, { value: PropDecl => targetFuncDecl.propDecl = value })
            case ASTKind.VAR_DECL =>
                let sourceVarDecl = (node as VarDecl).getOrThrow()
                let targetVarDecl = (target as VarDecl).getOrThrow()
                TargetAddrMapInsert(sourceVarDecl.parentPattern,
                    { value: Pattern => targetVarDecl.parentPattern = value })
            case _ => ()
        }
        visitor(node, target)
        cloneDepth--
        if (isRoot) {
            for ((source, targetAddr) in targetAddr2targetAddr) {
                if (let Some(cloned) <- source2cloned.get(source)) {
                    targetAddr(cloned)
                }
            }
            visitor = DefaultVisitFunc
        }
        return target
    }

    private static func cloneExpr(node: Option<Expr>): Option<Expr> {
        if (let Some(value) <- node) {
            return Clone(value) as Expr
        }
        return None
    }

    private static func cloneType(node: Option<Type>): Option<Type> {
        if (let Some(value) <- node) {
            return Clone(value) as Type
        }
        return None
    }

    private static func clonePattern(node: Option<Pattern>): Option<Pattern> {
        if (let Some(value) <- node) {
            return Clone(value) as Pattern
        }
        return None
    }

    private static func cloneBlock(node: Option<Block>): Option<Block> {
        if (let Some(value) <- node) {
            return Clone(value) as Block
        }
        return None
    }

    private static func cloneFuncBody(node: Option<FuncBody>): Option<FuncBody> {
        if (let Some(value) <- node) {
            return Clone(value) as FuncBody
        }
        return None
    }

    private static func cloneRefType(node: Option<RefType>): Option<RefType> {
        if (let Some(value) <- node) {
            return Clone(value) as RefType
        }
        return None
    }

    private static func cloneFuncArg(node: Option<FuncArg>): Option<FuncArg> {
        if (let Some(value) <- node) {
            return Clone(value) as FuncArg
        }
        return None
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

    private static func copyCommon(source: Node, target: Node): Unit {
        if (let Some(sourceExpr) <- (source as Expr)) {
            if (let Some(targetExpr) <- (target as Expr)) {
                targetExpr.desugarExpr = cloneExpr(sourceExpr.desugarExpr)
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
                    if (let Some(cloned) <- (Clone(modifier) as Modifier)) { targetDecl.modifiers.add(cloned) }
                }
                for (annotation in sourceDecl.annotations) {
                    if (let Some(cloned) <- (Clone(annotation) as Annotation)) { targetDecl.annotations.add(cloned) }
                }
                if (let Some(array) <- sourceDecl.annotationsArray) {
                    targetDecl.annotationsArray = Clone(array) as ArrayLit
                }
                targetDecl.identifier = cloneSrcIdentifier(sourceDecl.identifier)
                targetDecl.generic = if (let Some(generic) <- sourceDecl.generic) { Clone(generic) as Generic } else { None }
                targetDecl.identifierForLsp = sourceDecl.identifierForLsp
                targetDecl.keywordPos = sourceDecl.keywordPos
                targetDecl.rawMangleName = sourceDecl.rawMangleName
                targetDecl.hash = sourceDecl.hash
                targetDecl.toBeCompiled = sourceDecl.toBeCompiled
                targetDecl.mangledName = sourceDecl.mangledName
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

    private static func copySpecific(source: Node, target: Node): Unit {
        copyImportAndPackage(source, target)
        copyDecl(source, target)
        copyPattern(source, target)
        copyType(source, target)
        copyExpr(source, target)
        copyMacro(source, target)
    }

    private static func copyImportAndPackage(source: Node, target: Node): Unit {
        if (let Some(src) <- (source as FeatureId)) {
            if (let Some(dst) <- (target as FeatureId)) {
                for (id in src.identifiers) { dst.identifiers.add(cloneIdentifier(id)) }
                for (pos in src.dotPoses) { dst.dotPoses.add(pos) }
            }
        }
        if (let Some(src) <- (source as FeaturesSet)) {
            if (let Some(dst) <- (target as FeaturesSet)) {
                dst.lCurlPos = src.lCurlPos
                for (item in src.content) { if (let Some(cloned) <- (Clone(item) as FeatureId)) { dst.content.add(cloned) } }
                for (pos in src.commaPoses) { dst.commaPoses.add(pos) }
                dst.rCurlPos = src.rCurlPos
            }
        }
        if (let Some(src) <- (source as FeaturesDirective)) {
            if (let Some(dst) <- (target as FeaturesDirective)) {
                for (annotation in src.annotations) { if (let Some(cloned) <- (Clone(annotation) as Annotation)) { dst.annotations.add(cloned) } }
                dst.featuresSet = if (let Some(set) <- src.featuresSet) { Clone(set) as FeaturesSet } else { None }
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
                for (item in src.items) { if (let Some(cloned) <- (Clone(item) as ImportContent)) { dst.items.add(cloned) } }
                for (pos in src.commaPoses) { dst.commaPoses.add(pos) }
                dst.rightCurlPos = src.rightCurlPos
                dst.isDecl = src.isDecl
            }
        }
        if (let Some(src) <- (source as ImportSpec)) {
            if (let Some(dst) <- (target as ImportSpec)) {
                dst.modifier = if (let Some(modifier) <- src.modifier) { Clone(modifier) as Modifier } else { None }
                dst.importPos = src.importPos
                if (let Some(content) <- (Clone(src.content) as ImportContent)) { dst.content = content }
                for (annotation in src.annotations) { if (let Some(cloned) <- (Clone(annotation) as Annotation)) { dst.annotations.add(cloned) } }
                dst.withImplicitExport = src.withImplicitExport
            }
        }
        if (let Some(src) <- (source as PackageSpec)) {
            if (let Some(dst) <- (target as PackageSpec)) {
                dst.modifier = if (let Some(modifier) <- src.modifier) { Clone(modifier) as Modifier } else { None }
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
                dst.feature = if (let Some(feature) <- src.feature) { Clone(feature) as FeaturesDirective } else { None }
                dst.packageSpec = if (let Some(pkgSpec) <- src.packageSpec) { Clone(pkgSpec) as PackageSpec } else { None }
                for (importSpec in src.imports) { if (let Some(cloned) <- (Clone(importSpec) as ImportSpec)) { dst.imports.add(cloned) } }
                for (decl in src.decls) { if (let Some(cloned) <- (Clone(decl) as Decl)) { dst.decls.add(cloned) } }
                for (node in src.trashBin) { dst.trashBin.add(Clone(node)) }
                dst.curPackage = src.curPackage
                dst.indexOfPackage = src.indexOfPackage
                dst.hasMacro = src.hasMacro
                dst.macroCallFilePath = src.macroCallFilePath
                dst.macroCallPosBase = src.macroCallPosBase
                for (node in src.originalMacroCallNodes) { dst.originalMacroCallNodes.add(Clone(node)) }
                for (decl in src.exportedInternalDecls) { if (let Some(cloned) <- (Clone(decl) as Decl)) { dst.exportedInternalDecls.add(cloned) } }
                dst.isCommon = src.isCommon
                dst.isSpecific = src.isSpecific
            }
        }
        if (let Some(src) <- (source as Package)) {
            if (let Some(dst) <- (target as Package)) {
                dst.fullPackageName = src.fullPackageName
                for (file in src.files) { if (let Some(cloned) <- (Clone(file) as File)) { dst.files.add(cloned) } }
                for (decl in src.genericInstantiatedDecls) { if (let Some(cloned) <- (Clone(decl) as Decl)) { dst.genericInstantiatedDecls.add(cloned) } }
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

    private static func copyDecl(source: Node, target: Node): Unit {
        if (let Some(src) <- (source as InheritableDecl)) {
            if (let Some(dst) <- (target as InheritableDecl)) {
                dst.upperBoundPos = src.upperBoundPos
                for (ty in src.inheritedTypes) { if (let Some(cloned) <- (Clone(ty) as Type)) { dst.inheritedTypes.add(cloned) } }
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
                dst.typeNode = cloneType(src.typeNode)
                dst.colonPos = src.colonPos
                dst.initializer = cloneExpr(src.initializer)
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
            if (let Some(dst) <- (target as VarWithPatternDecl)) { dst.irrefutablePattern = clonePattern(src.irrefutablePattern) }
        }
        if (let Some(src) <- (source as FuncParam)) {
            if (let Some(dst) <- (target as FuncParam)) {
                dst.notMarkPos = src.notMarkPos
                dst.assignment = cloneExpr(src.assignment)
                dst.commaPos = src.commaPos
                dst.desugarDecl = if (let Some(decl) <- src.desugarDecl) { Clone(decl) as FuncDecl } else { None }
                dst.isNamedParam = src.isNamedParam
                dst.hasLetOrVar = src.hasLetOrVar
            }
        }
        if (let Some(src) <- (source as EnumDecl)) {
            if (let Some(dst) <- (target as EnumDecl)) {
                dst.leftCurlPos = src.leftCurlPos
                dst.bodyScope = if (let Some(bodyScope) <- src.bodyScope) { Clone(bodyScope) as DummyBody } else { None }
                for (decl in src.constructors) { if (let Some(cloned) <- (Clone(decl) as Decl)) { dst.constructors.add(cloned) } }
                for (pos in src.bitOrPosVector) { dst.bitOrPosVector.add(pos) }
                for (decl in src.members) { if (let Some(cloned) <- (Clone(decl) as Decl)) { dst.members.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
                dst.hasArguments = src.hasArguments
                dst.hasEllipsis = src.hasEllipsis
                dst.ellipsisPos = src.ellipsisPos
            }
        }
        if (let Some(src) <- (source as TypeAliasDecl)) {
            if (let Some(dst) <- (target as TypeAliasDecl)) {
                dst.assignPos = src.assignPos
                dst.typeNode = cloneType(src.typeNode)
            }
        }
        if (let Some(src) <- (source as FuncParamList)) {
            if (let Some(dst) <- (target as FuncParamList)) {
                dst.leftParenPos = src.leftParenPos
                for (param in src.params) { if (let Some(cloned) <- (Clone(param) as FuncParam)) { dst.params.add(cloned) } }
                dst.rightParenPos = src.rightParenPos
                dst.variadicArgIndex = src.variadicArgIndex
                dst.hasVariableLenArg = src.hasVariableLenArg
            }
        }
        if (let Some(src) <- (source as FuncBody)) {
            if (let Some(dst) <- (target as FuncBody)) {
                for (params in src.paramLists) { if (let Some(cloned) <- (Clone(params) as FuncParamList)) { dst.paramLists.add(cloned) } }
                dst.doubleArrowPos = src.doubleArrowPos
                dst.colonPos = src.colonPos
                dst.retType = cloneType(src.retType)
                dst.body = cloneBlock(src.body)
                dst.generic = if (let Some(generic) <- src.generic) { Clone(generic) as Generic } else { None }
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
                dst.funcBody = cloneFuncBody(src.funcBody)
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
                dst.funcBody = cloneFuncBody(src.funcBody)
                dst.desugarDecl = if (let Some(decl) <- src.desugarDecl) { Clone(decl) as FuncDecl } else { None }
            }
        }
        if (let Some(src) <- (source as MainDecl)) {
            if (let Some(dst) <- (target as MainDecl)) {
                dst.funcBody = cloneFuncBody(src.funcBody)
                dst.desugarDecl = if (let Some(decl) <- src.desugarDecl) { Clone(decl) as FuncDecl } else { None }
                dst.overflowStrategy = src.overflowStrategy
                dst.isFastNative = src.isFastNative
            }
        }
        if (let Some(src) <- (source as PrimaryCtorDecl)) {
            if (let Some(dst) <- (target as PrimaryCtorDecl)) {
                dst.funcBody = cloneFuncBody(src.funcBody)
                dst.overflowStrategy = src.overflowStrategy
                dst.hasVariableLenArg = src.hasVariableLenArg
                dst.isFastNative = src.isFastNative
                dst.isConst = src.isConst
            }
        }
        if (let Some(src) <- (source as PropDecl)) {
            if (let Some(dst) <- (target as PropDecl)) {
                dst.leftCurlPos = src.leftCurlPos
                for (getter in src.getters) { if (let Some(cloned) <- (Clone(getter) as FuncDecl)) { dst.getters.add(cloned) } }
                for (setter in src.setters) { if (let Some(cloned) <- (Clone(setter) as FuncDecl)) { dst.setters.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
        if (let Some(src) <- (source as StructBody)) {
            if (let Some(dst) <- (target as StructBody)) {
                dst.leftCurlPos = src.leftCurlPos
                for (decl in src.decls) { if (let Some(cloned) <- (Clone(decl) as Decl)) { dst.decls.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
        if (let Some(src) <- (source as StructDecl)) {
            if (let Some(dst) <- (target as StructDecl)) { dst.body = if (let Some(body) <- src.body) { Clone(body) as StructBody } else { None } }
        }
        if (let Some(src) <- (source as InterfaceBody)) {
            if (let Some(dst) <- (target as InterfaceBody)) {
                dst.leftCurlPos = src.leftCurlPos
                for (decl in src.decls) { if (let Some(cloned) <- (Clone(decl) as Decl)) { dst.decls.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
        if (let Some(src) <- (source as ClassLikeDecl)) {
            if (let Some(dst) <- (target as ClassLikeDecl)) {
                for (decl in src.subDecls) { if (let Some(cloned) <- (Clone(decl) as Decl)) { dst.subDecls.add(cloned) } }
            }
        }
        if (let Some(src) <- (source as InterfaceDecl)) {
            if (let Some(dst) <- (target as InterfaceDecl)) { dst.body = if (let Some(body) <- src.body) { Clone(body) as InterfaceBody } else { None } }
        }
        if (let Some(src) <- (source as ClassBody)) {
            if (let Some(dst) <- (target as ClassBody)) {
                dst.leftCurlPos = src.leftCurlPos
                for (decl in src.decls) { if (let Some(cloned) <- (Clone(decl) as Decl)) { dst.decls.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
        if (let Some(src) <- (source as ClassDecl)) {
            if (let Some(dst) <- (target as ClassDecl)) { dst.body = if (let Some(body) <- src.body) { Clone(body) as ClassBody } else { None } }
        }
        if (let Some(src) <- (source as ExtendDecl)) {
            if (let Some(dst) <- (target as ExtendDecl)) {
                dst.extendedType = cloneType(src.extendedType)
                dst.wherePos = src.wherePos
                dst.bodyScope = if (let Some(bodyScope) <- src.bodyScope) { Clone(bodyScope) as DummyBody } else { None }
                dst.leftCurlPos = src.leftCurlPos
                for (decl in src.members) { if (let Some(cloned) <- (Clone(decl) as Decl)) { dst.members.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
    }

    private static func copyPattern(source: Node, target: Node): Unit {
        if (let Some(src) <- (source as ConstPattern)) {
            if (let Some(dst) <- (target as ConstPattern)) {
                dst.literal = cloneExpr(src.literal)
                dst.operatorCallExpr = if (let Some(call) <- src.operatorCallExpr) { Clone(call) as CallExpr } else { None }
            }
        }
        if (let Some(src) <- (source as VarPattern)) {
            if (let Some(dst) <- (target as VarPattern)) {
                dst.varDecl = if (let Some(decl) <- src.varDecl) { Clone(decl) as VarDecl } else { None }
                dst.desugarExpr = cloneExpr(src.desugarExpr)
            }
        }
        if (let Some(src) <- (source as TuplePattern)) {
            if (let Some(dst) <- (target as TuplePattern)) {
                dst.leftBracePos = src.leftBracePos
                for (pattern in src.patterns) { if (let Some(cloned) <- (Clone(pattern) as Pattern)) { dst.patterns.add(cloned) } }
                for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }
                dst.rightBracePos = src.rightBracePos
            }
        }
        if (let Some(src) <- (source as TypePattern)) {
            if (let Some(dst) <- (target as TypePattern)) {
                dst.pattern = clonePattern(src.pattern)
                dst.colonPos = src.colonPos
                dst.typeNode = cloneType(src.typeNode)
                dst.desugarExpr = cloneExpr(src.desugarExpr)
                dst.desugarVarPattern = if (let Some(pattern) <- src.desugarVarPattern) { Clone(pattern) as VarPattern } else { None }
                dst.needRuntimeTypeCheck = src.needRuntimeTypeCheck
                dst.matchBeforeRuntime = src.matchBeforeRuntime
            }
        }
        if (let Some(src) <- (source as EnumPattern)) {
            if (let Some(dst) <- (target as EnumPattern)) {
                dst.constructor = cloneExpr(src.constructor)
                for (pattern in src.patterns) { if (let Some(cloned) <- (Clone(pattern) as Pattern)) { dst.patterns.add(cloned) } }
                dst.leftParenPos = src.leftParenPos
                for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }
                dst.rightParenPos = src.rightParenPos
            }
        }
        if (let Some(src) <- (source as VarOrEnumPattern)) {
            if (let Some(dst) <- (target as VarOrEnumPattern)) {
                dst.identifier = cloneSrcIdentifier(src.identifier)
                dst.pattern = clonePattern(src.pattern)
            }
        }
        if (let Some(src) <- (source as ExceptTypePattern)) {
            if (let Some(dst) <- (target as ExceptTypePattern)) {
                dst.pattern = clonePattern(src.pattern)
                dst.patternPos = src.patternPos
                dst.colonPos = src.colonPos
                for (ty in src.types) { if (let Some(cloned) <- (Clone(ty) as Type)) { dst.types.add(cloned) } }
                for (pos in src.bitOrPosVector) { dst.bitOrPosVector.add(pos) }
            }
        }
        if (let Some(src) <- (source as CommandTypePattern)) {
            if (let Some(dst) <- (target as CommandTypePattern)) {
                dst.pattern = clonePattern(src.pattern)
                dst.patternPos = src.patternPos
                dst.colonPos = src.colonPos
                for (ty in src.types) { if (let Some(cloned) <- (Clone(ty) as Type)) { dst.types.add(cloned) } }
                for (pos in src.bitOrPosVector) { dst.bitOrPosVector.add(pos) }
            }
        }
    }

    private static func copyType(source: Node, target: Node): Unit {
        if (let Some(src) <- (source as RefType)) {
            if (let Some(dst) <- (target as RefType)) {
                dst.ref = cloneReference(src.ref)
                dst.leftAnglePos = src.leftAnglePos
                for (ty in src.typeArguments) { if (let Some(cloned) <- (Clone(ty) as Type)) { dst.typeArguments.add(cloned) } }
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
                dst.innerType = cloneType(src.innerType)
                dst.rightParenPos = src.rightParenPos
            }
        }
        if (let Some(src) <- (source as QualifiedType)) {
            if (let Some(dst) <- (target as QualifiedType)) {
                dst.baseType = cloneType(src.baseType)
                dst.dotPos = src.dotPos
                dst.field = cloneSrcIdentifier(src.field)
                dst.leftAnglePos = src.leftAnglePos
                for (ty in src.typeArguments) { if (let Some(cloned) <- (Clone(ty) as Type)) { dst.typeArguments.add(cloned) } }
                dst.rightAnglePos = src.rightAnglePos
                dst.target = src.target
            }
        }
        if (let Some(src) <- (source as OptionType)) {
            if (let Some(dst) <- (target as OptionType)) {
                dst.componentType = cloneType(src.componentType)
                dst.questNum = src.questNum
                for (pos in src.questVector) { dst.questVector.add(pos) }
                dst.desugarType = cloneRefType(src.desugarType)
            }
        }
        if (let Some(src) <- (source as ConstantType)) {
            if (let Some(dst) <- (target as ConstantType)) {
                dst.constantExpr = cloneExpr(src.constantExpr)
                dst.dollarPos = src.dollarPos
            }
        }
        if (let Some(src) <- (source as VArrayType)) {
            if (let Some(dst) <- (target as VArrayType)) {
                dst.varrayPos = src.varrayPos
                dst.leftAnglePos = src.leftAnglePos
                dst.typeArgument = cloneType(src.typeArgument)
                dst.constantType = cloneType(src.constantType)
                dst.rightAnglePos = src.rightAnglePos
            }
        }
        if (let Some(src) <- (source as FuncType)) {
            if (let Some(dst) <- (target as FuncType)) {
                dst.leftParenPos = src.leftParenPos
                for (ty in src.paramTypes) { if (let Some(cloned) <- (Clone(ty) as Type)) { dst.paramTypes.add(cloned) } }
                dst.rightParenPos = src.rightParenPos
                dst.arrowPos = src.arrowPos
                dst.retType = cloneType(src.retType)
                dst.isC = src.isC
            }
        }
        if (let Some(src) <- (source as TupleType)) {
            if (let Some(dst) <- (target as TupleType)) {
                dst.leftParenPos = src.leftParenPos
                dst.rightParenPos = src.rightParenPos
                for (ty in src.fieldTypes) { if (let Some(cloned) <- (Clone(ty) as Type)) { dst.fieldTypes.add(cloned) } }
                for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }
            }
        }
        if (let Some(src) <- (source as GenericConstraint)) {
            if (let Some(dst) <- (target as GenericConstraint)) {
                dst.wherePos = src.wherePos
                dst.refType = cloneRefType(src.refType)
                dst.operatorPos = src.operatorPos
                for (pos in src.bitAndPos) { dst.bitAndPos.add(pos) }
                for (ty in src.upperBounds) { if (let Some(cloned) <- (Clone(ty) as Type)) { dst.upperBounds.add(cloned) } }
                dst.commaPos = src.commaPos
                dst.isImplicitlyIntroduced = src.isImplicitlyIntroduced
            }
        }
        if (let Some(src) <- (source as Generic)) {
            if (let Some(dst) <- (target as Generic)) {
                dst.leftAnglePos = src.leftAnglePos
                for (param in src.typeParameters) { if (let Some(cloned) <- (Clone(param) as GenericParamDecl)) { dst.typeParameters.add(cloned) } }
                dst.rightAnglePos = src.rightAnglePos
                for (constraint in src.genericConstraints) { if (let Some(cloned) <- (Clone(constraint) as GenericConstraint)) { dst.genericConstraints.add(cloned) } }
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

    private static func copyExpr(source: Node, target: Node): Unit {
        if (let Some(src) <- (source as Block)) {
            if (let Some(dst) <- (target as Block)) {
                dst.leftCurlPos = src.leftCurlPos
                for (node in src.body) { dst.body.add(Clone(node)) }
                dst.rightCurlPos = src.rightCurlPos
                dst.unsafePos = src.unsafePos
            }
        }
        if (let Some(src) <- (source as IfExpr)) {
            if (let Some(dst) <- (target as IfExpr)) {
                dst.ifPos = src.ifPos
                dst.leftParenPos = src.leftParenPos
                dst.condExpr = cloneExpr(src.condExpr)
                dst.rightParenPos = src.rightParenPos
                dst.thenBody = cloneBlock(src.thenBody)
                dst.elsePos = src.elsePos
                dst.elseBody = cloneExpr(src.elseBody)
                dst.isElseIf = src.isElseIf
                dst.hasElse = src.hasElse
                dst.sugarKind = src.sugarKind
            }
        }
        if (let Some(src) <- (source as LetPatternDestructor)) {
            if (let Some(dst) <- (target as LetPatternDestructor)) {
                for (pattern in src.patterns) { if (let Some(cloned) <- (Clone(pattern) as Pattern)) { dst.patterns.add(cloned) } }
                for (pos in src.orPos) { dst.orPos.add(pos) }
                dst.backarrowPos = src.backarrowPos
                dst.initializer = cloneExpr(src.initializer)
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
                for (expr in src.exprs) { if (let Some(cloned) <- (Clone(expr) as Expr)) { dst.exprs.add(cloned) } }
            }
        }
        if (let Some(src) <- (source as MatchCase)) {
            if (let Some(dst) <- (target as MatchCase)) {
                for (pattern in src.patterns) { if (let Some(cloned) <- (Clone(pattern) as Pattern)) { dst.patterns.add(cloned) } }
                for (pos in src.bitOrPosVector) { dst.bitOrPosVector.add(pos) }
                dst.patternGuard = cloneExpr(src.patternGuard)
                dst.wherePos = src.wherePos
                dst.arrowPos = src.arrowPos
                dst.exprOrDecls = cloneBlock(src.exprOrDecls)
            }
        }
        if (let Some(src) <- (source as MatchCaseOther)) {
            if (let Some(dst) <- (target as MatchCaseOther)) {
                dst.matchExpr = cloneExpr(src.matchExpr)
                dst.arrowPos = src.arrowPos
                dst.exprOrDecls = cloneBlock(src.exprOrDecls)
            }
        }
        if (let Some(src) <- (source as MatchExpr)) {
            if (let Some(dst) <- (target as MatchExpr)) {
                dst.sugarKind = src.sugarKind
                dst.matchMode = src.matchMode
                dst.leftParenPos = src.leftParenPos
                dst.selector = cloneExpr(src.selector)
                dst.rightParenPos = src.rightParenPos
                dst.leftCurlPos = src.leftCurlPos
                for (matchCase in src.matchCases) { if (let Some(cloned) <- (Clone(matchCase) as MatchCase)) { dst.matchCases.add(cloned) } }
                for (other in src.matchCaseOthers) { if (let Some(cloned) <- (Clone(other) as MatchCaseOther)) { dst.matchCaseOthers.add(cloned) } }
                dst.rightCurlPos = src.rightCurlPos
            }
        }
        copyControlExpr(source, target)
        copyOperatorExpr(source, target)
        copyLiteralAndCallExpr(source, target)
        copyReferenceExpr(source, target)
    }

    private static func copyControlExpr(source: Node, target: Node): Unit {
        if (let Some(src) <- (source as TryExpr)) {
            if (let Some(dst) <- (target as TryExpr)) {
                dst.tryPos = src.tryPos
                dst.lParen = src.lParen
                for (decl in src.resourceSpec) { if (let Some(cloned) <- (Clone(decl) as VarDecl)) { dst.resourceSpec.add(cloned) } }
                for (pos in src.resourceSpecCommaPos) { dst.resourceSpecCommaPos.add(pos) }
                dst.rParen = src.rParen
                dst.tryBlock = cloneBlock(src.tryBlock)
                for (pos in src.catchPosVector) { dst.catchPosVector.add(pos) }
                for (pos in src.catchLParenPosVector) { dst.catchLParenPosVector.add(pos) }
                for (pos in src.catchRParenPosVector) { dst.catchRParenPosVector.add(pos) }
                for (block in src.catchBlocks) { if (let Some(cloned) <- (Clone(block) as Block)) { dst.catchBlocks.add(cloned) } }
                for (pattern in src.catchPatterns) { if (let Some(cloned) <- (Clone(pattern) as Pattern)) { dst.catchPatterns.add(cloned) } }
                dst.finallyPos = src.finallyPos
                dst.finallyBlock = cloneBlock(src.finallyBlock)
                for (handler in src.handlers) { dst.handlers.add(cloneHandler(handler)) }
                dst.isIllegalResourceSpec = src.isIllegalResourceSpec
                dst.isDesugaredFromTryWithResources = src.isDesugaredFromTryWithResources
                dst.isDesugaredFromSyncBlock = src.isDesugaredFromSyncBlock
                dst.tryLambda = if (let Some(lambda) <- src.tryLambda) { Clone(lambda) as LambdaExpr } else { None }
                dst.finallyLambda = if (let Some(lambda) <- src.finallyLambda) { Clone(lambda) as LambdaExpr } else { None }
            }
        }
        if (let Some(src) <- (source as ThrowExpr)) { if (let Some(dst) <- (target as ThrowExpr)) { dst.throwPos = src.throwPos; dst.expr = cloneExpr(src.expr) } }
        if (let Some(src) <- (source as PerformExpr)) { if (let Some(dst) <- (target as PerformExpr)) { dst.performPos = src.performPos; dst.expr = cloneExpr(src.expr) } }
        if (let Some(src) <- (source as ResumeExpr)) {
            if (let Some(dst) <- (target as ResumeExpr)) {
                dst.resumePos = src.resumePos
                dst.withPos = src.withPos
                dst.withExpr = cloneExpr(src.withExpr)
                dst.throwingPos = src.throwingPos
                dst.throwingExpr = cloneExpr(src.throwingExpr)
                dst.enclosing = src.enclosing
            }
        }
        if (let Some(src) <- (source as ReturnExpr)) { if (let Some(dst) <- (target as ReturnExpr)) { dst.returnPos = src.returnPos; dst.expr = cloneExpr(src.expr); dst.refFuncBody = src.refFuncBody } }
        if (let Some(src) <- (source as JumpExpr)) { if (let Some(dst) <- (target as JumpExpr)) { dst.refLoop = src.refLoop; dst.isBreak = src.isBreak } }
        if (let Some(src) <- (source as ForInExpr)) {
            if (let Some(dst) <- (target as ForInExpr)) {
                dst.leftParenPos = src.leftParenPos
                dst.pattern = clonePattern(src.pattern)
                dst.patternInDesugarExpr = src.patternInDesugarExpr
                dst.inPos = src.inPos
                dst.inExpression = cloneExpr(src.inExpression)
                dst.rightParenPos = src.rightParenPos
                dst.wherePos = src.wherePos
                dst.patternGuard = cloneExpr(src.patternGuard)
                dst.body = cloneBlock(src.body)
                dst.forInKind = src.forInKind
            }
        }
        if (let Some(src) <- (source as WhileExpr)) { if (let Some(dst) <- (target as WhileExpr)) { dst.whilePos = src.whilePos; dst.leftParenPos = src.leftParenPos; dst.condExpr = cloneExpr(src.condExpr); dst.rightParenPos = src.rightParenPos; dst.body = cloneBlock(src.body); dst.sugarKind = src.sugarKind } }
        if (let Some(src) <- (source as DoWhileExpr)) { if (let Some(dst) <- (target as DoWhileExpr)) { dst.doPos = src.doPos; dst.body = cloneBlock(src.body); dst.whilePos = src.whilePos; dst.leftParenPos = src.leftParenPos; dst.condExpr = cloneExpr(src.condExpr); dst.rightParenPos = src.rightParenPos } }
    }

    private static func cloneHandler(source: Handler): Handler {
        let target = Handler()
        target.pos = source.pos
        target.commandPattern = clonePattern(source.commandPattern)
        target.block = cloneBlock(source.block)
        target.desugaredLambda = if (let Some(lambda) <- source.desugaredLambda) { Clone(lambda) as LambdaExpr } else { None }
        target.commandResultTy = source.commandResultTy
        return target
    }

    private static func copyOperatorExpr(source: Node, target: Node): Unit {
        if (let Some(src) <- (source as OverloadableExpr)) { if (let Some(dst) <- (target as OverloadableExpr)) { dst.op = src.op } }
        if (let Some(src) <- (source as AssignExpr)) { if (let Some(dst) <- (target as AssignExpr)) { dst.leftValue = cloneExpr(src.leftValue); dst.assignPos = src.assignPos; dst.rightExpr = cloneExpr(src.rightExpr); dst.isCompound = src.isCompound } }
        if (let Some(src) <- (source as IncOrDecExpr)) { if (let Some(dst) <- (target as IncOrDecExpr)) { dst.operatorPos = src.operatorPos; dst.expr = cloneExpr(src.expr) } }
        if (let Some(src) <- (source as UnaryExpr)) { if (let Some(dst) <- (target as UnaryExpr)) { dst.expr = cloneExpr(src.expr); dst.operatorPos = src.operatorPos } }
        if (let Some(src) <- (source as BinaryExpr)) { if (let Some(dst) <- (target as BinaryExpr)) { dst.leftExpr = cloneExpr(src.leftExpr); dst.rightExpr = cloneExpr(src.rightExpr); dst.operatorPos = src.operatorPos } }
        if (let Some(src) <- (source as IsExpr)) { if (let Some(dst) <- (target as IsExpr)) { dst.leftExpr = cloneExpr(src.leftExpr); dst.isType = cloneType(src.isType); dst.isPos = src.isPos } }
        if (let Some(src) <- (source as AsExpr)) { if (let Some(dst) <- (target as AsExpr)) { dst.leftExpr = cloneExpr(src.leftExpr); dst.asType = cloneType(src.asType); dst.asPos = src.asPos } }
        if (let Some(src) <- (source as RangeExpr)) { if (let Some(dst) <- (target as RangeExpr)) { dst.startExpr = cloneExpr(src.startExpr); dst.rangePos = src.rangePos; dst.stopExpr = cloneExpr(src.stopExpr); dst.colonPos = src.colonPos; dst.stepExpr = cloneExpr(src.stepExpr); dst.decl = src.decl; dst.isClosed = src.isClosed } }
        if (let Some(src) <- (source as SubscriptExpr)) {
            if (let Some(dst) <- (target as SubscriptExpr)) {
                dst.baseExpr = cloneExpr(src.baseExpr)
                dst.leftParenPos = src.leftParenPos
                for (expr in src.indexExprs) { if (let Some(cloned) <- (Clone(expr) as Expr)) { dst.indexExprs.add(cloned) } }
                for (pos in src.commaPos) { dst.commaPos.add(pos) }
                dst.rightParenPos = src.rightParenPos
                dst.isTupleAccess = src.isTupleAccess
            }
        }
    }

    private static func copyLiteralAndCallExpr(source: Node, target: Node): Unit {
        if (let Some(src) <- (source as InterpolationExpr)) { if (let Some(dst) <- (target as InterpolationExpr)) { dst.rawString = src.rawString; dst.dollarPos = src.dollarPos; dst.block = cloneBlock(src.block) } }
        if (let Some(src) <- (source as StrInterpolationExpr)) {
            if (let Some(dst) <- (target as StrInterpolationExpr)) {
                dst.rawString = src.rawString
                for (part in src.strParts) { dst.strParts.add(part) }
                for (expr in src.strPartExprs) { if (let Some(cloned) <- (Clone(expr) as Expr)) { dst.strPartExprs.add(cloned) } }
            }
        }
        if (let Some(src) <- (source as LitConstExpr)) {
            if (let Some(dst) <- (target as LitConstExpr)) {
                dst.ref = cloneRefType(src.ref)
                dst.rawString = src.rawString
                dst.siExpr = if (let Some(expr) <- src.siExpr) { Clone(expr) as StrInterpolationExpr } else { None }
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
                dst.expr = cloneExpr(src.expr)
                dst.commaPos = src.commaPos
                dst.withInout = src.withInout
                dst.inoutPos = src.inoutPos
            }
        }
        if (let Some(src) <- (source as CallExpr)) {
            if (let Some(dst) <- (target as CallExpr)) {
                dst.baseFunc = cloneExpr(src.baseFunc)
                if (let Some(baseFunc) <- dst.baseFunc) {
                    if (let Some(member) <- (baseFunc as MemberAccess)) {
                        member.callOrPattern = dst
                    }
                }
                dst.leftParenPos = src.leftParenPos
                let cloneTable = HashMap<Node, FuncArg>()
                for (arg in src.args) {
                    if (let Some(cloned) <- (Clone(arg) as FuncArg)) {
                        dst.args.add(cloned)
                        cloneTable[arg] = cloned
                    }
                }
                dst.rightParenPos = src.rightParenPos
                dst.resolvedFunction = src.resolvedFunction
                dst.callKind = src.callKind
                if (let Some(sourceDesugarArgs) <- src.desugarArgs) {
                    for (arg in src.defaultArgs) {
                        if (let Some(cloned) <- (Clone(arg) as FuncArg)) {
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

    private static func copyReferenceExpr(source: Node, target: Node): Unit {
        if (let Some(src) <- (source as NameReferenceExpr)) {
            if (let Some(dst) <- (target as NameReferenceExpr)) {
                dst.leftAnglePos = src.leftAnglePos
                for (ty in src.typeArguments) { if (let Some(cloned) <- (Clone(ty) as Type)) { dst.typeArguments.add(cloned) } }
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
                dst.baseExpr = cloneExpr(src.baseExpr)
                dst.dotPos = src.dotPos
                dst.field = cloneSrcIdentifier(src.field)
                for (decl in src.targets) { dst.targets.add(decl) }
                dst.target = src.target
                for (entry in src.foundUpperBoundMap) { dst.foundUpperBoundMap.add(entry) }
                dst.isExposedAccess = src.isExposedAccess
                dst.isPattern = src.isPattern
            }
        }
        if (let Some(src) <- (source as ParenExpr)) { if (let Some(dst) <- (target as ParenExpr)) { dst.leftParenPos = src.leftParenPos; dst.expr = cloneExpr(src.expr); dst.rightParenPos = src.rightParenPos } }
        if (let Some(src) <- (source as LambdaExpr)) { if (let Some(dst) <- (target as LambdaExpr)) { dst.funcBody = cloneFuncBody(src.funcBody); dst.mangledName = src.mangledName } }
        if (let Some(src) <- (source as IfAvailableExpr)) {
            if (let Some(dst) <- (target as IfAvailableExpr)) {
                if (let Some(arg) <- src.GetArg()) {
                    if (let Some(cloned) <- (Clone(arg) as FuncArg)) {
                        dst.SetArg(cloned)
                    }
                }
                if (let Some(lambda) <- src.GetLambda1()) {
                    if (let Some(cloned) <- (Clone(lambda) as LambdaExpr)) {
                        dst.SetLambda1(cloned)
                    }
                }
                if (let Some(lambda) <- src.GetLambda2()) {
                    if (let Some(cloned) <- (Clone(lambda) as LambdaExpr)) {
                        dst.SetLambda2(cloned)
                    }
                }
            }
        }
        if (let Some(src) <- (source as TrailingClosureExpr)) { if (let Some(dst) <- (target as TrailingClosureExpr)) { dst.leftLambda = src.leftLambda; dst.expr = cloneExpr(src.expr); dst.lambda = if (let Some(lambda) <- src.lambda) { Clone(lambda) as LambdaExpr } else { None }; dst.rightLambda = src.rightLambda } }
        if (let Some(src) <- (source as OptionalExpr)) { if (let Some(dst) <- (target as OptionalExpr)) { dst.baseExpr = cloneExpr(src.baseExpr); dst.questPos = src.questPos } }
        if (let Some(src) <- (source as OptionalChainExpr)) { if (let Some(dst) <- (target as OptionalChainExpr)) { dst.expr = cloneExpr(src.expr) } }
        if (let Some(src) <- (source as ArrayLit)) { if (let Some(dst) <- (target as ArrayLit)) { dst.leftSquarePos = src.leftSquarePos; for (expr in src.children) { if (let Some(cloned) <- (Clone(expr) as Expr)) { dst.children.add(cloned) } }; for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }; dst.rightSquarePos = src.rightSquarePos; dst.initFunc = src.initFunc } }
        if (let Some(src) <- (source as ArrayExpr)) { if (let Some(dst) <- (target as ArrayExpr)) { dst.typeNode = cloneType(src.typeNode); dst.leftParenPos = src.leftParenPos; for (arg in src.args) { if (let Some(cloned) <- (Clone(arg) as FuncArg)) { dst.args.add(cloned) } }; for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }; dst.rightParenPos = src.rightParenPos; dst.initFunc = src.initFunc; dst.isValueArray = src.isValueArray } }
        if (let Some(src) <- (source as PointerExpr)) { if (let Some(dst) <- (target as PointerExpr)) { dst.typeNode = cloneType(src.typeNode); dst.arg = cloneFuncArg(src.arg) } }
        if (let Some(src) <- (source as TupleLit)) { if (let Some(dst) <- (target as TupleLit)) { dst.leftParenPos = src.leftParenPos; for (expr in src.children) { if (let Some(cloned) <- (Clone(expr) as Expr)) { dst.children.add(cloned) } }; for (pos in src.commaPosVector) { dst.commaPosVector.add(pos) }; dst.rightParenPos = src.rightParenPos } }
        if (let Some(src) <- (source as TypeConvExpr)) { if (let Some(dst) <- (target as TypeConvExpr)) { dst.typeNode = cloneType(src.typeNode); dst.leftParenPos = src.leftParenPos; dst.expr = cloneExpr(src.expr); dst.rightParenPos = src.rightParenPos } }
        if (let Some(src) <- (source as RefExpr)) { if (let Some(dst) <- (target as RefExpr)) { dst.ref = cloneReference(src.ref); dst.isThis = src.isThis; dst.isSuper = src.isSuper; dst.isQuoteDollar = src.isQuoteDollar } }
        if (let Some(src) <- (source as PrimitiveTypeExpr)) { if (let Some(dst) <- (target as PrimitiveTypeExpr)) { dst.typeKind = src.typeKind } }
        if (let Some(src) <- (source as InvalidExpr)) { if (let Some(dst) <- (target as InvalidExpr)) { dst.value = src.value } }
        if (let Some(src) <- (source as SpawnExpr)) { if (let Some(dst) <- (target as SpawnExpr)) { dst.spawnPos = src.spawnPos; dst.futureObj = if (let Some(decl) <- src.futureObj) { Clone(decl) as VarDecl } else { None }; dst.task = cloneExpr(src.task); dst.arg = cloneExpr(src.arg); dst.leftParenPos = src.leftParenPos; dst.rightParenPos = src.rightParenPos } }
        if (let Some(src) <- (source as SynchronizedExpr)) { if (let Some(dst) <- (target as SynchronizedExpr)) { dst.syncPos = src.syncPos; dst.leftParenPos = src.leftParenPos; dst.mutex = cloneExpr(src.mutex); dst.rightParenPos = src.rightParenPos; dst.body = cloneBlock(src.body) } }
    }

    private static func copyMacro(source: Node, target: Node): Unit {
        if (let Some(src) <- (source as MacroExpandExpr)) {
            if (let Some(dst) <- (target as MacroExpandExpr)) {
                dst.invocation = CloneMacroInvocation(src.invocation)
                dst.identifier = cloneIdentifier(src.identifier)
                for (annotation in src.annotations) { if (let Some(cloned) <- (Clone(annotation) as Annotation)) { dst.annotations.add(cloned) } }
                for (modifier in src.modifiers) { if (let Some(cloned) <- (Clone(modifier) as Modifier)) { dst.modifiers.add(cloned) } }
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
                for (arg in src.args) { if (let Some(cloned) <- (Clone(arg) as FuncArg)) { dst.args.add(cloned) } }
                dst.rsquarePos = src.rsquarePos
                dst.overflowStrategy = src.overflowStrategy
                for (token in src.attrs) { dst.attrs.add(token) }
                for (pos in src.attrCommas) { dst.attrCommas.add(pos) }
                dst.definedPackage = src.definedPackage
                dst.condExpr = cloneExpr(src.condExpr)
                dst.target = src.target
                dst.runtimeVisible = src.runtimeVisible
                dst.baseExpr = cloneExpr(src.baseExpr)
            }
        }
    }
}
