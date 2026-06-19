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

private func lookupResolvedPackageDecl(ctx: ASTContext, packageName: String, name: String): Option<Decl> {
    if (let Some(packageMap) <- ctx.resolvedPackageMemberDeclsMap.get(packageName)) {
        if (let Some(decls) <- packageMap.get(name)) {
            for (decl in decls) {
                if (decl.identifier.Val() == name) {
                    return Some(decl)
                }
            }
        }
    }
    for (packageDecl in ctx.packageDecls) {
        if (packageDecl.fullPackageName == packageName || packageDecl.srcPackage.fullPackageName == packageName) {
            for (file in packageDecl.srcPackage.files) {
                for (decl2 in file.decls) {
                    if (decl2.identifier.Val() == name) {
                        return Some(decl2)
                    }
                }
            }
        }
    }
    return None
}

private func addDeclUniqueToPackage(values: ArrayList<Decl>, decl: Decl): Unit {
    for (value in values) {
        if (sameImportedAwareDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
}

private func sameImportedAwareDecl(left: Decl, right: Decl): Bool {
    if (left.TestAttr(Attribute.IMPORTED) && right.TestAttr(Attribute.IMPORTED)) {
        if (!left.rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
            return left.rawMangleName == right.rawMangleName
        }
        if (!left.mangledName.isEmpty() || !right.mangledName.isEmpty()) {
            return left.mangledName == right.mangledName
        }
    }
    return SameDecl(left, right)
}

private func addImportedDeclToCurrentPackage(ctx: ASTContext, decl: Decl): Unit {
    if (!decl.TestAttr(Attribute.IMPORTED)) {
        return
    }
    if (let Some(pkg) <- ctx.curPackage) {
        addDeclUniqueToPackage(pkg.srcImportedNonGenericDecls, decl)
    }
}

private func addImportedTyToCurrentPackage(ctx: ASTContext, ty: Ty): Unit {
    if (let Some(structTy) <- (ty as StructTy)) {
        if (let Some(decl) <- structTy.decl) {
            addImportedDeclToCurrentPackage(ctx, decl)
        }
    } else if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(decl2) <- classTy.decl) {
            addImportedDeclToCurrentPackage(ctx, decl2)
        }
    } else if (let Some(enumTy) <- (ty as EnumTy)) {
        if (let Some(decl3) <- enumTy.decl) {
            addImportedDeclToCurrentPackage(ctx, decl3)
        }
    } else if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
        if (let Some(decl4) <- interfaceTy.decl) {
            addImportedDeclToCurrentPackage(ctx, decl4)
        }
    } else if (let Some(funcTy) <- (ty as FuncTy)) {
        for (paramTy in funcTy.paramTys) {
            addImportedTyToCurrentPackage(ctx, paramTy)
        }
        addImportedTyToCurrentPackage(ctx, funcTy.retTy)
    }
    for (arg in ty.typeArgs) {
        addImportedTyToCurrentPackage(ctx, arg)
    }
}

private func addImportedDeclAndDependencies(ctx: ASTContext, decl: Decl): Unit {
    addImportedDeclToCurrentPackage(ctx, decl)
    if (let Some(outer) <- decl.outerDecl) {
        addImportedDeclToCurrentPackage(ctx, outer)
    }
    if (let Some(ty) <- decl.GetTy()) {
        addImportedTyToCurrentPackage(ctx, ty)
    }
}

private func isStringLiteral(expr: Expr): Bool {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        return lit.kind == LitConstKind.STRING || lit.kind == LitConstKind.JSTRING
    }
    return false
}

public class TypeChecker {
    private var ci: Option<CompilerInstance> = None
    private var impl: TypeCheckerImpl = TypeCheckerImpl()
    private let contexts: ArrayList<ASTContext> = ArrayList<ASTContext>()
    private var currentFuncBody: Option<FuncBody> = None

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
        SeedImportedPackageDecls(ctx)
        AddCurFile(pkg)
        Collector().BuildSymbolTable(ctx, pkg)
        impl.WarmupCache(ctx)
    }

    private func SeedImportedPackageDecls(ctx: ASTContext): Unit {
        ctx.packageDecls.clear()
        ctx.resolvedImportedDeclsMap.clear()
        ctx.resolvedPackageMemberDeclsMap.clear()
        if (let Some(instance) <- ci) {
            for (packageDecl in instance.packageDecls) {
                ctx.packageDecls.add(packageDecl)
            }
            for (fileHash in instance.resolvedImportedDeclsMap.keys()) {
                if (let Some(fileMap) <- instance.resolvedImportedDeclsMap.get(fileHash)) {
                    let ctxFileMap = HashMap<String, ArrayList<Decl>>()
                    for (name in fileMap.keys()) {
                        if (let Some(decls) <- fileMap.get(name)) {
                            let copiedDecls = ArrayList<Decl>()
                            for (decl in decls) {
                                copiedDecls.add(decl)
                            }
                            ctxFileMap[name] = copiedDecls
                        }
                    }
                    ctx.resolvedImportedDeclsMap[fileHash] = ctxFileMap
                }
            }
            for (packageName in instance.resolvedPackageMemberDeclsMap.keys()) {
                if (let Some(packageMap) <- instance.resolvedPackageMemberDeclsMap.get(packageName)) {
                    let ctxPackageMap = HashMap<String, ArrayList<Decl>>()
                    for (name in packageMap.keys()) {
                        if (let Some(decls) <- packageMap.get(name)) {
                            let copiedDecls = ArrayList<Decl>()
                            for (decl in decls) {
                                copiedDecls.add(decl)
                            }
                            ctxPackageMap[name] = copiedDecls
                        }
                    }
                    ctx.resolvedPackageMemberDeclsMap[packageName] = ctxPackageMap
                }
            }
        }
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
        PreparePackageSignatures(ctx)
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
        return SynthesizeNode(ctx, root)
    }

    private func SynthesizeNode(ctx: ASTContext, node: Node): Ty {
        if (let Some(typeNode) <- (node as Type)) {
            impl.SetTypeTy(ctx, typeNode)
            return tyOrInvalid(typeNode)
        }
        if (let Some(funcArg) <- (node as FuncArg)) {
            return SynthesizeFuncArg(ctx, funcArg)
        }
        if (let Some(funcBody) <- (node as FuncBody)) {
            return SynthesizeFuncBody(ctx, funcBody)
        }
        if (let Some(decl) <- (node as Decl)) {
            return SynthesizeDecl(ctx, decl)
        }
        if (let Some(expr) <- (node as Expr)) {
            return Synthesize(ctx, expr)
        }
        return tyOrInvalid(node)
    }

    private func SynthesizeTypeNode(ctx: ASTContext, typeNode: Option<Type>): Unit {
        if (let Some(value) <- typeNode) {
            impl.SetTypeTy(ctx, value)
        }
    }

    private func SynthesizeFuncArg(ctx: ASTContext, arg: FuncArg): Ty {
        if (let Some(expr) <- arg.expr) {
            let exprTy = Synthesize(ctx, expr)
            if (Ty.IsTyCorrect(exprTy)) {
                let concreteTy = TcReplaceIdeal(impl.typeManager, expr)
                arg.SetTy(concreteTy)
                return concreteTy
            }
        }
        let invalidTy = TypeManager.GetInvalidTy()
        arg.SetTy(invalidTy)
        return invalidTy
    }

    private func SynthesizeNodeChildren(ctx: ASTContext, node: Node): Unit {
        for (child in node.Children()) {
            let _ = SynthesizeNode(ctx, child)
        }
    }

    private func SetCallOrPattern(expr: Expr, owner: Node): Unit {
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            nameRef.callOrPattern = Some(owner)
        }
    }

    private func SetFunctionBodyOwner(decl: Decl, body: FuncBody): Unit {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            body.funcDecl = Some(funcDecl)
        }
        if (let Some(outer) <- decl.outerDecl) {
            if (let Some(classLike) <- (outer as ClassLikeDecl)) {
                body.parentClassLike = Some(classLike)
            } else if (let Some(structDecl) <- (outer as StructDecl)) {
                body.parentStruct = Some(structDecl)
            } else if (let Some(enumDecl) <- (outer as EnumDecl)) {
                body.parentEnum = Some(enumDecl)
            } else if (let Some(extendDecl) <- (outer as ExtendDecl)) {
                if (let Some(extendedType) <- extendDecl.extendedType) {
                    if (let Some(target) <- extendedType.GetTarget()) {
                        if (let Some(classLikeTarget) <- (target as ClassLikeDecl)) {
                            body.parentClassLike = Some(classLikeTarget)
                        } else if (let Some(structTarget) <- (target as StructDecl)) {
                            body.parentStruct = Some(structTarget)
                        } else if (let Some(enumTarget) <- (target as EnumDecl)) {
                            body.parentEnum = Some(enumTarget)
                        }
                    }
                }
            }
        }
    }

    private func SynthesizeDeclList(ctx: ASTContext, decls: ArrayList<Decl>): Unit {
        for (member in decls) {
            let _ = SynthesizeDecl(ctx, member)
        }
    }

    private func PreparePackageSignatures(ctx: ASTContext): Unit {
        for (sym in impl.GetToplevelDecls(ctx)) {
            if (let Some(node) <- sym.node) {
                if (let Some(decl) <- (node as Decl)) {
                    PrepareDeclSignature(ctx, decl)
                }
            }
        }
    }

    private func PrepareDeclListSignatures(ctx: ASTContext, decls: ArrayList<Decl>): Unit {
        for (member in decls) {
            PrepareDeclSignature(ctx, member)
        }
    }

    private func PrepareParamSignature(ctx: ASTContext, param: FuncParam): Unit {
        SynthesizeTypeNode(ctx, param.typeNode)
        if (let Some(typeNode) <- param.typeNode) {
            if (let Some(paramTy) <- typeNode.GetTy()) {
                param.SetTy(paramTy)
            }
        }
    }

    private func ConstructorReturnTy(fb: FuncBody): Option<Ty> {
        if (let Some(funcDecl) <- fb.funcDecl) {
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                if (let Some(outerDecl) <- funcDecl.outerDecl) {
                    return outerDecl.GetTy()
                }
            }
        }
        return None
    }

    private func IsConstructorBody(fb: FuncBody): Bool {
        if (let Some(funcDecl) <- fb.funcDecl) {
            return funcDecl.TestAttr(Attribute.CONSTRUCTOR)
        }
        return false
    }

    private func SignatureReturnTy(fb: FuncBody, retType: Type): Ty {
        if (let Some(ctorTy) <- ConstructorReturnTy(fb)) {
            retType.SetTy(ctorTy)
            return ctorTy
        }
        return retType.GetTy() ?? questTy()
    }

    private func PrepareFuncBodySignature(ctx: ASTContext, fb: FuncBody): Ty {
        for (paramList in fb.paramLists) {
            for (param in paramList.params) {
                PrepareParamSignature(ctx, param)
            }
        }
        let retType = EnsureRetType(ctx, fb)
        let paramTys = GetFuncBodyParamTys(fb)
        let retTy = SignatureReturnTy(fb, retType)
        let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retTy)
        fb.SetTy(funcTy)
        if (let Some(funcDecl) <- fb.funcDecl) {
            funcDecl.SetTy(funcTy)
        }
        return funcTy
    }

    private func PrepareDeclSignature(ctx: ASTContext, decl: Decl): Unit {
        if (let Some(vd) <- (decl as VarDeclAbstract)) {
            SynthesizeTypeNode(ctx, vd.typeNode)
            if (let Some(typeNode) <- vd.typeNode) {
                if (let Some(varTy) <- typeNode.GetTy()) {
                    vd.SetTy(varTy)
                }
            }
            return
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                SetFunctionBodyOwner(funcDecl, body)
                let _ = PrepareFuncBodySignature(ctx, body)
            }
            return
        }
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(body2) <- mainDecl.funcBody) {
                SetFunctionBodyOwner(mainDecl, body2)
                let mainTy = PrepareFuncBodySignature(ctx, body2)
                mainDecl.SetTy(mainTy)
            }
            return
        }
        if (let Some(macroDecl) <- (decl as MacroDecl)) {
            if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
                PrepareDeclSignature(ctx, desugarDecl)
            }
            if (let Some(body3) <- macroDecl.funcBody) {
                SetFunctionBodyOwner(macroDecl, body3)
                let macroTy = PrepareFuncBodySignature(ctx, body3)
                macroDecl.SetTy(macroTy)
            }
            return
        }
        if (let Some(primaryCtor) <- (decl as PrimaryCtorDecl)) {
            if (let Some(body4) <- primaryCtor.funcBody) {
                SetFunctionBodyOwner(primaryCtor, body4)
                let ctorTy = PrepareFuncBodySignature(ctx, body4)
                primaryCtor.SetTy(ctorTy)
            }
            return
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(body5) <- classDecl.body) {
                PrepareDeclListSignatures(ctx, body5.decls)
            }
            return
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            if (let Some(body6) <- structDecl.body) {
                PrepareDeclListSignatures(ctx, body6.decls)
            }
            return
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            if (let Some(body7) <- interfaceDecl.body) {
                PrepareDeclListSignatures(ctx, body7.decls)
            }
            return
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            PrepareDeclListSignatures(ctx, enumDecl.constructors)
            PrepareDeclListSignatures(ctx, enumDecl.members)
            return
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            SynthesizeTypeNode(ctx, extendDecl.extendedType)
            for (inheritedType in extendDecl.inheritedTypes) {
                impl.SetTypeTy(ctx, inheritedType)
            }
            PrepareDeclListSignatures(ctx, extendDecl.members)
            return
        }
        if (let Some(typeAlias) <- (decl as TypeAliasDecl)) {
            SynthesizeTypeNode(ctx, typeAlias.typeNode)
        }
    }

    private func SynthesizeDecl(ctx: ASTContext, decl: Decl): Ty {
        if (let Some(vd) <- (decl as VarDeclAbstract)) {
            SynthesizeTypeNode(ctx, vd.typeNode)
            if (let Some(initializer) <- vd.initializer) {
                if (let Some(typeNode) <- vd.typeNode) {
                    if (let Some(targetTy) <- typeNode.GetTy()) {
                        let _ = Check(ctx, targetTy, initializer)
                    } else {
                        let _ = Synthesize(ctx, initializer)
                    }
                } else {
                    let _ = Synthesize(ctx, initializer)
                }
            }
            let declTy = TypeCheckDeclSynchronizeTypeAndInitializer(impl.typeManager, vd)
            BindLocalDeclIfNeeded(ctx, decl)
            return declTy
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (funcDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                return TypeCheckDeclSetEnumElementTy(impl.typeManager, funcDecl)
            }
            if (let Some(body) <- funcDecl.funcBody) {
                SetFunctionBodyOwner(funcDecl, body)
                return SynthesizeFuncBody(ctx, body)
            }
        }
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(body) <- mainDecl.funcBody) {
                SetFunctionBodyOwner(mainDecl, body)
                let mainTy = SynthesizeFuncBody(ctx, body)
                mainDecl.SetTy(mainTy)
                return mainTy
            }
        }
        if (let Some(macroDecl) <- (decl as MacroDecl)) {
            if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
                return SynthesizeDecl(ctx, desugarDecl)
            }
            if (let Some(body) <- macroDecl.funcBody) {
                SetFunctionBodyOwner(macroDecl, body)
                let macroTy = SynthesizeFuncBody(ctx, body)
                macroDecl.SetTy(macroTy)
                return macroTy
            }
        }
        if (let Some(primaryCtor) <- (decl as PrimaryCtorDecl)) {
            if (let Some(body) <- primaryCtor.funcBody) {
                SetFunctionBodyOwner(primaryCtor, body)
                let primaryTy = SynthesizeFuncBody(ctx, body)
                primaryCtor.SetTy(primaryTy)
                return primaryTy
            }
        }
        if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            return TypeCheckDeclSetEnumElementTy(impl.typeManager, decl)
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                SynthesizeDeclList(ctx, body.decls)
            }
            return tyOrInvalid(classDecl)
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            if (let Some(body2) <- structDecl.body) {
                SynthesizeDeclList(ctx, body2.decls)
            }
            return tyOrInvalid(structDecl)
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            if (let Some(body3) <- interfaceDecl.body) {
                SynthesizeDeclList(ctx, body3.decls)
            }
            return tyOrInvalid(interfaceDecl)
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            SynthesizeDeclList(ctx, enumDecl.constructors)
            SynthesizeDeclList(ctx, enumDecl.members)
            return tyOrInvalid(enumDecl)
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            SynthesizeTypeNode(ctx, extendDecl.extendedType)
            for (inheritedType in extendDecl.inheritedTypes) {
                impl.SetTypeTy(ctx, inheritedType)
            }
            SynthesizeDeclList(ctx, extendDecl.members)
            return tyOrInvalid(extendDecl)
        }
        if (let Some(typeAlias) <- (decl as TypeAliasDecl)) {
            SynthesizeTypeNode(ctx, typeAlias.typeNode)
            return tyOrInvalid(typeAlias)
        }
        return tyOrInvalid(decl)
    }

    private func SynthesizeFuncBody(ctx: ASTContext, fb: FuncBody): Ty {
        let retType = EnsureRetType(ctx, fb)
        SynthesizeFuncParams(ctx, fb)
        let paramTys = GetFuncBodyParamTys(fb)
        var retTy = SignatureReturnTy(fb, retType)
        if (let Some(body) <- fb.body) {
            let previousFuncBody = currentFuncBody
            currentFuncBody = Some(fb)
            if (retTy.IsQuest()) {
                let bodyTy = SynthesizeBlock(ctx, body)
                retType.SetTy(bodyTy)
                retTy = bodyTy
            } else if (retTy.IsUnit()) {
                let _ = SynthesizeBlock(ctx, body)
            } else if (IsConstructorBody(fb)) {
                let _ = SynthesizeBlock(ctx, body)
            } else if (NeedCheckBodyReturn(fb)) {
                let _ = CheckBlock(ctx, retTy, body)
            } else {
                let _ = SynthesizeBlock(ctx, body)
            }
            currentFuncBody = previousFuncBody
        }
        let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retTy)
        fb.SetTy(funcTy)
        if (let Some(funcDecl) <- fb.funcDecl) {
            funcDecl.SetTy(funcTy)
        }
        return funcTy
    }

    private func SynthesizeFuncParams(ctx: ASTContext, fb: FuncBody): Unit {
        for (paramList in fb.paramLists) {
            for (param in paramList.params) {
                let _ = SynthesizeDecl(ctx, param)
            }
        }
    }

    private func BindLocalDeclIfNeeded(ctx: ASTContext, decl: Decl): Unit {
        if (decl.astKind == ASTKind.FUNC_PARAM || decl.scopeLevel != 0u32 || (let Some(_) <- currentFuncBody)) {
            BindLocalDecl(ctx, decl)
        }
    }

    private func BindLocalDecl(ctx: ASTContext, decl: Decl): Unit {
        let name = decl.identifier.Val()
        if (name.isEmpty() || name == INVALID_IDENTIFIER) {
            return
        }
        ctx.AddDeclName(Names(name, scopeNameOf(decl)), decl)
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

    private func SynthesizeBlock(ctx: ASTContext, block: Block): Ty {
        for (item in block.body) {
            let _ = SynthesizeNode(ctx, item)
        }
        return SynBlock(impl.typeManager, block)
    }

    private func CheckBlock(ctx: ASTContext, target: Ty, block: Block): Bool {
        if (block.body.isEmpty()) {
            return ChkBlock(impl.typeManager, target, block)
        }
        if (block.body.size > 1) {
            for (idx in 0..block.body.size - 1) {
                let _ = SynthesizeNode(ctx, block.body[idx])
            }
        }
        if (let Some(lastNode) <- block.GetLastExprOrDecl()) {
            if (let Some(lastExpr) <- (lastNode as Expr)) {
                let _ = Check(ctx, target, lastExpr)
            } else {
                let _ = SynthesizeNode(ctx, lastNode)
            }
        }
        return ChkBlock(impl.typeManager, target, block)
    }

    private func SynthesizeCallChildren(ctx: ASTContext, callExpr: CallExpr): Unit {
        if (let Some(baseFunc) <- callExpr.baseFunc) {
            SetIsNotAlone(baseFunc)
            SetCallOrPattern(baseFunc, callExpr)
            let _ = Synthesize(ctx, baseFunc)
        }
        for (arg in callExpr.args) {
            let _ = SynthesizeFuncArg(ctx, arg)
        }
    }

    private func SynthesizeIfChildren(ctx: ASTContext, ifExpr: IfExpr): Unit {
        if (let Some(condExpr) <- ifExpr.condExpr) {
            let _ = Synthesize(ctx, condExpr)
        }
        if (let Some(thenBody) <- ifExpr.thenBody) {
            let _ = SynthesizeBlock(ctx, thenBody)
        }
        if (let Some(elseBody) <- ifExpr.elseBody) {
            let _ = Synthesize(ctx, elseBody)
        }
    }

    private func SynthesizeMatchChildren(ctx: ASTContext, matchExpr: MatchExpr): Unit {
        if (let Some(selector) <- matchExpr.selector) {
            let _ = Synthesize(ctx, selector)
        }
        for (matchCase in matchExpr.matchCases) {
            if (let Some(patternGuard) <- matchCase.patternGuard) {
                let _ = Synthesize(ctx, patternGuard)
            }
            if (let Some(action) <- matchCase.exprOrDecls) {
                let _ = SynthesizeBlock(ctx, action)
            }
        }
        for (matchCaseOther in matchExpr.matchCaseOthers) {
            if (let Some(matchCaseExpr) <- matchCaseOther.matchExpr) {
                let _ = Synthesize(ctx, matchCaseExpr)
            }
            if (let Some(otherAction) <- matchCaseOther.exprOrDecls) {
                let _ = SynthesizeBlock(ctx, otherAction)
            }
        }
    }

    private func SynthesizeLoopChildren(ctx: ASTContext, loopExpr: Expr): Unit {
        if (let Some(forInExpr) <- (loopExpr as ForInExpr)) {
            if (let Some(inExpression) <- forInExpr.inExpression) {
                let _ = Synthesize(ctx, inExpression)
            }
            if (let Some(patternGuard) <- forInExpr.patternGuard) {
                let _ = Synthesize(ctx, patternGuard)
            }
            if (let Some(body) <- forInExpr.body) {
                let _ = SynthesizeBlock(ctx, body)
            }
            return
        }
        if (let Some(whileExpr) <- (loopExpr as WhileExpr)) {
            if (let Some(condExpr) <- whileExpr.condExpr) {
                let _ = Synthesize(ctx, condExpr)
            }
            if (let Some(body2) <- whileExpr.body) {
                let _ = SynthesizeBlock(ctx, body2)
            }
            return
        }
        if (let Some(doWhileExpr) <- (loopExpr as DoWhileExpr)) {
            if (let Some(body3) <- doWhileExpr.body) {
                let _ = SynthesizeBlock(ctx, body3)
            }
            if (let Some(condExpr2) <- doWhileExpr.condExpr) {
                let _ = Synthesize(ctx, condExpr2)
            }
        }
    }

    private func SynthesizeNameReference(ctx: ASTContext, nameRef: NameReferenceExpr): Ty {
        for (typeArg in nameRef.GetTypeArgs()) {
            impl.SetTypeTy(ctx, typeArg)
        }
        if (let Some(memberAccess) <- (nameRef as MemberAccess)) {
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                SetIsNotAlone(baseExpr)
                let _ = Synthesize(ctx, baseExpr)
            }
        } else if (let Some(refExpr) <- (nameRef as RefExpr)) {
            ResolveRefExpr(ctx, refExpr)
        }
        let ty = SynNameReferenceExpr(impl.typeManager, nameRef)
        if (let Some(target) <- nameRef.GetTarget()) {
            addImportedDeclAndDependencies(ctx, target)
        }
        for (target2 in nameRef.GetTargets()) {
            addImportedDeclAndDependencies(ctx, target2)
        }
        return ty
    }

    private func SynthesizeDesugarIfNeeded(ctx: ASTContext, expr: Expr): Unit {
        if (let Some(desugar) <- expr.desugarExpr) {
            let _ = Synthesize(ctx, desugar)
        }
    }

    private func SynthesizeDesugarsInTree(ctx: ASTContext, expr: Expr): Unit {
        let walker = Walker(expr, visitPre: { node: Node =>
            if (let Some(innerExpr) <- (node as Expr)) {
                SynthesizeDesugarIfNeeded(ctx, innerExpr)
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func RefreshNameReferencesInTree(ctx: ASTContext, expr: Expr): Unit {
        let walker = Walker(expr, visitPost: { node: Node =>
            if (let Some(nameRef) <- (node as NameReferenceExpr)) {
                let _ = SynthesizeNameReference(ctx, nameRef)
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func RefreshUnsetExprTypesInTree(expr: Expr): Unit {
        let walker = Walker(expr, visitPost: { node: Node =>
            if (let Some(innerExpr) <- (node as Expr)) {
                if (Ty.IsInitialTy(innerExpr.GetTy()) || !Ty.IsTyCorrect(innerExpr.GetTy())) {
                    let _ = SynExprShallow(impl.typeManager, innerExpr)
                }
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func FinishSynthesize(ctx: ASTContext, expr: Expr, ty: Ty): Ty {
        SynthesizeDesugarsInTree(ctx, expr)
        RefreshNameReferencesInTree(ctx, expr)
        RefreshUnsetExprTypesInTree(expr)
        RefreshNameReferencesInTree(ctx, expr)
        return ty
    }

    private func FinishCheck(ctx: ASTContext, expr: Expr, ok: Bool): Bool {
        SynthesizeDesugarsInTree(ctx, expr)
        RefreshNameReferencesInTree(ctx, expr)
        RefreshUnsetExprTypesInTree(expr)
        RefreshNameReferencesInTree(ctx, expr)
        return ok
    }

    private func Synthesize(ctx: ASTContext, expr: Expr): Ty {
        if (let Some(desugar) <- expr.desugarExpr) {
            let _ = Synthesize(ctx, desugar)
        }
        if (let Some(block) <- (expr as Block)) {
            return SynthesizeBlock(ctx, block)
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            SynthesizeCallChildren(ctx, callExpr)
            return FinishSynthesize(ctx, callExpr, SynExprShallow(impl.typeManager, callExpr))
        }
        if (let Some(ifExpr) <- (expr as IfExpr)) {
            SynthesizeIfChildren(ctx, ifExpr)
            return FinishSynthesize(ctx, ifExpr, SynExprShallow(impl.typeManager, ifExpr))
        }
        if (let Some(matchExpr) <- (expr as MatchExpr)) {
            SynthesizeMatchChildren(ctx, matchExpr)
            return FinishSynthesize(ctx, matchExpr, SynMatchExpr(impl.typeManager, ctx, matchExpr, diag: impl.diag))
        }
        if (expr.IsLoopExpr()) {
            SynthesizeLoopChildren(ctx, expr)
            return FinishSynthesize(ctx, expr, SynExprShallow(impl.typeManager, expr))
        }
        if (let Some(returnExpr) <- (expr as ReturnExpr)) {
            if (let Some(fb) <- currentFuncBody) {
                returnExpr.refFuncBody = Some(fb)
            }
            SynthesizeNodeChildren(ctx, returnExpr)
            return FinishSynthesize(ctx, returnExpr, SynExprShallow(impl.typeManager, returnExpr))
        }
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            return FinishSynthesize(ctx, nameRef, SynthesizeNameReference(ctx, nameRef))
        }
        if (let Some(typeConv) <- (expr as TypeConvExpr)) {
            SynthesizeTypeNode(ctx, typeConv.typeNode)
            if (let Some(innerExpr) <- typeConv.expr) {
                let _ = Synthesize(ctx, innerExpr)
            }
            return FinishSynthesize(ctx, typeConv, SynExprShallow(impl.typeManager, typeConv))
        }
        if (let Some(isExpr) <- (expr as IsExpr)) {
            SynthesizeTypeNode(ctx, isExpr.isType)
            if (let Some(leftExpr) <- isExpr.leftExpr) {
                let _ = Synthesize(ctx, leftExpr)
            }
            return FinishSynthesize(ctx, isExpr, SynExprShallow(impl.typeManager, isExpr))
        }
        if (let Some(asExpr) <- (expr as AsExpr)) {
            SynthesizeTypeNode(ctx, asExpr.asType)
            if (let Some(leftExpr2) <- asExpr.leftExpr) {
                let _ = Synthesize(ctx, leftExpr2)
            }
            return FinishSynthesize(ctx, asExpr, SynExprShallow(impl.typeManager, asExpr))
        }
        if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
            SynthesizeTypeNode(ctx, arrayExpr.typeNode)
            for (arg in arrayExpr.args) {
                let _ = SynthesizeFuncArg(ctx, arg)
            }
            return FinishSynthesize(ctx, arrayExpr, SynArrayExpr(impl.typeManager, arrayExpr, diag: impl.diag))
        }
        if (let Some(pointerExpr) <- (expr as PointerExpr)) {
            SynthesizeTypeNode(ctx, pointerExpr.typeNode)
            if (let Some(arg2) <- pointerExpr.arg) {
                let _ = SynthesizeFuncArg(ctx, arg2)
            }
            return FinishSynthesize(ctx, pointerExpr, SynPointerExpr(impl.typeManager, pointerExpr, diag: impl.diag))
        }
        if (isStringLiteral(expr)) {
            if (let Some(lit) <- (expr as LitConstExpr)) {
                var stringTy: Option<Ty> = None
                if (let Some(stringDecl) <- lookupResolvedPackageDecl(ctx, "std.core", "String")) {
                    addImportedDeclAndDependencies(ctx, stringDecl)
                    stringTy = stringDecl.GetTy()
                }
                return FinishSynthesize(ctx, lit, SynLitConstExpr(lit, stringTy: stringTy))
            }
        }
        SynthesizeNodeChildren(ctx, expr)
        if (let Some(arrayLit) <- (expr as ArrayLit)) {
            return FinishSynthesize(ctx, arrayLit, SynArrayLit(impl.typeManager, arrayLit))
        }
        return FinishSynthesize(ctx, expr, SynExprShallow(impl.typeManager, expr))
    }

    private func Check(ctx: ASTContext, target: Ty, expr: Expr): Bool {
        if (let Some(block) <- (expr as Block)) {
            return CheckBlock(ctx, target, block)
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            SynthesizeCallChildren(ctx, callExpr)
            return FinishCheck(ctx, callExpr, ChkExprShallow(impl.typeManager, target, callExpr))
        }
        if (let Some(ifExpr) <- (expr as IfExpr)) {
            SynthesizeIfChildren(ctx, ifExpr)
            return FinishCheck(ctx, ifExpr, ChkExprShallow(impl.typeManager, target, ifExpr))
        }
        if (let Some(matchExpr) <- (expr as MatchExpr)) {
            SynthesizeMatchChildren(ctx, matchExpr)
            return FinishCheck(ctx, matchExpr, ChkMatchExpr(impl.typeManager, ctx, target, matchExpr, diag: impl.diag))
        }
        if (expr.IsLoopExpr()) {
            SynthesizeLoopChildren(ctx, expr)
            return FinishCheck(ctx, expr, ChkExprShallow(impl.typeManager, target, expr))
        }
        if (let Some(returnExpr) <- (expr as ReturnExpr)) {
            if (let Some(fb) <- currentFuncBody) {
                returnExpr.refFuncBody = Some(fb)
            }
            SynthesizeNodeChildren(ctx, returnExpr)
            return FinishCheck(ctx, returnExpr, ChkExprShallow(impl.typeManager, target, returnExpr))
        }
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            let _ = SynthesizeNameReference(ctx, nameRef)
            return FinishCheck(ctx, expr, ChkExprShallow(impl.typeManager, target, expr))
        }
        let _ = Synthesize(ctx, expr)
        return FinishCheck(ctx, expr, ChkExprShallow(impl.typeManager, target, expr))
    }

    private func ResolveRefExpr(ctx: ASTContext, refExpr: RefExpr): Unit {
        if ((let Some(_) <- refExpr.ref.target) || !refExpr.ref.targets.isEmpty()) {
            return
        }
        let targets = impl.Lookup(ctx, refExpr.ref.identifier.Val(), scopeNameOf(refExpr), refExpr)
        for (target in targets) {
            refExpr.ref.targets.add(target)
            addImportedDeclAndDependencies(ctx, target)
        }
        if (targets.size == 1) {
            ReplaceTarget(refExpr, Some(targets[0]), insertTarget: true)
        }
    }
}
