package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::option.IsUnsafeBackend as OptionIsUnsafeBackend
import cangjie_compiler::sema.*
import cangjie_compiler::sema.Desugar.*
import cangjie_compiler::sema.FFI.*
import cangjie_compiler::sema.InheritanceChecker.*
import cangjie_compiler::sema.LegalityOfUsage.*

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

private func typeCheckExprNodeHash(node: Node): Int64 {
    return node.begin.hashCode() ^ (node.end.hashCode() << 1) ^ ASTKindIndex(node.astKind)
}

private func typeCheckExprTargetTypeOf(ctx: ASTContext, node: Node): Option<Ty> {
    return ctx.targetTypeMap.get(typeCheckExprNodeHash(node))
}

private func typeCheckExprPutTargetType(ctx: ASTContext, node: Node, ty: Ty): Unit {
    ctx.targetTypeMap[typeCheckExprNodeHash(node)] = ty
}

private func typeCheckExprClearTargetType(ctx: ASTContext, node: Node): Unit {
    ctx.targetTypeMap.remove(typeCheckExprNodeHash(node))
}

private func typeCheckExprAllMacroFuncDecls(targets: ArrayList<Decl>): Bool {
    for (target in targets) {
        if (!target.TestAttr(Attribute.MACRO_FUNC)) {
            return false
        }
    }
    return true
}

private func typeCheckExprGetCurInheritableDecl(ctx: ASTContext, scopeName: String,
    currentFuncBody: Option<FuncBody>): Option<InheritableDecl> {
    var scopeGateName = GetScopeGateName(scopeName)
    while (!scopeGateName.isEmpty()) {
        if (let Some(symbol) <- GetScopeGate(ctx, scopeGateName)) {
            if (let Some(node) <- symbol.node) {
                if (let Some(decl) <- (node as InheritableDecl)) {
                    return Some(decl)
                }
            }
        }
        scopeGateName = GetScopeGateName(scopeGateName)
    }
    if (let Some(funcBody) <- currentFuncBody) {
        if (let Some(funcDecl) <- funcBody.funcDecl) {
            if (let Some(outer) <- funcDecl.outerDecl) {
                if (let Some(inheritable) <- (outer as InheritableDecl)) {
                    return Some(inheritable)
                }
            }
        }
        if (let Some(classLike) <- funcBody.parentClassLike) {
            return Some(classLike)
        }
        if (let Some(structDecl) <- funcBody.parentStruct) {
            return Some(structDecl)
        }
        if (let Some(enumDecl) <- funcBody.parentEnum) {
            return Some(enumDecl)
        }
    }
    return None
}

private func typeCheckExprReplaceWithGenericTyInInheritableDecl(typeManager: TypeManager, ty: Option<Ty>,
    outerDecl: InheritableDecl, targetDecl: InheritableDecl): Ty {
    let rawTy = ty ?? TypeManager.GetInvalidTy()
    if (!Ty.IsTyCorrect(rawTy) || !rawTy.HasGeneric()) {
        return rawTy
    }
    if (let Some(currentTy) <- outerDecl.GetTy()) {
        if (let Some(targetTy) <- targetDecl.GetTy()) {
            let mapping = Promotion(typeManager).GetPromoteTypeMapping(currentTy, targetTy)
            if (!mapping.entries.isEmpty()) {
                return typeManager.GetBestInstantiatedTy(rawTy, mapping)
            }
        }
    }
    return rawTy
}

private func typeCheckExprInferTypeOfThis(typeManager: TypeManager, re: RefExpr, outerDecl: InheritableDecl): Ty {
    var targetDecl = outerDecl
    if (let Some(extendDecl) <- (targetDecl as ExtendDecl)) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (let Some(extendedTy) <- extendedType.GetTy()) {
                if (extendedTy.IsBuiltin()) {
                    return extendedTy
                }
                if (let Some(realDecl) <- Ty.GetInheritableDeclPtrOfTy(Some(extendedTy))) {
                    targetDecl = realDecl
                } else {
                    return TypeManager.GetInvalidTy()
                }
            }
        }
    }
    ReplaceTarget(re, Some(targetDecl))
    let inferredTy = typeCheckExprReplaceWithGenericTyInInheritableDecl(typeManager, targetDecl.GetTy(),
        outerDecl, targetDecl)
    if (let Some(classTy) <- (inferredTy as ClassTy)) {
        if (let Some(classDecl) <- classTy.decl) {
            return typeManager.GetClassThisTy(classDecl, classTy.typeArgs.toArray())
        }
    }
    return inferredTy
}

private func typeCheckExprInferTypeOfSuper(typeManager: TypeManager, re: RefExpr, outerDecl: InheritableDecl): Ty {
    if (let None <- (outerDecl as ClassDecl)) {
        return TypeManager.GetInvalidTy()
    }
    let classDecl = (outerDecl as ClassDecl).getOrThrow()
    if (let Some(rawTy) <- classDecl.GetTy()) {
        if (let Some(classTy) <- (rawTy as ClassTy)) {
            if (let Some(superClassTy) <- classTy.GetSuperClassTy()) {
                if (let Some(superDecl) <- superClassTy.declPtr) {
                    ReplaceTarget(re, Some(superDecl))
                    return typeCheckExprReplaceWithGenericTyInInheritableDecl(typeManager, superDecl.GetTy(),
                        outerDecl, superDecl)
                }
            }
        }
    }
    return TypeManager.GetInvalidTy()
}

private func typeCheckExprCheckThisOrSuper(typeManager: TypeManager, ctx: ASTContext, re: RefExpr,
    currentFuncBody: Option<FuncBody>): Unit {
    if (!re.isThis && !re.isSuper) {
        return
    }
    if ((let Some(_) <- re.ref.target) || !re.ref.targets.isEmpty()) {
        return
    }
    re.SetTy(TypeManager.GetInvalidTy())
    if (let Some(outerDecl) <- typeCheckExprGetCurInheritableDecl(ctx, scopeNameOf(re), currentFuncBody)) {
        let inferredTy = if (re.isThis) {
            typeCheckExprInferTypeOfThis(typeManager, re, outerDecl)
        } else {
            typeCheckExprInferTypeOfSuper(typeManager, re, outerDecl)
        }
        re.SetTy(inferredTy)
    }
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

private func importedAwareDeclKey(decl: Decl): String {
    if (decl.TestAttr(Attribute.IMPORTED)) {
        if (!decl.rawMangleName.isEmpty()) {
            return "raw|" + decl.rawMangleName
        }
        if (!decl.mangledName.isEmpty()) {
            return "mangled|" + decl.mangledName
        }
    }
    return "decl|" + ASTKindName(decl.astKind) + "|" + decl.fullPackageName + "|" + decl.identifier.Val() + "|" +
        decl.begin.fileID.toString() + ":" + decl.begin.line.toString() + ":" + decl.begin.column.toString() + "|" +
        decl.end.fileID.toString() + ":" + decl.end.line.toString() + ":" + decl.end.column.toString()
}

private func ensureSrcImportedDeclKeys(pkg: Package): Unit {
    if (!pkg.srcImportedNonGenericDeclKeys.isEmpty() || pkg.srcImportedNonGenericDecls.isEmpty()) {
        return
    }
    for (decl in pkg.srcImportedNonGenericDecls) {
        pkg.srcImportedNonGenericDeclKeys.add(importedAwareDeclKey(decl))
    }
}

private func addImportedDeclToCurrentPackage(ctx: ASTContext, decl: Decl): Unit {
    if (!decl.TestAttr(Attribute.IMPORTED)) {
        return
    }
    if (let Some(pkg) <- ctx.curPackage) {
        ensureSrcImportedDeclKeys(pkg)
        let key = importedAwareDeclKey(decl)
        if (!pkg.srcImportedNonGenericDeclKeys.contains(key)) {
            pkg.srcImportedNonGenericDecls.add(decl)
            pkg.srcImportedNonGenericDeclKeys.add(key)
        }
    }
}

private func replaceTypeAliasInNode(typeManager: TypeManager, node: Node): Unit {
    let walker = Walker(node, visitPre: { current: Node =>
        if (current.astKind != ASTKind.TYPE_ALIAS_DECL && Ty.IsTyCorrect(current.GetTy())) {
            let ty = current.GetTy().getOrThrow()
            if (ty.HasAliasTy()) {
                current.SetTy(typeManager.SubstituteTypeAliasInTy(ty))
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func substituteImportedTypeAliasTy(typeManager: TypeManager, packageDecls: ArrayList<PackageDecl>): Unit {
    let seen = HashSet<String>()
    for (packageDecl in packageDecls) {
        let pkg = packageDecl.srcPackage
        if (seen.contains(pkg.fullPackageName)) {
            continue
        }
        seen.add(pkg.fullPackageName)
        for (file in pkg.files) {
            replaceTypeAliasInNode(typeManager, file)
        }
    }
}

private func findCoreImplicitDeclInMap(instance: CompilerInstance, name: String): Option<Decl> {
    if (let Some(packageMap) <- instance.resolvedPackageMemberDeclsMap.get("std.core")) {
        if (let Some(decls) <- packageMap.get(name)) {
            for (decl in decls) {
                if (decl.identifier.Val() == name) {
                    return Some(decl)
                }
            }
        }
    }
    return None
}

private func findCoreImplicitDeclInPackages(packageDecls: ArrayList<PackageDecl>, name: String): Option<Decl> {
    for (packageDecl in packageDecls) {
        let pkg = packageDecl.srcPackage
        if (pkg.fullPackageName != "std.core") {
            continue
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (decl.identifier.Val() == name) {
                    return Some(decl)
                }
            }
            for (decl in file.exportedInternalDecls) {
                if (decl.identifier.Val() == name) {
                    return Some(decl)
                }
            }
        }
    }
    return None
}

private func addImportedDeclAndDependencies(ctx: ASTContext, decl: Decl): Unit {
    addImportedDeclToCurrentPackage(ctx, decl)
    if (let Some(outer) <- decl.outerDecl) {
        addImportedDeclToCurrentPackage(ctx, outer)
    }
}

private func isStringLiteral(expr: Expr): Bool {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        return lit.kind == LitConstKind.STRING || lit.kind == LitConstKind.JSTRING
    }
    return false
}

private func typeCheckExprIsArithmeticOperator(op: TokenKind): Bool {
    return op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL ||
        op == TokenKind.DIV || op == TokenKind.EXP || op == TokenKind.MOD ||
        op == TokenKind.BITAND || op == TokenKind.BITOR || op == TokenKind.BITXOR
}

private func typeCheckExprAddConcreteIntegerKinds(kinds: ArrayList<TypeKind>): Unit {
    kinds.add(TypeKind.TYPE_INT8)
    kinds.add(TypeKind.TYPE_INT16)
    kinds.add(TypeKind.TYPE_INT32)
    kinds.add(TypeKind.TYPE_INT64)
    kinds.add(TypeKind.TYPE_INT_NATIVE)
    kinds.add(TypeKind.TYPE_UINT8)
    kinds.add(TypeKind.TYPE_UINT16)
    kinds.add(TypeKind.TYPE_UINT32)
    kinds.add(TypeKind.TYPE_UINT64)
    kinds.add(TypeKind.TYPE_UINT_NATIVE)
}

private func typeCheckExprConcreteBinaryCandidateKinds(op: TokenKind): ArrayList<TypeKind> {
    let kinds = ArrayList<TypeKind>()
    if (op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL || op == TokenKind.DIV) {
        typeCheckExprAddConcreteIntegerKinds(kinds)
        kinds.add(TypeKind.TYPE_FLOAT16)
        kinds.add(TypeKind.TYPE_FLOAT32)
        kinds.add(TypeKind.TYPE_FLOAT64)
    } else if (op == TokenKind.MOD || op == TokenKind.BITAND || op == TokenKind.BITOR ||
        op == TokenKind.BITXOR) {
        typeCheckExprAddConcreteIntegerKinds(kinds)
    } else if (op == TokenKind.EXP) {
        kinds.add(TypeKind.TYPE_INT64)
        kinds.add(TypeKind.TYPE_FLOAT64)
    }
    return kinds
}

private class TypeCheckerTargetSnapshot {
    let node: Node
    let target: Option<Decl>
    let targets: ArrayList<Decl> = ArrayList<Decl>()

    init(node: Node) {
        this.node = node
        this.target = node.GetTarget()
        for (value in node.GetTargets()) {
            targets.add(value)
        }
    }

    func Restore(): Unit {
        node.SetTarget(target)
        if (let Some(refExpr) <- (node as RefExpr)) {
            refExpr.ref.targets.clear()
            for (value in targets) {
                refExpr.ref.targets.add(value)
            }
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            memberAccess.targets.clear()
            for (value2 in targets) {
                memberAccess.targets.add(value2)
            }
        } else if (let Some(refType) <- (node as RefType)) {
            refType.ref.targets.clear()
            for (value3 in targets) {
                refType.ref.targets.add(value3)
            }
        }
    }
}

private func typeCheckExprCollectTargetSnapshots(node: Node): ArrayList<TypeCheckerTargetSnapshot> {
    let snapshots = ArrayList<TypeCheckerTargetSnapshot>()
    let walker = Walker(node, visitPre: { current: Node =>
        if ((let Some(_) <- current.GetTarget()) || !current.GetTargets().isEmpty()) {
            snapshots.add(TypeCheckerTargetSnapshot(current))
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return snapshots
}

private func typeCheckExprClearKeepTargets(expr: Expr): Unit {
    let snapshots = typeCheckExprCollectTargetSnapshots(expr)
    expr.Clear()
    for (snapshot in snapshots) {
        snapshot.Restore()
    }
}

public class TypeChecker {
    private var ci: Option<CompilerInstance> = None
    private var impl: TypeCheckerImpl = TypeCheckerImpl()
    private let contexts: ArrayList<ASTContext> = ArrayList<ASTContext>()
    private var currentFuncBody: Option<FuncBody> = None
    private let activeEnumConstructorRegistrations: ArrayList<EnumDecl> = ArrayList<EnumDecl>()

    public init(ci: Option<CompilerInstance>) {
        this.ci = ci
        let tm = if (let Some(instance) <- ci) { instance.typeManager } else { TypeManager() }
        impl = if (let Some(instance) <- ci) {
            TypeCheckerImpl(typeManager: tm, diag: instance.diag)
        } else {
            TypeCheckerImpl(typeManager: tm)
        }
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
        for (ctx in contexts) {
            SeedImportedExtendMaps(ctx)
        }
        for (ctx in contexts) {
            BuildCurrentPackageExtendMap(ctx)
        }
        return contexts
    }

    private func PrepareTypeCheck(ctx: ASTContext, pkg: Package): Unit {
        ctx.Reset()
        ctx.curPackage = pkg
        ctx.fullPackageName = pkg.fullPackageName
        SeedImportedPackageDecls(ctx)
        AddCurFile(pkg)
        AddDefaultFunction(pkg)
        AddDefaultParamFunctions(pkg)
        Collector().BuildSymbolTable(ctx, pkg, buildTrie: false)
        impl.WarmupCache(ctx)
    }

    private func AddDefaultFunction(pkg: Package): Unit {
        if (pkg.TestAttr(Attribute.TOOL_ADD)) {
            return
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                AddDefaultFunctionForDecl(decl)
            }
        }
    }

    private func AddDefaultFunctionForDecl(decl: Decl): Unit {
        if (let Some(structDecl) <- (decl as StructDecl)) {
            AddDefaultCtorIfNeeded(structDecl)
            if (let Some(body) <- structDecl.body) {
                for (member in body.decls) {
                    AddDefaultFunctionForDecl(member)
                }
            }
            return
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            AddDefaultCtorIfNeeded(classDecl)
            if (let Some(body) <- classDecl.body) {
                for (member in body.decls) {
                    AddDefaultFunctionForDecl(member)
                }
            }
            return
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            if (let Some(body) <- interfaceDecl.body) {
                for (member in body.decls) {
                    AddDefaultFunctionForDecl(member)
                }
            }
            return
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            for (member in enumDecl.members) {
                AddDefaultFunctionForDecl(member)
            }
            return
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            for (member in extendDecl.members) {
                AddDefaultFunctionForDecl(member)
            }
        }
    }

    private func AddDefaultParamFunctions(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                let walker = Walker(decl, visitPre: { node: Node =>
                    if (let Some(funcDecl) <- (node as FuncDecl)) {
                        GetSingleParamFunc(funcDecl)
                        if (funcDecl.IsFinalizer()) {
                            AddUnitType(funcDecl)
                        }
                        return VisitAction.WALK_CHILDREN
                    }
                    if (let Some(propDecl) <- (node as PropDecl)) {
                        AddReturnTypeForPropMemDecl(propDecl)
                        return VisitAction.WALK_CHILDREN
                    }
                    if (node.astKind == ASTKind.FUNC_PARAM) {
                        return VisitAction.SKIP_CHILDREN
                    }
                    VisitAction.WALK_CHILDREN
                })
                let _ = walker.Walk()
            }
        }
    }

    private func AddUnitType(fd: FuncDecl): Unit {
        let body = if (let Some(value) <- fd.funcBody) { value } else { return }
        if (let Some(_) <- body.retType) {
            return
        }
        let typeNode = PrimitiveType()
        typeNode.str = "Unit"
        typeNode.kind = TypeKind.TYPE_UNIT
        if (!body.paramLists.isEmpty()) {
            typeNode.begin = body.paramLists[0].end
            typeNode.end = body.paramLists[0].end
        }
        typeNode.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        typeNode.EnableAttr(Attribute.COMPILER_ADD)
        body.retType = Some(typeNode)
    }

    private func AddReturnTypeForPropMemDecl(pd: PropDecl): Unit {
        for (getter in pd.getters) {
            let body = if (let Some(value) <- getter.funcBody) { value } else { continue }
            if (pd.typeNode.isSome() && body.retType.isNone()) {
                body.retType = ASTCloner.Clone(pd.typeNode.getOrThrow()) as Type
            }
        }
        for (setter in pd.setters) {
            let typeNode = if (let Some(value) <- pd.typeNode) { value } else { continue }
            let body = if (let Some(value) <- setter.funcBody) { value } else { continue }
            if (body.paramLists.isEmpty() || body.paramLists[0].params.isEmpty()) {
                return
            }
            let firstParam = body.paramLists[0].params[0]
            if (firstParam.typeNode.isNone()) {
                firstParam.typeNode = ASTCloner.Clone(typeNode) as Type
            }
            AddUnitType(setter)
        }
    }

    private func MakeDefaultParamFunction(fp: FuncParam, funcDecl: FuncDecl,
        funcParams: ArrayList<FuncParam>): FuncDecl {
        fp.EnableAttr(Attribute.HAS_INITIAL)
        let ret = FuncDecl()
        if (let Some(assignment) <- fp.assignment) {
            CopyBasicInfo(assignment, ret)
        } else {
            CopyNodeScopeInfo(ret, funcDecl)
        }
        ret.isFrozen = funcDecl.isFrozen
        CopyNodeScopeInfo(ret, funcDecl)
        ret.identifier = SrcIdentifier(fp.identifier.Val() + "." + "${funcParams.size}")

        let funcBody = FuncBody()
        CopyNodeScopeInfo(funcBody, ret)
        let block = Block()
        CopyNodeScopeInfo(block, ret)
        let paramList = FuncParamList()
        CopyNodeScopeInfo(paramList, ret)
        for (param in funcParams) {
            paramList.params.add(CreateFuncParamForOptional(param))
        }
        funcBody.paramLists.add(paramList)
        funcBody.body = block
        funcBody.retType = if (let Some(typeNode) <- fp.typeNode) { ASTCloner.Clone(typeNode) as Type } else { None }

        if (let Some(assignment) <- fp.assignment) {
            if (let Some(returnExprValue) <- (ASTCloner.Clone(assignment) as Expr)) {
                let returnExpr = CreateReturnExpr(returnExprValue, Some(funcBody))
                returnExpr.begin = assignment.begin
                returnExpr.end = assignment.end
                block.body.add(returnExpr)
            }
            assignment.EnableAttr(Attribute.UNREACHABLE)
        }

        ret.funcBody = funcBody
        funcBody.funcDecl = ret
        ret.EnableAttr(Attribute.HAS_INITIAL)
        ret.EnableAttr(Attribute.IMPLICIT_ADD)
        ret.EnableAttr(Attribute.NO_REFLECT_INFO)
        ret.toBeCompiled = funcDecl.toBeCompiled
        ret.ownerFunc = Some(funcDecl)
        ret.fullPackageName = funcDecl.fullPackageName
        ret.outerDecl = funcDecl.outerDecl
        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            ret.EnableAttr(Attribute.STATIC)
        }
        if (funcDecl.TestAttr(Attribute.MUT)) {
            ret.EnableAttr(Attribute.MUT)
        }
        if (funcDecl.TestAttr(Attribute.GLOBAL)) {
            ret.EnableAttr(Attribute.GLOBAL)
        }
        AddCurFile(ret, file: funcDecl.curFile)
        return ret
    }

    private func GetSingleParamFunc(funcDecl: FuncDecl): Unit {
        if (let None <- funcDecl.funcBody) {
            return
        }
        let funcBody = funcDecl.funcBody.getOrThrow()
        if (funcBody.paramLists.isEmpty()) {
            return
        }
        let funcParams = ArrayList<FuncParam>()
        for (fp in funcBody.paramLists[0].params) {
            if (fp.assignment.isSome() && !fp.TestAttr(Attribute.HAS_INITIAL)) {
                fp.desugarDecl = Some(MakeDefaultParamFunction(fp, funcDecl, funcParams))
                if (let Some(assignment) <- fp.assignment) {
                    MarkParamWithInitialValue(assignment)
                }
            }
            funcParams.add(fp)
        }
    }

    private func HasCtorForTypeDecl(decl: InheritableDecl): Bool {
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.TestAttr(Attribute.CONSTRUCTOR) && !member.TestAttr(Attribute.STATIC)) {
                return true
            }
        }
        return false
    }

    private func AddDefaultCtorIfNeeded(decl: InheritableDecl): Unit {
        if (HasCtorForTypeDecl(decl)) {
            return
        }
        AddDefaultCtor(decl)
    }

    private func AddDefaultCtor(decl: InheritableDecl): Unit {
        if (decl.astKind != ASTKind.STRUCT_DECL && decl.astKind != ASTKind.CLASS_DECL) {
            return
        }
        if (decl.TestAnyAttr(Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SYNTHETIC_WRAPPER)) {
            return
        }
        if (decl.astKind == ASTKind.STRUCT_DECL && decl.TestAttr(Attribute.COMMON)) {
            return
        }
        if (decl.astKind == ASTKind.CLASS_DECL &&
            decl.TestAnyAttr(Attribute.COMMON, Attribute.JAVA_MIRROR)) {
            return
        }
        let ctor = CreateDefaultCtor(decl, isStatic: false)
        if (let Some(structDecl) <- (decl as StructDecl)) {
            if (let Some(body) <- structDecl.body) {
                body.decls.add(ctor)
            }
        } else if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                body.decls.add(ctor)
            }
        }
    }

    private func CreateDefaultCtor(decl: InheritableDecl, isStatic!: Bool = false): FuncDecl {
        let funcBody = FuncBody()
        CopyFileID(funcBody, decl)
        let block = Block()
        CopyFileID(block, decl)
        funcBody.body = block
        let paramList = FuncParamList()
        CopyFileID(paramList, decl)
        funcBody.paramLists.add(paramList)

        let initFunc = FuncDecl()
        CopyFileID(initFunc, decl)
        initFunc.funcBody = funcBody
        funcBody.funcDecl = initFunc
        initFunc.identifier = SrcIdentifier("init")
        initFunc.identifier.SetFileID(decl.begin.fileID)
        initFunc.begin = decl.identifier.Begin()
        initFunc.end = initFunc.begin + decl.identifier.Length()
        initFunc.funcBody.getOrThrow().begin = initFunc.begin
        initFunc.funcBody.getOrThrow().end = initFunc.end
        initFunc.outerDecl = decl
        initFunc.EnableAttr(Attribute.IMPLICIT_ADD)
        initFunc.toBeCompiled = HasRecompilingMemberVar(decl, isStatic)
        if (isStatic) {
            initFunc.EnableAttr(Attribute.STATIC)
            initFunc.EnableAttr(Attribute.PRIVATE)
        } else {
            initFunc.EnableAttr(Attribute.PUBLIC)
        }
        SetCtorFuncPosition(decl, initFunc)
        initFunc.EnableAttr(Attribute.CONSTRUCTOR)
        initFunc.EnableAttr(Attribute.COMPILER_ADD)
        if (let Some(structDecl) <- (decl as StructDecl)) {
            funcBody.parentStruct = structDecl
        } else if (let Some(classDecl) <- (decl as ClassDecl)) {
            funcBody.parentClassLike = classDecl
        }
        AddCurFile(initFunc, file: decl.curFile)
        return initFunc
    }

    private func HasRecompilingMemberVar(decl: InheritableDecl, isStatic: Bool): Bool {
        var found = false
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.astKind == ASTKind.VAR_DECL && member.TestAttr(Attribute.STATIC) == isStatic) {
                found = true
                if (member.toBeCompiled) {
                    return true
                }
            }
        }
        return !found
    }

    private func SetCtorFuncPosition(decl: InheritableDecl, initFunc: FuncDecl): Unit {
        if (initFunc.TestAttr(Attribute.STATIC)) {
            return
        }
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(Attribute.STATIC)) {
                initFunc.begin = member.begin
            }
        }
        initFunc.begin.fileID = decl.begin.fileID
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

    private func SeedImportedExtendMaps(ctx: ASTContext): Unit {
        let extends = ArrayList<ExtendDecl>()
        for (packageDecl in ctx.packageDecls) {
            for (file in packageDecl.srcPackage.files) {
                for (decl in file.decls) {
                    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                        extends.add(extendDecl)
                    }
                }
                for (decl in file.exportedInternalDecls) {
                    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                        extends.add(extendDecl)
                    }
                }
            }
            for (decl in packageDecl.srcPackage.genericInstantiatedDecls) {
                if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                    extends.add(extendDecl)
                }
            }
        }
        TypeCheckExtendUpdateExtendMap(impl.typeManager, extends)
    }

    private func BuildCurrentPackageExtendMap(ctx: ASTContext): Unit {
        let extends = ArrayList<ExtendDecl>()
        for (sym in impl.GetSymsByASTKind(ctx, ASTKind.EXTEND_DECL)) {
            if (let Some(node) <- sym.node) {
                if (let Some(extendDecl) <- (node as ExtendDecl)) {
                    StampCurrentExtendPackage(ctx, extendDecl)
                    extends.add(extendDecl)
                }
            }
        }
        if (extends.isEmpty()) {
            return
        }
        if (let Some(diagValue) <- impl.diag) {
            TypeCheckExtendBuildMap(diagValue, impl.typeManager, ctx, extends)
            return
        }
        for (extendDecl in extends) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    extendDecl.SetTy(extendedTy)
                }
            }
        }
        TypeCheckExtendUpdateExtendMap(impl.typeManager, extends)
    }

    private func StampCurrentExtendPackage(ctx: ASTContext, extendDecl: ExtendDecl): Unit {
        if (extendDecl.fullPackageName.isEmpty()) {
            extendDecl.fullPackageName = ctx.fullPackageName
        }
        for (member in extendDecl.members) {
            if (member.fullPackageName.isEmpty()) {
                member.fullPackageName = extendDecl.fullPackageName
            }
        }
    }

    private func PreCheck(activeContexts: ArrayList<ASTContext>): Unit {
        let enableMacroInLSP = if (let Some(instance) <- ci) { instance.globalOptions.enableMacroInLSP } else { false }
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                if (let Some(diagValue) <- impl.diag) {
                    CheckRedefinition(ctx, pkg, diagValue, enableMacroInLSP: enableMacroInLSP)
                }
            }
        }
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                PreCheckAnnoForFFI(pkg)
                let _ = PreCheckPackage(ctx, pkg, typeManager: impl.typeManager)
                let _ = CheckDeclAttributesForPackage(pkg, opts: GlobalOptions())
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
        let importedDecls = ArrayList<Decl>()
        for (decl in pkg.srcImportedNonGenericDecls) {
            importedDecls.add(decl)
        }
        for (decl in importedDecls) {
            SynthesizeTree(ctx, decl)
        }
        if (pkg.TestAttr(Attribute.IMPORTED)) {
            TypeCheckImportedGenericMember(ctx)
        }
    }

    private func PostTypeCheck(activeContexts: ArrayList<ASTContext>): Unit {
        let recursivePkgs = BuildRecursiveEliminationPackages(activeContexts)
        PerformRecursiveTypesElimination(recursivePkgs, impl.typeManager)
        let implicitUsedDecls = GetImplicitUsedCoreDecls()
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                SetOverflowStrategyForPkg(pkg)
                let _ = CollectUnusedImports(pkg)
                let _ = CheckConstEvaluation(pkg)
                RunInheritanceCheck(pkg)
                // Check legality of usage after sema type completed.
                // Mirrors C++ TypeChecker.cpp:2053 (CheckLegalityOfUsage).
                RunLegalityOfUsageCheck(pkg)
                PerformDesugarAfterTypeCheck(impl.typeManager, pkg, context: Some(ctx), options: GlobalOptions(),
                    synthesizer: Some({ synCtx: ASTContext, pos: SynPos, node: Node =>
                        SynthesizeWithoutRecover(synCtx, pos, node)
                    }))
                DesugarAfterInstantiation(impl.typeManager, recursivePkgs, pkg,
                    implicitUsedDecls: Some(implicitUsedDecls))
            }
        }
        substituteImportedTypeAliasTy(impl.typeManager, recursivePkgs)
    }

    private func GetImplicitUsedCoreDecls(): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        if (let Some(instance) <- ci) {
            for (name in ["CJ_CORE_ExecAtexitCallbacks", "getCommandLineArgs", "eprintln", "handleException",
                "NegativeArraySizeException", "createOverflowExceptionMsg", "createArithmeticExceptionMsg",
                "SpawnException"]) {
                let decl = match (findCoreImplicitDeclInMap(instance, name)) {
                    case Some(value) => Some(value)
                    case None => findCoreImplicitDeclInPackages(instance.packageDecls, name)
                }
                if (let Some(found) <- decl) {
                    out.add(found)
                }
            }
        }
        return out
    }

    private func RunInheritanceCheck(pkg: Package): Unit {
        if (let Some(diagValue) <- impl.diag) {
            StructInheritanceChecker(diagValue, impl.typeManager, pkg, opts: GlobalOptions()).Check()
        }
    }

    private func RunLegalityOfUsageCheck(pkg: Package): Unit {
        if (let Some(diagValue) <- impl.diag) {
            let result = CheckLegalityOfUsage(pkg)
            EmitLegalityOfUsage(diagValue, result)
        }
    }

    private func BuildRecursiveEliminationPackages(activeContexts: ArrayList<ASTContext>): ArrayList<PackageDecl> {
        let out = ArrayList<PackageDecl>()
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                AddRecursiveEliminationPackage(out, PackageDecl(pkg))
            }
            for (packageDecl in ctx.packageDecls) {
                AddRecursiveEliminationPackage(out, packageDecl)
            }
        }
        return out
    }

    private func AddRecursiveEliminationPackage(values: ArrayList<PackageDecl>, packageDecl: PackageDecl): Unit {
        for (value in values) {
            if (value.fullPackageName == packageDecl.fullPackageName) {
                return
            }
        }
        values.add(packageDecl)
    }

    private func GlobalOptions(): OptionGlobalOptions {
        if (let Some(instance) <- ci) {
            return instance.globalOptions
        }
        return OptionGlobalOptions()
    }

    private func TypeCheckTopLevelDecl(ctx: ASTContext, decl: Decl): Unit {
        let tyVarScope = BeginTyVarScope(impl.typeManager)
        SynthesizeTree(ctx, decl)
        EndTyVarScope(tyVarScope)
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

    private func SynthesizeWithoutRecover(ctx: ASTContext, pos: SynPos, node: Node): Ty {
        let _ = pos
        ctx.ClearTypeCheckCache(node)
        ctx.SkipSynForCorrectTyRec(node)
        return SynthesizeNode(ctx, node)
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
            if (!Ty.IsTyCorrect(value.GetTy())) {
                if (let Some(diagValue) <- impl.diag) {
                    let _ = DiagnoseInvalidTypeName(diagValue, value)
                }
            }
            if (let Some(target) <- value.GetTarget()) {
                addImportedDeclAndDependencies(ctx, target)
                if (let Some(enumDecl) <- (target as EnumDecl)) {
                    RegisterEnumConstructors(ctx, enumDecl)
                }
            }
        }
    }

    private func DiagnoseInvalidTypeName(diagValue: BasicDiagnosticEngine, typeNode: Type): Bool {
        if (typeNode.TestAttr(Attribute.IS_BROKEN) || Ty.IsTyCorrect(typeNode.GetTy())) {
            return false
        }
        if (let Some(refType) <- (typeNode as RefType)) {
            if ((let None <- refType.ref.target) && refType.ref.identifier.Val() != INVALID_IDENTIFIER) {
                let builder = diagValue.Diagnose(refType.begin, refType.end,
                    BasicDiagKind.sema_undeclared_type_name,
                    args: [BasicDiagArgument(refType.ref.identifier.Val())])
                builder.Emit()
                refType.EnableAttr(Attribute.IS_BROKEN)
                return true
            }
        }
        for (child in typeNode.Children()) {
            if (let Some(childType) <- (child as Type)) {
                if (DiagnoseInvalidTypeName(diagValue, childType)) {
                    return true
                }
            }
        }
        return false
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

    private func SynthesizeSubscriptChildren(ctx: ASTContext, subscript: SubscriptExpr): Unit {
        if (let Some(baseExpr) <- subscript.baseExpr) {
            SetIsNotAlone(baseExpr)
            let _ = Synthesize(ctx, baseExpr)
        }
        for (indexExpr in subscript.indexExprs) {
            let _ = Synthesize(ctx, indexExpr)
        }
    }

    private func SynthesizeAssignChildren(ctx: ASTContext, assign: AssignExpr): Unit {
        if (let Some(leftExpr) <- assign.leftValue) {
            if (let Some(subscript) <- (leftExpr as SubscriptExpr)) {
                SynthesizeSubscriptChildren(ctx, subscript)
                if (let Some(rightExpr) <- assign.rightExpr) {
                    let _ = Synthesize(ctx, rightExpr)
                }
                return
            }
        }
        SynthesizeNodeChildren(ctx, assign)
    }

    private func SynthesizeBinaryChildren(ctx: ASTContext, binaryExpr: BinaryExpr): Unit {
        if (let Some(leftExpr) <- binaryExpr.leftExpr) {
            let _ = Synthesize(ctx, leftExpr)
        }
        if (let Some(rightExpr) <- binaryExpr.rightExpr) {
            let _ = Synthesize(ctx, rightExpr)
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

    private func EnsureEnumDeclTy(enumDecl: EnumDecl): Ty {
        if (Ty.IsTyCorrect(enumDecl.GetTy())) {
            return enumDecl.GetTy().getOrThrow()
        }
        impl.SetDeclTy(enumDecl)
        return enumDecl.GetTy() ?? TypeManager.GetInvalidTy()
    }

    private func PrepareParamSignature(ctx: ASTContext, param: FuncParam): Unit {
        SynthesizeTypeNode(ctx, param.typeNode)
        if (let Some(typeNode) <- param.typeNode) {
            if (let Some(paramTy) <- typeNode.GetTy()) {
                param.SetTy(paramTy)
            }
        }
        if (let Some(desugarDecl) <- param.desugarDecl) {
            PrepareDeclSignature(ctx, desugarDecl)
            let _ = SynthesizeDecl(ctx, desugarDecl)
        }
    }

    private func PrepareEnumConstructorSignature(ctx: ASTContext, enumDecl: EnumDecl, constructor: Decl): Ty {
        let _ = EnsureEnumDeclTy(enumDecl)
        if (let Some(funcDecl) <- (constructor as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                SetFunctionBodyOwner(funcDecl, body)
                for (paramList in body.paramLists) {
                    for (param in paramList.params) {
                        PrepareParamSignature(ctx, param)
                    }
                }
            }
        }
        return TypeCheckDeclSetEnumElementTy(impl.typeManager, constructor, diag: impl.diag)
    }

    private func PrepareEnumDeclSignature(ctx: ASTContext, enumDecl: EnumDecl): Unit {
        let _ = EnsureEnumDeclTy(enumDecl)
        TypeCheckDeclInsertEnumConstructors(ctx, enumDecl)
        for (inheritedType in enumDecl.inheritedTypes) {
            impl.SetTypeTy(ctx, inheritedType)
        }
        for (constructor in enumDecl.constructors) {
            let _ = PrepareEnumConstructorSignature(ctx, enumDecl, constructor)
        }
        PrepareDeclListSignatures(ctx, enumDecl.members)
    }

    private func IsRegisteringEnumConstructors(enumDecl: EnumDecl): Bool {
        for (active in activeEnumConstructorRegistrations) {
            if (SameDecl(active, enumDecl)) {
                return true
            }
        }
        return false
    }

    private func FinishRegisteringEnumConstructors(enumDecl: EnumDecl): Unit {
        var idx: Int64 = activeEnumConstructorRegistrations.size - 1
        while (idx >= 0) {
            if (SameDecl(activeEnumConstructorRegistrations[idx], enumDecl)) {
                activeEnumConstructorRegistrations.remove(at: idx)
                return
            }
            idx--
        }
    }

    private func RegisterEnumConstructors(ctx: ASTContext, enumDecl: EnumDecl): Unit {
        TypeCheckDeclInsertEnumConstructors(ctx, enumDecl)
        if (IsRegisteringEnumConstructors(enumDecl)) {
            return
        }
        activeEnumConstructorRegistrations.add(enumDecl)
        for (constructor in enumDecl.constructors) {
            let _ = PrepareEnumConstructorSignature(ctx, enumDecl, constructor)
            addImportedDeclAndDependencies(ctx, constructor)
        }
        FinishRegisteringEnumConstructors(enumDecl)
    }

    private func SynthesizeInheritedTypes(ctx: ASTContext, decl: InheritableDecl): Unit {
        for (inheritedType in decl.inheritedTypes) {
            SynthesizeTypeNode(ctx, Some(inheritedType))
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
        let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: FunctionTyConfigForFuncBody(fb))
        fb.SetTy(funcTy)
        if (let Some(funcDecl) <- fb.funcDecl) {
            funcDecl.SetTy(funcTy)
        }
        return funcTy
    }

    private func PreparePropDeclSignature(ctx: ASTContext, pd: PropDecl): Ty {
        SynthesizeTypeNode(ctx, pd.typeNode)
        if (let Some(typeNode) <- pd.typeNode) {
            if (let Some(propTy) <- typeNode.GetTy()) {
                pd.SetTy(propTy)
            }
        }
        AddReturnTypeForPropMemDecl(pd)
        for (getter in pd.getters) {
            PrepareDeclSignature(ctx, getter)
        }
        for (setter in pd.setters) {
            PrepareDeclSignature(ctx, setter)
        }
        return pd.GetTy() ?? TypeManager.GetInvalidTy()
    }

    private func PrepareDeclSignature(ctx: ASTContext, decl: Decl): Unit {
        if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            if (let Some(outer) <- decl.outerDecl) {
                if (let Some(enumDecl) <- (outer as EnumDecl)) {
                    let _ = PrepareEnumConstructorSignature(ctx, enumDecl, decl)
                    return
                }
            }
        }
        if (let Some(propDecl) <- (decl as PropDecl)) {
            let _ = PreparePropDeclSignature(ctx, propDecl)
            return
        }
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
            if (let Some(desugarDecl) <- mainDecl.desugarDecl) {
                PrepareDeclSignature(ctx, desugarDecl)
                mainDecl.SetTy(desugarDecl.GetTy() ?? TypeManager.GetInvalidTy())
                return
            }
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
            SynthesizeInheritedTypes(ctx, classDecl)
            if (let Some(body5) <- classDecl.body) {
                PrepareDeclListSignatures(ctx, body5.decls)
            }
            return
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            SynthesizeInheritedTypes(ctx, structDecl)
            if (let Some(body6) <- structDecl.body) {
                PrepareDeclListSignatures(ctx, body6.decls)
            }
            return
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            SynthesizeInheritedTypes(ctx, interfaceDecl)
            if (let Some(body7) <- interfaceDecl.body) {
                PrepareDeclListSignatures(ctx, body7.decls)
            }
            return
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            PrepareEnumDeclSignature(ctx, enumDecl)
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

    private func SynthesizeFuncParam(ctx: ASTContext, fp: FuncParam): Ty {
        if (let Some(typeNode) <- fp.typeNode) {
            SynthesizeTypeNode(ctx, Some(typeNode))
            if (!Ty.IsTyCorrect(typeNode.GetTy())) {
                if (let Some(assignment) <- fp.assignment) {
                    let _ = Synthesize(ctx, assignment)
                }
                fp.SetTy(TypeManager.GetInvalidTy())
                return TypeManager.GetInvalidTy()
            }
            fp.SetTy(typeNode.GetTy() ?? TypeManager.GetInvalidTy())
        } else if (!Ty.IsTyCorrect(fp.GetTy())) {
            fp.SetTy(TypeManager.GetInvalidTy())
            return TypeManager.GetInvalidTy()
        }

        if (let Some(assignment) <- fp.assignment) {
            let targetTy = fp.GetTy() ?? TypeManager.GetInvalidTy()
            if (!Check(ctx, targetTy, assignment)) {
                fp.SetTy(TypeManager.GetInvalidTy())
                return TypeManager.GetInvalidTy()
            }
        }
        if (let Some(desugarDecl) <- fp.desugarDecl) {
            let _ = SynthesizeDecl(ctx, desugarDecl)
        }
        BindLocalDeclIfNeeded(ctx, fp)
        return fp.GetTy() ?? TypeManager.GetInvalidTy()
    }

    private func SynthesizePropDecl(ctx: ASTContext, pd: PropDecl): Ty {
        if (pd.TestAttr(Attribute.IS_CHECK_VISITED)) {
            if (Ty.IsInitialTy(pd.GetTy())) {
                pd.SetTy(TypeManager.GetInvalidTy())
            }
            return pd.GetTy() ?? TypeManager.GetInvalidTy()
        }
        pd.EnableAttr(Attribute.IS_CHECK_VISITED)
        let propTy = PreparePropDeclSignature(ctx, pd)
        for (getter in pd.getters) {
            let _ = SynthesizeDecl(ctx, getter)
        }
        for (setter in pd.setters) {
            let _ = SynthesizeDecl(ctx, setter)
        }
        BindLocalDeclIfNeeded(ctx, pd)
        return propTy
    }

    private func SynthesizeDecl(ctx: ASTContext, decl: Decl): Ty {
        if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            return TypeCheckDeclSetEnumElementTy(impl.typeManager, decl, diag: impl.diag)
        }
        if (let Some(funcParam) <- (decl as FuncParam)) {
            return SynthesizeFuncParam(ctx, funcParam)
        }
        if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
            return SynthesizeVarWithPatternDecl(ctx, vpd)
        }
        if (let Some(propDecl) <- (decl as PropDecl)) {
            return SynthesizePropDecl(ctx, propDecl)
        }
        if (let Some(vd) <- (decl as VarDeclAbstract)) {
            if (vd.TestAttr(Attribute.IS_CHECK_VISITED)) {
                if (IsGlobalOrMember(vd) && Ty.IsInitialTy(vd.GetTy())) {
                    vd.SetTy(TypeManager.GetInvalidTy())
                }
                return vd.GetTy() ?? TypeManager.GetInvalidTy()
            }
            vd.EnableAttr(Attribute.IS_CHECK_VISITED)
            SynthesizeTypeNode(ctx, vd.typeNode)
            if (let Some(initializer) <- vd.initializer) {
                if (let Some(typeNode) <- vd.typeNode) {
                    if (let Some(targetTy) <- typeNode.GetTy()) {
                        if (!Check(ctx, targetTy, initializer) && !IsGlobalOrMember(vd)) {
                            vd.DisableAttr(Attribute.IS_CHECK_VISITED)
                        }
                    } else {
                        let _ = Synthesize(ctx, initializer)
                    }
                } else {
                    let _ = Synthesize(ctx, initializer)
                    if (!Ty.IsTyCorrect(initializer.GetTy()) && !IsGlobalOrMember(vd)) {
                        vd.DisableAttr(Attribute.IS_CHECK_VISITED)
                    }
                }
            }
            let declTy = TypeCheckDeclSynchronizeTypeAndInitializer(impl.typeManager, vd)
            BindLocalDeclIfNeeded(ctx, decl)
            return declTy
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                SetFunctionBodyOwner(funcDecl, body)
                if (!Ty.IsTyCorrect(funcDecl.GetTy())) {
                    let _ = PrepareFuncBodySignature(ctx, body)
                }
                BindLocalDeclIfNeeded(ctx, funcDecl)
                return SynthesizeFuncBody(ctx, body)
            }
        }
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(desugarDecl) <- mainDecl.desugarDecl) {
                let mainTy = SynthesizeDecl(ctx, desugarDecl)
                mainDecl.SetTy(mainTy)
                return mainTy
            }
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
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            SynthesizeInheritedTypes(ctx, classDecl)
            if (let Some(body) <- classDecl.body) {
                SynthesizeDeclList(ctx, body.decls)
            }
            return tyOrInvalid(classDecl)
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            SynthesizeInheritedTypes(ctx, structDecl)
            if (let Some(body2) <- structDecl.body) {
                SynthesizeDeclList(ctx, body2.decls)
            }
            return tyOrInvalid(structDecl)
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            SynthesizeInheritedTypes(ctx, interfaceDecl)
            if (let Some(body3) <- interfaceDecl.body) {
                SynthesizeDeclList(ctx, body3.decls)
            }
            return tyOrInvalid(interfaceDecl)
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            let _ = EnsureEnumDeclTy(enumDecl)
            TypeCheckDeclInsertEnumConstructors(ctx, enumDecl)
            for (inheritedType in enumDecl.inheritedTypes) {
                impl.SetTypeTy(ctx, inheritedType)
            }
            for (constructor in enumDecl.constructors) {
                let _ = PrepareEnumConstructorSignature(ctx, enumDecl, constructor)
            }
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

    private func SynthesizeVarWithPatternDecl(ctx: ASTContext, vpd: VarWithPatternDecl): Ty {
        SynthesizeTypeNode(ctx, vpd.typeNode)
        if (let Some(initializer) <- vpd.initializer) {
            if (let Some(typeNode) <- vpd.typeNode) {
                if (let Some(targetTy) <- typeNode.GetTy()) {
                    let _ = Check(ctx, targetTy, initializer)
                } else {
                    let _ = Synthesize(ctx, initializer)
                }
            } else {
                let _ = Synthesize(ctx, initializer)
            }
        }
        let declTy = TypeCheckDeclSynchronizeTypeAndInitializer(impl.typeManager, vpd)
        BindLocalDeclIfNeeded(ctx, vpd)
        if (let Some(initializer2) <- vpd.initializer) {
            if (!Ty.IsTyCorrect(initializer2.GetTy())) {
                return declTy
            }
        }
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            if (Ty.IsTyCorrect(declTy)) {
                let ok = ChkPattern(impl.typeManager, ctx, declTy, pattern, isPatternInMatch: false)
                if (ok && IsIrrefutablePattern(pattern)) {
                    BindPatternBindings(ctx, pattern)
                }
            }
        }
        return declTy
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
                if ((let None <- fb.funcDecl) && !Ty.IsTyCorrect(bodyTy)) {
                    retType.SetTy(TypeManager.GetInvalidTy())
                    retTy = TypeManager.GetInvalidTy()
                } else {
                    let inferredRetTy = CalcFuncRetTyFromBody(fb)
                    retType.SetTy(inferredRetTy)
                    retTy = inferredRetTy
                }
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
        let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retTy, cfg: FunctionTyConfigForFuncBody(fb))
        fb.SetTy(funcTy)
        if (let Some(funcDecl) <- fb.funcDecl) {
            funcDecl.SetTy(funcTy)
        }
        return funcTy
    }

    private func CalcFuncRetTyFromBody(fb: FuncBody): Ty {
        let body = fb.body ?? return TypeManager.GetInvalidTy()
        if (body.body.isEmpty()) {
            return TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        }

        let lastNode = body.body[body.body.size - 1]
        let bodyTy = if (lastNode.IsDecl()) {
            TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        } else {
            lastNode.GetTy() ?? TypeManager.GetInvalidTy()
        }
        var retTy = bodyTy
        let retTys = TySet()
        let walker = Walker(body, visitPre: { node: Node =>
            if (node.astKind == ASTKind.FUNC_DECL || node.astKind == ASTKind.LAMBDA_EXPR) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(returnExpr) <- (node as ReturnExpr)) {
                if (let Some(expr) <- returnExpr.expr) {
                    if (Ty.IsTyCorrect(expr.GetTy())) {
                        retTys.Add(expr.GetTy().getOrThrow())
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()

        let returnUnit = Ty.IsTyCorrect(fb.retType.getOrThrow().GetTy()) &&
            fb.retType.getOrThrow().GetTy().getOrThrow().IsUnit()
        if (returnUnit) {
            if (retTys.values.isEmpty()) {
                return fb.retType.getOrThrow().GetTy().getOrThrow()
            }
        } else {
            retTys.Add(bodyTy)
        }
        if (!Ty.IsTyCorrect(bodyTy)) {
            return TypeManager.GetInvalidTy()
        }
        retTy = JoinAsVisibleTy(impl.typeManager, retTys, curFile: fb.curFile)
        return retTy
    }

    private func FunctionTyConfigForFuncBody(fb: FuncBody): FuncTyConfig {
        let cfg = FuncTyConfig()
        let isCFFIBackend = OptionIsUnsafeBackend(GlobalOptions().backend)
        if (fb.TestAttr(Attribute.C)) {
            cfg.isC = true
        } else if (let Some(funcDecl) <- fb.funcDecl) {
            cfg.isC = funcDecl.TestAttr(Attribute.FOREIGN) && isCFFIBackend
        }
        if (let Some(funcDecl) <- fb.funcDecl) {
            cfg.hasVariableLenArg = funcDecl.hasVariableLenArg
        }
        if (!cfg.hasVariableLenArg && !fb.paramLists.isEmpty()) {
            cfg.hasVariableLenArg = fb.paramLists[0].hasVariableLenArg
        }
        return cfg
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
        ctx.AddDeclName(Names(name, GetScopeNameWithoutTail(scopeNameOf(decl))), decl)
    }

    private func BindLocalDeclIfAbsent(ctx: ASTContext, decl: Decl): Unit {
        let name = decl.identifier.Val()
        if (name.isEmpty() || name == INVALID_IDENTIFIER) {
            return
        }
        let names = Names(name, GetScopeNameWithoutTail(scopeNameOf(decl)))
        for (existing in ctx.GetDeclsByName(names)) {
            if (SameDecl(existing, decl)) {
                return
            }
        }
        ctx.AddDeclName(names, decl)
    }

    private func BindPatternBindings(ctx: ASTContext, pattern: Pattern): Unit {
        let boundDecls = ArrayList<Decl>()
        CollectPatternBinding(pattern, boundDecls)
        for (decl in boundDecls) {
            BindLocalDeclIfAbsent(ctx, decl)
        }
    }

    private func EnsureRetType(ctx: ASTContext, fb: FuncBody): Type {
        if (let Some(retType) <- fb.retType) {
            if (Ty.IsInitialTy(retType.GetTy())) {
                SynthesizeTypeNode(ctx, Some(retType))
            } else if (let Some(target) <- retType.GetTarget()) {
                addImportedDeclAndDependencies(ctx, target)
                if (let Some(enumDecl) <- (target as EnumDecl)) {
                    RegisterEnumConstructors(ctx, enumDecl)
                }
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
        if (block.body.isEmpty()) {
            let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            block.SetTy(unitTy)
            return unitTy
        }
        MarkUnsafeBlockChildren(block)
        var existInvalid = false
        for (item in block.body) {
            let itemTy = SynthesizeNode(ctx, item)
            if (!Ty.IsTyCorrect(itemTy) || !ReplaceIdealTy(impl.typeManager, item)) {
                existInvalid = true
            }
        }
        let lastNode = block.body[block.body.size - 1]
        if (existInvalid) {
            block.SetTy(TypeManager.GetInvalidTy())
        } else if (lastNode.IsDecl()) {
            block.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        } else {
            block.SetTy(lastNode.GetTy() ?? TypeManager.GetInvalidTy())
        }
        return block.GetTy() ?? TypeManager.GetInvalidTy()
    }

    private func MarkUnsafeBlockChildren(block: Block): Unit {
        if (!block.TestAttr(Attribute.UNSAFE) && block.unsafePos.IsZero()) {
            return
        }
        block.EnableAttr(Attribute.UNSAFE)
        let walker = Walker(block, visitPre: { node: Node =>
            if (let Some(_) <- (node as CallExpr)) {
                node.EnableAttr(Attribute.UNSAFE)
            }
            if (let Some(expr) <- (node as OverloadableExpr)) {
                expr.EnableAttr(Attribute.UNSAFE)
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func CheckBlock(ctx: ASTContext, target: Ty, block: Block): Bool {
        if (block.body.isEmpty()) {
            return ChkBlock(impl.typeManager, target, block)
        }
        MarkUnsafeBlockChildren(block)
        if (block.body.size > 1) {
            for (idx in 0..block.body.size - 1) {
                let _ = SynthesizeNode(ctx, block.body[idx])
            }
        }
        if (let Some(lastNode) <- block.GetLastExprOrDecl()) {
            var nodeForCheck = lastNode
            if (!block.TestAttr(Attribute.COMPILER_ADD) && lastNode.TestAttr(Attribute.COMPILER_ADD) &&
                lastNode.astKind == ASTKind.RETURN_EXPR) {
                if (let Some(returnExpr) <- (lastNode as ReturnExpr)) {
                    if (let Some(innerExpr) <- returnExpr.expr) {
                        nodeForCheck = innerExpr
                    }
                }
            }
            if (let Some(lastExpr) <- (nodeForCheck as Expr)) {
                let _ = Check(ctx, target, lastExpr)
            } else {
                let _ = SynthesizeNode(ctx, nodeForCheck)
            }
        }
        return ChkBlock(impl.typeManager, target, block)
    }

    private func SynthesizeCallChildren(ctx: ASTContext, callExpr: CallExpr): Unit {
        if (let Some(baseFunc) <- callExpr.baseFunc) {
            SetIsNotAlone(baseFunc)
            SetCallOrPattern(baseFunc, callExpr)
            var copiedTargetToBase = false
            if (let Some(baseRef) <- (baseFunc as RefExpr)) {
                if (let Some(targetTy) <- typeCheckExprTargetTypeOf(ctx, callExpr)) {
                    typeCheckExprPutTargetType(ctx, baseRef, targetTy)
                    copiedTargetToBase = true
                }
            }
            let _ = Synthesize(ctx, baseFunc)
            if (copiedTargetToBase) {
                typeCheckExprClearTargetType(ctx, baseFunc)
            }
        }
        for (arg in callExpr.args) {
            let _ = SynthesizeFuncArg(ctx, arg)
        }
    }

    private func ClearLambdaBodyForContextCheck(le: LambdaExpr): Unit {
        if (let Some(funcBody) <- le.funcBody) {
            if (let Some(body) <- funcBody.body) {
                let walker = Walker(body, visitPre: { node: Node =>
                    if ((let Some(_) <- (node as Type)) || (let Some(_) <- (node as Generic))) {
                        return VisitAction.SKIP_CHILDREN
                    }
                    if (let Some(funcParam) <- (node as FuncParam)) {
                        if (funcParam.TestAttr(Attribute.HAS_INITIAL)) {
                            return VisitAction.SKIP_CHILDREN
                        }
                    }
                    node.Clear()
                    VisitAction.WALK_CHILDREN
                })
                let _ = walker.Walk()
            }
        }
    }

    private func LambdaParamListForCheck(le: LambdaExpr): Option<FuncParamList> {
        if (let Some(funcBody) <- le.funcBody) {
            if (!funcBody.paramLists.isEmpty()) {
                return Some(funcBody.paramLists[0])
            }
        }
        return None
    }

    private func CloneLambdaTargetFuncCfg(funcTy: FuncTy): FuncTyConfig {
        let cfg = FuncTyConfig()
        cfg.isC = funcTy.isC
        cfg.isClosureTy = funcTy.isClosureTy
        cfg.hasVariableLenArg = funcTy.hasVariableLenArg
        cfg.noCast = funcTy.noCast
        return cfg
    }

    private func CheckLambdaParamsWithTarget(ctx: ASTContext, le: LambdaExpr, targetFuncTy: FuncTy,
        outParamTys: ArrayList<Ty>): Bool {
        let paramList = LambdaParamListForCheck(le) ?? return false
        if (paramList.params.size != targetFuncTy.paramTys.size) {
            return false
        }
        for (idx in 0..paramList.params.size) {
            let param = paramList.params[idx]
            let targetParamTy = targetFuncTy.paramTys[idx]
            var paramTy = targetParamTy
            if (let Some(typeNode) <- param.typeNode) {
                SynthesizeTypeNode(ctx, param.typeNode)
                if (let Some(typeTy) <- typeNode.GetTy()) {
                    paramTy = typeTy
                } else {
                    return false
                }
            }
            param.SetTy(paramTy)
            if (!impl.typeManager.IsSubtype(targetParamTy, paramTy, implicitBoxed: false, allowOptionBox: false)) {
                return false
            }
            BindLocalDeclIfNeeded(ctx, param)
            outParamTys.add(paramTy)
        }
        return true
    }

    private func SetLambdaTargetRetType(le: LambdaExpr, retTy: Ty): Bool {
        if (let Some(funcBody) <- le.funcBody) {
            let retType = RefType()
            retType.begin = le.begin
            retType.end = le.end
            retType.SetTy(retTy)
            retType.EnableAttr(Attribute.COMPILER_ADD)
            funcBody.retType = Some(retType)
            return true
        }
        return false
    }

    private func CheckLambdaExprWithTarget(ctx: ASTContext, target: Ty, le: LambdaExpr): Bool {
        if (let None <- le.funcBody) {
            let _ = TcInvalid(le)
            return false
        }
        let targetTy = UnboxOptionType(target)
        if (let Some(targetFuncTy) <- (targetTy as FuncTy)) {
            let paramTys = ArrayList<Ty>()
            if (!CheckLambdaParamsWithTarget(ctx, le, targetFuncTy, paramTys)) {
                let _ = TcInvalid(le)
                return false
            }
            if (!SetLambdaTargetRetType(le, targetFuncTy.retTy)) {
                let _ = TcInvalid(le)
                return false
            }
            ClearLambdaBodyForContextCheck(le)
            RefreshNameReferencesInTree(ctx, le)
            let funcBody = le.funcBody.getOrThrow()
            if (let Some(body) <- funcBody.body) {
                if (!CheckBlock(ctx, targetFuncTy.retTy, body)) {
                    funcBody.SetTy(TypeManager.GetInvalidTy())
                    let _ = TcInvalid(le)
                    return false
                }
            }
            let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), targetFuncTy.retTy,
                cfg: CloneLambdaTargetFuncCfg(targetFuncTy))
            funcBody.SetTy(funcTy)
            le.SetTy(funcTy)
            return true
        }
        let synTy = Synthesize(ctx, le)
        if (Ty.IsTyCorrect(synTy) && impl.typeManager.CheckTypeCompatibility(target, synTy) !=
            TypeCompatibility.INCOMPATIBLE) {
            return true
        }
        let _ = TcInvalid(le)
        return false
    }

    private func CheckCallArgFromContext(ctx: ASTContext, target: Ty, arg: FuncArg): Bool {
        if (let Some(expr) <- arg.expr) {
            typeCheckExprClearKeepTargets(expr)
            let ok = Check(ctx, target, expr)
            if (ok) {
                arg.SetTy(expr.GetTy() ?? target)
            }
            return ok
        }
        return false
    }

    private func LookupCoreDeclForSpawn(ctx: ASTContext, name: String): Option<Decl> {
        if (let Some(decl) <- lookupResolvedPackageDecl(ctx, "std.core", name)) {
            addImportedDeclAndDependencies(ctx, decl)
            return Some(decl)
        }
        return None
    }

    private func LookupCoreFutureForSpawn(ctx: ASTContext): Option<ClassDecl> {
        if (let Some(decl) <- LookupCoreDeclForSpawn(ctx, "Future")) {
            return decl as ClassDecl
        }
        return None
    }

    private func LookupCoreThreadContextTyForSpawn(ctx: ASTContext): Option<Ty> {
        if (let Some(decl) <- LookupCoreDeclForSpawn(ctx, "ThreadContext")) {
            return decl.GetTy()
        }
        return None
    }

    private func DiagnoseNoCoreObjectForSpawn(expr: SpawnExpr): Unit {
        if (let Some(diagValue) <- impl.diag) {
            let builder = diagValue.Diagnose(expr.begin, expr.end, BasicDiagKind.sema_no_core_object)
            builder.Emit()
        }
    }

    private func SynthesizeSpawnExpr(ctx: ASTContext, expr: SpawnExpr): Ty {
        if (let Some(arg) <- expr.arg) {
            let _ = Synthesize(ctx, arg)
        }
        if (let Some(task) <- expr.task) {
            let _ = Synthesize(ctx, task)
        }
        let futureClass = LookupCoreFutureForSpawn(ctx)
        if (let None <- futureClass) {
            DiagnoseNoCoreObjectForSpawn(expr)
            expr.SetTy(TypeManager.GetInvalidTy())
            return TypeManager.GetInvalidTy()
        }
        let spawnTy = SynSpawnExpr(impl.typeManager, expr, futureClass: futureClass,
            threadContextTy: LookupCoreThreadContextTyForSpawn(ctx))
        return FinishSynthesize(ctx, expr, spawnTy)
    }

    private func SelectSpawnFutureTy(ctx: ASTContext, target: Ty): Option<Ty> {
        if (TypeManager.IsCoreFutureType(target)) {
            return Some(target)
        }
        if (let Some(futureClass) <- LookupCoreFutureForSpawn(ctx)) {
            if (let Some(futureTy) <- futureClass.GetTy()) {
                let fuTys = Promotion(impl.typeManager).Downgrade(futureTy, target)
                if (!fuTys.values.isEmpty()) {
                    return Some(fuTys.values[0])
                }
            }
        }
        return None
    }

    private func CheckSpawnExprWithTarget(ctx: ASTContext, target: Ty, expr: SpawnExpr): Bool {
        if (let Some(fuTy) <- SelectSpawnFutureTy(ctx, target)) {
            if (fuTy.typeArgs.isEmpty()) {
                expr.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            var isWellTyped = true
            if (let Some(arg) <- expr.arg) {
                let _ = Synthesize(ctx, arg)
                isWellTyped = CheckSpawnArgValid(impl.typeManager, arg,
                    threadContextTy: LookupCoreThreadContextTyForSpawn(ctx)) && isWellTyped
            }
            if (let Some(task) <- expr.task) {
                let funcTy = impl.typeManager.GetFunctionTy(Array<Ty>(), fuTy.typeArgs[0])
                isWellTyped = Check(ctx, funcTy, task) && isWellTyped
            } else {
                isWellTyped = false
            }
            if (!isWellTyped) {
                expr.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            expr.SetTy(fuTy)
            return true
        }
        let synTy = SynthesizeSpawnExpr(ctx, expr)
        if (Ty.IsTyCorrect(synTy) &&
            impl.typeManager.CheckTypeCompatibility(target, synTy) != TypeCompatibility.INCOMPATIBLE) {
            return true
        }
        expr.SetTy(TypeManager.GetInvalidTy())
        return false
    }

    private func ReturnExprTargetTy(returnExpr: ReturnExpr): Option<Ty> {
        if (let None <- returnExpr.refFuncBody) {
            return None
        }
        let fb = returnExpr.refFuncBody.getOrThrow()
        if (let None <- fb.retType) {
            return None
        }
        let retTy = fb.retType.getOrThrow().GetTy() ?? return None
        if (retTy.HasInvalidTy() || retTy.IsQuest()) {
            return None
        }
        if (let Some(funcDecl) <- fb.funcDecl) {
            if (IsInstanceConstructor(funcDecl)) {
                return Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
            }
        }
        return Some(retTy)
    }

    private func SynthesizeReturnChildren(ctx: ASTContext, returnExpr: ReturnExpr): Unit {
        if (let None <- returnExpr.expr) {
            return
        }
        let innerExpr = returnExpr.expr.getOrThrow()
        if (let Some(targetTy) <- ReturnExprTargetTy(returnExpr)) {
            let _ = Check(ctx, targetTy, innerExpr)
            return
        }
        let _ = Synthesize(ctx, innerExpr)
    }

    private func AddUniqueBoundDecl(decls: ArrayList<Decl>, decl: Decl): Unit {
        for (existing in decls) {
            if (SameDecl(existing, decl)) {
                return
            }
        }
        decls.add(decl)
    }

    private func PropagateConditionCtxExpr(pattern: Pattern, initializer: Expr): Unit {
        pattern.ctxExpr = initializer
        if (let Some(varPattern) <- (pattern as VarPattern)) {
            varPattern.ctxExpr = initializer
            return
        }
        if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
            for (subPattern in tuplePattern.patterns) {
                PropagateConditionCtxExpr(subPattern, initializer)
            }
            return
        }
        if (let Some(enumPattern) <- (pattern as EnumPattern)) {
            for (subPattern2 in enumPattern.patterns) {
                PropagateConditionCtxExpr(subPattern2, initializer)
            }
            return
        }
        if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
            if (let Some(inner) <- varOrEnum.pattern) {
                PropagateConditionCtxExpr(inner, initializer)
            }
            return
        }
        if (let Some(typePattern) <- (pattern as TypePattern)) {
            if (let Some(inner2) <- typePattern.pattern) {
                PropagateConditionCtxExpr(inner2, initializer)
            }
            return
        }
        if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            if (let Some(inner3) <- exceptPattern.pattern) {
                PropagateConditionCtxExpr(inner3, initializer)
            }
        }
    }

    private func PatternHasConditionBinding(ctx: ASTContext, pattern: Pattern): Bool {
        if (let Some(_) <- (pattern as VarPattern)) {
            return true
        }
        if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
            if (let Some(inner) <- varOrEnum.pattern) {
                return PatternHasConditionBinding(ctx, inner)
            }
            return !ctx.IsEnumConstructor(varOrEnum.identifier.Val())
        }
        if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
            for (subPattern in tuplePattern.patterns) {
                if (PatternHasConditionBinding(ctx, subPattern)) {
                    return true
                }
            }
            return false
        }
        if (let Some(enumPattern) <- (pattern as EnumPattern)) {
            for (subPattern2 in enumPattern.patterns) {
                if (PatternHasConditionBinding(ctx, subPattern2)) {
                    return true
                }
            }
            return false
        }
        if (let Some(typePattern) <- (pattern as TypePattern)) {
            if (let Some(inner2) <- typePattern.pattern) {
                return PatternHasConditionBinding(ctx, inner2)
            }
            return false
        }
        if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            if (let Some(inner3) <- exceptPattern.pattern) {
                return PatternHasConditionBinding(ctx, inner3)
            }
        }
        return false
    }

    private func ConditionHasBinding(ctx: ASTContext, expr: Expr): Bool {
        if (let Some(letPattern) <- (expr as LetPatternDestructor)) {
            for (pattern in letPattern.patterns) {
                if (PatternHasConditionBinding(ctx, pattern)) {
                    return true
                }
            }
            return false
        }
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            if (let Some(inner) <- parenExpr.expr) {
                return ConditionHasBinding(ctx, inner)
            }
            return false
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            if (let Some(left) <- binaryExpr.leftExpr) {
                if (ConditionHasBinding(ctx, left)) {
                    return true
                }
            }
            if (let Some(right) <- binaryExpr.rightExpr) {
                return ConditionHasBinding(ctx, right)
            }
        }
        return false
    }

    private func BindCollectedConditionDecls(ctx: ASTContext, patterns: ArrayList<Pattern>,
        boundDecls: ArrayList<Decl>): Unit {
        let collected = ArrayList<Decl>()
        CollectPatternBindings(patterns, collected)
        for (decl in collected) {
            BindLocalDeclIfAbsent(ctx, decl)
            AddUniqueBoundDecl(boundDecls, decl)
        }
    }

    private func CheckLetPatternCondition(ctx: ASTContext, letPattern: LetPatternDestructor,
        boundDecls: ArrayList<Decl>, suppressIntroducingVariableError: Bool): Bool {
        if (let None <- letPattern.initializer) {
            let _ = TcInvalid(letPattern)
            return false
        }
        let initializer = letPattern.initializer.getOrThrow()
        for (pattern in letPattern.patterns) {
            PropagateConditionCtxExpr(pattern, initializer)
        }
        let _ = Synthesize(ctx, initializer)
        let selectorTy = if (Ty.IsTyCorrect(initializer.GetTy())) {
            TcReplaceIdeal(impl.typeManager, initializer)
        } else {
            initializer.GetTy() ?? TypeManager.GetInvalidTy()
        }
        if (!ChkPatternsSameASTKind(ctx, letPattern.patterns, diag: impl.diag)) {
            let _ = TcInvalid(letPattern)
            return false
        }
        var good = !suppressIntroducingVariableError &&
            ChkNoVarPatternInOrPattern(ctx, letPattern.patterns, diag: impl.diag)
        var subpatternsGood = true
        for (pattern in letPattern.patterns) {
            subpatternsGood = ChkPattern(impl.typeManager, ctx, selectorTy, pattern, isPatternInMatch: false,
                exprChecker: Some({ target: Ty, expr: Expr =>
                    Check(ctx, target, expr)
                })) && subpatternsGood
        }
        if (Ty.IsTyCorrect(selectorTy) && subpatternsGood) {
            letPattern.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))
            BindCollectedConditionDecls(ctx, letPattern.patterns, boundDecls)
            return good
        }
        let _ = TcInvalid(letPattern)
        return false
    }

    private func CheckConditionWithBindings(ctx: ASTContext, expr: Expr, boundDecls: ArrayList<Decl>,
        suppressIntroducingVariableError: Bool): Bool {
        if (let Some(letPattern) <- (expr as LetPatternDestructor)) {
            return CheckLetPatternCondition(ctx, letPattern, boundDecls, suppressIntroducingVariableError)
        }
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            if (let Some(inner) <- parenExpr.expr) {
                let ok = CheckConditionWithBindings(ctx, inner, boundDecls, suppressIntroducingVariableError)
                parenExpr.SetTy(inner.GetTy() ?? TypeManager.GetInvalidTy())
                return ok
            }
            let _ = TcInvalid(parenExpr)
            return false
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            if (binaryExpr.op == TokenKind.AND || binaryExpr.op == TokenKind.OR) {
                var suppressChildren = suppressIntroducingVariableError
                if (!suppressChildren && binaryExpr.op == TokenKind.OR && ConditionHasBinding(ctx, binaryExpr)) {
                    suppressChildren = true
                }
                var ok = true
                if (let Some(left) <- binaryExpr.leftExpr) {
                    ok = CheckConditionWithBindings(ctx, left, boundDecls, suppressChildren) && ok
                } else {
                    ok = false
                }
                if (let Some(right) <- binaryExpr.rightExpr) {
                    ok = CheckConditionWithBindings(ctx, right, boundDecls, suppressChildren) && ok
                } else {
                    ok = false
                }
                if (ok && !suppressChildren) {
                    binaryExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))
                    return true
                }
                let _ = TcInvalid(binaryExpr)
                return false
            }
        }
        return Check(ctx, TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN), expr)
    }

    private func CheckUnaryExprWithTarget(ctx: ASTContext, target: Ty, unaryExpr: UnaryExpr): Bool {
        if (let Some(innerExpr) <- unaryExpr.expr) {
            let unboxedTarget = UnboxOptionType(target)
            if (Ty.IsTyCorrect(unboxedTarget) && unboxedTarget.IsBuiltin()) {
                let _ = Check(ctx, unboxedTarget, innerExpr)
                if (let Some(innerTy) <- innerExpr.GetTy()) {
                    innerExpr.SetTy(impl.typeManager.TryGreedySubst(innerTy))
                }
            } else {
                let _ = Synthesize(ctx, innerExpr)
            }
        }
        return ChkUnaryExpr(impl.typeManager, target, unaryExpr)
    }

    private func SynthesizeIfChildren(ctx: ASTContext, ifExpr: IfExpr): Unit {
        let conditionBindings = ArrayList<Decl>()
        if (let Some(condExpr) <- ifExpr.condExpr) {
            let _ = CheckConditionWithBindings(ctx, condExpr, conditionBindings, false)
        }
        if (let Some(thenBody) <- ifExpr.thenBody) {
            let _ = SynthesizeBlock(ctx, thenBody)
        }
        RemovePatternBindings(ctx, conditionBindings)
        if (let Some(elseBody) <- ifExpr.elseBody) {
            let _ = Synthesize(ctx, elseBody)
        }
    }

    private func SynthesizeMatchChildren(ctx: ASTContext, matchExpr: MatchExpr): Unit {
        var selectorTy: Option<Ty> = None
        if (let Some(selector) <- matchExpr.selector) {
            let _ = Synthesize(ctx, selector)
            selectorTy = selector.GetTy()
        }
        for (matchCase in matchExpr.matchCases) {
            let boundDecls = ArrayList<Decl>()
            if (let Some(targetTy) <- selectorTy) {
                if (Ty.IsTyCorrect(targetTy)) {
                    matchCase.SetCtxExprForPatterns(matchExpr.selector.getOrThrow())
                    let _ = ChkMatchCasePatterns(impl.typeManager, ctx, targetTy, matchCase, diag: impl.diag,
                        exprChecker: Some({ target: Ty, expr: Expr =>
                            Check(ctx, target, expr)
                        }))
                    BindCollectedConditionDecls(ctx, matchCase.patterns, boundDecls)
                }
            }
            if (let Some(patternGuard) <- matchCase.patternGuard) {
                let _ = Synthesize(ctx, patternGuard)
            }
            if (let Some(action) <- matchCase.exprOrDecls) {
                let _ = SynthesizeBlock(ctx, action)
            }
            RemovePatternBindings(ctx, boundDecls)
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

    private func CollectPatternBinding(pattern: Pattern, out: ArrayList<Decl>): Unit {
        if (let Some(varPattern) <- (pattern as VarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                out.add(varDecl)
            }
            return
        }
        if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
            if (let Some(inner) <- varOrEnum.pattern) {
                CollectPatternBinding(inner, out)
            }
            return
        }
        if (let Some(enumPattern) <- (pattern as EnumPattern)) {
            for (subPattern in enumPattern.patterns) {
                CollectPatternBinding(subPattern, out)
            }
            return
        }
        if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
            for (subPattern2 in tuplePattern.patterns) {
                CollectPatternBinding(subPattern2, out)
            }
            return
        }
        if (let Some(typePattern) <- (pattern as TypePattern)) {
            if (let Some(inner2) <- typePattern.pattern) {
                CollectPatternBinding(inner2, out)
            }
            return
        }
        if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            if (let Some(inner3) <- exceptPattern.pattern) {
                CollectPatternBinding(inner3, out)
            }
        }
    }

    private func CollectPatternBindings(patterns: ArrayList<Pattern>, out: ArrayList<Decl>): Unit {
        for (pattern in patterns) {
            CollectPatternBinding(pattern, out)
        }
    }

    private func RemovePatternBindings(ctx: ASTContext, decls: ArrayList<Decl>): Unit {
        for (decl in decls) {
            let name = decl.identifier.Val()
            if (!name.isEmpty() && name != INVALID_IDENTIFIER) {
                ctx.RemoveDeclByName(Names(name, decl.scopeName), decl)
            }
        }
    }

    private func SynthesizeLoopChildren(ctx: ASTContext, loopExpr: Expr): Unit {
        if (let Some(forInExpr) <- (loopExpr as ForInExpr)) {
            let boundDecls = ArrayList<Decl>()
            var elementTy: Ty = TypeManager.GetInvalidTy()
            if (let Some(inExpression) <- forInExpr.inExpression) {
                let _ = Synthesize(ctx, inExpression)
                if (Ty.IsTyCorrect(inExpression.GetTy())) {
                    elementTy = ForInIterableElementTy(impl.typeManager, inExpression.curFile,
                        TcReplaceIdeal(impl.typeManager, inExpression))
                }
            }
            if (let Some(pattern) <- forInExpr.pattern) {
                if (Ty.IsTyCorrect(elementTy)) {
                    let _ = ChkPattern(impl.typeManager, ctx, elementTy, pattern, isPatternInMatch: false)
                    CollectPatternBinding(pattern, boundDecls)
                }
            }
            if (let Some(patternGuard) <- forInExpr.patternGuard) {
                let _ = Synthesize(ctx, patternGuard)
            }
            if (let Some(body) <- forInExpr.body) {
                let _ = SynthesizeBlock(ctx, body)
            }
            RemovePatternBindings(ctx, boundDecls)
            return
        }
        if (let Some(whileExpr) <- (loopExpr as WhileExpr)) {
            let conditionBindings = ArrayList<Decl>()
            if (let Some(condExpr) <- whileExpr.condExpr) {
                let _ = CheckConditionWithBindings(ctx, condExpr, conditionBindings, false)
            }
            if (let Some(body2) <- whileExpr.body) {
                let _ = SynthesizeBlock(ctx, body2)
            }
            RemovePatternBindings(ctx, conditionBindings)
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
        if (impl.typeManager.GetUnsolvedTyVars().isEmpty() && ctx.IsSynSkippedForCorrectTy(nameRef)) {
            return nameRef.GetTy() ?? TypeManager.GetInvalidTy()
        }
        for (typeArg in nameRef.GetTypeArgs()) {
            impl.SetTypeTy(ctx, typeArg)
        }
        if (let Some(memberAccess) <- (nameRef as MemberAccess)) {
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                SetIsNotAlone(baseExpr)
                let _ = Synthesize(ctx, baseExpr)
                ResolvePrimitiveStaticMemberAccess(ctx, memberAccess)
            }
        } else if (let Some(refExpr) <- (nameRef as RefExpr)) {
            if (refExpr.isThis || refExpr.isSuper) {
                typeCheckExprCheckThisOrSuper(impl.typeManager, ctx, refExpr, currentFuncBody)
            } else {
                ResolveRefExpr(ctx, refExpr)
            }
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

    private func ResolvePrimitiveStaticMemberAccess(ctx: ASTContext, memberAccess: MemberAccess): Unit {
        if ((let Some(_) <- memberAccess.target) || !memberAccess.targets.isEmpty()) {
            return
        }
        if (let None <- memberAccess.baseExpr) {
            return
        }
        let baseExpr = memberAccess.baseExpr.getOrThrow()
        if (!(baseExpr is PrimitiveTypeExpr)) {
            return
        }
        if (let None <- memberAccess.curFile) {
            return
        }
        let file = memberAccess.curFile.getOrThrow()
        memberAccess.SetTy(TypeManager.GetInvalidTy())
        let targets = ExtendFieldLookup(impl.typeManager, file, baseExpr.GetTy(), memberAccess.field.Val())
        if (let Some(diagValue) <- impl.diag) {
            if (!TypeCheckReferenceFilterAndCheckTargetsOfNameAccess(
                diagValue, impl.typeManager, ctx, memberAccess, targets)) {
                return
            }
        }
        if (targets.isEmpty()) {
            return
        }
        let target = GetAccessibleDecl(memberAccess, targets) ?? targets[0]
        ReplaceTarget(memberAccess, Some(target))
        AddFuncTargetsForMemberAccess(memberAccess, targets)
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
                ctx.SkipSynForCorrectTy(nameRef)
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
        ctx.SkipSynForCorrectTy(expr)
        return ty
    }

    private func FinishCheck(ctx: ASTContext, expr: Expr, ok: Bool): Bool {
        SynthesizeDesugarsInTree(ctx, expr)
        RefreshNameReferencesInTree(ctx, expr)
        RefreshUnsetExprTypesInTree(expr)
        RefreshNameReferencesInTree(ctx, expr)
        if (ok) {
            ctx.SkipSynForCorrectTy(expr)
        }
        return ok
    }

    private func LookupCoreTy(ctx: ASTContext, name: String): Option<Ty> {
        if (let Some(decl) <- lookupResolvedPackageDecl(ctx, "std.core", name)) {
            addImportedDeclAndDependencies(ctx, decl)
            return decl.GetTy()
        }
        return None
    }

    private func LookupCoreEnumDecl(ctx: ASTContext, name: String): Option<EnumDecl> {
        if (let Some(decl) <- lookupResolvedPackageDecl(ctx, "std.core", name)) {
            addImportedDeclAndDependencies(ctx, decl)
            return decl as EnumDecl
        }
        return None
    }

    private func SynthesizeThrowExpr(ctx: ASTContext, throwExpr: ThrowExpr): Ty {
        if (let Some(innerExpr) <- throwExpr.expr) {
            let _ = Synthesize(ctx, innerExpr)
        }
        return FinishSynthesize(ctx, throwExpr, SynThrowExpr(impl.typeManager, throwExpr,
            exceptionTy: LookupCoreTy(ctx, "Exception"), errorTy: LookupCoreTy(ctx, "Error")))
    }

    private func SynthesizeTryCatchPatternTypes(ctx: ASTContext, pattern: Pattern): Unit {
        if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            for (typeNode in exceptPattern.types) {
                SynthesizeTypeNode(ctx, Some(typeNode))
            }
            if (let Some(inner) <- exceptPattern.pattern) {
                let target = CatchPatternBindingTargetTy(ctx, exceptPattern)
                let _ = ChkPattern(impl.typeManager, ctx, target, inner, isPatternInMatch: false)
            }
            return
        }
        if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
            if (let Some(inner2) <- varOrEnum.pattern) {
                SynthesizeTryCatchPatternTypes(ctx, inner2)
                return
            }
        }
        let catchTarget = LookupCoreTy(ctx, "Exception") ?? impl.typeManager.GetAnyTy()
        let _ = ChkPattern(impl.typeManager, ctx, catchTarget, pattern, isPatternInMatch: false)
    }

    private func CatchPatternBindingTargetTy(ctx: ASTContext, pattern: ExceptTypePattern): Ty {
        if (let Some(patternTy) <- pattern.GetTy()) {
            if (Ty.IsTyCorrect(patternTy)) {
                return patternTy
            }
        }
        for (typeNode in pattern.types) {
            if (let Some(typeTy) <- typeNode.GetTy()) {
                if (Ty.IsTyCorrect(typeTy)) {
                    return typeTy
                }
            }
        }
        return LookupCoreTy(ctx, "Exception") ?? impl.typeManager.GetAnyTy()
    }

    private func SynthesizeTryExprChildren(ctx: ASTContext, tryExpr: TryExpr): Unit {
        let _ = LookupCoreTy(ctx, "Object")
        let _ = LookupCoreTy(ctx, "Exception")
        let _ = LookupCoreTy(ctx, "Error")
        for (resource in tryExpr.resourceSpec) {
            let _ = SynthesizeDecl(ctx, resource)
        }
        if (let Some(tryBlock) <- tryExpr.tryBlock) {
            let _ = SynthesizeBlock(ctx, tryBlock)
        }
        var idx: Int64 = 0
        while (idx < tryExpr.catchPatterns.size) {
            let boundDecls = ArrayList<Decl>()
            let pattern = tryExpr.catchPatterns[idx]
            SynthesizeTryCatchPatternTypes(ctx, pattern)
            CollectPatternBinding(pattern, boundDecls)
            for (decl in boundDecls) {
                BindLocalDeclIfAbsent(ctx, decl)
            }
            if (idx < tryExpr.catchBlocks.size) {
                let _ = SynthesizeBlock(ctx, tryExpr.catchBlocks[idx])
            }
            RemovePatternBindings(ctx, boundDecls)
            idx++
        }
        for (handler in tryExpr.handlers) {
            if (let Some(commandPattern) <- handler.commandPattern) {
                SynthesizeTryCatchPatternTypes(ctx, commandPattern)
            }
            if (let Some(block) <- handler.block) {
                let _ = SynthesizeBlock(ctx, block)
            }
        }
        if (let Some(finallyBlock) <- tryExpr.finallyBlock) {
            let _ = SynthesizeBlock(ctx, finallyBlock)
        }
        if (let Some(tryLambda) <- tryExpr.tryLambda) {
            let _ = Synthesize(ctx, tryLambda)
        }
        if (let Some(finallyLambda) <- tryExpr.finallyLambda) {
            let _ = Synthesize(ctx, finallyLambda)
        }
    }

    private func SynthesizeTryExpr(ctx: ASTContext, tryExpr: TryExpr): Ty {
        SynthesizeTryExprChildren(ctx, tryExpr)
        return FinishSynthesize(ctx, tryExpr, SynTryExpr(impl.typeManager, tryExpr))
    }

    private func CheckArrayLit(ctx: ASTContext, target: Ty, arrayLit: ArrayLit): Bool {
        let targetTy = UnboxOptionType(target)
        var matched = true
        if (targetTy.typeArgs.size >= 1) {
            let elemTy = targetTy.typeArgs[0]
            for (child in arrayLit.children) {
                if (!Check(ctx, elemTy, child)) {
                    matched = false
                    break
                }
            }
        }
        if (!ChkArrayLit(impl.typeManager, target, arrayLit)) {
            matched = false
        }
        return matched
    }

    private func Synthesize(ctx: ASTContext, expr: Expr): Ty {
        if (expr.TestAttr(Attribute.IS_BROKEN)) {
            expr.SetTy(TypeManager.GetInvalidTy())
            return expr.GetTy() ?? TypeManager.GetInvalidTy()
        }
        if (impl.typeManager.GetUnsolvedTyVars().isEmpty() && ctx.IsSynSkippedForCorrectTy(expr)) {
            return expr.GetTy() ?? TypeManager.GetInvalidTy()
        }
        if (let Some(desugar) <- expr.desugarExpr) {
            let _ = Synthesize(ctx, desugar)
        }
        if (let Some(block) <- (expr as Block)) {
            return SynthesizeBlock(ctx, block)
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            SynthesizeCallChildren(ctx, callExpr)
            let callTy = SynCallExprWithArgChecker(impl.typeManager, callExpr,
                Some({ target: Ty, arg: FuncArg => CheckCallArgFromContext(ctx, target, arg) }), diag: impl.diag)
            return FinishSynthesize(ctx, callExpr, callTy)
        }
        if (let Some(ifExpr) <- (expr as IfExpr)) {
            SynthesizeIfChildren(ctx, ifExpr)
            return FinishSynthesize(ctx, ifExpr, SynExprShallow(impl.typeManager, ifExpr))
        }
        if (let Some(matchExpr) <- (expr as MatchExpr)) {
            SynthesizeMatchChildren(ctx, matchExpr)
            return FinishSynthesize(ctx, matchExpr, SynMatchExpr(impl.typeManager, ctx, matchExpr, diag: impl.diag,
                exprChecker: Some({ target: Ty, expr: Expr =>
                    Check(ctx, target, expr)
                })))
        }
        if (let Some(jumpExpr) <- (expr as JumpExpr)) {
            return FinishSynthesize(ctx, jumpExpr, SynLoopControlExpr(ctx, jumpExpr))
        }
        if (expr.IsLoopExpr()) {
            SynthesizeLoopChildren(ctx, expr)
            return FinishSynthesize(ctx, expr, SynExprShallow(impl.typeManager, expr))
        }
        if (let Some(returnExpr) <- (expr as ReturnExpr)) {
            if (let Some(fb) <- currentFuncBody) {
                returnExpr.refFuncBody = Some(fb)
            }
            SynthesizeReturnChildren(ctx, returnExpr)
            return FinishSynthesize(ctx, returnExpr, SynExprShallow(impl.typeManager, returnExpr))
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            SynthesizeBinaryChildren(ctx, binaryExpr)
            let binaryTy = SynBinaryExpr(impl.typeManager, binaryExpr)
            if (Ty.IsTyCorrect(binaryTy)) {
                return FinishSynthesize(ctx, binaryExpr, binaryTy)
            }
            if (let Some(overloadTy) <- TrySynthesizeBinaryOperatorOverload(ctx, binaryExpr)) {
                return FinishSynthesize(ctx, binaryExpr, overloadTy)
            }
            return FinishSynthesize(ctx, binaryExpr, binaryTy)
        }
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            return FinishSynthesize(ctx, nameRef, SynthesizeNameReference(ctx, nameRef))
        }
        if (let Some(subscript) <- (expr as SubscriptExpr)) {
            SynthesizeSubscriptChildren(ctx, subscript)
            return FinishSynthesize(ctx, subscript, SynSubscriptExpr(impl.typeManager, subscript))
        }
        if (let Some(assign) <- (expr as AssignExpr)) {
            SynthesizeAssignChildren(ctx, assign)
            return FinishSynthesize(ctx, assign, SynAssignExpr(impl.typeManager, assign))
        }
        if (let Some(throwExpr) <- (expr as ThrowExpr)) {
            return SynthesizeThrowExpr(ctx, throwExpr)
        }
        if (let Some(tryExpr) <- (expr as TryExpr)) {
            return SynthesizeTryExpr(ctx, tryExpr)
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
            return FinishSynthesize(ctx, asExpr, SynAsExpr(impl.typeManager, asExpr, LookupCoreEnumDecl(ctx, "Option")))
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
                return FinishSynthesize(ctx, lit,
                    SynLitConstExpr(lit, stringTy: stringTy, typeManager: Some(impl.typeManager), ctx: Some(ctx)))
            }
        }
        SynthesizeNodeChildren(ctx, expr)
        if (let Some(rangeExpr) <- (expr as RangeExpr)) {
            var rangeStruct: Option<StructDecl> = None
            if (let Some(rangeDecl) <- lookupResolvedPackageDecl(ctx, "std.core", "Range")) {
                addImportedDeclAndDependencies(ctx, rangeDecl)
                rangeStruct = rangeDecl as StructDecl
            }
            return FinishSynthesize(ctx, rangeExpr, SynRangeExpr(impl.typeManager, rangeExpr, rangeDecl: rangeStruct))
        }
        if (let Some(arrayLit) <- (expr as ArrayLit)) {
            var arrayStruct: Option<StructDecl> = None
            if (let Some(arrayDecl) <- lookupResolvedPackageDecl(ctx, "std.core", "Array")) {
                addImportedDeclAndDependencies(ctx, arrayDecl)
                arrayStruct = arrayDecl as StructDecl
            }
            let arrayTy = SynArrayLit(impl.typeManager, arrayLit, arrayStruct)
            if (let Some(initFunc) <- arrayLit.initFunc) {
                addImportedDeclAndDependencies(ctx, initFunc)
            }
            return FinishSynthesize(ctx, arrayLit, arrayTy)
        }
        if (let Some(spawnExpr) <- (expr as SpawnExpr)) {
            return SynthesizeSpawnExpr(ctx, spawnExpr)
        }
        return FinishSynthesize(ctx, expr, SynExprShallow(impl.typeManager, expr))
    }

    private func CheckArithmeticBinaryExpr(ctx: ASTContext, target: Ty, be: BinaryExpr): Bool {
        if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
            be.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        let targetTy = UnboxOptionType(target)
        if (!Ty.IsTyCorrect(targetTy)) {
            return false
        }
        let leftExpr = be.leftExpr.getOrThrow()
        let rightExpr = be.rightExpr.getOrThrow()
        for (kindValue in typeCheckExprConcreteBinaryCandidateKinds(be.op)) {
            let candidateTy = TypeManager.GetPrimitiveTy(kindValue)
            if (!impl.typeManager.IsSubtype(candidateTy, targetTy)) {
                continue
            }
            typeCheckExprClearKeepTargets(leftExpr)
            typeCheckExprClearKeepTargets(rightExpr)
            let leftOk = Check(ctx, candidateTy, leftExpr)
            let rightOk = Check(ctx, candidateTy, rightExpr)
            if (leftOk && rightOk) {
                be.SetTy(candidateTy)
                return true
            }
        }
        be.SetTy(TypeManager.GetInvalidTy())
        return false
    }

    private func CheckBinaryExpr(ctx: ASTContext, target: Ty, be: BinaryExpr): Bool {
        if (let Some(desugar) <- be.desugarExpr) {
            if (let Some(desugarTy) <- desugar.GetTy()) {
                return impl.typeManager.CheckTypeCompatibility(target, desugarTy) != TypeCompatibility.INCOMPATIBLE
            }
        }
        if (typeCheckExprIsArithmeticOperator(be.op) && CheckArithmeticBinaryExpr(ctx, target, be)) {
            return true
        }
        if (TryCheckBinaryOperatorOverload(ctx, target, be)) {
            return true
        }
        let _ = Synthesize(ctx, be)
        return ChkExprShallow(impl.typeManager, target, be)
    }

    private func ShouldTryBinaryOperatorOverload(be: BinaryExpr): Bool {
        if (!IsOverloadableOperator(be.op)) {
            return false
        }
        if (be.op != TokenKind.EQUAL && be.op != TokenKind.NOTEQ) {
            return true
        }
        if (let Some(leftExpr) <- be.leftExpr) {
            if (let Some(rightExpr) <- be.rightExpr) {
                if (let Some(leftTy) <- leftExpr.GetTy()) {
                    if (let Some(rightTy) <- rightExpr.GetTy()) {
                        return !(leftTy.IsTuple() && rightTy.IsTuple())
                    }
                }
            }
        }
        return true
    }

    private func PropagateBinaryOperatorTarget(be: BinaryExpr, desugar: Expr): Unit {
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            if (let Some(resolved) <- callExpr.resolvedFunction) {
                ReplaceTarget(be, Some(resolved))
            }
        }
    }

    private func TryCheckBinaryOperatorOverload(ctx: ASTContext, target: Ty, be: BinaryExpr): Bool {
        if (!ShouldTryBinaryOperatorOverload(be)) {
            return false
        }
        DesugarOperatorOverloadExpr(be)
        if (let Some(desugar) <- be.desugarExpr) {
            if (Check(ctx, target, desugar)) {
                be.SetTy(desugar.GetTy() ?? TypeManager.GetInvalidTy())
                PropagateBinaryOperatorTarget(be, desugar)
                return true
            }
        }
        RecoverToBinaryExpr(be)
        return false
    }

    private func TrySynthesizeBinaryOperatorOverload(ctx: ASTContext, be: BinaryExpr): Option<Ty> {
        if (!ShouldTryBinaryOperatorOverload(be)) {
            return None
        }
        DesugarOperatorOverloadExpr(be)
        if (let Some(desugar) <- be.desugarExpr) {
            let desugarTy = Synthesize(ctx, desugar)
            if (Ty.IsTyCorrect(desugarTy)) {
                be.SetTy(desugarTy)
                PropagateBinaryOperatorTarget(be, desugar)
                return Some(desugarTy)
            }
        }
        RecoverToBinaryExpr(be)
        be.SetTy(TypeManager.GetInvalidTy())
        return None
    }

    private func Check(ctx: ASTContext, target: Ty, expr: Expr): Bool {
        if (let Some(lambda) <- (expr as LambdaExpr)) {
            return FinishCheck(ctx, lambda, CheckLambdaExprWithTarget(ctx, target, lambda))
        }
        if (let Some(block) <- (expr as Block)) {
            return CheckBlock(ctx, target, block)
        }
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            typeCheckExprPutTargetType(ctx, nameRef, target)
            let _ = Synthesize(ctx, nameRef)
            let ok = ChkNameReferenceExpr(impl.typeManager, target, nameRef)
            typeCheckExprClearTargetType(ctx, nameRef)
            return FinishCheck(ctx, expr, ok)
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            typeCheckExprPutTargetType(ctx, callExpr, target)
            SynthesizeCallChildren(ctx, callExpr)
            let ok = ChkCallExprWithArgChecker(impl.typeManager, impl.diag, Some(target), callExpr,
                Some({ paramTy: Ty, arg: FuncArg => CheckCallArgFromContext(ctx, paramTy, arg) }))
            typeCheckExprClearTargetType(ctx, callExpr)
            return FinishCheck(ctx, callExpr, ok)
        }
        if (let Some(ifExpr) <- (expr as IfExpr)) {
            SynthesizeIfChildren(ctx, ifExpr)
            return FinishCheck(ctx, ifExpr, ChkExprShallow(impl.typeManager, target, ifExpr))
        }
        if (let Some(matchExpr) <- (expr as MatchExpr)) {
            SynthesizeMatchChildren(ctx, matchExpr)
            return FinishCheck(ctx, matchExpr, ChkMatchExpr(impl.typeManager, ctx, target, matchExpr, diag: impl.diag,
                exprChecker: Some({ target2: Ty, expr: Expr =>
                    Check(ctx, target2, expr)
                })))
        }
        if (let Some(jumpExpr) <- (expr as JumpExpr)) {
            return FinishCheck(ctx, jumpExpr, ChkLoopControlExpr(ctx, jumpExpr))
        }
        if (expr.IsLoopExpr()) {
            SynthesizeLoopChildren(ctx, expr)
            return FinishCheck(ctx, expr, ChkExprShallow(impl.typeManager, target, expr))
        }
        if (let Some(lit) <- (expr as LitConstExpr)) {
            return FinishCheck(ctx, lit, ChkLitConstExpr(impl.typeManager, target, lit, ctx: Some(ctx)))
        }
        if (let Some(arrayLit) <- (expr as ArrayLit)) {
            return FinishCheck(ctx, arrayLit, CheckArrayLit(ctx, target, arrayLit))
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            return FinishCheck(ctx, binaryExpr, CheckBinaryExpr(ctx, target, binaryExpr))
        }
        if (let Some(unaryExpr) <- (expr as UnaryExpr)) {
            return FinishCheck(ctx, unaryExpr, CheckUnaryExprWithTarget(ctx, target, unaryExpr))
        }
        if (let Some(returnExpr) <- (expr as ReturnExpr)) {
            if (let Some(fb) <- currentFuncBody) {
                returnExpr.refFuncBody = Some(fb)
            }
            SynthesizeReturnChildren(ctx, returnExpr)
            return FinishCheck(ctx, returnExpr, ChkExprShallow(impl.typeManager, target, returnExpr))
        }
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            let _ = SynthesizeNameReference(ctx, nameRef)
            return FinishCheck(ctx, expr, ChkExprShallow(impl.typeManager, target, expr))
        }
        if (let Some(throwExpr) <- (expr as ThrowExpr)) {
            let throwTy = SynthesizeThrowExpr(ctx, throwExpr)
            return FinishCheck(ctx, throwExpr, Ty.IsTyCorrect(throwTy) &&
                impl.typeManager.CheckTypeCompatibility(target, throwTy) != TypeCompatibility.INCOMPATIBLE)
        }
        if (let Some(tryExpr) <- (expr as TryExpr)) {
            SynthesizeTryExprChildren(ctx, tryExpr)
            return FinishCheck(ctx, tryExpr, ChkTryExpr(impl.typeManager, target, tryExpr))
        }
        if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
            SynthesizeTypeNode(ctx, arrayExpr.typeNode)
            for (arg in arrayExpr.args) {
                let _ = SynthesizeFuncArg(ctx, arg)
            }
            return FinishCheck(ctx, arrayExpr, ChkArrayExpr(impl.typeManager, target, arrayExpr, diag: impl.diag))
        }
        if (let Some(spawnExpr) <- (expr as SpawnExpr)) {
            return FinishCheck(ctx, spawnExpr, CheckSpawnExprWithTarget(ctx, target, spawnExpr))
        }
        if (let Some(asExpr) <- (expr as AsExpr)) {
            SynthesizeTypeNode(ctx, asExpr.asType)
            if (let Some(leftExpr) <- asExpr.leftExpr) {
                let _ = Synthesize(ctx, leftExpr)
            }
            return FinishCheck(ctx, asExpr, ChkAsExpr(impl.typeManager, target, asExpr, LookupCoreEnumDecl(ctx, "Option")))
        }
        let _ = Synthesize(ctx, expr)
        return FinishCheck(ctx, expr, ChkExprShallow(impl.typeManager, target, expr))
    }

    private func ResolveRefExpr(ctx: ASTContext, refExpr: RefExpr): Unit {
        if (let Some(_) <- refExpr.ref.target) {
            return
        }
        let targets = ArrayList<Decl>()
        for (target in refExpr.ref.targets) {
            targets.add(target)
        }
        if (targets.isEmpty()) {
            for (target in impl.Lookup(ctx, refExpr.ref.identifier.Val(), scopeNameOf(refExpr), refExpr)) {
                targets.add(target)
            }
        }
        if (!refExpr.TestAttr(Attribute.MACRO_INVOKE_BODY) && typeCheckExprAllMacroFuncDecls(targets)) {
            let checker = EnumSugarChecker(impl.typeManager, ctx, refExpr)
            let (resolved, resolvedTargets) = checker.Resolve()
            if (resolved) {
                targets.clear()
                for (target in resolvedTargets) {
                    targets.add(target)
                }
                if (targets.isEmpty()) {
                    refExpr.SetTy(TypeManager.GetInvalidTy())
                    refExpr.ref.targets.clear()
                    return
                }
            }
        }
        if (targets.isEmpty()) {
            refExpr.SetTy(TypeManager.GetInvalidTy())
            refExpr.ref.targets.clear()
            return
        }
        if (let Some(diagValue) <- impl.diag) {
            if (!TypeCheckReferenceFilterAndCheckTargetsOfRef(diagValue, impl.typeManager, ctx, refExpr, targets)) {
                refExpr.SetTy(TypeManager.GetInvalidTy())
                refExpr.ref.targets.clear()
                return
            }
        }
        if (targets.isEmpty()) {
            refExpr.SetTy(TypeManager.GetInvalidTy())
            refExpr.ref.targets.clear()
            return
        }
        var decl = GetAccessibleDecl(refExpr, targets)
        if (let None <- decl) {
            decl = Some(targets[0])
        }
        ModifyTargetOfRef(refExpr, decl.getOrThrow(), targets)
        for (target in refExpr.ref.targets) {
            addImportedDeclAndDependencies(ctx, target)
        }
        if (let Some(target) <- refExpr.ref.target) {
            addImportedDeclAndDependencies(ctx, target)
        }
    }
}
