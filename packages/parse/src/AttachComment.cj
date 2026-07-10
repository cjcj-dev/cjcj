package cjcj::parse

import cjcj::ast.{Comment, CommentGroup, CommentKind, CommentStyle, PointerExpr}
import cjcj::utils.CJC_ASSERT
import std.collection.*
import std.sort.*

private class CNode {
    public var node: Option<Node> = None
    public var position: Option<Position> = None

    public init(node: Node) {
        this.node = node
    }

    public init(position: Position) {
        this.position = position
    }
}

private func Begin(cnode: CNode): Position {
    if (let Some(nodeValue) <- cnode.node) {
        return nodeValue.begin
    }
    return cnode.position.getOrThrow()
}

private func End(cnode: CNode): Position {
    if (let Some(nodeValue) <- cnode.node) {
        return nodeValue.end
    }
    return cnode.position.getOrThrow()
}

private class CNodeWalker {
    private let enterFunc: (CNode) -> Unit
    private let exitFunc: Option<(CNode) -> Unit>

    public init(enterFunc: (CNode) -> Unit, exitFunc!: Option<(CNode) -> Unit> = None) {
        this.enterFunc = enterFunc
        this.exitFunc = exitFunc
    }

    public func Visit(cnode: CNode): Unit {
        if (let Some(nodeValue) <- cnode.node) {
            if (nodeValue.TestAnyAttr(Attribute.HAS_BROKEN, Attribute.IS_BROKEN)) {
                return
            }
        }
        enterFunc(cnode)
        if (let Some(nodeValue) <- cnode.node) {
            VisitChildren(nodeValue)
        }
        if (let Some(exitValue) <- exitFunc) {
            exitValue(cnode)
        }
    }

    private func VisitModifiers(modifiers: ArrayList<Modifier>): Unit {
        for (modifier in modifiers) {
            Visit(CNode(modifier))
        }
    }

    private func VisitToken(pos: Position): Unit {
        if (pos.IsZero()) {
            return
        }
        Visit(CNode(pos))
    }

    private func VisitAnnotations(annotations: ArrayList<Annotation>): Unit {
        for (annotation in annotations) {
            Visit(CNode(annotation))
        }
    }

    private func VisitIdentifier(id: Identifier): Unit {
        VisitToken(id.Begin())
    }

    private func VisitChild<T>(child: T): Unit where T <: Node {
        Visit(CNode(child))
    }

    private func VisitChild<T>(child: Option<T>): Unit where T <: Node {
        if (let Some(childValue) <- child) {
            Visit(CNode(childValue))
        }
    }

    private func VisitEnumCtors(e: EnumDecl): Unit {
        var ctorIdx: Int64 = 0
        var bitOrIdx: Int64 = 0
        if (e.hasEllipsis) {
            if (e.bitOrPosVector.size > e.constructors.size) {
                VisitToken(e.bitOrPosVector[bitOrIdx])
                bitOrIdx++
            }
        } else {
            if (e.bitOrPosVector.size == e.constructors.size) {
                VisitToken(e.bitOrPosVector[bitOrIdx])
                bitOrIdx++
            }
        }
        while (ctorIdx < e.constructors.size) {
            VisitChild(e.constructors[ctorIdx])
            if (bitOrIdx < e.bitOrPosVector.size) {
                VisitToken(e.bitOrPosVector[bitOrIdx])
                bitOrIdx++
            }
            ctorIdx++
        }
        if (e.hasEllipsis) {
            VisitToken(e.ellipsisPos)
        }
    }

    private func VisitChildren(node: Node): Unit {
        match (node.astKind) {
            case ASTKind.VAR_DECL =>
                if (let Some(v) <- (node as VarDecl)) {
                    VisitAnnotations(v.annotations)
                    VisitModifiers(v.modifiers)
                    VisitToken(v.keywordPos)
                    VisitIdentifier(v.identifier)
                    if (let Some(typeValue) <- v.typeNode) {
                        VisitToken(v.colonPos)
                        VisitChild(typeValue)
                    }
                    if (let Some(initValue) <- v.initializer) {
                        VisitToken(v.assignPos)
                        VisitChild(initValue)
                    }
                }
            case ASTKind.FUNC_DECL =>
                if (let Some(f) <- (node as FuncDecl)) {
                    VisitAnnotations(f.annotations)
                    VisitModifiers(f.modifiers)
                    VisitToken(f.keywordPos)
                    VisitIdentifier(f.identifier)
                    VisitChild(f.funcBody)
                }
            case ASTKind.PROP_DECL =>
                if (let Some(p) <- (node as PropDecl)) {
                    VisitAnnotations(p.annotations)
                    VisitModifiers(p.modifiers)
                    VisitToken(p.keywordPos)
                    VisitIdentifier(p.identifier)
                    if (let Some(typeValue) <- p.typeNode) {
                        VisitToken(p.colonPos)
                        VisitChild(typeValue)
                    }
                    VisitToken(p.leftCurlPos)
                    for (getter in p.getters) {
                        VisitChild(getter)
                    }
                    for (setter in p.setters) {
                        VisitChild(setter)
                    }
                    VisitToken(p.rightCurlPos)
                }
            case ASTKind.INTERFACE_DECL =>
                if (let Some(c) <- (node as InterfaceDecl)) {
                    VisitAnnotations(c.annotations)
                    VisitModifiers(c.modifiers)
                    VisitToken(c.keywordPos)
                    VisitIdentifier(c.identifier)
                    VisitGenericParams(c.generic)
                    for (it in c.inheritedTypes) {
                        VisitChild(it)
                        VisitToken(it.bitAndPos)
                    }
                    VisitGenericConstraints(c.generic)
                    VisitChild(c.body)
                }
            case ASTKind.CLASS_BODY =>
                if (let Some(b) <- (node as ClassBody)) {
                    VisitToken(b.leftCurlPos)
                    for (decl in b.decls) {
                        VisitChild(decl)
                    }
                    VisitToken(b.rightCurlPos)
                }
            case ASTKind.FUNC_PARAM_LIST =>
                if (let Some(pl) <- (node as FuncParamList)) {
                    VisitToken(pl.leftParenPos)
                    for (param in pl.params) {
                        VisitChild(param)
                        VisitToken(param.commaPos)
                    }
                    VisitToken(pl.rightParenPos)
                }
            case ASTKind.FUNC_BODY =>
                if (let Some(fb) <- (node as FuncBody)) {
                    VisitGenericParams(fb.generic)
                    for (paramList in fb.paramLists) {
                        VisitChild(paramList)
                    }
                    VisitToken(fb.colonPos)
                    VisitChild(fb.retType)
                    VisitGenericConstraints(fb.generic)
                    VisitChild(fb.body)
                }
            case ASTKind.BLOCK =>
                if (let Some(b) <- (node as Block)) {
                    VisitToken(b.unsafePos)
                    VisitToken(b.leftCurlPos)
                    for (bodyNode in b.body) {
                        VisitChild(bodyNode)
                    }
                    VisitToken(b.rightCurlPos)
                }
            case ASTKind.STRUCT_BODY =>
                if (let Some(b) <- (node as StructBody)) {
                    VisitToken(b.leftCurlPos)
                    for (decl in b.decls) {
                        VisitChild(decl)
                    }
                    VisitToken(b.rightCurlPos)
                }
            case ASTKind.INTERFACE_BODY =>
                if (let Some(b) <- (node as InterfaceBody)) {
                    VisitToken(b.leftCurlPos)
                    for (decl in b.decls) {
                        VisitChild(decl)
                    }
                    VisitToken(b.rightCurlPos)
                }
            case ASTKind.ENUM_DECL =>
                if (let Some(e) <- (node as EnumDecl)) {
                    VisitAnnotations(e.annotations)
                    VisitModifiers(e.modifiers)
                    VisitToken(e.keywordPos)
                    VisitIdentifier(e.identifier)
                    VisitGenericParams(e.generic)
                    for (it in e.inheritedTypes) {
                        VisitChild(it)
                        VisitToken(it.bitAndPos)
                    }
                    VisitGenericConstraints(e.generic)
                    VisitToken(e.leftCurlPos)
                    VisitEnumCtors(e)
                    for (member in e.members) {
                        VisitChild(member)
                    }
                    VisitToken(e.rightCurlPos)
                }
            case ASTKind.EXTEND_DECL =>
                if (let Some(ex) <- (node as ExtendDecl)) {
                    VisitAnnotations(ex.annotations)
                    VisitModifiers(ex.modifiers)
                    VisitToken(ex.keywordPos)
                    VisitIdentifier(ex.identifier)
                    VisitGenericParams(ex.generic)
                    VisitToken(ex.wherePos)
                    VisitChild(ex.extendedType)
                    VisitGenericConstraints(ex.generic)
                    VisitToken(ex.leftCurlPos)
                    for (member in ex.members) {
                        VisitChild(member)
                    }
                    VisitToken(ex.rightCurlPos)
                }
            case ASTKind.VAR_WITH_PATTERN_DECL =>
                if (let Some(vp) <- (node as VarWithPatternDecl)) {
                    VisitAnnotations(vp.annotations)
                    VisitModifiers(vp.modifiers)
                    VisitToken(vp.keywordPos)
                    VisitIdentifier(vp.identifier)
                    VisitChild(vp.irrefutablePattern)
                    VisitToken(vp.assignPos)
                    VisitChild(vp.initializer)
                }
            case ASTKind.MACRO_EXPAND_PARAM =>
                if (let Some(mp) <- (node as MacroExpandParam)) {
                    VisitAnnotations(mp.annotations)
                    VisitInvocation(mp.invocation)
                    VisitModifiers(mp.modifiers)
                    VisitToken(mp.keywordPos)
                    VisitIdentifier(mp.identifier)
                    VisitToken(mp.notMarkPos)
                    VisitToken(mp.colonPos)
                    VisitChild(mp.typeNode)
                    VisitChild(mp.assignment)
                }
            case ASTKind.MACRO_DECL =>
                if (let Some(m) <- (node as MacroDecl)) {
                    VisitAnnotations(m.annotations)
                    VisitModifiers(m.modifiers)
                    VisitToken(m.keywordPos)
                    VisitIdentifier(m.identifier)
                    VisitChild(m.funcBody)
                }
            case ASTKind.MAIN_DECL =>
                if (let Some(md) <- (node as MainDecl)) {
                    VisitAnnotations(md.annotations)
                    VisitModifiers(md.modifiers)
                    VisitToken(md.keywordPos)
                    VisitIdentifier(md.identifier)
                    VisitChild(md.funcBody)
                }
            case ASTKind.PRIMARY_CTOR_DECL =>
                if (let Some(pc) <- (node as PrimaryCtorDecl)) {
                    VisitAnnotations(pc.annotations)
                    VisitModifiers(pc.modifiers)
                    VisitToken(pc.keywordPos)
                    VisitIdentifier(pc.identifier)
                    VisitChild(pc.funcBody)
                }
            case ASTKind.IF_EXPR =>
                if (let Some(e) <- (node as IfExpr)) {
                    VisitToken(e.ifPos)
                    VisitToken(e.leftParenPos)
                    VisitChild(e.condExpr)
                    VisitToken(e.rightParenPos)
                    VisitChild(e.thenBody)
                    if (e.hasElse) {
                        VisitToken(e.elsePos)
                        VisitChild(e.elseBody)
                    }
                }
            case ASTKind.LET_PATTERN_DESTRUCTOR =>
                if (let Some(e) <- (node as LetPatternDestructor)) {
                    var idx: Int64 = 0
                    while (idx < e.patterns.size) {
                        VisitChild(e.patterns[idx])
                        if (idx < e.orPos.size) {
                            VisitToken(e.orPos[idx])
                        }
                        idx++
                    }
                    VisitToken(e.backarrowPos)
                    VisitChild(e.initializer)
                }
            case ASTKind.MATCH_CASE =>
                if (let Some(mc) <- (node as MatchCase)) {
                    var idx: Int64 = 0
                    while (idx < mc.patterns.size) {
                        VisitChild(mc.patterns[idx])
                        if (idx < mc.bitOrPosVector.size) {
                            VisitToken(mc.bitOrPosVector[idx])
                        }
                        idx++
                    }
                    VisitToken(mc.wherePos)
                    VisitChild(mc.patternGuard)
                    VisitToken(mc.arrowPos)
                    VisitChild(mc.exprOrDecls)
                }
            case ASTKind.MATCH_CASE_OTHER =>
                if (let Some(mco) <- (node as MatchCaseOther)) {
                    VisitChild(mco.matchExpr)
                    VisitToken(mco.arrowPos)
                    VisitChild(mco.exprOrDecls)
                }
            case ASTKind.MATCH_EXPR =>
                if (let Some(me) <- (node as MatchExpr)) {
                    VisitToken(me.leftParenPos)
                    VisitChild(me.selector)
                    VisitToken(me.rightParenPos)
                    VisitToken(me.leftCurlPos)
                    for (matchCase in me.matchCases) {
                        VisitChild(matchCase)
                    }
                    for (matchCaseOther in me.matchCaseOthers) {
                        VisitChild(matchCaseOther)
                    }
                    VisitToken(me.rightCurlPos)
                }
            case ASTKind.TRY_EXPR =>
                if (let Some(te) <- (node as TryExpr)) {
                    VisitToken(te.tryPos)
                    VisitToken(te.lParen)
                    var idx: Int64 = 0
                    while (idx < te.resourceSpec.size) {
                        VisitChild(te.resourceSpec[idx])
                        if (idx < te.resourceSpecCommaPos.size) {
                            VisitToken(te.resourceSpecCommaPos[idx])
                        }
                        idx++
                    }
                    VisitToken(te.rParen)
                    VisitChild(te.tryBlock)
                    idx = 0
                    while (idx < te.catchPosVector.size) {
                        VisitToken(te.catchPosVector[idx])
                        if (idx < te.catchLParenPosVector.size) {
                            VisitToken(te.catchLParenPosVector[idx])
                        }
                        if (idx < te.catchPatterns.size) {
                            VisitChild(te.catchPatterns[idx])
                        }
                        if (idx < te.catchRParenPosVector.size) {
                            VisitToken(te.catchRParenPosVector[idx])
                        }
                        if (idx < te.catchBlocks.size) {
                            VisitChild(te.catchBlocks[idx])
                        }
                        idx++
                    }
                    VisitToken(te.finallyPos)
                    VisitChild(te.finallyBlock)
                    for (handler in te.handlers) {
                        VisitToken(handler.pos)
                        VisitChild(handler.commandPattern)
                        VisitChild(handler.block)
                    }
                }
            case ASTKind.THROW_EXPR =>
                if (let Some(e) <- (node as ThrowExpr)) {
                    VisitToken(e.throwPos)
                    VisitChild(e.expr)
                }
            case ASTKind.PERFORM_EXPR =>
                if (let Some(e) <- (node as PerformExpr)) {
                    VisitToken(e.performPos)
                    VisitChild(e.expr)
                }
            case ASTKind.RESUME_EXPR =>
                if (let Some(e) <- (node as ResumeExpr)) {
                    VisitToken(e.resumePos)
                    VisitToken(e.withPos)
                    VisitChild(e.withExpr)
                    VisitToken(e.throwingPos)
                    VisitChild(e.throwingExpr)
                }
            case ASTKind.RETURN_EXPR =>
                if (let Some(e) <- (node as ReturnExpr)) {
                    VisitToken(e.returnPos)
                    VisitChild(e.expr)
                }
            case ASTKind.FOR_IN_EXPR =>
                if (let Some(e) <- (node as ForInExpr)) {
                    VisitToken(e.leftParenPos)
                    VisitChild(e.pattern)
                    VisitToken(e.inPos)
                    VisitChild(e.inExpression)
                    VisitToken(e.wherePos)
                    VisitChild(e.patternGuard)
                    VisitToken(e.rightParenPos)
                    VisitChild(e.body)
                }
            case ASTKind.WHILE_EXPR =>
                if (let Some(e) <- (node as WhileExpr)) {
                    VisitToken(e.whilePos)
                    VisitToken(e.leftParenPos)
                    VisitChild(e.condExpr)
                    VisitToken(e.rightParenPos)
                    VisitChild(e.body)
                }
            case ASTKind.DO_WHILE_EXPR =>
                if (let Some(e) <- (node as DoWhileExpr)) {
                    VisitToken(e.doPos)
                    VisitChild(e.body)
                    VisitToken(e.whilePos)
                    VisitToken(e.leftParenPos)
                    VisitChild(e.condExpr)
                    VisitToken(e.rightParenPos)
                }
            case ASTKind.ASSIGN_EXPR =>
                if (let Some(e) <- (node as AssignExpr)) {
                    VisitChild(e.leftValue)
                    VisitToken(e.assignPos)
                    VisitChild(e.rightExpr)
                }
            case ASTKind.INC_OR_DEC_EXPR =>
                if (let Some(e) <- (node as IncOrDecExpr)) {
                    VisitChild(e.expr)
                    VisitToken(e.operatorPos)
                }
            case ASTKind.UNARY_EXPR =>
                if (let Some(e) <- (node as UnaryExpr)) {
                    VisitToken(e.operatorPos)
                    VisitChild(e.expr)
                }
            case ASTKind.BINARY_EXPR =>
                if (let Some(e) <- (node as BinaryExpr)) {
                    VisitChild(e.leftExpr)
                    VisitToken(e.operatorPos)
                    VisitChild(e.rightExpr)
                }
            case ASTKind.IS_EXPR =>
                if (let Some(e) <- (node as IsExpr)) {
                    VisitChild(e.leftExpr)
                    VisitToken(e.isPos)
                    VisitChild(e.isType)
                }
            case ASTKind.AS_EXPR =>
                if (let Some(e) <- (node as AsExpr)) {
                    VisitChild(e.leftExpr)
                    VisitToken(e.asPos)
                    VisitChild(e.asType)
                }
            case ASTKind.RANGE_EXPR =>
                if (let Some(e) <- (node as RangeExpr)) {
                    VisitChild(e.startExpr)
                    VisitToken(e.rangePos)
                    VisitChild(e.stopExpr)
                    VisitToken(e.colonPos)
                    VisitChild(e.stepExpr)
                }
            case ASTKind.SUBSCRIPT_EXPR =>
                if (let Some(e) <- (node as SubscriptExpr)) {
                    VisitChild(e.baseExpr)
                    VisitToken(e.leftParenPos)
                    var idx: Int64 = 0
                    while (idx < e.indexExprs.size) {
                        VisitChild(e.indexExprs[idx])
                        if (idx < e.commaPos.size) {
                            VisitToken(e.commaPos[idx])
                        }
                        idx++
                    }
                    VisitToken(e.rightParenPos)
                }
            case ASTKind.INTERPOLATION_EXPR =>
                if (let Some(e) <- (node as InterpolationExpr)) {
                    VisitToken(e.dollarPos)
                    VisitChild(e.block)
                }
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(e) <- (node as LitConstExpr)) {
                    if (let Some(siExpr) <- e.siExpr) {
                        VisitChild(siExpr)
                    } else {
                        VisitToken(e.begin)
                    }
                }
            case ASTKind.TOKEN_PART =>
                if (let Some(e) <- (node as TokenPart)) {
                    for (token in e.tokens) {
                        VisitToken(token.Begin())
                    }
                }
            case ASTKind.QUOTE_EXPR =>
                if (let Some(e) <- (node as QuoteExpr)) {
                    VisitToken(e.quotePos)
                    VisitToken(e.leftParenPos)
                    for (exprValue in e.exprs) {
                        VisitChild(exprValue)
                    }
                    VisitToken(e.rightParenPos)
                }
            case ASTKind.STR_INTERPOLATION_EXPR =>
                if (let Some(e) <- (node as StrInterpolationExpr)) {
                    for (part in e.strPartExprs) {
                        VisitChild(part)
                    }
                }
            case ASTKind.PAREN_EXPR =>
                if (let Some(e) <- (node as ParenExpr)) {
                    VisitToken(e.leftParenPos)
                    VisitChild(e.expr)
                    VisitToken(e.rightParenPos)
                }
            case ASTKind.LAMBDA_EXPR =>
                if (let Some(e) <- (node as LambdaExpr)) {
                    if (let Some(fb) <- e.funcBody) {
                        if (let Some(bodyValue) <- fb.body) {
                            VisitToken(bodyValue.leftCurlPos)
                            for (paramList in fb.paramLists) {
                                VisitChild(paramList)
                            }
                            VisitToken(fb.doubleArrowPos)
                            for (exprValue in bodyValue.body) {
                                VisitChild(exprValue)
                            }
                            VisitToken(bodyValue.rightCurlPos)
                        }
                    }
                }
            case ASTKind.TRAIL_CLOSURE_EXPR =>
                if (let Some(e) <- (node as TrailingClosureExpr)) {
                    VisitChild(e.lambda)
                    VisitChild(e.expr)
                }
            case ASTKind.OPTIONAL_EXPR =>
                if (let Some(e) <- (node as OptionalExpr)) {
                    VisitChild(e.baseExpr)
                    VisitToken(e.questPos)
                }
            case ASTKind.OPTIONAL_CHAIN_EXPR =>
                if (let Some(e) <- (node as OptionalChainExpr)) {
                    VisitChild(e.expr)
                }
            case ASTKind.ARRAY_LIT =>
                if (let Some(e) <- (node as ArrayLit)) {
                    VisitToken(e.leftSquarePos)
                    var idx: Int64 = 0
                    while (idx < e.children.size) {
                        VisitChild(e.children[idx])
                        if (idx < e.commaPosVector.size) {
                            VisitToken(e.commaPosVector[idx])
                        }
                        idx++
                    }
                    VisitToken(e.rightSquarePos)
                }
            case ASTKind.ARRAY_EXPR =>
                if (let Some(e) <- (node as ArrayExpr)) {
                    VisitChild(e.typeNode)
                    VisitToken(e.leftParenPos)
                    var idx: Int64 = 0
                    while (idx < e.args.size) {
                        VisitChild(e.args[idx])
                        if (idx < e.commaPosVector.size) {
                            VisitToken(e.commaPosVector[idx])
                        }
                        idx++
                    }
                    VisitToken(e.rightParenPos)
                }
            case ASTKind.POINTER_EXPR =>
                if (let Some(e) <- (node as PointerExpr)) {
                    VisitChild(e.typeNode)
                    VisitChild(e.arg)
                }
            case ASTKind.TUPLE_LIT =>
                if (let Some(e) <- (node as TupleLit)) {
                    VisitToken(e.leftParenPos)
                    var idx: Int64 = 0
                    while (idx < e.children.size) {
                        VisitChild(e.children[idx])
                        if (idx < e.commaPosVector.size) {
                            VisitToken(e.commaPosVector[idx])
                        }
                        idx++
                    }
                    VisitToken(e.rightParenPos)
                }
            case ASTKind.TYPE_CONV_EXPR =>
                if (let Some(e) <- (node as TypeConvExpr)) {
                    VisitChild(e.typeNode)
                    VisitToken(e.leftParenPos)
                    VisitChild(e.expr)
                    VisitToken(e.rightParenPos)
                }
            case ASTKind.REF_EXPR =>
                if (let Some(e) <- (node as RefExpr)) {
                    VisitToken(e.leftAnglePos)
                    for (typeArgument in e.typeArguments) {
                        VisitChild(typeArgument)
                    }
                    VisitToken(e.rightAnglePos)
                }
            case ASTKind.MEMBER_ACCESS =>
                if (let Some(e) <- (node as MemberAccess)) {
                    VisitChild(e.baseExpr)
                    VisitToken(e.dotPos)
                    VisitIdentifier(e.field)
                    VisitToken(e.leftAnglePos)
                    for (typeArgument in e.typeArguments) {
                        VisitChild(typeArgument)
                    }
                    VisitToken(e.rightAnglePos)
                }
            case ASTKind.CALL_EXPR =>
                if (let Some(e) <- (node as CallExpr)) {
                    VisitChild(e.baseFunc)
                    VisitToken(e.leftParenPos)
                    for (arg in e.args) {
                        VisitChild(arg)
                        VisitToken(arg.commaPos)
                    }
                    VisitToken(e.rightParenPos)
                }
            case ASTKind.FUNC_ARG =>
                if (let Some(a) <- (node as FuncArg)) {
                    VisitToken(a.name.Begin())
                    VisitToken(a.colonPos)
                    VisitToken(a.inoutPos)
                    VisitChild(a.expr)
                }
            case ASTKind.SPAWN_EXPR =>
                if (let Some(e) <- (node as SpawnExpr)) {
                    VisitToken(e.spawnPos)
                    VisitToken(e.leftParenPos)
                    VisitChild(e.arg)
                    VisitToken(e.rightParenPos)
                    VisitChild(e.task)
                }
            case ASTKind.SYNCHRONIZED_EXPR =>
                if (let Some(e) <- (node as SynchronizedExpr)) {
                    VisitToken(e.syncPos)
                    VisitToken(e.leftParenPos)
                    VisitChild(e.mutex)
                    VisitToken(e.rightParenPos)
                    VisitChild(e.body)
                }
            case ASTKind.CONST_PATTERN =>
                if (let Some(p) <- (node as ConstPattern)) {
                    VisitChild(p.literal)
                }
            case ASTKind.VAR_PATTERN =>
                if (let Some(p) <- (node as VarPattern)) {
                    VisitChild(p.varDecl)
                }
            case ASTKind.TUPLE_PATTERN =>
                if (let Some(p) <- (node as TuplePattern)) {
                    VisitToken(p.leftBracePos)
                    var idx: Int64 = 0
                    while (idx < p.patterns.size) {
                        VisitChild(p.patterns[idx])
                        if (idx < p.commaPosVector.size) {
                            VisitToken(p.commaPosVector[idx])
                        }
                        idx++
                    }
                    VisitToken(p.rightBracePos)
                }
            case ASTKind.TYPE_PATTERN =>
                if (let Some(p) <- (node as TypePattern)) {
                    VisitChild(p.pattern)
                    VisitToken(p.colonPos)
                    VisitChild(p.typeNode)
                }
            case ASTKind.ENUM_PATTERN =>
                if (let Some(p) <- (node as EnumPattern)) {
                    VisitChild(p.constructor)
                    VisitToken(p.leftParenPos)
                    var idx: Int64 = 0
                    while (idx < p.patterns.size) {
                        VisitChild(p.patterns[idx])
                        if (idx < p.commaPosVector.size) {
                            VisitToken(p.commaPosVector[idx])
                        }
                        idx++
                    }
                    VisitToken(p.rightParenPos)
                }
            case ASTKind.VAR_OR_ENUM_PATTERN =>
                if (let Some(p) <- (node as VarOrEnumPattern)) {
                    VisitChild(p.pattern)
                }
            case ASTKind.EXCEPT_TYPE_PATTERN =>
                if (let Some(p) <- (node as ExceptTypePattern)) {
                    VisitChild(p.pattern)
                    VisitToken(p.colonPos)
                    var idx: Int64 = 0
                    while (idx < p.types.size) {
                        VisitChild(p.types[idx])
                        if (idx < p.bitOrPosVector.size) {
                            VisitToken(p.bitOrPosVector[idx])
                        }
                        idx++
                    }
                }
            case ASTKind.COMMAND_TYPE_PATTERN =>
                if (let Some(p) <- (node as CommandTypePattern)) {
                    VisitChild(p.pattern)
                    VisitToken(p.patternPos)
                    VisitToken(p.colonPos)
                    var idx: Int64 = 0
                    while (idx < p.types.size) {
                        VisitChild(p.types[idx])
                        if (idx < p.bitOrPosVector.size) {
                            VisitToken(p.bitOrPosVector[idx])
                        }
                        idx++
                    }
                }
            case ASTKind.REF_TYPE =>
                if (let Some(t) <- (node as RefType)) {
                    VisitToken(t.leftAnglePos)
                    for (typeArgument in t.typeArguments) {
                        VisitChild(typeArgument)
                    }
                    VisitToken(t.rightAnglePos)
                }
            case ASTKind.PAREN_TYPE =>
                if (let Some(t) <- (node as ParenType)) {
                    VisitToken(t.leftParenPos)
                    VisitChild(t.innerType)
                    VisitToken(t.rightParenPos)
                }
            case ASTKind.QUALIFIED_TYPE =>
                if (let Some(t) <- (node as QualifiedType)) {
                    VisitChild(t.baseType)
                    VisitToken(t.dotPos)
                    VisitToken(t.leftAnglePos)
                    for (typeArgument in t.typeArguments) {
                        VisitChild(typeArgument)
                    }
                    VisitToken(t.rightAnglePos)
                }
            case ASTKind.OPTION_TYPE =>
                if (let Some(t) <- (node as OptionType)) {
                    VisitChild(t.componentType)
                    for (quest in t.questVector) {
                        VisitToken(quest)
                    }
                }
            case ASTKind.CONSTANT_TYPE =>
                if (let Some(t) <- (node as ConstantType)) {
                    VisitToken(t.dollarPos)
                    VisitChild(t.constantExpr)
                }
            case ASTKind.VARRAY_TYPE =>
                if (let Some(t) <- (node as VArrayType)) {
                    VisitToken(t.varrayPos)
                    VisitToken(t.leftAnglePos)
                    VisitChild(t.typeArgument)
                    if (let Some(typeArgument) <- t.typeArgument) {
                        VisitToken(typeArgument.commaPos)
                    }
                    VisitChild(t.constantType)
                    VisitToken(t.rightAnglePos)
                }
            case ASTKind.FUNC_TYPE =>
                if (let Some(t) <- (node as FuncType)) {
                    VisitToken(t.leftParenPos)
                    for (paramType in t.paramTypes) {
                        VisitChild(paramType)
                        VisitToken(paramType.commaPos)
                    }
                    VisitToken(t.rightParenPos)
                    VisitToken(t.arrowPos)
                    VisitChild(t.retType)
                }
            case ASTKind.TUPLE_TYPE =>
                if (let Some(t) <- (node as TupleType)) {
                    VisitToken(t.leftParenPos)
                    var idx: Int64 = 0
                    while (idx < t.fieldTypes.size) {
                        VisitChild(t.fieldTypes[idx])
                        if (idx < t.commaPosVector.size) {
                            VisitToken(t.commaPosVector[idx])
                        }
                        idx++
                    }
                    VisitToken(t.rightParenPos)
                }
            case ASTKind.MACRO_EXPAND_EXPR =>
                if (let Some(e) <- (node as MacroExpandExpr)) {
                    VisitAnnotations(e.annotations)
                    VisitInvocation(e.invocation)
                    if (let Some(decl) <- e.invocation.decl) {
                        VisitChild(decl)
                    } else {
                        for (invocationNode in e.invocation.nodes) {
                            VisitChild(invocationNode)
                        }
                    }
                    VisitToken(e.invocation.rightParenPos)
                }
            case ASTKind.MACRO_EXPAND_DECL =>
                if (let Some(d) <- (node as MacroExpandDecl)) {
                    VisitAnnotations(d.annotations)
                    VisitInvocation(d.invocation)
                    VisitChild(d.invocation.decl)
                }
            case ASTKind.IMPORT_CONTENT =>
                if (let Some(ic) <- (node as ImportContent)) {
                    for (pos in ic.prefixPoses) {
                        VisitToken(pos)
                    }
                    for (pos in ic.prefixDotPoses) {
                        VisitToken(pos)
                    }
                    VisitToken(ic.identifier.Begin())
                    VisitToken(ic.asPos)
                    VisitToken(ic.aliasName.Begin())
                    VisitToken(ic.leftCurlPos)
                    var idx: Int64 = 0
                    while (idx < ic.items.size) {
                        VisitToken(ic.items[idx].begin)
                        if (idx < ic.commaPoses.size) {
                            VisitToken(ic.commaPoses[idx])
                        }
                        idx++
                    }
                    VisitToken(ic.rightCurlPos)
                }
            case ASTKind.IMPORT_SPEC =>
                if (let Some(importSpec) <- (node as ImportSpec)) {
                    VisitChild(importSpec.modifier)
                    VisitToken(importSpec.importPos)
                    VisitAnnotations(importSpec.annotations)
                    VisitChild(importSpec.content)
                }
            case ASTKind.PACKAGE_SPEC =>
                if (let Some(ps) <- (node as PackageSpec)) {
                    VisitChild(ps.modifier)
                    VisitToken(ps.macroPos)
                    VisitToken(ps.packagePos)
                    var idx: Int64 = 0
                    while (idx < ps.prefixPoses.size) {
                        VisitToken(ps.prefixPoses[idx])
                        if (idx < ps.prefixDotPoses.size) {
                            VisitToken(ps.prefixDotPoses[idx])
                        }
                        idx++
                    }
                    VisitToken(ps.packageName.Begin())
                }
            case ASTKind.FEATURE_ID =>
                if (let Some(fid) <- (node as FeatureId)) {
                    var idx: Int64 = 0
                    while (idx < fid.identifiers.size) {
                        VisitToken(fid.identifiers[idx].Begin())
                        if (idx < fid.dotPoses.size) {
                            VisitToken(fid.dotPoses[idx])
                        }
                        idx++
                    }
                }
            case ASTKind.FEATURES_SET =>
                if (let Some(fSet) <- (node as FeaturesSet)) {
                    VisitToken(fSet.lCurlPos)
                    var idx: Int64 = 0
                    while (idx < fSet.content.size) {
                        VisitChild(fSet.content[idx])
                        if (idx < fSet.commaPoses.size) {
                            VisitToken(fSet.commaPoses[idx])
                        }
                        idx++
                    }
                    VisitToken(fSet.rCurlPos)
                }
            case ASTKind.FEATURES_DIRECTIVE =>
                if (let Some(fd) <- (node as FeaturesDirective)) {
                    VisitAnnotations(fd.annotations)
                    VisitToken(fd.featuresPos)
                    VisitChild(fd.featuresSet)
                }
            case ASTKind.GENERIC_CONSTRAINT =>
                if (let Some(gc) <- (node as GenericConstraint)) {
                    VisitToken(gc.wherePos)
                    VisitChild(gc.refType)
                    VisitToken(gc.operatorPos)
                    var idx: Int64 = 0
                    while (idx < gc.upperBounds.size) {
                        VisitChild(gc.upperBounds[idx])
                        if (idx < gc.bitAndPos.size) {
                            VisitToken(gc.bitAndPos[idx])
                        }
                        idx++
                    }
                }
            case ASTKind.FUNC_PARAM =>
                if (let Some(p) <- (node as FuncParam)) {
                    VisitAnnotations(p.annotations)
                    VisitModifiers(p.modifiers)
                    VisitToken(p.keywordPos)
                    VisitIdentifier(p.identifier)
                    VisitToken(p.notMarkPos)
                    VisitToken(p.colonPos)
                    VisitChild(p.typeNode)
                    VisitChild(p.assignment)
                }
            case ASTKind.TYPE_ALIAS_DECL =>
                if (let Some(t) <- (node as TypeAliasDecl)) {
                    VisitAnnotations(t.annotations)
                    VisitModifiers(t.modifiers)
                    VisitToken(t.keywordPos)
                    VisitIdentifier(t.identifier)
                    VisitToken(t.assignPos)
                    VisitChild(t.typeNode)
                }
            case ASTKind.CLASS_DECL =>
                if (let Some(c) <- (node as ClassDecl)) {
                    VisitAnnotations(c.annotations)
                    VisitModifiers(c.modifiers)
                    VisitToken(c.keywordPos)
                    VisitIdentifier(c.identifier)
                    VisitGenericParams(c.generic)
                    for (it in c.inheritedTypes) {
                        VisitChild(it)
                        VisitToken(it.bitAndPos)
                    }
                    VisitGenericConstraints(c.generic)
                    VisitChild(c.body)
                }
            case ASTKind.STRUCT_DECL =>
                if (let Some(s) <- (node as StructDecl)) {
                    VisitAnnotations(s.annotations)
                    VisitModifiers(s.modifiers)
                    VisitToken(s.keywordPos)
                    VisitIdentifier(s.identifier)
                    VisitGenericParams(s.generic)
                    for (it in s.inheritedTypes) {
                        VisitChild(it)
                        VisitToken(it.bitAndPos)
                    }
                    VisitGenericConstraints(s.generic)
                    VisitChild(s.body)
                }
            case ASTKind.FILE =>
                if (let Some(f) <- (node as File)) {
                    VisitChild(f.feature)
                    VisitChild(f.packageSpec)
                    for (importSpec in f.imports) {
                        VisitChild(importSpec)
                    }
                    for (decl in f.decls) {
                        VisitChild(decl)
                    }
                }
            case ASTKind.ANNOTATION =>
                if (let Some(a) <- (node as Annotation)) {
                    VisitToken(a.begin)
                    VisitIdentifier(a.identifier)
                    VisitToken(a.lsquarePos)
                    var idx: Int64 = 0
                    while (idx < a.attrs.size) {
                        VisitToken(a.attrs[idx].Begin())
                        if (idx < a.attrCommas.size) {
                            VisitToken(a.attrCommas[idx])
                        }
                        idx++
                    }
                    VisitChild(a.condExpr)
                    VisitToken(a.rsquarePos)
                    for (arg in a.args) {
                        VisitChild(arg)
                        VisitToken(arg.commaPos)
                    }
                }
            case ASTKind.PRIMITIVE_TYPE_EXPR =>
                VisitToken(node.begin)
            case ASTKind.MODIFIER =>
                VisitToken(node.begin)
            case ASTKind.THIS_TYPE =>
                VisitToken(node.begin)
            case ASTKind.PRIMITIVE_TYPE =>
                VisitToken(node.begin)
            case ASTKind.JUMP_EXPR =>
                VisitToken(node.begin)
            case ASTKind.WILDCARD_PATTERN =>
                VisitToken(node.begin)
            case ASTKind.WILDCARD_EXPR =>
                VisitToken(node.begin)
            case ASTKind.GENERIC =>
                CJC_ASSERT(false)
            case _ => ()
        }
    }

    private func VisitGenericParams(generic: Option<Generic>): Unit {
        if (let Some(genericValue) <- generic) {
            VisitToken(genericValue.leftAnglePos)
            for (typeParam in genericValue.typeParameters) {
                VisitChild(typeParam)
            }
            VisitToken(genericValue.rightAnglePos)
        }
    }

    private func VisitGenericConstraints(generic: Option<Generic>): Unit {
        if (let Some(genericValue) <- generic) {
            for (constraint in genericValue.genericConstraints) {
                VisitChild(constraint)
                VisitToken(constraint.commaPos)
            }
        }
    }

    private func VisitInvocation(invocation: MacroInvocation): Unit {
        VisitToken(invocation.atPos)
        VisitToken(invocation.macroNamePos)
        VisitToken(invocation.leftSquarePos)
        for (token in invocation.attrs) {
            VisitToken(token.Begin())
        }
        VisitToken(invocation.rightSquarePos)
        VisitToken(invocation.leftParenPos)
    }
}

private func CollectPtrsOfASTNodes(node: File): ArrayList<CNode> {
    let ptrs = ArrayList<CNode>()
    let collect = { cnode: CNode =>
        var collectValue = true
        if (let Some(nodeValue) <- cnode.node) {
            if (nodeValue.astKind == ASTKind.FILE) {
                collectValue = false
            }
        }
        if (collectValue) {
            ptrs.add(cnode)
        }
    }
    let walker = CNodeWalker(collect)
    walker.Visit(CNode(node))
    return ptrs
}

private func SortNodesByRange(nodes: ArrayList<CNode>): Unit {
    sort(nodes, by: { left: CNode, right: CNode =>
        if (Begin(left) < Begin(right) || (Begin(left) == Begin(right) && End(left) > End(right))) {
            Ordering.LT
        } else if (Begin(right) < Begin(left) || (Begin(left) == Begin(right) && End(right) > End(left))) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: false)
}

private func AppendCommentGroup(comment: Comment, cgs: ArrayList<CommentGroup>): Unit {
    let cg = CommentGroup()
    cg.cms.add(comment)
    cgs.add(cg)
}

private func AddCommentToBackGroup(comment: Comment, cgs: ArrayList<CommentGroup>): Unit {
    CJC_ASSERT(!cgs.isEmpty())
    cgs[cgs.size - 1].cms.add(comment)
}

private func UpdateFollowInfoAndAppendCommentGroup(
    preTkIdxIgnTrivialStuff: Option<Int64>,
    comment: Comment,
    cgPreInfo: HashMap<Int64, Int64>,
    commentGroups: ArrayList<CommentGroup>
): Unit {
    if (let Some(preIdx) <- preTkIdxIgnTrivialStuff) {
        cgPreInfo[commentGroups.size] = preIdx
    }
    AppendCommentGroup(comment, commentGroups)
}

private func GetCommentKind(token: Token): CommentKind {
    CJC_ASSERT(token.kind == TokenKind.COMMENT)
    let value = token.Value()
    if (!value.startsWith("/*")) {
        return CommentKind.LINE
    }
    if (!value.startsWith("/**")) {
        return CommentKind.BLOCK
    }
    if (value.startsWith("/***")) {
        return CommentKind.BLOCK
    }
    if (value.startsWith("/**/")) {
        return CommentKind.BLOCK
    }
    return CommentKind.DOCUMENT
}

private func UpdateCommentGroups(
    tk: Token,
    preTokenIgnoreNL: Token,
    preTkIdxIgnTrivialStuff: Option<Int64>,
    commentGroups: ArrayList<CommentGroup>,
    cgPreInfo: HashMap<Int64, Int64>
): Bool {
    let commentKind = GetCommentKind(tk)
    let diffLine = tk.Begin().line - preTokenIgnoreNL.Begin().line
    if (preTokenIgnoreNL.kind == TokenKind.COMMENT) {
        if (diffLine == 0) {
            AddCommentToBackGroup(Comment(CommentStyle.OTHER, commentKind, tk), commentGroups)
        } else if (diffLine == 1) {
            let isLeadLine = match (commentGroups[commentGroups.size - 1].cms[0].style) {
                case CommentStyle.LEAD_LINE => true
                case _ => false
            }
            if (isLeadLine) {
                AddCommentToBackGroup(Comment(CommentStyle.LEAD_LINE, commentKind, tk), commentGroups)
            } else {
                UpdateFollowInfoAndAppendCommentGroup(
                    preTkIdxIgnTrivialStuff, Comment(CommentStyle.LEAD_LINE, commentKind, tk), cgPreInfo,
                    commentGroups)
                return true
            }
        } else {
            UpdateFollowInfoAndAppendCommentGroup(
                preTkIdxIgnTrivialStuff, Comment(CommentStyle.LEAD_LINE, commentKind, tk), cgPreInfo, commentGroups)
            return true
        }
    } else {
        let commentStyle = if (diffLine == 0) { CommentStyle.TRAIL_CODE } else { CommentStyle.LEAD_LINE }
        UpdateFollowInfoAndAppendCommentGroup(
            preTkIdxIgnTrivialStuff, Comment(commentStyle, commentKind, tk), cgPreInfo, commentGroups)
        return true
    }
    return false
}

private func IsTrailCommentsInRuleOne(
    cg: CommentGroup,
    cgIdx: Int64,
    node: Node,
    cgFollowInfo: HashMap<Int64, Int64>,
    tkStream: ArrayList<Token>
): Bool {
    CJC_ASSERT(!cg.cms.isEmpty())
    let diffline = cg.cms[0].info.Begin().line - node.GetEnd().line
    if (diffline == 0) {
        return true
    }
    if (diffline == 1) {
        if (cgFollowInfo.contains(cgIdx)) {
            let followIdx = cgFollowInfo.get(cgIdx).getOrThrow()
            let blankLine = tkStream[followIdx].Begin().line - cg.cms[cg.cms.size - 1].info.End().line
            if (blankLine > 1) {
                return true
            }
        } else {
            return true
        }
    }
    return false
}

private func WhetherExistNextNodeBeforeOuterNodeEnd(
    nodes: ArrayList<CNode>,
    offsetIdx: Int64,
    curNode: Node,
    nodeStack: ArrayList<Int64>
): (Bool, Position) {
    var findFlag = false
    CJC_ASSERT(!nodes.isEmpty())
    var searchEnd = End(nodes[nodes.size - 1])
    if (!nodeStack.isEmpty()) {
        searchEnd = End(nodes[nodeStack[nodeStack.size - 1]])
    }
    var nodeIdx = offsetIdx + 1
    while (nodeIdx < nodes.size) {
        if (Begin(nodes[nodeIdx]) > searchEnd) {
            break
        }
        if (Begin(nodes[nodeIdx]) > curNode.GetEnd() && Begin(nodes[nodeIdx]) < searchEnd) {
            findFlag = true
            break
        }
        nodeIdx++
    }
    return (findFlag, searchEnd)
}

private enum CommentPlace {
    | LEADING
    | TRAILING
    | INNER
}

private func AddComment(node: Node, cg: CommentGroup, place: CommentPlace): Unit {
    match (place) {
        case CommentPlace.LEADING =>
            node.comments.leadingComments.add(cg)
        case CommentPlace.TRAILING =>
            if ((node as File).isSome()) {
                node.comments.trailingComments.add(cg, at: 0)
            } else {
                node.comments.trailingComments.add(cg)
            }
        case CommentPlace.INNER =>
            node.comments.innerComments.add(cg)
    }
}

private func AddTrailingComment(node: Node, cg: CommentGroup): Unit {
    AddComment(node, cg, CommentPlace.TRAILING)
}

private func AddLeadingComment(node: Node, cg: CommentGroup): Unit {
    AddComment(node, cg, CommentPlace.LEADING)
}

private func AddInnerComment(node: Node, cg: CommentGroup): Unit {
    AddComment(node, cg, CommentPlace.INNER)
}

private class CommentGroupsLocInfo {
    public let cgs: ArrayList<CommentGroup> = ArrayList<CommentGroup>()
    public let cgPreInfo: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    public let cgFollowInfo: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    public let tkStream: ArrayList<Token> = ArrayList<Token>()

    public init(tokens: TreeSet<Token>) {
        for (token in tokens) {
            tkStream.add(token)
        }
    }
}

private func AttachCommentToOuterNode(
    nodes: ArrayList<CNode>,
    cgInfo: CommentGroupsLocInfo,
    cgIdx: Int64,
    nodeStack: ArrayList<Int64>
): Int64 {
    CJC_ASSERT(!nodes.isEmpty())
    CJC_ASSERT(!nodeStack.isEmpty())
    var outerNode = nodes[nodeStack[nodeStack.size - 1]].node.getOrThrow()
    nodeStack.remove(at: nodeStack.size - 1)
    while (!nodeStack.isEmpty() && End(CNode(outerNode)) == End(nodes[nodeStack[nodeStack.size - 1]])) {
        outerNode = nodes[nodeStack[nodeStack.size - 1]].node.getOrThrow()
        nodeStack.remove(at: nodeStack.size - 1)
    }
    var curCgIdx = cgIdx
    while (curCgIdx < cgInfo.cgs.size) {
        CJC_ASSERT(cgInfo.cgPreInfo.contains(curCgIdx))
        let preInfoIdx = cgInfo.cgPreInfo.get(curCgIdx).getOrThrow()
        if (End(CNode(outerNode)) <= cgInfo.tkStream[preInfoIdx].Begin()) {
            return curCgIdx
        }
        CJC_ASSERT(curCgIdx < cgInfo.cgs.size)
        if (!IsTrailCommentsInRuleOne(
            cgInfo.cgs[curCgIdx], curCgIdx, outerNode, cgInfo.cgFollowInfo, cgInfo.tkStream)) {
            break
        }
        AddTrailingComment(outerNode, cgInfo.cgs[curCgIdx])
        curCgIdx++
    }
    if (curCgIdx >= cgInfo.cgs.size) {
        return curCgIdx
    }
    return curCgIdx
}

private func AttachCommentToNode(
    nodes: ArrayList<CNode>,
    curNodeIdx: Int64,
    cgInfo: CommentGroupsLocInfo,
    cgIdx: Int64,
    nodeStack: ArrayList<Int64>
): Int64 {
    var currentCgIdx = cgIdx
    var currentNodeIdx = curNodeIdx
    while (currentCgIdx < cgInfo.cgs.size) {
        let curCg = cgInfo.cgs[currentCgIdx]
        CJC_ASSERT(!curCg.cms.isEmpty())
        let curCgBegin = curCg.cms[0].info.Begin()
        let curNodeBegin = Begin(nodes[currentNodeIdx])
        let curNodeEnd = End(nodes[currentNodeIdx])
        CJC_ASSERT(curCgBegin != curNodeBegin)
        let cnode = nodes[currentNodeIdx]
        var nodeValue: Option<Node> = cnode.node
        var ppos = cnode.position
        if (curCgBegin < curNodeBegin) {
            if (let Some(nodeForLeading) <- nodeValue) {
                AddLeadingComment(nodeForLeading, curCg)
            } else {
                AddInnerComment(nodes[nodeStack[nodeStack.size - 1]].node.getOrThrow(), curCg)
            }
        } else if (curCgBegin < curNodeEnd) {
            if (currentNodeIdx + 1 < nodes.size && Begin(nodes[currentNodeIdx + 1]) < curNodeEnd) {
                nodeStack.add(currentNodeIdx)
                break
            }
        } else {
            if (!nodeStack.isEmpty() && End(nodes[nodeStack[nodeStack.size - 1]]) < curCgBegin) {
                currentCgIdx = AttachCommentToOuterNode(nodes, cgInfo, currentCgIdx, nodeStack)
                break
            }
            let preInfoIdx = cgInfo.cgPreInfo.get(currentCgIdx).getOrThrow()
            if (curNodeEnd <= cgInfo.tkStream[preInfoIdx].Begin()) {
                break
            }
            while (let Some(posValue) <- ppos) {
                if (!(posValue < curCgBegin) || currentNodeIdx + 1 >= nodes.size) {
                    break
                }
                currentNodeIdx++
                if (let Some(nextNode) <- nodes[currentNodeIdx].node) {
                    nodeValue = nextNode
                    ppos = None
                } else {
                    ppos = nodes[currentNodeIdx].position
                }
            }
            if (let None <- nodeValue) {
                break
            }
            let nodeForTrailing = nodeValue.getOrThrow()
            if (IsTrailCommentsInRuleOne(
                curCg, currentCgIdx, nodeForTrailing, cgInfo.cgFollowInfo, cgInfo.tkStream)) {
                AddTrailingComment(nodeForTrailing, curCg)
                currentCgIdx++
                continue
            }
            let (findNextFlag, _) = WhetherExistNextNodeBeforeOuterNodeEnd(
                nodes, currentNodeIdx, nodeForTrailing, nodeStack)
            if (findNextFlag) {
                break
            }
            if (!nodeStack.isEmpty()) {
                AddInnerComment(nodes[nodeStack[nodeStack.size - 1]].node.getOrThrow(), curCg)
            }
        }
        currentCgIdx++
    }
    return currentCgIdx
}

private func CollectCommentGroups(tokens: TreeSet<Token>): CommentGroupsLocInfo {
    let cgInfo = CommentGroupsLocInfo(tokens)
    var preTokenIgnoreNL = Token(TokenKind.SENTINEL, "", Position(0u64, 1, 1), Position(0u64, 1, 1))
    var needUpdateFollowInfo = false
    var preTkIdxIgnTrivialStuff: Option<Int64> = None
    var idx: Int64 = 0
    while (idx < cgInfo.tkStream.size) {
        let tk = cgInfo.tkStream[idx]
        if (tk.kind == TokenKind.NL || tk.commentForMacroDebug) {
            idx++
            continue
        }
        if (tk.kind != TokenKind.COMMENT) {
            if (tk.kind != TokenKind.SEMI) {
                preTkIdxIgnTrivialStuff = idx
            }
            preTokenIgnoreNL = tk
            if (needUpdateFollowInfo && tk.kind != TokenKind.END) {
                CJC_ASSERT(cgInfo.cgs.size > 0)
                cgInfo.cgFollowInfo[cgInfo.cgs.size - 1] = idx
                needUpdateFollowInfo = false
            }
            idx++
            continue
        }
        if (UpdateCommentGroups(tk, preTokenIgnoreNL, preTkIdxIgnTrivialStuff, cgInfo.cgs, cgInfo.cgPreInfo)) {
            needUpdateFollowInfo = true
        }
        preTokenIgnoreNL = tk
        idx++
    }
    return cgInfo
}

private func AttachCommentToSortedNodes(nodes: ArrayList<CNode>, cgInfo: CommentGroupsLocInfo, cgIdx: Int64): Unit {
    if (cgInfo.cgs.isEmpty()) {
        return
    }
    let nodeStack = ArrayList<Int64>()
    var currentCgIdx = cgIdx
    var idx: Int64 = 0
    while (idx < nodes.size && currentCgIdx < cgInfo.cgs.size) {
        currentCgIdx = AttachCommentToNode(nodes, idx, cgInfo, currentCgIdx, nodeStack)
        idx++
    }
}

private func CollectFileCG(nodes: ArrayList<CNode>, cgInfo: CommentGroupsLocInfo, node: File): Int64 {
    var begin: Int64 = 0
    while (begin < cgInfo.cgs.size) {
        if (nodes.isEmpty() || cgInfo.cgs[begin].cms[cgInfo.cgs[begin].cms.size - 1].info.End().line + 1 <
            Begin(nodes[0]).line) {
            AddLeadingComment(node, cgInfo.cgs[begin])
            begin++
        } else {
            break
        }
    }
    if (cgInfo.cgs.isEmpty()) {
        return 0
    }
    var end = cgInfo.cgs.size - 1
    var endLine: Int64 = 0
    for (cnode in nodes) {
        endLine = max(endLine, End(cnode).line + 1)
    }
    while (end >= begin && cgInfo.cgs[end].cms[cgInfo.cgs[end].cms.size - 1].info.Begin().line > endLine) {
        AddTrailingComment(node, cgInfo.cgs[end])
        if (end == 0) {
            end = -1
            break
        }
        end--
    }
    let removeFrom = end + 1
    while (cgInfo.cgs.size > removeFrom) {
        cgInfo.cgs.remove(at: cgInfo.cgs.size - 1)
    }
    return begin
}

extend ParserImpl {
    public func AttachCommentToNodes(nodes: ArrayList<Node>): Unit {
        let nps = ArrayList<CNode>()
        for (node in nodes) {
            nps.add(CNode(node))
        }
        SortNodesByRange(nps)
        let cgInfo = CollectCommentGroups(lexer.GetTokenStream())
        AttachCommentToSortedNodes(nps, cgInfo, 0)
    }

    public func AttachCommentToFile(file: File): Unit {
        let nodes = CollectPtrsOfASTNodes(file)
        let cgInfo = CollectCommentGroups(lexer.GetTokenStream())
        let cgIdx = CollectFileCG(nodes, cgInfo, file)
        AttachCommentToSortedNodes(nodes, cgInfo, cgIdx)
    }
}
