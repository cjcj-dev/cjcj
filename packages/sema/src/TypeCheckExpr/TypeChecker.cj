package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::sema.*
import cangjie_compiler::sema.Desugar.*
import cangjie_compiler::sema.FFI.*

private func contextPackage(ctx: ASTContext): Option<Package> {
    return ctx.curPackage
}

private func scopeNameOf(node: Node): String {
    return if (node.scopeName.isEmpty()) { TOPLEVEL_SCOPE_NAME } else { node.scopeName }
}

private func tyOrInvalid(node: Node): Ty {
    return node.GetTy() ?? TypeManager.GetInvalidTy()
}

private func questTy(): Ty {
    return TypeManager.GetQuestTy()
}

public class TypeChecker {
    private var ci: Option<CompilerInstance> = None
    private var impl: TypeCheckerImpl = TypeCheckerImpl()
    private let contexts: ArrayList<ASTContext> = ArrayList<ASTContext>()

    public init(ci: Option<CompilerInstance>) {
        this.ci = ci
        let tm = if (let Some(instance) <- ci) { instance.typeManager } else { TypeManager() }
        impl = TypeCheckerImpl(typeManager: tm)
    }

    public func TypeCheckForPackages(pkgs: ArrayList<Package>): Unit {
        let activeContexts = PreTypeCheck(pkgs)
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                DoTypeCheck(ctx, pkg)
            }
        }
        PostTypeCheck(activeContexts)
    }

    public func SetOverflowStrategy(pkgs: ArrayList<Package>): Unit {
        var optionStrategy = OverflowStrategy.THROWING
        if (let Some(instance) <- ci) {
            optionStrategy = instance.globalOptions.overflowStrategy
        }
        SetIntegerOverflowStrategy(pkgs, optionStrategy)
    }

    public func CheckInlineFunctions(pkgs: ArrayList<Package>): Unit {
        var options = OptionGlobalOptions()
        if (let Some(instance) <- ci) {
            options = instance.globalOptions
        }
        CheckInlineFunctionsForPackages(pkgs, options)
    }

    public func CheckUnusedImportSpec(pkg: Package): ArrayList<UnusedImportFinding> {
        return CollectUnusedImports(pkg)
    }

    public func CheckAllDeclAttributes(pkg: Package): ArrayList<DeclAttributeIssue> {
        return CheckDeclAttributesForPackage(pkg, opts: GlobalOptions())
    }

    private func PreTypeCheck(pkgs: ArrayList<Package>): ArrayList<ASTContext> {
        contexts.clear()
        for (pkg in pkgs) {
            let ctx = ASTContext(pkg)
            contexts.add(ctx)
        }
        for (ctx in contexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                PrepareTypeCheck(ctx, pkg)
            }
        }
        PreCheck(contexts)
        return contexts
    }

    private func PrepareTypeCheck(ctx: ASTContext, pkg: Package): Unit {
        ctx.Reset()
        ctx.curPackage = pkg
        ctx.fullPackageName = pkg.fullPackageName
        AddCurFile(pkg)
        Collector().BuildSymbolTable(ctx, pkg)
        impl.WarmupCache(ctx)
    }

    private func PreCheck(activeContexts: ArrayList<ASTContext>): Unit {
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                PreCheckAnnoForFFI(pkg)
                let _ = PreCheckPackage(ctx, pkg, typeManager: impl.typeManager)
            }
        }
        impl.typeManager.ClearMapCache()
    }

    private func DoTypeCheck(ctx: ASTContext, pkg: Package): Unit {
        ResolveReferenceTargets(ctx, pkg)
        for (sym in impl.GetToplevelDecls(ctx)) {
            if (let Some(node) <- sym.node) {
                if (let Some(decl) <- (node as Decl)) {
                    TypeCheckTopLevelDecl(ctx, decl)
                }
            }
        }
        for (decl in pkg.srcImportedNonGenericDecls) {
            SynthesizeTree(ctx, decl)
        }
        if (pkg.TestAttr(Attribute.IMPORTED)) {
            TypeCheckImportedGenericMember(ctx)
        }
    }

    private func PostTypeCheck(activeContexts: ArrayList<ASTContext>): Unit {
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                SetOverflowStrategyForPkg(pkg)
                let _ = CollectUnusedImports(pkg)
                let _ = CheckConstEvaluation(pkg)
                PerformDesugarAfterTypeCheck(impl.typeManager, pkg, options: GlobalOptions())
            }
        }
    }

    private func GlobalOptions(): OptionGlobalOptions {
        if (let Some(instance) <- ci) {
            return instance.globalOptions
        }
        return OptionGlobalOptions()
    }

    private func TypeCheckTopLevelDecl(ctx: ASTContext, decl: Decl): Unit {
        SynthesizeTree(ctx, decl)
    }

    private func TypeCheckImportedGenericMember(ctx: ASTContext): Unit {
        for (sym in impl.GetAllStructDecls(ctx)) {
            if (let Some(node) <- sym.node) {
                if (let Some(inheritable) <- (node as InheritableDecl)) {
                    if (inheritable.TestAttr(Attribute.GENERIC)) {
                        continue
                    }
                    for (member in inheritable.GetMemberDecls()) {
                        if (member.TestAttr(Attribute.GENERIC)) {
                            SynthesizeTree(ctx, member)
                        }
                    }
                }
            }
        }
    }

    private func SynthesizeTree(ctx: ASTContext, root: Node): Ty {
        let checker = this
        let walker = Walker(root, visitPost: { node: Node =>
            let _ = checker.SynthesizeNode(ctx, node)
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        return tyOrInvalid(root)
    }

    private func SynthesizeNode(ctx: ASTContext, node: Node): Ty {
        if (let Some(typeNode) <- (node as Type)) {
            impl.SetTypeTy(ctx, typeNode)
            return tyOrInvalid(typeNode)
        }
        if (let Some(funcBody) <- (node as FuncBody)) {
            return SynthesizeFuncBody(ctx, funcBody)
        }
        if (let Some(decl) <- (node as Decl)) {
            return SynthesizeDecl(ctx, decl)
        }
        if (let Some(expr) <- (node as Expr)) {
            return SynExprShallow(impl.typeManager, expr)
        }
        return tyOrInvalid(node)
    }

    private func SynthesizeDecl(ctx: ASTContext, decl: Decl): Ty {
        if (let Some(vd) <- (decl as VarDeclAbstract)) {
            if (let Some(initializer) <- vd.initializer) {
                let _ = SynExprShallow(impl.typeManager, initializer)
            }
            return TypeCheckDeclSynchronizeTypeAndInitializer(impl.typeManager, vd)
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (funcDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                return TypeCheckDeclSetEnumElementTy(impl.typeManager, funcDecl)
            }
            if (let Some(body) <- funcDecl.funcBody) {
                body.funcDecl = Some(funcDecl)
                return SynthesizeFuncBody(ctx, body)
            }
        }
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(body) <- mainDecl.funcBody) {
                return SynthesizeFuncBody(ctx, body)
            }
        }
        if (let Some(macroDecl) <- (decl as MacroDecl)) {
            if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
                return SynthesizeDecl(ctx, desugarDecl)
            }
            if (let Some(body) <- macroDecl.funcBody) {
                return SynthesizeFuncBody(ctx, body)
            }
        }
        if (let Some(primaryCtor) <- (decl as PrimaryCtorDecl)) {
            if (let Some(body) <- primaryCtor.funcBody) {
                return SynthesizeFuncBody(ctx, body)
            }
        }
        if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            return TypeCheckDeclSetEnumElementTy(impl.typeManager, decl)
        }
        return tyOrInvalid(decl)
    }

    private func SynthesizeFuncBody(ctx: ASTContext, fb: FuncBody): Ty {
        let retType = EnsureRetType(ctx, fb)
        let paramTys = GetFuncBodyParamTys(fb)
        var retTy = retType.GetTy() ?? questTy()
        if (let Some(body) <- fb.body) {
            if (retTy.IsQuest()) {
                let bodyTy = SynBlock(impl.typeManager, body)
                retType.SetTy(bodyTy)
                retTy = bodyTy
            } else if (retTy.IsUnit()) {
                let _ = SynBlock(impl.typeManager, body)
            } else if (NeedCheckBodyReturn(fb)) {
                let _ = ChkBlock(impl.typeManager, retTy, body)
            } else {
                let _ = SynBlock(impl.typeManager, body)
            }
        }
        let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retTy)
        fb.SetTy(funcTy)
        if (let Some(funcDecl) <- fb.funcDecl) {
            funcDecl.SetTy(funcTy)
        }
        return funcTy
    }

    private func EnsureRetType(ctx: ASTContext, fb: FuncBody): Type {
        if (let Some(retType) <- fb.retType) {
            if (Ty.IsInitialTy(retType.GetTy())) {
                retType.SetTy(impl.GetTyFromASTType(ctx, retType))
            }
            return retType
        }
        let retType = RefType()
        retType.EnableAttr(Attribute.COMPILER_ADD)
        retType.SetTy(questTy())
        fb.retType = Some(retType)
        return retType
    }

    private func ResolveReferenceTargets(ctx: ASTContext, pkg: Package): Unit {
        let checker = this
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(refExpr) <- (node as RefExpr)) {
                checker.ResolveRefExpr(ctx, refExpr)
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func ResolveRefExpr(ctx: ASTContext, refExpr: RefExpr): Unit {
        if ((let Some(_) <- refExpr.ref.target) || !refExpr.ref.targets.isEmpty()) {
            return
        }
        let targets = impl.Lookup(ctx, refExpr.ref.identifier.Val(), scopeNameOf(refExpr), refExpr)
        for (target in targets) {
            refExpr.ref.targets.add(target)
        }
        if (targets.size == 1) {
            ReplaceTarget(refExpr, Some(targets[0]), insertTarget: true)
        }
    }
}
