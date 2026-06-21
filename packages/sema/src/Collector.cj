package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public class Collector {
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    private let scopeManager: ScopeManager = ScopeManager()

    public init() {}

    public func BuildSymbolTable(ctx: ASTContext, pkg: Package, buildTrie!: Bool = true): Unit {
        ctx.curPackage = pkg
        ctx.fullPackageName = pkg.fullPackageName
        scopeManager.Reset()
        ctx.currentScopeLevel = 0u32
        ctx.currentMaxDepth = 0u32
        ctx.currentScopeName = TOPLEVEL_SCOPE_NAME
        AssignPackageScopes(ctx, pkg)
        let collector = this
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(lce) <- (node as LitConstExpr)) {
                collector.CollectLitConstExpr(ctx, lce, buildTrie: buildTrie)
            } else {
                collector.AddSymbol(ctx, node, buildTrie: buildTrie)
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        ctx.searcher.InvalidateCache()
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
        let scopeName = if (node.scopeName.isEmpty()) { TOPLEVEL_SCOPE_NAME } else { node.scopeName }
        let fileHash = if (let Some(file) <- node.curFile) { file.fileHash } else { 0u64 }
        let symbol = Symbol(fileHash, SymbolName(node), node, node.scopeLevel, scopeName)
        node.symbol = Some(symbol)
        ctx.symbolTable.add(symbol)
        ctx.invertedIndex.Index(symbol, withTrie: buildTrie)
    }

    private func CollectLitConstExpr(ctx: ASTContext, lce: LitConstExpr, buildTrie!: Bool = true): Unit {
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
        AddSymbol(ctx, lce, buildTrie: buildTrie)
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

    private func AssignVarDecl(ctx: ASTContext, vd: VarDeclAbstract): Unit {
        SetCurrentScope(ctx, vd)
        if (let Some(typeNode) <- vd.typeNode) {
            AssignNode(ctx, typeNode)
        }
        if (let Some(initializer) <- vd.initializer) {
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

    private func AssignIfExpr(ctx: ASTContext, ie: IfExpr): Unit {
        SetScopeGate(ctx, ie)
        scopeManager.InitializeScope(ctx)
        if (let Some(cond) <- ie.condExpr) {
            AssignNode(ctx, cond)
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
            AssignNode(ctx, cond)
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
