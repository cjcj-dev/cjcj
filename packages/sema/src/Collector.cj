package cjcj::sema

import std.collection.*
import cjcj::ast.*

private func WalkMacroCall(macrocall: Node, decl: Decl): Unit {
    let walker = Walker(decl, visitPre: { curNode: Node =>
        curNode.isInMacroCall = true
        curNode.curMacroCall = macrocall
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

public class Collector {
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    private let scopeManager: ScopeManager = ScopeManager()
    private var enableMacroInLsp: Bool = false

    public init(enableMacroInLsp!: Bool = false) {
        this.enableMacroInLsp = enableMacroInLsp
    }

    public func BuildSymbolTable(ctx: ASTContext, pkg: Package, buildTrie!: Bool = true): Unit {
        ctx.curPackage = pkg
        ctx.fullPackageName = pkg.fullPackageName
        UpdatePosLimit(pkg)
        scopeManager.Reset()
        ctx.currentScopeLevel = 0u32
        ctx.currentMaxDepth = 0u32
        ctx.currentScopeName = TOPLEVEL_SCOPE_NAME
        AssignPackageScopes(ctx, pkg)
        let collector = this
        let walkerBox = Box<Option<Walker>>(None)
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (node.IsExpr()) {
                if (let Some(file) <- node.curFile) {
                    if (file.TestAttr(Attribute.FROM_COMMON_PART)) {
                        return VisitAction.SKIP_CHILDREN
                    }
                }
            }
            if (let Some(expr) <- (node as Expr)) {
                if (expr.astKind != ASTKind.FOR_IN_EXPR && expr.astKind != ASTKind.SYNCHRONIZED_EXPR) {
                    if (let Some(desugarExpr) <- expr.desugarExpr) {
                        if (let Some(currentWalker) <- walkerBox.value) {
                            let action = currentWalker.WalkNode(desugarExpr)
                            if (action == VisitAction.STOP_NOW) {
                                return action
                            }
                        }
                    }
                }
            }
            if (let Some(lce) <- (node as LitConstExpr)) {
                collector.CollectLitConstExpr(ctx, lce, walker: walkerBox.value, buildTrie: buildTrie)
            } else if (let Some(macroDecl) <- (node as MacroExpandDecl)) {
                if (let Some(currentWalker) <- walkerBox.value) {
                    for (annotation in macroDecl.annotations) {
                        let action = currentWalker.WalkNode(annotation)
                        if (action == VisitAction.STOP_NOW) {
                            return action
                        }
                    }
                }
                collector.AddSymbol(ctx, node, buildTrie: buildTrie)
                collector.CollectMacroExpandDecl(macroDecl)
            } else if (let Some(macroExpr) <- (node as MacroExpandExpr)) {
                collector.AddSymbol(ctx, node, buildTrie: buildTrie)
                collector.CollectMacroExpandExpr(macroExpr)
            } else if (let Some(macroParam) <- (node as MacroExpandParam)) {
                collector.AddSymbol(ctx, node, buildTrie: buildTrie)
                collector.CollectMacroExpandParam(macroParam)
            } else if (let Some(mainDecl) <- (node as MainDecl)) {
                collector.CollectMainDecl(ctx, mainDecl, walkerBox.value.getOrThrow(), buildTrie: buildTrie)
                return VisitAction.SKIP_CHILDREN
            } else if (let Some(macroDecl) <- (node as MacroDecl)) {
                // Faithful port of C++ Collector::BuildSymbolTable MACRO_DECL case
                // (src/Sema/Collector.cpp:770-776). DesugarMacroDecl rewrites a macro
                // definition into a companion FuncDecl (macroDecl.desugarDecl) carrying the
                // same identifier and the moved funcBody. Only that desugar must contribute a
                // symbol: adding one for the MacroDecl node itself would register the macro
                // name twice (macro node + desugar) and make PreCheck.CheckRedefinition report
                // a false redefinition of the macro against its own desugar. Collect only the
                // desugar by descending into it; when no desugar exists, collect nothing.
                if (macroDecl.desugarDecl.isNone()) {
                    return VisitAction.SKIP_CHILDREN
                }
            } else if (let Some(syncExpr) <- (node as SynchronizedExpr)) {
                collector.AddSymbol(ctx, node, buildTrie: buildTrie)
                if (let Some(currentWalker2) <- walkerBox.value) {
                    if (let Some(mutex) <- syncExpr.mutex) {
                        let action = currentWalker2.WalkNode(mutex)
                        if (action == VisitAction.STOP_NOW) {
                            return action
                        }
                    }
                    if (let Some(desugarExpr) <- syncExpr.desugarExpr) {
                        let action = currentWalker2.WalkNode(desugarExpr)
                        if (action == VisitAction.STOP_NOW) {
                            return action
                        }
                    }
                }
                return VisitAction.SKIP_CHILDREN
            } else {
                collector.AddSymbol(ctx, node, buildTrie: buildTrie)
            }
            VisitAction.WALK_CHILDREN
        }, visitPost: { node: Node =>
            if (collector.enableMacroInLsp) {
                if (let Some(file) <- (node as File)) {
                    if (let Some(currentWalker) <- walkerBox.value) {
                        for (macroCall in file.originalMacroCallNodes) {
                            let action = currentWalker.WalkNode(macroCall)
                            if (action == VisitAction.STOP_NOW) {
                                return action
                            }
                            AddCurFile(macroCall, file: file)
                        }
                    }
                }
            }
            VisitAction.KEEP_DECISION
        }, walkExprDesugar: false)
        walkerBox.value = Some(walker)
        let _ = walker.Walk()
        ctx.searcher.InvalidateCache()
    }

    public func UpdatePosLimit(pkg: Package): Unit {
        let fileIdMax = Box<UInt64>(0u64)
        let lineNumMax = Box<Int64>(0)
        let columnNumMax = Box<Int64>(0)
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (node.begin.fileID > fileIdMax.value) {
                fileIdMax.value = node.begin.fileID
            }
            if (node.end.fileID > fileIdMax.value) {
                fileIdMax.value = node.end.fileID
            }
            if (node.begin.line > lineNumMax.value) {
                lineNumMax.value = node.begin.line
            }
            if (node.end.line > lineNumMax.value) {
                lineNumMax.value = node.end.line
            }
            if (node.begin.column > columnNumMax.value) {
                columnNumMax.value = node.begin.column
            }
            if (node.end.column > columnNumMax.value) {
                columnNumMax.value = node.end.column
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        PosSearchApi.UpdatePosLimit(fileIdMax.value, lineNumMax.value, columnNumMax.value)
    }

    public func Collect(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                collectDecl(decl)
            }
        }
    }

    private func collectDecl(decl: Decl): Unit {
        decls.add(decl)
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            for (constructor in enumDecl.constructors) {
                collectDecl(constructor)
            }
        }
        for (member in decl.GetMemberDecls()) {
            collectDecl(member)
        }
    }

    private func AddSymbol(ctx: ASTContext, node: Node, buildTrie!: Bool = true): Unit {
        if (let Some(callExpr) <- (node as CallExpr)) {
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                SetIsNotAlone(baseFunc)
            }
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                SetIsNotAlone(baseExpr)
            }
        } else if (let Some(subscriptExpr) <- (node as SubscriptExpr)) {
            if (let Some(baseExpr2) <- subscriptExpr.baseExpr) {
                SetIsNotAlone(baseExpr2)
            }
        } else if (let Some(assignExpr) <- (node as AssignExpr)) {
            if ((let None <- assignExpr.desugarExpr) && (let Some(leftValue) <- assignExpr.leftValue)) {
                leftValue.EnableAttr(Attribute.LEFT_VALUE)
            }
        }
        if (let Some(decl) <- (node as Decl)) {
            if (decl.fullPackageName.isEmpty()) {
                decl.fullPackageName = ctx.fullPackageName
            }
        }
        let scopeName = if (node.scopeName.isEmpty()) { TOPLEVEL_SCOPE_NAME } else { node.scopeName }
        let fileHash = if (let Some(file) <- node.curFile) { file.fileHash } else { 0u64 }
        let symbol = Symbol(fileHash, SymbolName(node), node, node.scopeLevel, scopeName)
        node.symbol = Some(symbol)
        ctx.symbolTable.add(symbol)
        ctx.invertedIndex.Index(symbol, withTrie: buildTrie)
        if (let Some(enumDecl) <- (node as EnumDecl)) {
            if (let Some(bodyScope) <- enumDecl.bodyScope) {
                AddSymbol(ctx, bodyScope, buildTrie: buildTrie)
            }
        } else if (let Some(extendDecl) <- (node as ExtendDecl)) {
            if (let Some(bodyScope) <- extendDecl.bodyScope) {
                AddSymbol(ctx, bodyScope, buildTrie: buildTrie)
            }
        }
    }

    private func CollectLitConstExpr(ctx: ASTContext, lce: LitConstExpr, walker!: Option<Walker> = None,
        buildTrie!: Bool = true): Unit {
        if (let Some(refName) <- StringLiteralRefName(lce.kind)) {
            if (let None <- lce.ref) {
                let refType = RefType()
                refType.begin = lce.begin
                refType.ref.identifier = SrcIdentifier(refName)
                refType.EnableAttr(Attribute.COMPILER_ADD)
                refType.EnableAttr(Attribute.IN_CORE)
                lce.ref = Some(refType)
                AddSymbol(ctx, refType, buildTrie: buildTrie)
            }
        }
        if (let Some(siExpr) <- lce.siExpr) {
            if (let Some(currentWalker) <- walker) {
                let _ = currentWalker.WalkNode(siExpr)
            }
        }
        AddSymbol(ctx, lce, buildTrie: buildTrie)
    }

    private func CollectMacroExpandDecl(med: MacroExpandDecl): Unit {
        if (let Some(decl) <- med.invocation.decl) {
            WalkMacroCall(med, decl)
        }
    }

    private func CollectMacroExpandExpr(mee: MacroExpandExpr): Unit {
        if (let Some(decl) <- mee.invocation.decl) {
            WalkMacroCall(mee, decl)
        }
    }

    private func CollectMacroExpandParam(mep: MacroExpandParam): Unit {
        if (let Some(decl) <- mep.invocation.decl) {
            WalkMacroCall(mep, decl)
        }
    }

    private func CollectMainDecl(ctx: ASTContext, md: MainDecl, walker: Walker, buildTrie!: Bool = true): Unit {
        if (let Some(desugarDecl) <- md.desugarDecl) {
            let _ = walker.WalkNode(desugarDecl)
            return
        }
        for (annotation in md.annotations) {
            let _ = walker.WalkNode(annotation)
        }
        AddSymbol(ctx, md, buildTrie: buildTrie)
        if (let Some(body) <- md.funcBody) {
            let _ = walker.WalkNode(body)
        }
    }

    private func StringLiteralRefName(kind: LitConstKind): Option<String> {
        if (kind == LitConstKind.STRING) {
            return Some("String")
        }
        if (kind == LitConstKind.JSTRING) {
            return Some("JString")
        }
        return None
    }

    private func SetCurrentScope(ctx: ASTContext, node: Node): Unit {
        node.scopeName = ctx.currentScopeName
        node.scopeLevel = ctx.currentScopeLevel
    }

    private func SetScopeGate(ctx: ASTContext, node: Node): Unit {
        node.scopeName = scopeManager.CalcScopeGateName(ctx)
        node.scopeLevel = ctx.currentScopeLevel
    }

    private func AssignPackageScopes(ctx: ASTContext, pkg: Package): Unit {
        pkg.scopeName = TOPLEVEL_SCOPE_NAME
        pkg.scopeLevel = 0u32
        for (file in pkg.files) {
            AssignFileScopes(ctx, file)
        }
    }

    private func AssignFileScopes(ctx: ASTContext, file: File): Unit {
        file.scopeName = TOPLEVEL_SCOPE_NAME
        file.scopeLevel = 0u32
        for (importSpec in file.imports) {
            AssignPlainSubtree(ctx, importSpec)
        }
        var idx: Int64 = 0
        while (idx < file.decls.size) {
            AssignNode(ctx, file.decls[idx])
            idx++
        }
        if (enableMacroInLsp) {
            scopeManager.InitializeScope(ctx)
            for (macroCall in file.originalMacroCallNodes) {
                AssignNode(ctx, macroCall)
            }
            scopeManager.FinalizeScope(ctx)
        }
    }

    private func AssignPlainSubtree(ctx: ASTContext, root: Node): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            if (AssignDispatchedNode(ctx, node)) {
                return VisitAction.SKIP_CHILDREN
            }
            SetCurrentScope(ctx, node)
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func AssignBlockContents(ctx: ASTContext, block: Block): Unit {
        SetCurrentScope(ctx, block)
        for (child in block.body) {
            AssignNode(ctx, child)
        }
    }

    private func AssignFuncBody(ctx: ASTContext, fb: FuncBody): Unit {
        SetScopeGate(ctx, fb)
        if (let Some(generic) <- fb.generic) {
            AssignGeneric(ctx, generic)
        }
        scopeManager.InitializeScope(ctx)
        for (paramList in fb.paramLists) {
            SetCurrentScope(ctx, paramList)
            for (param in paramList.params) {
                AssignNode(ctx, param)
            }
        }
        if (let Some(retType) <- fb.retType) {
            AssignNode(ctx, retType)
        }
        if (let Some(body) <- fb.body) {
            AssignBlockContents(ctx, body)
        }
        for (captured in fb.capturedVars) {
            AssignNode(ctx, captured)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignGeneric(ctx: ASTContext, generic: Generic): Unit {
        SetCurrentScope(ctx, generic)
        for (param in generic.typeParameters) {
            SetScopeGate(ctx, param)
        }
        for (constraint in generic.genericConstraints) {
            SetCurrentScope(ctx, constraint)
            if (let Some(refType) <- constraint.refType) {
                AssignNode(ctx, refType)
            }
            for (upperBound in constraint.upperBounds) {
                AssignNode(ctx, upperBound)
            }
        }
    }

    private func AssignClassBody(ctx: ASTContext, body: ClassBody): Unit {
        SetScopeGate(ctx, body)
        scopeManager.InitializeScope(ctx)
        for (decl in body.decls) {
            decl.EnableAttr(Attribute.IN_CLASSLIKE)
            AssignNode(ctx, decl)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignStructBody(ctx: ASTContext, body: StructBody): Unit {
        SetScopeGate(ctx, body)
        scopeManager.InitializeScope(ctx)
        for (decl in body.decls) {
            AssignNode(ctx, decl)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignInterfaceBody(ctx: ASTContext, body: InterfaceBody): Unit {
        SetScopeGate(ctx, body)
        scopeManager.InitializeScope(ctx)
        for (decl in body.decls) {
            AssignNode(ctx, decl)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignClassDecl(ctx: ASTContext, cd: ClassDecl): Unit {
        for (annotation in cd.annotations) {
            AssignNode(ctx, annotation)
        }
        SetScopeGate(ctx, cd)
        scopeManager.InitializeScope(ctx)
        if (let Some(generic) <- cd.generic) {
            AssignGeneric(ctx, generic)
        }
        for (inheritedType in cd.inheritedTypes) {
            AssignNode(ctx, inheritedType)
        }
        if (let Some(body) <- cd.body) {
            AssignClassBody(ctx, body)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignStructDecl(ctx: ASTContext, sd: StructDecl): Unit {
        for (annotation in sd.annotations) {
            AssignNode(ctx, annotation)
        }
        SetScopeGate(ctx, sd)
        scopeManager.InitializeScope(ctx)
        if (let Some(generic) <- sd.generic) {
            AssignGeneric(ctx, generic)
        }
        for (inheritedType in sd.inheritedTypes) {
            AssignNode(ctx, inheritedType)
        }
        if (let Some(body) <- sd.body) {
            AssignStructBody(ctx, body)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignInterfaceDecl(ctx: ASTContext, id: InterfaceDecl): Unit {
        for (annotation in id.annotations) {
            AssignNode(ctx, annotation)
        }
        SetScopeGate(ctx, id)
        scopeManager.InitializeScope(ctx)
        if (let Some(generic) <- id.generic) {
            AssignGeneric(ctx, generic)
        }
        for (inheritedType in id.inheritedTypes) {
            AssignNode(ctx, inheritedType)
        }
        if (let Some(body) <- id.body) {
            AssignInterfaceBody(ctx, body)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignEnumDecl(ctx: ASTContext, ed: EnumDecl): Unit {
        for (annotation in ed.annotations) {
            AssignNode(ctx, annotation)
        }
        SetScopeGate(ctx, ed)
        scopeManager.InitializeScope(ctx)
        if (let Some(generic) <- ed.generic) {
            AssignGeneric(ctx, generic)
        }
        for (inheritedType in ed.inheritedTypes) {
            AssignNode(ctx, inheritedType)
        }
        let bodyScope = ed.bodyScope ?? DummyBody()
        bodyScope.curFile = ed.curFile
        ed.bodyScope = Some(bodyScope)
        SetScopeGate(ctx, bodyScope)
        scopeManager.InitializeScope(ctx)
        for (ctor in ed.constructors) {
            if (let Some(fd) <- (ctor as FuncDecl)) {
                if (let Some(funcBody) <- fd.funcBody) {
                    funcBody.parentEnum = Some(ed)
                }
            }
            AssignNode(ctx, ctor)
        }
        for (member in ed.members) {
            AssignNode(ctx, member)
            if (let Some(fd2) <- (member as FuncDecl)) {
                if (let Some(funcBody2) <- fd2.funcBody) {
                    funcBody2.parentEnum = Some(ed)
                }
            }
        }
        scopeManager.FinalizeScope(ctx)
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignExtendDecl(ctx: ASTContext, ed: ExtendDecl): Unit {
        for (annotation in ed.annotations) {
            AssignNode(ctx, annotation)
        }
        SetScopeGate(ctx, ed)
        scopeManager.InitializeScope(ctx)
        if (let Some(generic) <- ed.generic) {
            AssignGeneric(ctx, generic)
        }
        if (let Some(extendedType) <- ed.extendedType) {
            AssignNode(ctx, extendedType)
        }
        for (inheritedType in ed.inheritedTypes) {
            AssignNode(ctx, inheritedType)
        }
        let bodyScope = ed.bodyScope ?? DummyBody()
        bodyScope.curFile = ed.curFile
        ed.bodyScope = Some(bodyScope)
        SetScopeGate(ctx, bodyScope)
        scopeManager.InitializeScope(ctx)
        for (member in ed.members) {
            AssignNode(ctx, member)
        }
        scopeManager.FinalizeScope(ctx)
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignTypeAliasDecl(ctx: ASTContext, tad: TypeAliasDecl): Unit {
        SetScopeGate(ctx, tad)
        scopeManager.InitializeScope(ctx)
        if (let Some(generic) <- tad.generic) {
            AssignGeneric(ctx, generic)
        }
        if (let Some(typeNode) <- tad.typeNode) {
            AssignNode(ctx, typeNode)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignFuncDecl(ctx: ASTContext, fd: FuncDecl): Unit {
        for (annotation in fd.annotations) {
            AssignNode(ctx, annotation)
        }
        SetScopeGate(ctx, fd)
        if (let Some(body) <- fd.funcBody) {
            scopeManager.InitializeScope(ctx)
            body.funcDecl = Some(fd)
            AssignFuncBody(ctx, body)
            scopeManager.FinalizeScope(ctx)
        }
    }

    private func AssignMainDecl(ctx: ASTContext, md: MainDecl): Unit {
        if (let Some(desugarDecl) <- md.desugarDecl) {
            AssignNode(ctx, desugarDecl)
            return
        }
        for (annotation in md.annotations) {
            AssignNode(ctx, annotation)
        }
        SetScopeGate(ctx, md)
        if (let Some(body) <- md.funcBody) {
            scopeManager.InitializeScope(ctx)
            AssignFuncBody(ctx, body)
            scopeManager.FinalizeScope(ctx)
        }
    }

    private func SetPropAccessorContext(propDecl: PropDecl, accessor: FuncDecl): Unit {
        accessor.identifierForLsp = accessor.identifier.Val()
        if (accessor.isGetter && accessor.identifier.Val() == "get") {
            accessor.identifier = SrcIdentifier("$${propDecl.identifier.Val()}get", accessor.identifier.Begin(),
                accessor.identifier.End(), accessor.identifier.IsRaw())
        } else if (accessor.isSetter && accessor.identifier.Val() == "set") {
            accessor.identifier = SrcIdentifier("$${propDecl.identifier.Val()}set", accessor.identifier.Begin(),
                accessor.identifier.End(), accessor.identifier.IsRaw())
        }
        accessor.propDecl = propDecl
        if (let Some(outer) <- propDecl.outerDecl) {
            accessor.outerDecl = outer
            if (let Some(body) <- accessor.funcBody) {
                if (let Some(classLike) <- (outer as ClassLikeDecl)) {
                    body.parentClassLike = classLike
                } else if (let Some(structDecl) <- (outer as StructDecl)) {
                    body.parentStruct = structDecl
                } else if (let Some(enumDecl) <- (outer as EnumDecl)) {
                    body.parentEnum = enumDecl
                }
            }
        }
    }

    private func AssignPropDecl(ctx: ASTContext, pd: PropDecl): Unit {
        AssignVarDecl(ctx, pd)
        for (setter in pd.setters) {
            SetPropAccessorContext(pd, setter)
            AssignNode(ctx, setter)
        }
        for (getter in pd.getters) {
            SetPropAccessorContext(pd, getter)
            AssignNode(ctx, getter)
        }
    }

    private func AssignVarDecl(ctx: ASTContext, vd: VarDeclAbstract): Unit {
        SetCurrentScope(ctx, vd)
        if (let Some(typeNode) <- vd.typeNode) {
            AssignNode(ctx, typeNode)
        }
        if (let Some(initializer) <- vd.initializer) {
            AssignNode(ctx, initializer)
        }
    }

    private func AssignVarWithPatternDecl(ctx: ASTContext, vpd: VarWithPatternDecl): Unit {
        SetCurrentScope(ctx, vpd)
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            AssignNode(ctx, pattern)
        }
        if (let Some(typeNode) <- vpd.typeNode) {
            AssignNode(ctx, typeNode)
        }
        if (let Some(initializer) <- vpd.initializer) {
            AssignNode(ctx, initializer)
        }
    }

    private func AssignFuncParam(ctx: ASTContext, fp: FuncParam): Unit {
        SetCurrentScope(ctx, fp)
        if (let Some(typeNode) <- fp.typeNode) {
            AssignNode(ctx, typeNode)
        }
        if (let Some(assign) <- fp.assignment) {
            AssignNode(ctx, assign)
        }
        if (let Some(desugarDecl) <- fp.desugarDecl) {
            AssignNode(ctx, desugarDecl)
        }
    }

    private func AssignBlock(ctx: ASTContext, block: Block): Unit {
        SetScopeGate(ctx, block)
        scopeManager.InitializeScope(ctx)
        for (child in block.body) {
            AssignNode(ctx, child)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func CollectCondition(ctx: ASTContext, e: Expr): Unit {
        if (let Some(letPattern) <- (e as LetPatternDestructor)) {
            if (let Some(initializer) <- letPattern.initializer) {
                AssignNode(ctx, initializer)
            }
            SetCurrentScope(ctx, letPattern)
            for (pattern in letPattern.patterns) {
                AssignNode(ctx, pattern)
            }
            return
        }

        if (let Some(paren) <- (e as ParenExpr)) {
            SetCurrentScope(ctx, paren)
            if (let Some(inner) <- paren.expr) {
                CollectCondition(ctx, inner)
            }
            return
        }

        if (let Some(binop) <- (e as BinaryExpr)) {
            if (binop.op == TokenKind.AND || binop.op == TokenKind.OR) {
                SetCurrentScope(ctx, binop)
                if (let Some(leftExpr) <- binop.leftExpr) {
                    CollectCondition(ctx, leftExpr)
                }
                if (let Some(rightExpr) <- binop.rightExpr) {
                    CollectCondition(ctx, rightExpr)
                }
                return
            }
        }

        AssignNode(ctx, e)
    }

    private func AssignIfExpr(ctx: ASTContext, ie: IfExpr): Unit {
        SetScopeGate(ctx, ie)
        scopeManager.InitializeScope(ctx)
        if (let Some(cond) <- ie.condExpr) {
            CollectCondition(ctx, cond)
        }
        if (let Some(thenBody) <- ie.thenBody) {
            AssignBlockContents(ctx, thenBody)
        }
        scopeManager.FinalizeScope(ctx)
        if (ie.hasElse) {
            if (let Some(elseBody) <- ie.elseBody) {
                AssignNode(ctx, elseBody)
            }
        }
    }

    private func AssignForInExpr(ctx: ASTContext, fie: ForInExpr): Unit {
        if (let Some(inExpr) <- fie.inExpression) {
            AssignNode(ctx, inExpr)
        }
        SetScopeGate(ctx, fie)
        scopeManager.InitializeScope(ctx)
        if (let Some(pattern) <- fie.pattern) {
            AssignNode(ctx, pattern)
        }
        if (let Some(pattern) <- fie.patternInDesugarExpr) {
            AssignNode(ctx, pattern)
        }
        if (let Some(guard) <- fie.patternGuard) {
            AssignNode(ctx, guard)
        }
        if (let Some(body) <- fie.body) {
            AssignBlockContents(ctx, body)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignWhileExpr(ctx: ASTContext, we: WhileExpr): Unit {
        SetScopeGate(ctx, we)
        scopeManager.InitializeScope(ctx)
        if (let Some(cond) <- we.condExpr) {
            CollectCondition(ctx, cond)
        }
        if (let Some(body) <- we.body) {
            AssignBlockContents(ctx, body)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignDoWhileExpr(ctx: ASTContext, dwe: DoWhileExpr): Unit {
        SetScopeGate(ctx, dwe)
        scopeManager.InitializeScope(ctx)
        if (let Some(cond) <- dwe.condExpr) {
            AssignNode(ctx, cond)
        }
        if (let Some(body) <- dwe.body) {
            AssignNode(ctx, body)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignLambdaExpr(ctx: ASTContext, le: LambdaExpr): Unit {
        SetScopeGate(ctx, le)
        scopeManager.InitializeScope(ctx)
        if (let Some(body) <- le.funcBody) {
            AssignFuncBody(ctx, body)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignMatchExpr(ctx: ASTContext, me: MatchExpr): Unit {
        SetCurrentScope(ctx, me)
        if (let Some(selector) <- me.selector) {
            AssignNode(ctx, selector)
        }
        for (matchCase in me.matchCases) {
            AssignNode(ctx, matchCase)
        }
        for (matchCaseOther in me.matchCaseOthers) {
            AssignNode(ctx, matchCaseOther)
        }
    }

    private func AssignMatchCase(ctx: ASTContext, mc: MatchCase): Unit {
        SetScopeGate(ctx, mc)
        scopeManager.InitializeScope(ctx)
        for (pattern in mc.patterns) {
            AssignNode(ctx, pattern)
        }
        if (let Some(guard) <- mc.patternGuard) {
            AssignNode(ctx, guard)
        }
        if (let Some(body) <- mc.exprOrDecls) {
            AssignBlockContents(ctx, body)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignMatchCaseOther(ctx: ASTContext, mco: MatchCaseOther): Unit {
        SetCurrentScope(ctx, mco)
        if (let Some(matchExpr) <- mco.matchExpr) {
            AssignNode(ctx, matchExpr)
        }
        if (let Some(body) <- mco.exprOrDecls) {
            AssignNode(ctx, body)
        }
    }

    private func AssignTryExpr(ctx: ASTContext, te: TryExpr): Unit {
        SetScopeGate(ctx, te)
        scopeManager.InitializeScope(ctx)
        for (resource in te.resourceSpec) {
            AssignNode(ctx, resource)
        }
        if (let Some(tryBlock) <- te.tryBlock) {
            AssignBlockContents(ctx, tryBlock)
        }
        scopeManager.FinalizeScope(ctx)
        if (!te.handlers.isEmpty()) {
            if (let Some(tryLambda) <- te.tryLambda) {
                AssignNode(ctx, tryLambda)
            }
            if (let Some(finallyLambda) <- te.finallyLambda) {
                AssignNode(ctx, finallyLambda)
            }
        }
        var catchIdx: Int64 = 0
        while (catchIdx < te.catchBlocks.size) {
            let catchBlock = te.catchBlocks[catchIdx]
            SetScopeGate(ctx, catchBlock)
            scopeManager.InitializeScope(ctx)
            if (catchIdx < te.catchPatterns.size) {
                AssignNode(ctx, te.catchPatterns[catchIdx])
            }
            for (child in catchBlock.body) {
                AssignNode(ctx, child)
            }
            scopeManager.FinalizeScope(ctx)
            catchIdx++
        }
        for (handler in te.handlers) {
            if (let Some(block) <- handler.block) {
                SetScopeGate(ctx, block)
                scopeManager.InitializeScope(ctx)
                if (let Some(pattern) <- handler.commandPattern) {
                    AssignNode(ctx, pattern)
                }
                for (child in block.body) {
                    AssignNode(ctx, child)
                }
                scopeManager.FinalizeScope(ctx)
            }
            if (let Some(lambda) <- handler.desugaredLambda) {
                AssignNode(ctx, lambda)
            }
        }
        if (let Some(finallyBlock) <- te.finallyBlock) {
            AssignNode(ctx, finallyBlock)
        }
    }

    private func AssignSynchronizedExpr(ctx: ASTContext, se: SynchronizedExpr): Unit {
        SetScopeGate(ctx, se)
        scopeManager.InitializeScope(ctx)
        if (let Some(mutex) <- se.mutex) {
            AssignNode(ctx, mutex)
        }
        if (let Some(desugarExpr) <- se.desugarExpr) {
            AssignNode(ctx, desugarExpr)
        }
        scopeManager.FinalizeScope(ctx)
    }

    private func AssignDispatchedNode(ctx: ASTContext, node: Node): Bool {
        if (let Some(macroDecl) <- (node as MacroExpandDecl)) {
            for (annotation in macroDecl.annotations) {
                AssignNode(ctx, annotation)
            }
            SetCurrentScope(ctx, macroDecl)
            if (let Some(decl) <- macroDecl.invocation.decl) {
                scopeManager.InitializeScope(ctx)
                AssignNode(ctx, decl)
                scopeManager.FinalizeScope(ctx)
            }
            return true
        }
        if (let Some(macroExpr) <- (node as MacroExpandExpr)) {
            SetCurrentScope(ctx, macroExpr)
            if (let Some(decl) <- macroExpr.invocation.decl) {
                scopeManager.InitializeScope(ctx)
                AssignNode(ctx, decl)
                scopeManager.FinalizeScope(ctx)
            }
            return true
        }
        if (let Some(macroParam) <- (node as MacroExpandParam)) {
            SetCurrentScope(ctx, macroParam)
            if (let Some(decl) <- macroParam.invocation.decl) {
                scopeManager.InitializeScope(ctx)
                AssignNode(ctx, decl)
                scopeManager.FinalizeScope(ctx)
            }
            return true
        }
        if (let Some(classDecl) <- (node as ClassDecl)) {
            AssignClassDecl(ctx, classDecl)
            return true
        }
        if (let Some(structDecl) <- (node as StructDecl)) {
            AssignStructDecl(ctx, structDecl)
            return true
        }
        if (let Some(interfaceDecl) <- (node as InterfaceDecl)) {
            AssignInterfaceDecl(ctx, interfaceDecl)
            return true
        }
        if (let Some(enumDecl) <- (node as EnumDecl)) {
            AssignEnumDecl(ctx, enumDecl)
            return true
        }
        if (let Some(extendDecl) <- (node as ExtendDecl)) {
            AssignExtendDecl(ctx, extendDecl)
            return true
        }
        if (let Some(typeAlias) <- (node as TypeAliasDecl)) {
            AssignTypeAliasDecl(ctx, typeAlias)
            return true
        }
        if (let Some(funcDecl) <- (node as FuncDecl)) {
            AssignFuncDecl(ctx, funcDecl)
            return true
        }
        if (let Some(mainDecl) <- (node as MainDecl)) {
            AssignMainDecl(ctx, mainDecl)
            return true
        }
        if (let Some(funcBody) <- (node as FuncBody)) {
            AssignFuncBody(ctx, funcBody)
            return true
        }
        if (let Some(funcParam) <- (node as FuncParam)) {
            AssignFuncParam(ctx, funcParam)
            return true
        }
        if (let Some(varWithPattern) <- (node as VarWithPatternDecl)) {
            AssignVarWithPatternDecl(ctx, varWithPattern)
            return true
        }
        if (let Some(propDecl) <- (node as PropDecl)) {
            AssignPropDecl(ctx, propDecl)
            return true
        }
        if (let Some(varDecl) <- (node as VarDeclAbstract)) {
            AssignVarDecl(ctx, varDecl)
            return true
        }
        if (let Some(block) <- (node as Block)) {
            AssignBlock(ctx, block)
            return true
        }
        if (let Some(ifExpr) <- (node as IfExpr)) {
            AssignIfExpr(ctx, ifExpr)
            return true
        }
        if (let Some(forInExpr) <- (node as ForInExpr)) {
            AssignForInExpr(ctx, forInExpr)
            return true
        }
        if (let Some(whileExpr) <- (node as WhileExpr)) {
            AssignWhileExpr(ctx, whileExpr)
            return true
        }
        if (let Some(doWhileExpr) <- (node as DoWhileExpr)) {
            AssignDoWhileExpr(ctx, doWhileExpr)
            return true
        }
        if (let Some(lambdaExpr) <- (node as LambdaExpr)) {
            AssignLambdaExpr(ctx, lambdaExpr)
            return true
        }
        if (let Some(matchExpr) <- (node as MatchExpr)) {
            AssignMatchExpr(ctx, matchExpr)
            return true
        }
        if (let Some(matchCase) <- (node as MatchCase)) {
            AssignMatchCase(ctx, matchCase)
            return true
        }
        if (let Some(matchCaseOther) <- (node as MatchCaseOther)) {
            AssignMatchCaseOther(ctx, matchCaseOther)
            return true
        }
        if (let Some(tryExpr) <- (node as TryExpr)) {
            AssignTryExpr(ctx, tryExpr)
            return true
        }
        if (let Some(syncExpr) <- (node as SynchronizedExpr)) {
            AssignSynchronizedExpr(ctx, syncExpr)
            return true
        }
        return false
    }

    private func AssignNode(ctx: ASTContext, node: Node): Unit {
        if (AssignDispatchedNode(ctx, node)) {
            return
        }
        AssignPlainSubtree(ctx, node)
    }

    private func SymbolName(node: Node): String {
        if (let Some(pkg) <- (node as Package)) {
            return pkg.fullPackageName
        }
        if (let Some(file) <- (node as File)) {
            return if (!file.fileName.isEmpty()) { file.fileName } else { file.filePath }
        }
        if (let Some(macroDecl) <- (node as MacroExpandDecl)) {
            return macroDecl.invocation.macroCallDiagInfo.fullName
        }
        if (let Some(macroExpr) <- (node as MacroExpandExpr)) {
            return macroExpr.invocation.macroCallDiagInfo.fullName
        }
        if (let Some(macroParam) <- (node as MacroExpandParam)) {
            return macroParam.invocation.macroCallDiagInfo.fullName
        }
        if (let Some(decl) <- (node as Decl)) {
            return decl.identifier.Val()
        }
        if (let Some(refExpr) <- (node as RefExpr)) {
            return refExpr.ref.identifier.Val()
        }
        if (let Some(member) <- (node as MemberAccess)) {
            return member.field.Val()
        }
        if (let Some(refType) <- (node as RefType)) {
            return refType.ref.identifier.Val()
        }
        if (let Some(qualifiedType) <- (node as QualifiedType)) {
            return qualifiedType.field.Val()
        }
        if (let Some(primitiveType) <- (node as PrimitiveType)) {
            return primitiveType.str
        }
        if (let Some(varOrEnumPattern) <- (node as VarOrEnumPattern)) {
            return varOrEnumPattern.identifier.Val()
        }
        if (let Some(enumPattern) <- (node as EnumPattern)) {
            return enumPattern.GetIdentifier()
        }
        return ""
    }
}
