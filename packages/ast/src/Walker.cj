package cangjie_compiler::ast

import cangjie_compiler::utils.CJC_ASSERT
import std.sync.AtomicUInt32

public enum VisitAction {
    | WALK_CHILDREN
    | SKIP_CHILDREN
    | STOP_NOW
    | KEEP_DECISION
}

private func VisitActionIndex(action: VisitAction): Int64 {
    return match (action) {
        case VisitAction.WALK_CHILDREN => 0
        case VisitAction.SKIP_CHILDREN => 1
        case VisitAction.STOP_NOW => 2
        case VisitAction.KEEP_DECISION => 3
    }
}

extend VisitAction <: Equatable<VisitAction> {
    public operator func ==(right: VisitAction): Bool {
        return VisitActionIndex(this) == VisitActionIndex(right)
    }

    public operator func !=(right: VisitAction): Bool {
        return !(this == right)
    }
}

private let nextWalkerID = AtomicUInt32(1u32)

public func GetNextWalkerID(): UInt32 {
    var out = nextWalkerID.fetchAdd(1u32)
    while (out == 0u32) {
        out = nextWalkerID.fetchAdd(1u32)
    }
    return out
}

public class Walker {
    private var root: Option<Node> = None
    private var id: UInt32 = 0u32
    private var visitPre: Option<(Node) -> VisitAction> = None
    private var visitPost: Option<(Node) -> VisitAction> = None
    private var walkExprDesugar: Bool = true

    public init(node: Node, visitPre!: Option<(Node) -> VisitAction> = None,
        visitPost!: Option<(Node) -> VisitAction> = None, walkExprDesugar!: Bool = true) {
        root = node
        id = GetNextWalkerID()
        this.visitPre = visitPre
        this.visitPost = visitPost
        this.walkExprDesugar = walkExprDesugar
    }

    public init(node: Node, walkerID: UInt32, visitPre!: Option<(Node) -> VisitAction> = None,
        visitPost!: Option<(Node) -> VisitAction> = None, walkExprDesugar!: Bool = true) {
        root = node
        id = walkerID
        this.visitPre = visitPre
        this.visitPost = visitPost
        this.walkExprDesugar = walkExprDesugar
    }

    public func Walk(): VisitAction {
        if (let Some(node) <- root) {
            return WalkNode(node)
        }
        return VisitAction.WALK_CHILDREN
    }

    public func WalkNode(curNode: Node): VisitAction {
        // Mirrors C++ Walker.cpp:44 `curNode->astKind != ASTKind::MODIFIER` (a trivial integer
        // compare). Matching on the constructor lowers to an O(1) tag check, whereas the
        // `ASTKind !=` operator routes through the linear ASTKindIndex match; this is hot because
        // it runs once per WalkNode on every node visit.
        let isModifier = match (curNode.astKind) {
            case ASTKind.MODIFIER => true
            case _ => false
        }
        if (!isModifier && curNode.visitedByWalkerID == id) {
            return VisitAction.WALK_CHILDREN
        }
        curNode.visitedByWalkerID = id

        var action = VisitAction.WALK_CHILDREN
        if (let Some(pre) <- visitPre) {
            action = pre(curNode)
        }
        if (action == VisitAction.STOP_NOW) {
            return action
        }
        if (action == VisitAction.WALK_CHILDREN) {
            let childAction = WalkChildren(curNode)
            if (childAction == VisitAction.STOP_NOW) {
                return childAction
            }
        }
        if (let Some(post) <- visitPost) {
            let postAction = post(curNode)
            if (postAction == VisitAction.STOP_NOW) {
                return postAction
            }
            if (postAction != VisitAction.KEEP_DECISION) {
                action = postAction
            }
        }
        CJC_ASSERT(action != VisitAction.KEEP_DECISION)
        return action
    }

    private func stopIf(action: VisitAction): Bool {
        return action == VisitAction.STOP_NOW
    }

    private func walkExprOption(node: Option<Expr>): VisitAction {
        if (let Some(value) <- node) {
            return WalkNode(value)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func walkTypeOption(node: Option<Type>): VisitAction {
        if (let Some(value) <- node) {
            return WalkNode(value)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func walkPatternOption(node: Option<Pattern>): VisitAction {
        if (let Some(value) <- node) {
            return WalkNode(value)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func walkMacroInvocation(invocation: MacroInvocation): VisitAction {
        if (let Some(decl) <- invocation.decl) {
            return WalkNode(decl)
        }
        return VisitAction.WALK_CHILDREN
    }

    public func WalkChildren(curNode: Node): VisitAction {
        // Base-class child walks mirror the leading Is<Expr>/Is<Decl> handling in C++ Walker.cpp:60-75.
        if (walkExprDesugar && (let Some(expr) <- (curNode as Expr))) {
            if (stopIf(walkExprOption(expr.desugarExpr))) { return VisitAction.STOP_NOW }
        } else if (let Some(decl) <- (curNode as Decl)) {
            for (annotation in decl.annotations) {
                if (stopIf(WalkNode(annotation))) { return VisitAction.STOP_NOW }
            }
            if (let Some(array) <- decl.annotationsArray) {
                if (stopIf(WalkNode(array))) { return VisitAction.STOP_NOW }
            }
        }

        // Per-kind child walks. Dispatch on the exact astKind (an O(1) jump) instead of the
        // former cascade of ~75 `node as XxxNode` dynamic casts, faithfully mirroring the C++
        // `switch (curNode->astKind)` in Walker.cpp:76-1204. The concrete-kind blocks below are
        // mutually exclusive on exact kind, so converting them to a single match changes neither
        // which children are walked nor their order.
        if (stopIf(WalkChildrenByKind(curNode))) { return VisitAction.STOP_NOW }
        return VisitAction.WALK_CHILDREN
    }

    private func WalkChildrenByKind(curNode: Node): VisitAction {
        match (curNode.astKind) {
            case ASTKind.FEATURES_SET =>
                if (let Some(featureSet) <- (curNode as FeaturesSet)) {
                    for (feature in featureSet.content) {
                        if (stopIf(WalkNode(feature))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.FEATURES_DIRECTIVE =>
                if (let Some(features) <- (curNode as FeaturesDirective)) {
                    for (annotation in features.annotations) {
                        if (stopIf(WalkNode(annotation))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(set) <- features.featuresSet) {
                        if (stopIf(WalkNode(set))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.IMPORT_CONTENT =>
                if (let Some(content) <- (curNode as ImportContent)) {
                    for (item in content.items) {
                        if (stopIf(WalkNode(item))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.IMPORT_SPEC =>
                if (let Some(importSpec) <- (curNode as ImportSpec)) {
                    if (let Some(modifier) <- importSpec.modifier) {
                        if (stopIf(WalkNode(modifier))) { return VisitAction.STOP_NOW }
                    }
                    if (stopIf(WalkNode(importSpec.content))) { return VisitAction.STOP_NOW }
                    for (annotation in importSpec.annotations) {
                        if (stopIf(WalkNode(annotation))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.PACKAGE_SPEC =>
                if (let Some(packageSpec) <- (curNode as PackageSpec)) {
                    if (let Some(modifier) <- packageSpec.modifier) {
                        if (stopIf(WalkNode(modifier))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.PACKAGE =>
                if (let Some(pkg) <- (curNode as Package)) {
                    for (decl in pkg.genericInstantiatedDecls) {
                        if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW }
                    }
                    for (file in pkg.files) {
                        if (stopIf(WalkNode(file))) { return VisitAction.STOP_NOW }
                    }
                    for (decl in pkg.srcImportedNonGenericDecls) {
                        if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.FILE =>
                if (let Some(file) <- (curNode as File)) {
                    if (let Some(feature) <- file.feature) {
                        if (stopIf(WalkNode(feature))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(pkgSpec) <- file.packageSpec) {
                        if (stopIf(WalkNode(pkgSpec))) { return VisitAction.STOP_NOW }
                    }
                    for (importSpec in file.imports) {
                        if (stopIf(WalkNode(importSpec))) { return VisitAction.STOP_NOW }
                    }
                    for (decl in file.exportedInternalDecls) {
                        if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW }
                    }
                    for (decl in file.decls) {
                        if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.ENUM_DECL =>
                if (let Some(enumDecl) <- (curNode as EnumDecl)) {
                    if (let Some(generic) <- enumDecl.generic) {
                        if (stopIf(WalkNode(generic))) { return VisitAction.STOP_NOW }
                    }
                    for (ty in enumDecl.inheritedTypes) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                    for (constructor in enumDecl.constructors) {
                        if (stopIf(WalkNode(constructor))) { return VisitAction.STOP_NOW }
                    }
                    for (member in enumDecl.members) {
                        if (stopIf(WalkNode(member))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.TYPE_ALIAS_DECL =>
                if (let Some(typeAlias) <- (curNode as TypeAliasDecl)) {
                    if (let Some(generic) <- typeAlias.generic) {
                        if (stopIf(WalkNode(generic))) { return VisitAction.STOP_NOW }
                    }
                    if (stopIf(walkTypeOption(typeAlias.typeNode))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.FUNC_PARAM_LIST =>
                if (let Some(paramList) <- (curNode as FuncParamList)) {
                    for (param in paramList.params) {
                        if (stopIf(WalkNode(param))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.FUNC_BODY =>
                if (let Some(funcBody) <- (curNode as FuncBody)) {
                    if (let Some(generic) <- funcBody.generic) {
                        if (stopIf(WalkNode(generic))) { return VisitAction.STOP_NOW }
                    }
                    for (params in funcBody.paramLists) {
                        if (stopIf(WalkNode(params))) { return VisitAction.STOP_NOW }
                    }
                    if (stopIf(walkTypeOption(funcBody.retType))) { return VisitAction.STOP_NOW }
                    if (let Some(body) <- funcBody.body) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.FUNC_PARAM =>
                if (let Some(funcParam) <- (curNode as FuncParam)) {
                    if (stopIf(walkTypeOption(funcParam.typeNode))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(funcParam.assignment))) { return VisitAction.STOP_NOW }
                    if (let Some(desugarDecl) <- funcParam.desugarDecl) {
                        if (stopIf(WalkNode(desugarDecl))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.FUNC_DECL =>
                if (let Some(funcDecl) <- (curNode as FuncDecl)) {
                    for (modifier in funcDecl.modifiers) {
                        if (stopIf(WalkNode(modifier))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(body) <- funcDecl.funcBody) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.MACRO_DECL =>
                if (let Some(macroDecl) <- (curNode as MacroDecl)) {
                    for (modifier in macroDecl.modifiers) {
                        if (stopIf(WalkNode(modifier))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
                        if (stopIf(WalkNode(desugarDecl))) { return VisitAction.STOP_NOW }
                    } else if (let Some(body) <- macroDecl.funcBody) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.MAIN_DECL =>
                if (let Some(mainDecl) <- (curNode as MainDecl)) {
                    if (let Some(desugarDecl) <- mainDecl.desugarDecl) {
                        if (stopIf(WalkNode(desugarDecl))) { return VisitAction.STOP_NOW }
                    } else if (let Some(body) <- mainDecl.funcBody) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.PRIMARY_CTOR_DECL =>
                if (let Some(primaryCtor) <- (curNode as PrimaryCtorDecl)) {
                    for (modifier in primaryCtor.modifiers) {
                        if (stopIf(WalkNode(modifier))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(body) <- primaryCtor.funcBody) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.PROP_DECL =>
                if (let Some(propDecl) <- (curNode as PropDecl)) {
                    for (modifier in propDecl.modifiers) {
                        if (stopIf(WalkNode(modifier))) { return VisitAction.STOP_NOW }
                    }
                    if (stopIf(walkTypeOption(propDecl.typeNode))) { return VisitAction.STOP_NOW }
                    for (getter in propDecl.getters) {
                        if (stopIf(WalkNode(getter))) { return VisitAction.STOP_NOW }
                    }
                    for (setter in propDecl.setters) {
                        if (stopIf(WalkNode(setter))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.VAR_WITH_PATTERN_DECL =>
                if (let Some(varWithPattern) <- (curNode as VarWithPatternDecl)) {
                    if (stopIf(walkPatternOption(varWithPattern.irrefutablePattern))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkTypeOption(varWithPattern.typeNode))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(varWithPattern.initializer))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.VAR_DECL =>
                if (let Some(varDecl) <- (curNode as VarDecl)) {
                    for (modifier in varDecl.modifiers) {
                        if (stopIf(WalkNode(modifier))) { return VisitAction.STOP_NOW }
                    }
                    if (stopIf(walkTypeOption(varDecl.typeNode))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(varDecl.initializer))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.CLASS_BODY =>
                if (let Some(body) <- (curNode as ClassBody)) {
                    for (decl in body.decls) { if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW } }
                }
            case ASTKind.STRUCT_BODY =>
                if (let Some(body) <- (curNode as StructBody)) {
                    for (decl in body.decls) { if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW } }
                }
            case ASTKind.INTERFACE_BODY =>
                if (let Some(body) <- (curNode as InterfaceBody)) {
                    for (decl in body.decls) { if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW } }
                }
            case ASTKind.CLASS_DECL =>
                if (let Some(classDecl) <- (curNode as ClassDecl)) {
                    for (modifier in classDecl.modifiers) {
                        if (stopIf(WalkNode(modifier))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(generic) <- classDecl.generic) {
                        if (stopIf(WalkNode(generic))) { return VisitAction.STOP_NOW }
                    }
                    for (ty in classDecl.inheritedTypes) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(body) <- classDecl.body) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.STRUCT_DECL =>
                if (let Some(structDecl) <- (curNode as StructDecl)) {
                    for (modifier in structDecl.modifiers) {
                        if (stopIf(WalkNode(modifier))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(generic) <- structDecl.generic) {
                        if (stopIf(WalkNode(generic))) { return VisitAction.STOP_NOW }
                    }
                    for (ty in structDecl.inheritedTypes) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(body) <- structDecl.body) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.INTERFACE_DECL =>
                if (let Some(interfaceDecl) <- (curNode as InterfaceDecl)) {
                    for (modifier in interfaceDecl.modifiers) {
                        if (stopIf(WalkNode(modifier))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(generic) <- interfaceDecl.generic) {
                        if (stopIf(WalkNode(generic))) { return VisitAction.STOP_NOW }
                    }
                    for (ty in interfaceDecl.inheritedTypes) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(body) <- interfaceDecl.body) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.EXTEND_DECL =>
                if (let Some(extendDecl) <- (curNode as ExtendDecl)) {
                    if (stopIf(walkTypeOption(extendDecl.extendedType))) { return VisitAction.STOP_NOW }
                    for (ty in extendDecl.inheritedTypes) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(generic) <- extendDecl.generic) {
                        if (stopIf(WalkNode(generic))) { return VisitAction.STOP_NOW }
                    }
                    for (memberDecl in extendDecl.members) {
                        if (stopIf(WalkNode(memberDecl))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.BLOCK =>
                if (let Some(block) <- (curNode as Block)) {
                    for (node in block.body) {
                        if (stopIf(WalkNode(node))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.IF_EXPR =>
                if (let Some(ifExpr) <- (curNode as IfExpr)) {
                    if (stopIf(walkExprOption(ifExpr.condExpr))) { return VisitAction.STOP_NOW }
                    if (let Some(thenBody) <- ifExpr.thenBody) {
                        if (stopIf(WalkNode(thenBody))) { return VisitAction.STOP_NOW }
                    }
                    if (ifExpr.hasElse) {
                        if (stopIf(walkExprOption(ifExpr.elseBody))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.LET_PATTERN_DESTRUCTOR =>
                if (let Some(letPattern) <- (curNode as LetPatternDestructor)) {
                    for (patternValue in letPattern.patterns) {
                        if (stopIf(WalkNode(patternValue))) { return VisitAction.STOP_NOW }
                    }
                    if (stopIf(walkExprOption(letPattern.initializer))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.QUOTE_EXPR =>
                if (let Some(quoteExpr) <- (curNode as QuoteExpr)) {
                    for (exprValue in quoteExpr.exprs) {
                        if (stopIf(WalkNode(exprValue))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.MATCH_CASE =>
                if (let Some(matchCase) <- (curNode as MatchCase)) {
                    for (patternValue in matchCase.patterns) {
                        if (stopIf(WalkNode(patternValue))) { return VisitAction.STOP_NOW }
                    }
                    if (stopIf(walkExprOption(matchCase.patternGuard))) { return VisitAction.STOP_NOW }
                    if (let Some(body) <- matchCase.exprOrDecls) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.MATCH_CASE_OTHER =>
                if (let Some(other) <- (curNode as MatchCaseOther)) {
                    if (stopIf(walkExprOption(other.matchExpr))) { return VisitAction.STOP_NOW }
                    if (let Some(body) <- other.exprOrDecls) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.MATCH_EXPR =>
                if (let Some(matchExpr) <- (curNode as MatchExpr)) {
                    if (matchExpr.matchMode) {
                        if (stopIf(walkExprOption(matchExpr.selector))) { return VisitAction.STOP_NOW }
                        for (matchCase in matchExpr.matchCases) {
                            if (stopIf(WalkNode(matchCase))) { return VisitAction.STOP_NOW }
                        }
                    } else {
                        for (other in matchExpr.matchCaseOthers) {
                            if (stopIf(WalkNode(other))) { return VisitAction.STOP_NOW }
                        }
                    }
                }
            case ASTKind.TRY_EXPR =>
                if (let Some(tryExpr) <- (curNode as TryExpr)) {
                    for (resource in tryExpr.resourceSpec) {
                        if (stopIf(WalkNode(resource))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(blockValue) <- tryExpr.tryBlock) {
                        if (stopIf(WalkNode(blockValue))) { return VisitAction.STOP_NOW }
                    }
                    for (patternValue in tryExpr.catchPatterns) {
                        if (stopIf(WalkNode(patternValue))) { return VisitAction.STOP_NOW }
                    }
                    for (blockValue in tryExpr.catchBlocks) {
                        if (stopIf(WalkNode(blockValue))) { return VisitAction.STOP_NOW }
                    }
                    if (let None <- tryExpr.desugarExpr) {
                        for (handler in tryExpr.handlers) {
                            if (stopIf(walkPatternOption(handler.commandPattern))) { return VisitAction.STOP_NOW }
                            if (let Some(blockValue) <- handler.block) {
                                if (stopIf(WalkNode(blockValue))) { return VisitAction.STOP_NOW }
                            }
                            if (let Some(lambda) <- handler.desugaredLambda) {
                                if (stopIf(WalkNode(lambda))) { return VisitAction.STOP_NOW }
                            }
                        }
                    }
                    if (let Some(blockValue) <- tryExpr.finallyBlock) {
                        if (stopIf(WalkNode(blockValue))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(lambda) <- tryExpr.tryLambda) {
                        if (stopIf(WalkNode(lambda))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(lambda) <- tryExpr.finallyLambda) {
                        if (stopIf(WalkNode(lambda))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.THROW_EXPR =>
                if (let Some(throwExpr) <- (curNode as ThrowExpr)) {
                    if (stopIf(walkExprOption(throwExpr.expr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.PERFORM_EXPR =>
                if (let Some(performExpr) <- (curNode as PerformExpr)) {
                    if (stopIf(walkExprOption(performExpr.expr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.RESUME_EXPR =>
                if (let Some(resumeExpr) <- (curNode as ResumeExpr)) {
                    if (stopIf(walkExprOption(resumeExpr.withExpr))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(resumeExpr.throwingExpr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.RETURN_EXPR =>
                if (let Some(returnExpr) <- (curNode as ReturnExpr)) {
                    if (let None <- returnExpr.desugarExpr) {
                        if (stopIf(walkExprOption(returnExpr.expr))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.FOR_IN_EXPR =>
                if (let Some(forIn) <- (curNode as ForInExpr)) {
                    if (stopIf(walkPatternOption(forIn.pattern))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(forIn.inExpression))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(forIn.patternGuard))) { return VisitAction.STOP_NOW }
                    if (let Some(body) <- forIn.body) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.WHILE_EXPR =>
                if (let Some(whileExpr) <- (curNode as WhileExpr)) {
                    if (stopIf(walkExprOption(whileExpr.condExpr))) { return VisitAction.STOP_NOW }
                    if (let Some(body) <- whileExpr.body) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.DO_WHILE_EXPR =>
                if (let Some(doWhile) <- (curNode as DoWhileExpr)) {
                    if (let Some(body) <- doWhile.body) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                    if (stopIf(walkExprOption(doWhile.condExpr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.ASSIGN_EXPR =>
                if (let Some(assign) <- (curNode as AssignExpr)) {
                    if (stopIf(walkExprOption(assign.leftValue))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(assign.rightExpr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.INC_OR_DEC_EXPR =>
                if (let Some(incOrDec) <- (curNode as IncOrDecExpr)) {
                    if (stopIf(walkExprOption(incOrDec.expr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.UNARY_EXPR =>
                if (let Some(unary) <- (curNode as UnaryExpr)) {
                    if (stopIf(walkExprOption(unary.expr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.BINARY_EXPR =>
                if (let Some(binary) <- (curNode as BinaryExpr)) {
                    if (stopIf(walkExprOption(binary.leftExpr))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(binary.rightExpr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.IS_EXPR =>
                if (let Some(isExpr) <- (curNode as IsExpr)) {
                    if (stopIf(walkExprOption(isExpr.leftExpr))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkTypeOption(isExpr.isType))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.AS_EXPR =>
                if (let Some(asExpr) <- (curNode as AsExpr)) {
                    if (stopIf(walkExprOption(asExpr.leftExpr))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkTypeOption(asExpr.asType))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.BUILTIN_DECL =>
                if (let Some(builtinDecl) <- (curNode as BuiltInDecl)) {
                    if (let Some(generic) <- builtinDecl.generic) {
                        if (stopIf(WalkNode(generic))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.RANGE_EXPR =>
                if (let Some(range) <- (curNode as RangeExpr)) {
                    if (stopIf(walkExprOption(range.startExpr))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(range.stopExpr))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(range.stepExpr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.SUBSCRIPT_EXPR =>
                if (let Some(subscript) <- (curNode as SubscriptExpr)) {
                    if (stopIf(walkExprOption(subscript.baseExpr))) { return VisitAction.STOP_NOW }
                    for (exprValue in subscript.indexExprs) {
                        if (stopIf(WalkNode(exprValue))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.INTERPOLATION_EXPR =>
                if (let Some(interpolation) <- (curNode as InterpolationExpr)) {
                    if (let Some(blockValue) <- interpolation.block) {
                        if (stopIf(WalkNode(blockValue))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.STR_INTERPOLATION_EXPR =>
                if (let Some(strInterpolation) <- (curNode as StrInterpolationExpr)) {
                    for (exprValue in strInterpolation.strPartExprs) {
                        if (stopIf(WalkNode(exprValue))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(lit) <- (curNode as LitConstExpr)) {
                    if (let Some(refType) <- lit.ref) {
                        if (stopIf(WalkNode(refType))) { return VisitAction.STOP_NOW }
                    }
                    if (let None <- lit.desugarExpr) {
                        if (let Some(siExpr) <- lit.siExpr) {
                            if (stopIf(WalkNode(siExpr))) { return VisitAction.STOP_NOW }
                        }
                    }
                }
            case ASTKind.FUNC_ARG =>
                if (let Some(arg) <- (curNode as FuncArg)) {
                    if (stopIf(walkExprOption(arg.expr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.CALL_EXPR =>
                if (let Some(call) <- (curNode as CallExpr)) {
                    if (stopIf(walkExprOption(call.baseFunc))) { return VisitAction.STOP_NOW }
                    if (let Some(desugarArgs) <- call.desugarArgs) {
                        for (arg in desugarArgs) {
                            if (stopIf(WalkNode(arg))) { return VisitAction.STOP_NOW }
                        }
                    } else {
                        for (arg in call.args) {
                            if (stopIf(WalkNode(arg))) { return VisitAction.STOP_NOW }
                        }
                    }
                }
            case ASTKind.MEMBER_ACCESS =>
                if (let Some(member) <- (curNode as MemberAccess)) {
                    if (stopIf(walkExprOption(member.baseExpr))) { return VisitAction.STOP_NOW }
                    for (ty in member.typeArguments) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.REF_EXPR =>
                if (let Some(refExpr) <- (curNode as RefExpr)) {
                    for (ty in refExpr.typeArguments) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.PAREN_EXPR =>
                if (let Some(parenExpr) <- (curNode as ParenExpr)) {
                    if (stopIf(walkExprOption(parenExpr.expr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.LAMBDA_EXPR =>
                if (let Some(lambda) <- (curNode as LambdaExpr)) {
                    if (let Some(body) <- lambda.funcBody) {
                        if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.IF_AVAILABLE_EXPR =>
                if (let Some(ifAvailable) <- (curNode as IfAvailableExpr)) {
                    if (let Some(arg) <- ifAvailable.GetArg()) {
                        if (stopIf(WalkNode(arg))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(lambda) <- ifAvailable.GetLambda1()) {
                        if (stopIf(WalkNode(lambda))) { return VisitAction.STOP_NOW }
                    }
                    if (let Some(lambda) <- ifAvailable.GetLambda2()) {
                        if (stopIf(WalkNode(lambda))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.TRAIL_CLOSURE_EXPR =>
                if (let Some(trailing) <- (curNode as TrailingClosureExpr)) {
                    if (stopIf(walkExprOption(trailing.expr))) { return VisitAction.STOP_NOW }
                    if (let Some(lambda) <- trailing.lambda) {
                        if (stopIf(WalkNode(lambda))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.OPTIONAL_EXPR =>
                if (let Some(optional) <- (curNode as OptionalExpr)) {
                    if (stopIf(walkExprOption(optional.baseExpr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.OPTIONAL_CHAIN_EXPR =>
                if (let Some(chain) <- (curNode as OptionalChainExpr)) {
                    if (let None <- chain.desugarExpr) {
                        if (stopIf(walkExprOption(chain.expr))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.ARRAY_LIT =>
                if (let Some(arrayLit) <- (curNode as ArrayLit)) {
                    for (exprValue in arrayLit.children) {
                        if (stopIf(WalkNode(exprValue))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.ARRAY_EXPR =>
                if (let Some(arrayExpr) <- (curNode as ArrayExpr)) {
                    if (stopIf(walkTypeOption(arrayExpr.typeNode))) { return VisitAction.STOP_NOW }
                    for (arg in arrayExpr.args) {
                        if (stopIf(WalkNode(arg))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.POINTER_EXPR =>
                if (let Some(pointer) <- (curNode as PointerExpr)) {
                    if (stopIf(walkTypeOption(pointer.typeNode))) { return VisitAction.STOP_NOW }
                    if (let Some(argValue) <- pointer.arg) {
                        if (stopIf(WalkNode(argValue))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.TUPLE_LIT =>
                if (let Some(tupleLit) <- (curNode as TupleLit)) {
                    for (exprValue in tupleLit.children) {
                        if (stopIf(WalkNode(exprValue))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.TYPE_CONV_EXPR =>
                if (let Some(typeConv) <- (curNode as TypeConvExpr)) {
                    if (stopIf(walkTypeOption(typeConv.typeNode))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(typeConv.expr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.SPAWN_EXPR =>
                if (let Some(spawnExpr) <- (curNode as SpawnExpr)) {
                    if (stopIf(walkExprOption(spawnExpr.arg))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkExprOption(spawnExpr.task))) { return VisitAction.STOP_NOW }
                    if (let Some(futureObj) <- spawnExpr.futureObj) {
                        if (stopIf(WalkNode(futureObj))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.SYNCHRONIZED_EXPR =>
                if (let Some(sync) <- (curNode as SynchronizedExpr)) {
                    if (stopIf(walkExprOption(sync.mutex))) { return VisitAction.STOP_NOW }
                    if (let None <- sync.desugarExpr) {
                        if (let Some(body) <- sync.body) {
                            if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
                        }
                    }
                }
            case ASTKind.REF_TYPE =>
                if (let Some(refType) <- (curNode as RefType)) {
                    for (ty in refType.typeArguments) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.PAREN_TYPE =>
                if (let Some(parenType) <- (curNode as ParenType)) {
                    if (stopIf(walkTypeOption(parenType.innerType))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.QUALIFIED_TYPE =>
                if (let Some(qualified) <- (curNode as QualifiedType)) {
                    if (stopIf(walkTypeOption(qualified.baseType))) { return VisitAction.STOP_NOW }
                    for (ty in qualified.typeArguments) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.OPTION_TYPE =>
                if (let Some(optionType) <- (curNode as OptionType)) {
                    if (let Some(desugarType) <- optionType.desugarType) {
                        if (stopIf(WalkNode(desugarType))) { return VisitAction.STOP_NOW }
                    }
                    if (stopIf(walkTypeOption(optionType.componentType))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.CONSTANT_TYPE =>
                if (let Some(constantType) <- (curNode as ConstantType)) {
                    if (stopIf(walkExprOption(constantType.constantExpr))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.VARRAY_TYPE =>
                if (let Some(varrayType) <- (curNode as VArrayType)) {
                    if (stopIf(walkTypeOption(varrayType.typeArgument))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkTypeOption(varrayType.constantType))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.FUNC_TYPE =>
                if (let Some(funcType) <- (curNode as FuncType)) {
                    for (ty in funcType.paramTypes) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                    if (stopIf(walkTypeOption(funcType.retType))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.TUPLE_TYPE =>
                if (let Some(tupleType) <- (curNode as TupleType)) {
                    for (ty in tupleType.fieldTypes) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.GENERIC =>
                if (let Some(generic) <- (curNode as Generic)) {
                    for (param in generic.typeParameters) {
                        if (stopIf(WalkNode(param))) { return VisitAction.STOP_NOW }
                    }
                    for (constraint in generic.genericConstraints) {
                        if (stopIf(WalkNode(constraint))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.GENERIC_CONSTRAINT =>
                if (let Some(constraint) <- (curNode as GenericConstraint)) {
                    if (let Some(refType) <- constraint.refType) {
                        if (stopIf(WalkNode(refType))) { return VisitAction.STOP_NOW }
                    }
                    for (upperBound in constraint.upperBounds) {
                        if (stopIf(WalkNode(upperBound))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.CONST_PATTERN =>
                if (let Some(constPattern) <- (curNode as ConstPattern)) {
                    if (stopIf(walkExprOption(constPattern.literal))) { return VisitAction.STOP_NOW }
                    if (let Some(callExpr) <- constPattern.operatorCallExpr) {
                        if (stopIf(WalkNode(callExpr))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.VAR_PATTERN =>
                if (let Some(varPattern) <- (curNode as VarPattern)) {
                    if (let Some(decl) <- varPattern.varDecl) {
                        if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.TUPLE_PATTERN =>
                if (let Some(tuplePattern) <- (curNode as TuplePattern)) {
                    for (patternValue in tuplePattern.patterns) {
                        if (stopIf(WalkNode(patternValue))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.TYPE_PATTERN =>
                if (let Some(typePattern) <- (curNode as TypePattern)) {
                    if (stopIf(walkPatternOption(typePattern.pattern))) { return VisitAction.STOP_NOW }
                    if (stopIf(walkTypeOption(typePattern.typeNode))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.ENUM_PATTERN =>
                if (let Some(enumPattern) <- (curNode as EnumPattern)) {
                    if (stopIf(walkExprOption(enumPattern.constructor))) { return VisitAction.STOP_NOW }
                    for (patternValue in enumPattern.patterns) {
                        if (stopIf(WalkNode(patternValue))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.VAR_OR_ENUM_PATTERN =>
                if (let Some(varOrEnum) <- (curNode as VarOrEnumPattern)) {
                    if (stopIf(walkPatternOption(varOrEnum.pattern))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.EXCEPT_TYPE_PATTERN =>
                if (let Some(exceptPattern) <- (curNode as ExceptTypePattern)) {
                    if (stopIf(walkPatternOption(exceptPattern.pattern))) { return VisitAction.STOP_NOW }
                    for (ty in exceptPattern.types) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.COMMAND_TYPE_PATTERN =>
                if (let Some(commandPattern) <- (curNode as CommandTypePattern)) {
                    if (stopIf(walkPatternOption(commandPattern.pattern))) { return VisitAction.STOP_NOW }
                    for (ty in commandPattern.types) {
                        if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.ANNOTATION =>
                if (let Some(annotation) <- (curNode as Annotation)) {
                    if (stopIf(walkExprOption(annotation.baseExpr))) { return VisitAction.STOP_NOW }
                    for (arg in annotation.args) {
                        if (stopIf(WalkNode(arg))) { return VisitAction.STOP_NOW }
                    }
                }
            case ASTKind.MACRO_EXPAND_EXPR =>
                if (let Some(macroExpr) <- (curNode as MacroExpandExpr)) {
                    if (stopIf(walkMacroInvocation(macroExpr.invocation))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.MACRO_EXPAND_DECL =>
                if (let Some(macroDecl) <- (curNode as MacroExpandDecl)) {
                    if (stopIf(walkMacroInvocation(macroDecl.invocation))) { return VisitAction.STOP_NOW }
                }
            case ASTKind.MACRO_EXPAND_PARAM =>
                if (let Some(macroParam) <- (curNode as MacroExpandParam)) {
                    if (stopIf(walkMacroInvocation(macroParam.invocation))) { return VisitAction.STOP_NOW }
                }
            case _ => ()
        }
        return VisitAction.WALK_CHILDREN
    }
}

public type ConstWalker = Walker
