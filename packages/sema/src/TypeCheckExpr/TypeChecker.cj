package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DEFAULT_POSITION as BasicDefaultPosition
import cjcj::basic.DiagnosticCache
import cjcj::basic.Diagnostic
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::option.GlobalOptions as OptionGlobalOptions
import cjcj::option.OutputMode as OptionOutputMode
import cjcj::option.IsUnsafeBackend as OptionIsUnsafeBackend
import cjcj::sema.*
import cjcj::sema.Desugar.*
import cjcj::sema.Desugar.AfterTypeCheck.*
import cjcj::sema.FFI.*
import cjcj::sema.InheritanceChecker.*
import cjcj::sema.LegalityOfUsage.*
import cjcj::sema.NativeFFI.*
import cjcj::utils.CFUNC_NAME
import cjcj::utils.CORE_PACKAGE_NAME as UTILS_CORE_PACKAGE_NAME
import cjcj::utils.CPOINTER_NAME
import cjcj::utils.CSTRING_NAME
import cjcj::utils.CTYPE_NAME as UtilsCTypeName
import cjcj::utils.CJC_ASSERT
import cjcj::utils.MAIN_INVOKE
import cjcj::utils.OBJECT_NAME
import cjcj::utils.ProfileRecorder
import cjcj::utils.RAW_ARRAY_NAME
import cjcj::utils.VARRAY_NAME

private let INOUT_TEMP_VALUE: String = "temporary value"
private let INOUT_IMMUTABLE: String = "is a immutable variable"

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

private func typeCheckExprTargetTypeOf(ctx: ASTContext, node: Node): Option<Ty> {
    return ctx.targetTypeMap.get(node)
}

func typeCheckExprPutTargetType(ctx: ASTContext, node: Node, ty: Ty): Unit {
    ctx.targetTypeMap[node] = ty
}

private func typeCheckExprClearTargetType(ctx: ASTContext, node: Node): Unit {
    ctx.targetTypeMap.remove(node)
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

private func findCoreImplicitMemberDeclInMap(instance: CompilerInstance, className: String,
    memberName: String): Option<Decl> {
    if (let Some(packageMap) <- instance.resolvedPackageMemberDeclsMap.get("std.core")) {
        if (let Some(decls) <- packageMap.get(className)) {
            for (decl in decls) {
                if (decl.identifier.Val() != className) {
                    continue
                }
                for (member in decl.GetMemberDeclPtrs()) {
                    if (member.identifier.Val() == memberName) {
                        return Some(member)
                    }
                }
            }
        }
    }
    return None
}

private func findCoreImplicitMemberDeclInPackages(packageDecls: ArrayList<PackageDecl>, className: String,
    memberName: String): Option<Decl> {
    for (packageDecl in packageDecls) {
        let pkg = packageDecl.srcPackage
        if (pkg.fullPackageName != "std.core") {
            continue
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (decl.identifier.Val() != className) {
                    continue
                }
                for (member in decl.GetMemberDeclPtrs()) {
                    if (member.identifier.Val() == memberName) {
                        return Some(member)
                    }
                }
            }
            for (decl in file.exportedInternalDecls) {
                if (decl.identifier.Val() != className) {
                    continue
                }
                for (member in decl.GetMemberDeclPtrs()) {
                    if (member.identifier.Val() == memberName) {
                        return Some(member)
                    }
                }
            }
        }
    }
    return None
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

private func typeCheckExprIsLogicalOperator(op: TokenKind): Bool {
    return op == TokenKind.AND || op == TokenKind.OR
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

private func CollectGenericParam(funcDecl: FuncDecl, desugared: FuncDecl): Unit {
    let funcBody = if (let Some(value) <- funcDecl.funcBody) { value } else { return }
    let originalGeneric = if (let Some(value) <- funcBody.generic) { value } else { return }
    if (originalGeneric.typeParameters.isEmpty()) {
        return
    }
    let generic = Generic()
    var typeParamIdx: Int64 = 0
    let orig2New = HashMap<String, String>()
    for (param in originalGeneric.typeParameters) {
        let typeParam = GenericParamDecl()
        let newIdentifier = param.identifier.Val() + "$" + typeParamIdx.toString()
        typeParamIdx++
        typeParam.identifier = SrcIdentifier(newIdentifier)
        typeParam.outerDecl = desugared
        if (!orig2New.contains(param.identifier.Val())) {
            orig2New[param.identifier.Val()] = newIdentifier
        }
        generic.typeParameters.add(typeParam)
    }
    for (constraint in originalGeneric.genericConstraints) {
        let genericConstraint = GenericConstraint()
        CopyBasicInfo(constraint, genericConstraint)
        let constraintType = constraint.refType.getOrThrow()
        let constraintIdentifier = constraintType.ref.identifier.Val()
        let newConstraintIdentifier = if (let Some(value) <- orig2New.get(constraintIdentifier)) {
            value
        } else {
            orig2New[constraintIdentifier] = ""
            ""
        }
        let refType = RefType()
        refType.ref.identifier = SrcIdentifier(newConstraintIdentifier)
        genericConstraint.refType = refType
        for (upperBound in constraint.upperBounds) {
            genericConstraint.upperBounds.add((ASTCloner.Clone(upperBound) as Type).getOrThrow())
        }
        generic.genericConstraints.add(genericConstraint)
    }
    desugared.funcBody.getOrThrow().generic = generic
    let replacesTypeParams = { node: Node =>
        if (let Some(refType) <- (node as RefType)) {
            if (let Some(newIdentifier) <- orig2New.get(refType.ref.identifier.Val())) {
                refType.ref.identifier = SrcIdentifier(newIdentifier)
            }
        } else if (let Some(refExpr) <- (node as RefExpr)) {
            if (let Some(newIdentifier) <- orig2New.get(refExpr.ref.identifier.Val())) {
                refExpr.ref.identifier = SrcIdentifier(newIdentifier)
            }
        }
        VisitAction.WALK_CHILDREN
    }
    let _ = Walker(desugared, visitPre: replacesTypeParams).Walk()
    desugared.EnableAttr(Attribute.GENERIC)
}

public class TypeChecker {
    private var ci: Option<CompilerInstance> = None
    private var impl: TypeCheckerImpl = TypeCheckerImpl()
    private let contexts: ArrayList<ASTContext> = ArrayList<ASTContext>()
    private var currentFuncBody: Option<FuncBody> = None
    private let activeEnumConstructorRegistrations: ArrayList<EnumDecl> = ArrayList<EnumDecl>()
    private let mainFunctionMap: HashMap<Node, ArrayList<Decl>> = HashMap<Node, ArrayList<Decl>>()

    public init(ci: Option<CompilerInstance>) {
        this.ci = ci
        let tm = if (let Some(instance) <- ci) { instance.typeManager } else { TypeManager() }
        if (let Some(instance) <- ci) {
            tm.compileTestsOnly = instance.globalOptions.compileTestsOnly
        }
        impl = if (let Some(instance) <- ci) {
            TypeCheckerImpl(typeManager: tm, diag: instance.diag, importManager: instance.importManager)
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
        for (pkg in pkgs) {
            SetOverflowStrategyForPkg(pkg)
        }
    }

    public func CheckInlineFunctions(pkgs: ArrayList<Package>): Unit {
        var options = OptionGlobalOptions()
        if (let Some(instance) <- ci) {
            options = instance.globalOptions
        }
        CheckInlineFunctionsForPackages(pkgs, options)
    }

    public func CheckUnusedImportSpec(pkg: Package): ArrayList<UnusedImportFinding> {
        return CollectUnusedImports(pkg, impl.importManager.getOrThrow())
    }

    public func CheckAllDeclAttributes(pkg: Package): ArrayList<DeclAttributeIssue> {
        return CheckDeclAttributesForPackage(pkg, impl.diag.getOrThrow(), opts: GlobalOptions())
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
        BuildImportedExtendMap()
        for (ctx in contexts) {
            BuildCurrentPackageExtendMap(ctx)
        }
        CheckCHIRClassDependencies()
        UpdateAnyTy()
        UpdateCTypeTy()
        for (ctx in contexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                CollectDeclsWithMember(pkg, ctx)
            }
        }
        return contexts
    }

    private func PrepareTypeCheck(ctx: ASTContext, pkg: Package): Unit {
        ctx.Reset()
        ctx.curPackage = pkg
        ctx.fullPackageName = pkg.fullPackageName
        CheckPrimaryCtorBeforeMerge(pkg)
        SeedImportedPackageDecls(ctx)
        AddDefaultFunction(pkg)
        if (pkg.fullPackageName == UTILS_CORE_PACKAGE_NAME && !pkg.files.isEmpty() &&
            !pkg.TestAttr(Attribute.IMPORTED)) {
            AddBuiltInArrayDecl(pkg)
            AddBuiltInVArrayDecl(pkg)
            AddBuiltInPointerDecl(pkg)
            AddBuiltinCFuncDecl(pkg)
            AddBuiltInCStringDecl(pkg)
        }
        AddDefaultParamFunctions(pkg)
        let enableMacroInLSP = if (let Some(instance) <- ci) { instance.globalOptions.enableMacroInLSP } else { false }
        Collector(enableMacroInLsp: enableMacroInLSP).BuildSymbolTable(ctx, pkg, buildTrie: false)
        MarkOutermostBinaryExpressions(pkg)
        AddCurFile(pkg)
        MarkParamWithInitialValue(pkg)
        impl.WarmupCache(ctx)
    }

    private func CheckPrimaryCtorBeforeMerge(root: Node): Unit {
        try (recorder = ProfileRecorder("PrepareTypeCheck", "CheckPrimaryCtorBeforeMerge")) {
            if (root.TestAttr(Attribute.TOOL_ADD)) {
                return
            }
            let walker = Walker(root, visitPre: { node: Node =>
                if (let Some(file) <- (node as File)) {
                    for (decl in file.decls) {
                        if (let Some(inheritableDecl) <- (decl as InheritableDecl)) {
                            if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.STRUCT_DECL) {
                                CheckPrimaryCtorForClassOrStruct(inheritableDecl)
                            }
                        }
                    }
                    return VisitAction.SKIP_CHILDREN
                }
                return VisitAction.WALK_CHILDREN
            })
            let _ = walker.Walk()
        }
    }

    private func CheckPrimaryCtorForClassOrStruct(inheritableDecl: InheritableDecl): Unit {
        if (inheritableDecl.TestAttr(Attribute.IMPORTED)) {
            return
        }
        var primaryCtor = false
        var hasDesugared = false
        var target: Option<PrimaryCtorDecl> = None
        for (decl in inheritableDecl.GetMemberDecls()) {
            if (let Some(primaryCtorDecl) <- (decl as PrimaryCtorDecl)) {
                if (primaryCtor) {
                    let typeName = if (inheritableDecl.astKind == ASTKind.CLASS_DECL) { "class" } else { "struct" }
                    Diagnose(impl.diag.getOrThrow(), primaryCtorDecl,
                        BasicDiagKind.sema_multiple_primary_constructors,
                        args: [BasicDiagArgument(typeName),
                            BasicDiagArgument(inheritableDecl.identifier.Val())]).Emit()
                } else {
                    primaryCtor = true
                    target = primaryCtorDecl
                }
                if (let Some(funcBody) <- primaryCtorDecl.funcBody) {
                    if (funcBody.generic.isSome()) {
                        Diagnose(impl.diag.getOrThrow(), decl, BasicDiagKind.sema_forbid_generic_constructor,
                            args: [BasicDiagArgument(decl.identifier.Val())]).Emit()
                    }
                    if (funcBody.paramLists.size > 1) {
                        Diagnose(impl.diag.getOrThrow(), funcBody.paramLists[0],
                            BasicDiagKind.sema_cannot_currying,
                            args: [BasicDiagArgument("constructor")]).Emit()
                    }
                }
            }
            if (decl.TestAttr(Attribute.PRIMARY_CONSTRUCTOR) && decl.astKind == ASTKind.FUNC_DECL) {
                hasDesugared = true
            }
        }
        if (let Some(primaryCtorDecl) <- target) {
            if (!hasDesugared) {
                DesugarPrimaryCtor(inheritableDecl, primaryCtorDecl)
            }
        }
    }

    private func AddBuiltInArrayDecl(pkg: Package): Unit {
        let builtInDecl = BuiltInDecl(BuiltInType.ARRAY)
        builtInDecl.identifier = SrcIdentifier(RAW_ARRAY_NAME)
        let generic = Generic()
        let typeParameter = GenericParamDecl()
        typeParameter.identifier = SrcIdentifier("T")
        typeParameter.outerDecl = builtInDecl
        generic.typeParameters.add(typeParameter)
        builtInDecl.generic = generic
        builtInDecl.EnableAttr(Attribute.GLOBAL)
        builtInDecl.EnableAttr(Attribute.GENERIC)
        CopyFileID(builtInDecl, pkg.files[0])
        pkg.files[0].decls.add(builtInDecl)
    }

    private func AddBuiltInPointerDecl(pkg: Package): Unit {
        let builtInDecl = BuiltInDecl(BuiltInType.POINTER)
        builtInDecl.identifier = SrcIdentifier(CPOINTER_NAME)
        let generic = Generic()
        let typeParameter = GenericParamDecl()
        typeParameter.identifier = SrcIdentifier("T")
        typeParameter.outerDecl = builtInDecl
        generic.typeParameters.add(typeParameter)
        generic.genericConstraints.add(CreateConstraintForFFI(UtilsCTypeName))
        builtInDecl.generic = generic
        builtInDecl.EnableAttr(Attribute.PUBLIC)
        builtInDecl.EnableAttr(Attribute.GLOBAL)
        builtInDecl.EnableAttr(Attribute.GENERIC)
        CopyFileID(builtInDecl, pkg.files[0])
        pkg.files[0].decls.add(builtInDecl)
    }

    private func AddBuiltInCStringDecl(pkg: Package): Unit {
        let builtInDecl = BuiltInDecl(BuiltInType.CSTRING)
        builtInDecl.identifier = SrcIdentifier(CSTRING_NAME)
        builtInDecl.generic = None
        builtInDecl.EnableAttr(Attribute.PUBLIC)
        builtInDecl.EnableAttr(Attribute.GLOBAL)
        CopyFileID(builtInDecl, pkg.files[0])
        pkg.files[0].decls.add(builtInDecl)
    }

    private func AddBuiltInVArrayDecl(pkg: Package): Unit {
        let builtInDecl = BuiltInDecl(BuiltInType.VARRAY)
        builtInDecl.identifier = SrcIdentifier(VARRAY_NAME)
        let generic = Generic()
        let typeParameter = GenericParamDecl()
        typeParameter.identifier = SrcIdentifier("T")
        typeParameter.outerDecl = builtInDecl
        generic.typeParameters.add(typeParameter)
        builtInDecl.generic = generic
        builtInDecl.EnableAttr(Attribute.GLOBAL)
        builtInDecl.EnableAttr(Attribute.PUBLIC)
        builtInDecl.EnableAttr(Attribute.GENERIC)
        CopyFileID(builtInDecl, pkg.files[0])
        pkg.files[0].decls.add(builtInDecl)
    }

    private func AddBuiltinCFuncDecl(pkg: Package): Unit {
        let builtInDecl = BuiltInDecl(BuiltInType.CFUNC)
        builtInDecl.identifier = SrcIdentifier(CFUNC_NAME)
        let generic = Generic()
        let typeParameter = GenericParamDecl()
        typeParameter.identifier = SrcIdentifier("T")
        typeParameter.outerDecl = builtInDecl
        generic.typeParameters.add(typeParameter)
        builtInDecl.generic = generic
        builtInDecl.EnableAttr(Attribute.GLOBAL)
        builtInDecl.EnableAttr(Attribute.PUBLIC)
        builtInDecl.EnableAttr(Attribute.GENERIC)
        CopyFileID(builtInDecl, pkg.files[0])
        pkg.files[0].decls.add(builtInDecl)
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
            if (let Some(body) <- structDecl.body) {
                if (body.TestAttr(Attribute.IS_BROKEN)) {
                    return
                }
                AddDefaultCtorIfNeeded(structDecl)
                AddSetterGetterInProp(structDecl)
                for (member in body.decls) {
                    AddDefaultFunctionForDecl(member)
                }
            }
            return
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                if (body.TestAttr(Attribute.IS_BROKEN)) {
                    return
                }
                AddDefaultCtorIfNeeded(classDecl)
                AddSetterGetterInProp(classDecl)
                AddDefaultSuperCallForConstructors(classDecl)
                for (member in body.decls) {
                    AddDefaultFunctionForDecl(member)
                }
            }
            return
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            if (let Some(body) <- interfaceDecl.body) {
                if (body.TestAttr(Attribute.IS_BROKEN)) {
                    return
                }
                AddSetterGetterInProp(interfaceDecl)
                for (member in body.decls) {
                    AddDefaultFunctionForDecl(member)
                }
            }
            return
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            AddSetterGetterInProp(enumDecl)
            for (member in enumDecl.members) {
                AddDefaultFunctionForDecl(member)
            }
            return
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            AddSetterGetterInProp(extendDecl)
            for (member in extendDecl.members) {
                AddDefaultFunctionForDecl(member)
            }
        }
    }

    private func SetConstructorCalls(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                SetConstructorCallsForDecl(decl)
            }
        }
    }

    private func SetConstructorCallsForDecl(decl: Decl): Unit {
        if (let Some(structDecl) <- (decl as StructDecl)) {
            if (let Some(body) <- structDecl.body) {
                for (member in body.decls) {
                    if (let Some(funcDecl) <- (member as FuncDecl)) {
                        if (IsInstanceConstructor(funcDecl)) {
                            SetFuncDeclConstructorCall(funcDecl)
                        }
                    }
                    SetConstructorCallsForDecl(member)
                }
            }
            return
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                for (member in body.decls) {
                    if (let Some(funcDecl) <- (member as FuncDecl)) {
                        if (IsInstanceConstructor(funcDecl)) {
                            SetFuncDeclConstructorCall(funcDecl)
                        }
                    }
                    SetConstructorCallsForDecl(member)
                }
            }
            return
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            if (let Some(body) <- interfaceDecl.body) {
                for (member in body.decls) {
                    SetConstructorCallsForDecl(member)
                }
            }
            return
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            for (member in enumDecl.members) {
                SetConstructorCallsForDecl(member)
            }
            return
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            for (member in extendDecl.members) {
                SetConstructorCallsForDecl(member)
            }
        }
    }

    private func IsCoreObjectClass(classDecl: ClassDecl): Bool {
        var fullPackageName = ""
        if (let Some(fileValue) <- classDecl.curFile) {
            if (let Some(pkgValue) <- fileValue.curPackage) {
                fullPackageName = pkgValue.fullPackageName
            }
        }
        return classDecl.identifier.Val() == OBJECT_NAME && fullPackageName == UTILS_CORE_PACKAGE_NAME
    }

    private func AddDefaultSuperCallForConstructors(classDecl: ClassDecl): Unit {
        let classBody = if (let Some(bodyValue) <- classDecl.body) { bodyValue } else { return }
        for (member in classBody.decls) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (!IsInstanceConstructor(funcDecl)) {
                    continue
                }
                if (let Some(funcBody) <- funcDecl.funcBody) {
                    if (let Some(_) <- funcBody.body) {
                        SetFuncDeclConstructorCall(funcDecl)
                        let noConstructorCall = match (funcDecl.constructorCall) {
                            case ConstructorCall.NONE => true
                            case _ => false
                        }
                        if (noConstructorCall && !IsCoreObjectClass(classDecl)) {
                            AddDefaultSuperCall(funcBody)
                            funcDecl.constructorCall = ConstructorCall.SUPER
                        }
                    }
                }
            }
        }
    }

    private func AddDefaultSuperCall(funcBody: FuncBody): Unit {
        let block = if (let Some(bodyValue) <- funcBody.body) { bodyValue } else { return }
        let hasSuper = Box<Bool>(false)
        let walker = Walker(block, visitPre: { node: Node =>
            if (let Some(refExpr) <- (node as RefExpr)) {
                if (refExpr.isSuper && refExpr.isBaseFunc) {
                    hasSuper.value = true
                    return VisitAction.STOP_NOW
                }
            } else if (node.astKind == ASTKind.FUNC_BODY) {
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        if (hasSuper.value) {
            return
        }
        let superCall = CallExpr()
        CopyBasicInfo(funcBody, superCall)
        let superExpr = CreateRefExpr("super")
        superExpr.isSuper = true
        superExpr.isAlone = false
        CopyBasicInfo(funcBody, superExpr)
        superCall.baseFunc = superExpr
        superCall.EnableAttr(Attribute.COMPILER_ADD)
        if (block.body.isEmpty()) {
            superCall.begin = funcBody.begin
        }
        block.body.add(superCall, at: 0)
    }

    private func SetFuncDeclConstructorCall(fd: FuncDecl): Unit {
        let funcBody = if (let Some(value) <- fd.funcBody) { value } else { return }
        let body = if (let Some(value) <- funcBody.body) { value } else { return }
        if (body.body.isEmpty()) {
            return
        }
        var refExpr: Option<RefExpr> = None
        if (let Some(callExpr) <- (body.body[0] as CallExpr)) {
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                if (let Some(baseRef) <- (baseFunc as RefExpr)) {
                    refExpr = Some(baseRef)
                }
            }
        } else if (let Some(trailing) <- (body.body[0] as TrailingClosureExpr)) {
            if (let Some(desugar) <- trailing.desugarExpr) {
                if (let Some(callExpr) <- (desugar as CallExpr)) {
                    if (let Some(baseFunc) <- callExpr.baseFunc) {
                        if (let Some(baseRef) <- (baseFunc as RefExpr)) {
                            refExpr = Some(baseRef)
                        }
                    }
                } else if (let Some(baseRef) <- (desugar as RefExpr)) {
                    refExpr = Some(baseRef)
                }
            }
        }
        if (let Some(value) <- refExpr) {
            if (value.isThis && !fd.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) {
                fd.constructorCall = ConstructorCall.OTHER_INIT
            }
            if (value.isSuper) {
                fd.constructorCall = ConstructorCall.SUPER
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

    private func AddSetterGetterInProp(cld: InheritableDecl): Unit {
        for (member in cld.GetMemberDeclPtrs()) {
            if (member.astKind != ASTKind.PROP_DECL || member.TestAttr(Attribute.IMPORTED) ||
                member.TestAttr(Attribute.FROM_COMMON_PART)) {
                continue
            }
            if (!member.TestAttr(Attribute.ABSTRACT) && !IsCommonWithoutDefault(member)) {
                continue
            }
            let propDecl = (member as PropDecl).getOrThrow()
            let getter = FuncDecl()
            getter.propDecl = Some(propDecl)
            getter.identifier = SrcIdentifier("get")
            getter.isGetter = true
            getter.CloneAttrs(propDecl)
            getter.DisableAttr(Attribute.MUT)
            getter.EnableAttr(Attribute.IMPLICIT_ADD)
            getter.EnableAttr(Attribute.COMPILER_ADD)
            if (cld.astKind == ASTKind.INTERFACE_DECL) {
                getter.EnableAttr(Attribute.PUBLIC)
            }
            let getFuncParamList = FuncParamList()
            let getFuncBody = FuncBody()
            getFuncBody.paramLists.add(getFuncParamList)
            getter.funcBody = Some(getFuncBody)
            propDecl.getters.add(getter)
            if (!propDecl.isVar) {
                continue
            }
            let setter = FuncDecl()
            setter.propDecl = Some(propDecl)
            setter.isSetter = true
            setter.identifier = SrcIdentifier("set")
            setter.CloneAttrs(propDecl)
            setter.DisableAttr(Attribute.MUT)
            setter.EnableAttr(Attribute.IMPLICIT_ADD)
            if (cld.astKind == ASTKind.INTERFACE_DECL) {
                setter.EnableAttr(Attribute.PUBLIC)
            }
            let setFuncParamList = FuncParamList()
            let param = CreateFuncParam("set")
            setFuncParamList.params.add(param)
            let setFuncBody = FuncBody()
            setFuncBody.paramLists.add(setFuncParamList)
            setter.funcBody = Some(setFuncBody)
            propDecl.setters.add(setter)
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
        ret.EnableAttr(Attribute.PRIVATE)
        CollectGenericParam(funcDecl, ret)
        AddCurFile(ret, file: funcDecl.curFile)
        return ret
    }

    private func GetSingleParamFunc(funcDecl: FuncDecl): Unit {
        if (let None <- funcDecl.funcBody) {
            return
        }
        let funcBody = funcDecl.funcBody.getOrThrow()
        if (funcBody.paramLists.isEmpty() || funcDecl.TestAttr(Attribute.IMPORTED)) {
            return
        }
        let funcParams = ArrayList<FuncParam>()
        let isStatic = funcDecl.TestAttr(Attribute.STATIC)
        let walkFunc = { node: Node =>
            if (let Some(nestedFunc) <- (node as FuncDecl)) {
                if (isStatic) {
                    nestedFunc.EnableAttr(Attribute.STATIC)
                }
                GetSingleParamFunc(nestedFunc)
            }
            VisitAction.WALK_CHILDREN
        }
        let walkOrigin = { node: Node =>
            if (node.astKind == ASTKind.FUNC_DECL && isStatic) {
                node.EnableAttr(Attribute.STATIC)
            }
            VisitAction.WALK_CHILDREN
        }
        for (fp in funcBody.paramLists[0].params) {
            if (fp.assignment.isSome() && !fp.TestAttr(Attribute.HAS_INITIAL)) {
                if (funcDecl.op != TokenKind.ILLEGAL ||
                    funcDecl.TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT, Attribute.DEFAULT)) {
                    if (let Some(diagValue) <- impl.diag) {
                        DiagCannotHaveDefaultParam(diagValue, funcDecl, fp)
                    }
                    return
                }
                let desugarDecl = MakeDefaultParamFunction(fp, funcDecl, funcParams)
                fp.desugarDecl = Some(desugarDecl)
                let _ = Walker(desugarDecl, visitPre: walkFunc).Walk()
                if (let Some(assignment) <- fp.assignment) {
                    let _ = Walker(assignment, visitPre: walkOrigin).Walk()
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
        ctx.resolvedImplicitPackageMemberDeclsMap.clear()
        ctx.resolvedImportPackageNameMap.clear()
        ctx.resolvedPackageDeclMap.clear()
        ctx.resolvedCjoPackageMemberDeclsMap.clear()
        ctx.resolvedUsedMacroDeclsMap.clear()
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
            for (implicitPackageName in instance.resolvedImplicitPackageMemberDeclsMap.keys()) {
                if (let Some(implicitPackageMap) <- instance.resolvedImplicitPackageMemberDeclsMap.get(
                    implicitPackageName)) {
                    let ctxImplicitPackageMap = HashMap<String, Decl>()
                    for (name in implicitPackageMap.keys()) {
                        if (let Some(decl) <- implicitPackageMap.get(name)) {
                            ctxImplicitPackageMap[name] = decl
                        }
                    }
                    ctx.resolvedImplicitPackageMemberDeclsMap[implicitPackageName] = ctxImplicitPackageMap
                }
            }
            for (importSpec in instance.resolvedImportPackageNameMap.keys()) {
                if (let Some(packageNamePair) <- instance.resolvedImportPackageNameMap.get(importSpec)) {
                    ctx.resolvedImportPackageNameMap[importSpec] = packageNamePair
                }
            }
            for (packageDeclName in instance.resolvedPackageDeclMap.keys()) {
                if (let Some(packageDecl) <- instance.resolvedPackageDeclMap.get(packageDeclName)) {
                    ctx.resolvedPackageDeclMap[packageDeclName] = packageDecl
                }
            }
            for (cjoPackageName in instance.resolvedCjoPackageMemberDeclsMap.keys()) {
                if (let Some(packageMap) <- instance.resolvedCjoPackageMemberDeclsMap.get(cjoPackageName)) {
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
                    ctx.resolvedCjoPackageMemberDeclsMap[cjoPackageName] = ctxPackageMap
                }
            }
            for (fileIndex in instance.resolvedUsedMacroDeclsMap.keys()) {
                if (let Some(usedMacroDeclMap) <- instance.resolvedUsedMacroDeclsMap.get(fileIndex)) {
                    let ctxUsedMacroDeclMap = HashMap<String, ArrayList<Decl>>()
                    for (packageName in usedMacroDeclMap.keys()) {
                        if (let Some(decls) <- usedMacroDeclMap.get(packageName)) {
                            let copiedDecls = ArrayList<Decl>()
                            for (decl in decls) {
                                copiedDecls.add(decl)
                            }
                            ctxUsedMacroDeclMap[packageName] = copiedDecls
                        }
                    }
                    ctx.resolvedUsedMacroDeclsMap[fileIndex] = ctxUsedMacroDeclMap
                }
            }
        }
    }

    private func BuildImportedExtendMap(): Unit {
        let extends = ArrayList<ExtendDecl>()
        if (let Some(manager) <- impl.importManager) {
            for (packageDecl in manager.GetAllImportedPackages(true)) {
                if (packageDecl.srcPackage.TestAttr(Attribute.IMPORTED)) {
                    IterateToplevelDecls(packageDecl.srcPackage, { decl: Decl =>
                        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                            extends.add(extendDecl)
                        }
                    })
                }
            }
        }
        TypeCheckExtendUpdateExtendMap(impl.typeManager, extends)
    }

    private func IsTypeDeclKind(kind: ASTKind): Bool {
        return kind == ASTKind.CLASS_DECL || kind == ASTKind.STRUCT_DECL || kind == ASTKind.ENUM_DECL ||
            kind == ASTKind.INTERFACE_DECL || kind == ASTKind.EXTEND_DECL || kind == ASTKind.BUILTIN_DECL
    }

    private func IsMemberDeclKind(kind: ASTKind): Bool {
        return kind == ASTKind.FUNC_DECL || kind == ASTKind.PROP_DECL || kind == ASTKind.VAR_DECL
    }

    private func GetTypeDecl(decl: Decl): Decl {
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(target) <- extendedType.GetTarget()) {
                    return GetRealTarget(target)
                }
                if (let Some(ty) <- extendedType.GetTy()) {
                    return impl.typeManager.GetDummyBuiltInDecl(ty)
                }
            }
        }
        return decl
    }

    private func GetTypeDeclOfMember(decl: Decl): Decl {
        if (let Some(outer) <- decl.outerDecl) {
            return GetTypeDecl(outer)
        }
        return decl
    }

    private func MemDecl2Sig(decl: Decl): MemSig {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            let arity = if (funcDecl.TestAttr(Attribute.IMPORTED)) {
                UInt64(GetParamTys(funcDecl).size)
            } else if (let Some(body) <- funcDecl.funcBody) {
                if (!body.paramLists.isEmpty()) {
                    UInt64(body.paramLists[0].params.size)
                } else {
                    0u64
                }
            } else {
                0u64
            }
            let genArity = if (let Some(generic) <- funcDecl.generic) {
                UInt64(generic.typeParameters.size)
            } else {
                0u64
            }
            return MemSig(funcDecl.identifier.Val(), false, arity, genArity)
        }
        return MemSig(decl.identifier.Val(), true, 0u64, 0u64)
    }

    private func CollectDeclsWithMember(pkg: Package, ctx: ASTContext): Unit {
        ctx.mem2Decls.clear()
        ctx.subtypeDeclsMap.clear()
        let allTops = ArrayList<Decl>()
        let processedDecls = ArrayList<Decl>()
        let collectDecl = { top: Decl =>
            var alreadyProcessed = false
            for (processed in processedDecls) {
                if (SameDecl(processed, top)) {
                    alreadyProcessed = true
                    break
                }
            }
            if (!alreadyProcessed) {
                processedDecls.add(top)
                if (IsTypeDeclKind(top.astKind)) {
                    var foundTop = false
                    for (existingTop in allTops) {
                        if (SameDecl(existingTop, top)) {
                            foundTop = true
                            break
                        }
                    }
                    if (!foundTop) {
                        allTops.add(top)
                    }
                }
                for (member in top.GetMemberDecls()) {
                    if (!IsMemberDeclKind(member.astKind)) {
                        continue
                    }
                    let sig = MemDecl2Sig(member)
                    let topDecl = GetTypeDeclOfMember(member)
                    ctx.AddMemDecl(sig, topDecl)
                    if (sig.genArity > 0u64) {
                        ctx.AddMemDecl(MemSig(sig.id, sig.isVarOrProp, sig.arity, 0u64), topDecl)
                    }
                }
            }
        }
        for (sym in impl.GetAllDecls(ctx)) {
            if (let Some(node) <- sym.node) {
                if (let Some(decl) <- (node as Decl)) {
                    collectDecl(decl)
                }
            }
        }
        if (let Some(manager) <- impl.importManager) {
            for (file in pkg.files) {
                for (decl in manager.GetAllImportedDecls(file)) {
                    collectDecl(decl)
                }
            }
        }
        for (entry in impl.typeManager.builtinTyToExtendMap) {
            for (top in entry.extends) {
                collectDecl(top)
            }
        }
        for (top in allTops) {
            let realTop = GetTypeDecl(top)
            if (let Some(inheritable) <- (top as InheritableDecl)) {
                for (superDecl in inheritable.GetAllSuperDecls()) {
                    if (!ctx.subtypeDeclsMap.contains(superDecl)) {
                        ctx.subtypeDeclsMap[superDecl] = ArrayList<Decl>()
                    }
                    if (let Some(subtypes) <- ctx.subtypeDeclsMap.get(superDecl)) {
                        var foundSubtype = false
                        for (subtype in subtypes) {
                            if (SameDecl(subtype, realTop)) {
                                foundSubtype = true
                                break
                            }
                        }
                        if (!foundSubtype) {
                            subtypes.add(realTop)
                        }
                    }
                }
            }
        }
    }

    private func BuildCurrentPackageExtendMap(ctx: ASTContext): Unit {
        let extends = ArrayList<ExtendDecl>()
        for (sym in impl.GetSymsByASTKind(ctx, ASTKind.EXTEND_DECL, order: SearchOrder.POS_ASC)) {
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
                if (let Some(diagValue) <- impl.diag) {
                    PreCheckAnnoForFFI(pkg, diagValue)
                } else {
                    PreCheckAnnoForFFI(pkg)
                }
                let _ = CheckDeclAttributesForPackage(pkg, impl.diag.getOrThrow(), opts: GlobalOptions())
                let _ = PreCheckPackage(ctx, pkg, typeManager: impl.typeManager,
                    importManager: impl.importManager, diag: impl.diag)
                // C2e[A]: overload-conflict detection runs after PreCheckPackage so parameter types
                // are resolved (the func return type may still be uninferred, matching C++).
                if (let Some(diagValue) <- impl.diag) {
                    PreCheckFuncRedefinition(pkg, impl.GetSymsByASTKind(ctx, ASTKind.FUNC_DECL), diagValue,
                        impl.typeManager)
                }
                CheckReturnAndJump(ctx)
            }
        }
        impl.typeManager.ClearMapCache()
    }

    // C++ src/Sema/PreCheck.cpp:1692-1707 GetDanglingReturn.
    private func GetDanglingReturn(fp: FuncParam): Option<ReturnExpr> {
        let assignment = fp.assignment ?? return None
        let result = Box<Option<ReturnExpr>>(None)
        let walker = Walker(assignment, visitPre: { node: Node =>
            if (node.astKind == ASTKind.FUNC_BODY) {
                return VisitAction.SKIP_CHILDREN
            } else if (let Some(returnExpr) <- (node as ReturnExpr)) {
                result.value = Some(returnExpr)
                return VisitAction.STOP_NOW
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        return result.value
    }

    // C++ src/Sema/PreCheck.cpp:1710-1749 TypeChecker::TypeCheckerImpl::CheckReturnAndJump.
    private func CheckReturnAndJump(ctx: ASTContext): Unit {
        let diag = impl.diag.getOrThrow()
        for (sym in impl.GetSymsByASTKind(ctx, ASTKind.RETURN_EXPR)) {
            let node = sym.node.getOrThrow()
            let returnExpr = (node as ReturnExpr).getOrThrow()
            if (let Some(refFuncBody) <- GetCurFuncBody(ctx, sym.scopeName)) {
                if (let Some(funcDecl) <- refFuncBody.funcDecl) {
                    if (IsStaticInitializer(funcDecl)) {
                        returnExpr.SetTy(TypeManager.GetInvalidTy())
                        diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_invalid_return_in_static_init,
                            MakeRange(node.begin, node.end)).Emit()
                        continue
                    }
                }
                returnExpr.refFuncBody = Some(refFuncBody)
            } else {
                returnExpr.SetTy(TypeManager.GetInvalidTy())
                diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_invalid_return,
                    MakeRange(node.begin, node.end)).Emit()
            }
        }
        for (sym in impl.GetSymsByASTKind(ctx, ASTKind.FUNC_PARAM)) {
            let param = (sym.node.getOrThrow() as FuncParam).getOrThrow()
            if (let Some(returnExpr2) <- GetDanglingReturn(param)) {
                returnExpr2.refFuncBody = None
                returnExpr2.SetTy(TypeManager.GetInvalidTy())
                diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_invalid_return,
                    MakeRange(returnExpr2.begin, returnExpr2.end)).Emit()
            }
        }
        for (sym in impl.GetSymsByASTKind(ctx, ASTKind.JUMP_EXPR)) {
            let node2 = sym.node.getOrThrow()
            if (let None <- GetRefLoopSymbol(ctx, node2)) {
                diag.Diagnose(node2.begin, node2.end, BasicDiagKind.sema_invalid_loop_control).Emit()
                node2.SetTy(TypeManager.GetInvalidTy())
            }
        }
    }

    private func CheckCHIRClassDependencies(): Unit {
        if (let None <- ci) {
            return
        }
        let instance = ci.getOrThrow()
        if (!instance.globalOptions.chirCC || instance.globalOptions.implicitPrelude) {
            return
        }
        let objectDecl: Option<Decl> = if (let Some(manager) <- impl.importManager) {
            manager.GetImportedDecl<Decl>(UTILS_CORE_PACKAGE_NAME, "Object")
        } else {
            None
        }
        if (let None <- objectDecl) {
            if (let Some(diagValue) <- impl.diag) {
                diagValue.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_core_object_not_found_when_no_prelude,
                    BasicDefaultPosition).Emit()
            }
        }
    }

    private func UpdateAnyTy(): Unit {
        if (let Some(manager) <- impl.importManager) {
            if (let Some(interfaceDecl) <- manager.GetCoreDecl<InterfaceDecl>("Any")) {
                if (Ty.IsTyCorrect(interfaceDecl.GetTy())) {
                    impl.typeManager.SetSemaAnyTy(interfaceDecl.GetTy().getOrThrow())
                }
            }
        }
    }

    private func UpdateCTypeTy(): Unit {
        if (let Some(instance) <- ci) {
            if (!instance.globalOptions.implicitPrelude) {
                return
            }
        }
        if (let Some(manager) <- impl.importManager) {
            if (let Some(interfaceDecl) <- manager.GetCoreDecl<InterfaceDecl>(UtilsCTypeName)) {
                if (Ty.IsTyCorrect(interfaceDecl.GetTy())) {
                    impl.typeManager.SetSemaCTypeTy(interfaceDecl.GetTy().getOrThrow())
                }
            }
        }
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
        let activePkgs = ArrayList<Package>()
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                activePkgs.add(pkg)
            }
        }
        for (ctx in activeContexts) {
            if (let Some(pkg) <- contextPackage(ctx)) {
                let manager = impl.importManager.getOrThrow()
                if (let Some(diagValue) <- impl.diag) {
                    let _ = ReportUnusedImports(pkg, diagValue, manager)
                } else {
                    let _ = CollectUnusedImports(pkg, manager)
                }
                RunInheritanceCheck(pkg)
                SetConstructorCalls(pkg)
                // Check legality of usage after sema type completed.
                // Mirrors C++ TypeChecker.cpp:2053 (CheckLegalityOfUsage).
                RunLegalityOfUsageCheck(ctx, pkg)
                // C++ TypeChecker.cpp:2060-2062 desugars property access in sema before const checking.
                DesugarForPropDecl(impl.typeManager, pkg)
                let _ = CheckConstEvaluation(pkg, impl.diag.getOrThrow())
                PerformDesugarAfterTypeCheck(impl.typeManager, pkg, context: Some(ctx), options: GlobalOptions(),
                    synthesizer: Some({ synCtx: ASTContext, pos: SynPos, node: Node =>
                        SynthesizeWithoutRecover(synCtx, pos, node)
                    }), diag: impl.diag)
                DesugarAfterInstantiation(impl.typeManager, recursivePkgs, pkg,
                    implicitUsedDecls: Some(implicitUsedDecls))
                CollectMainFunctionsFromMainDecls(pkg)
            }
        }
        GenerateMainInvoke()
        substituteImportedTypeAliasTy(impl.typeManager, recursivePkgs)
        CheckWhetherHasProgramEntry()
    }

    private func CreateConvInt64(vd: VarDecl, ty: Ty): TypeConvExpr {
        let convType = PrimitiveType()
        convType.kind = TypeKind.TYPE_INT64
        convType.SetTy(ty)
        let numConv = TypeConvExpr()
        numConv.typeNode = convType
        let refExpr = CreateRefExpr(vd)
        refExpr.SetTy(ty)
        numConv.expr = refExpr
        numConv.SetTy(ty)
        return numConv
    }

    private func CreateMainInvokeDecl(funcBody: FuncBody, mainFunc: FuncDecl, funcTy: Ty): FuncDecl {
        let mainInvokeFunc = FuncDecl()
        funcBody.funcDecl = mainInvokeFunc
        mainInvokeFunc.toBeCompiled = mainFunc.toBeCompiled
        mainInvokeFunc.SetTy(funcTy)
        mainInvokeFunc.identifier = SrcIdentifier(MAIN_INVOKE)
        mainInvokeFunc.funcBody = funcBody
        mainInvokeFunc.moduleName = mainFunc.moduleName
        mainInvokeFunc.fullPackageName = mainFunc.fullPackageName
        mainInvokeFunc.EnableAttr(Attribute.GLOBAL)
        AddCurFile(mainInvokeFunc, file: mainFunc.curFile)
        if (mainFunc.TestAttr(Attribute.INCRE_COMPILE)) {
            mainInvokeFunc.EnableAttr(Attribute.INCRE_COMPILE)
        }
        return mainInvokeFunc
    }

    private func CollectMainFunctionsFromMainDecls(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(mainDecl) <- (decl as MainDecl)) {
                    if (let Some(mainFunc) <- mainDecl.desugarDecl) {
                        AddMainFunction(file, mainFunc)
                    }
                }
            }
            for (decl2 in file.exportedInternalDecls) {
                if (let Some(mainDecl2) <- (decl2 as MainDecl)) {
                    if (let Some(mainFunc2) <- mainDecl2.desugarDecl) {
                        AddMainFunction(file, mainFunc2)
                    }
                }
            }
        }
    }

    private func AddMainFunction(file: File, decl: Decl): Unit {
        if (!mainFunctionMap.contains(file)) {
            mainFunctionMap[file] = ArrayList<Decl>()
        }
        for (value in mainFunctionMap[file]) {
            if (value.objectId == decl.objectId) {
                return
            }
        }
        mainFunctionMap[file].add(decl)
    }

    private func ContainsMainFunction(file: File, decl: Decl): Bool {
        if (let Some(values) <- mainFunctionMap.get(file)) {
            for (value in values) {
                if (value.objectId == decl.objectId) {
                    return true
                }
            }
        }
        return false
    }

    private func CheckEntryFunc(fd: FuncDecl): Unit {
        if (fd.curFile.isNone() || fd.curFile.getOrThrow().curPackage.isNone() || !fd.TestAttr(Attribute.GLOBAL)) {
            return
        }
        let file = fd.curFile.getOrThrow()
        if (let Some(diagValue) <- impl.diag) {
            if (file.isCommon) {
                let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_common_package_has_main,
                    MakeRange(fd.begin, fd.end))
                builder.Emit()
            }
            if (!mainFunctionMap.isEmpty() && (!mainFunctionMap.contains(file) || !ContainsMainFunction(file, fd))) {
                diagValue.Diagnose(fd.begin, fd.end, BasicDiagKind.sema_redefinition_entry).Emit()
            }
        }
        if (let Some(body) <- fd.funcBody) {
            if (let Some(retType) <- body.retType) {
                if (let Some(retTy) <- retType.GetTy()) {
                    if (Ty.IsTyCorrect(retTy) && !(retTy.IsInteger() || retTy.IsUnit())) {
                        if (let Some(diagValue2) <- impl.diag) {
                            diagValue2.Diagnose(fd.begin, fd.end,
                                BasicDiagKind.sema_unexpected_return_type_for_entry).Emit()
                        }
                    }
                }
            }
        }
        let body = match (fd.funcBody) {
            case Some(value) => value
            case None => return
        }
        if (body.paramLists.isEmpty()) {
            return
        }
        let params = body.paramLists[0].params
        var invalidParamTy = params.size > 1
        if (!invalidParamTy) {
            for (param in params) {
                let paramTy = param.GetTy()
                let isArrayTy = paramTy.isSome() && paramTy.getOrThrow().IsStructArray() &&
                    !paramTy.getOrThrow().typeArgs.isEmpty()
                let isArrayStringTy = isArrayTy && paramTy.getOrThrow().typeArgs[0].IsString()
                if (!isArrayStringTy) {
                    invalidParamTy = true
                    break
                }
            }
        }
        if (invalidParamTy) {
            if (let Some(diagValue3) <- impl.diag) {
                diagValue3.Diagnose(fd.begin, fd.end, BasicDiagKind.sema_unexpected_param_for_entry).Emit()
            }
        }
        AddMainFunction(file, fd)
    }

    private func GenerateMainInvoke(): Unit {
        if (mainFunctionMap.size != 1) {
            return
        }
        var mainFunctions: Option<ArrayList<Decl>> = None
        for (values in mainFunctionMap.values()) {
            mainFunctions = Some(values)
            break
        }
        if (let None <- mainFunctions) {
            return
        }
        let mainFunctionList = mainFunctions.getOrThrow()
        if (mainFunctionList.size != 1) {
            return
        }
        let mainFunc = if (let Some(value) <- (mainFunctionList[0] as FuncDecl)) {
            value
        } else {
            return
        }
        let mainFile = if (let Some(value2) <- mainFunc.curFile) {
            value2
        } else {
            return
        }
        let packageHasMain = if (let Some(value3) <- mainFile.curPackage) {
            value3
        } else {
            return
        }
        let rawFuncTy = if (let Some(value4) <- mainFunc.GetTy()) {
            value4
        } else {
            return
        }
        let funcTy = if (let Some(value5) <- (rawFuncTy as FuncTy)) {
            value5
        } else {
            return
        }
        var options = OptionGlobalOptions()
        if (let Some(instance) <- ci) {
            options = instance.globalOptions
        }
        let outputCHIR = options.outputMode == OptionOutputMode.CHIR
        let mainBody = if (let Some(value6) <- mainFunc.funcBody) {
            value6
        } else {
            return
        }
        if ((!options.CompileExecutable() && !outputCHIR) || packageHasMain.TestAttr(Attribute.IMPORTED) ||
            options.enIncrementalCompilation || !Ty.IsTyCorrect(funcTy.retTy) || mainBody.paramLists.isEmpty()) {
            return
        }

        let mainTy = funcTy.retTy
        let int64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let mainInvokeTy = impl.typeManager.GetFunctionTy(funcTy.paramTys.toArray(), int64Ty)
        let funcBody = FuncBody()
        funcBody.SetTy(mainInvokeTy)
        let block = Block()
        block.SetTy(mainInvokeTy)
        funcBody.body = block
        let funcParamList = FuncParamList()
        var argPtr: Option<VarDecl> = None
        if (!mainBody.paramLists[0].params.isEmpty()) {
            let param = mainBody.paramLists[0].params[0]
            var paramType: Option<Type> = None
            if (let Some(typeNode) <- param.typeNode) {
                paramType = ASTCloner.Clone(typeNode) as Type
            }
            let newParam = CreateFuncParam("v", paramType, None, param.GetTy())
            argPtr = newParam
            funcParamList.params.add(newParam)
        }
        funcBody.paramLists.add(funcParamList)

        let args = ArrayList<FuncArg>()
        if (let Some(argDecl) <- argPtr) {
            args.add(CreateFuncArg(CreateRefExpr(argDecl), "", argDecl.GetTy()))
        }
        let callMain = CreateCallExpr(CreateRefExpr(mainFunc), args, mainFunc, mainTy, CallKind.CALL_DECLARED_FUNCTION)
        let retVal = CreateVarDecl("retVal", callMain, None)
        let retExpr = if (mainTy.IsInteger()) {
            CreateReturnExpr(CreateConvInt64(retVal, int64Ty), funcBody)
        } else {
            CreateReturnExpr(CreateLitConstExpr(LitConstKind.INTEGER, "0", int64Ty), funcBody)
        }
        retExpr.SetTy(TypeManager.GetNothingTy())
        block.body.add(retVal)
        block.body.add(retExpr)
        mainFile.decls.add(CreateMainInvokeDecl(funcBody, mainFunc, mainInvokeTy))
    }

    private func CheckWhetherHasProgramEntry(): Unit {
        if (let None <- ci) {
            return
        }
        let instance = ci.getOrThrow()
        if (!instance.globalOptions.CompileExecutable() || instance.globalOptions.enableCompileTest ||
            instance.frontendDumpActionIsTypeCheck || !mainFunctionMap.isEmpty() || instance.globalOptions.compileCjd) {
            return
        }
        if (instance.sourcePackages.isEmpty() || instance.sourcePackages[0].files.isEmpty()) {
            return
        }
        if (let Some(diagValue) <- impl.diag) {
            let file = instance.sourcePackages[0].files[0]
            let builder = diagValue.Diagnose(file.begin, BasicDiagKind.sema_missing_entry)
            builder.Emit()
        }
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
            for ((className, memberName) in [
                ("OutOfMemoryError", "init"), ("Exception", "printStackTrace"), ("Error", "printStackTrace")
            ]) {
                let decl = match (findCoreImplicitMemberDeclInMap(instance, className, memberName)) {
                    case Some(value) => Some(value)
                    case None => findCoreImplicitMemberDeclInPackages(instance.packageDecls, className, memberName)
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
            StructInheritanceChecker(
                diagValue,
                impl.typeManager,
                pkg,
                impl.importManager.getOrThrow(),
                opts: GlobalOptions()
            ).Check()
        }
    }

    private func RunLegalityOfUsageCheck(ctx: ASTContext, pkg: Package): Unit {
        if (let Some(diagValue) <- impl.diag) {
            let result = CheckLegalityOfUsage(ctx, pkg, diagValue, impl.typeManager, opts: GlobalOptions())
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
        ctx.ClearTypeCheckCache(node)
        ctx.SkipSynForCorrectTyRec(node)
        let ret = SynthesizeNode(ctx, pos, node)
        DesugarForPropDecl(impl.typeManager, node)
        return ret
    }

    private func SynthesizeNode(ctx: ASTContext, node: Node): Ty {
        return SynthesizeNode(ctx, SynPos.NONE, node)
    }

    private func SynthesizeNode(ctx: ASTContext, pos: SynPos, node: Node): Ty {
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
            return Synthesize(ctx, pos, expr)
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
            let _ = Synthesize(ctx, SynPos.EXPR_ARG, expr)
            if (arg.withInout) {
                if (!Ty.IsTyCorrect(expr.GetTy()) || !ChkInoutFuncArg(arg)) {
                    arg.SetTy(TypeManager.GetInvalidTy())
                } else if (!Ty.IsMetCType(expr.GetTy().getOrThrow())) {
                    if (let Some(diagValue) <- impl.diag) {
                        DiagnoseRefactor(diagValue, BasicDiagKindRefactor.sema_inout_modify_non_ctype, arg).Emit()
                    }
                    arg.SetTy(TypeManager.GetInvalidTy())
                } else if (expr.GetTy().getOrThrow().IsCString()) {
                    if (let Some(diagValue2) <- impl.diag) {
                        DiagnoseRefactor(diagValue2,
                            BasicDiagKindRefactor.sema_inout_modify_cstring_or_zerosized,
                            arg, "type 'CString'").Emit()
                    }
                    arg.SetTy(TypeManager.GetInvalidTy())
                } else if (let Some(varrayTy) <- (expr.GetTy().getOrThrow() as VArrayTy)) {
                    arg.SetTy(impl.typeManager.GetPointerTy(varrayTy.typeArgs[0]))
                } else {
                    arg.SetTy(impl.typeManager.GetPointerTy(expr.GetTy().getOrThrow()))
                }
            } else {
                arg.SetTy(expr.GetTy() ?? TypeManager.GetInvalidTy())
            }
        } else {
            arg.SetTy(TypeManager.GetInvalidTy())
        }
        return arg.GetTy() ?? TypeManager.GetInvalidTy()
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

    private func CheckThisTypeOfFuncBody(fb: FuncBody): Bool {
        let retType = fb.retType.getOrThrow()
        var returnThis = retType.astKind == ASTKind.THIS_TYPE
        if (!returnThis) {
            if (let Some(refType) <- (retType as RefType)) {
                returnThis = refType.ref.identifier.Val() == "This"
            }
        }
        if (returnThis) {
            if (let Some(funcDecl) <- fb.funcDecl) {
                if (funcDecl.TestAttr(Attribute.STATIC)) {
                    return false
                }
            }
        }
        return true
    }

    private func CheckBodyRetType(ctx: ASTContext, fb: FuncBody): Bool {
        let retType = fb.retType.getOrThrow()
        let retTy = retType.GetTy().getOrThrow()
        if (let None <- fb.body) {
            if (retTy.HasQuestTy()) {
                retType.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            return true
        }
        let body = fb.body.getOrThrow()
        if (retTy.IsQuest()) {
            let ret = Synthesize(ctx, SynPos.NONE, body)
            if ((let None <- fb.funcDecl) && !Ty.IsTyCorrect(ret)) {
                retType.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            retType.SetTy(CalcFuncRetTyFromBody(fb))
            var isWellTyped = Ty.IsTyCorrect(retType.GetTy())
            if (retType.GetTy().getOrThrow().HasQuestTy()) {
                isWellTyped = false
                retType.SetTy(TypeManager.GetInvalidTy())
                if (!CanSkipDiag(fb)) {
                    if (let Some(diagValue) <- impl.diag) {
                        DiagUnableToInferReturnType(diagValue, fb)
                    }
                }
            }
            if (isWellTyped) {
                if (CheckReturnThisInFuncBody(fb)) {
                    ReplaceFuncRetTyWithThis(fb, retType.GetTy().getOrThrow())
                } else if (let Some(classThisTy) <- (retType.GetTy().getOrThrow() as ClassThisTy)) {
                    retType.SetTy(classThisTy.declPtr.getOrThrow().GetTy().getOrThrow())
                }
            }
            return isWellTyped
        } else {
            var isWellTyped = true
            if (retTy.IsUnit()) {
                isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.UNUSED, body))
            } else if (NeedCheckBodyReturn(fb)) {
                isWellTyped = Check(ctx, retTy, body)
                if (!isWellTyped && body.body.isEmpty()) {
                    if (let Some(diagValue2) <- impl.diag) {
                        DiagMismatchedTypes(diagValue2, body, retType, because: "return type")
                    }
                }
                if (isWellTyped && (retType.GetTy().getOrThrow() as ClassThisTy).isSome()) {
                    var node = body.body[body.body.size - 1]
                    while (true) {
                        if (let Some(expr) <- (node as Expr)) {
                            if (let Some(desugarExpr) <- expr.desugarExpr) {
                                node = desugarExpr
                                continue
                            }
                        }
                        break
                    }
                    let kind = node.astKind
                    if (kind != ASTKind.CALL_EXPR && kind != ASTKind.MEMBER_ACCESS && kind != ASTKind.REF_EXPR &&
                        kind != ASTKind.RETURN_EXPR && kind != ASTKind.PAREN_EXPR) {
                        body.SetTy(impl.typeManager.GetThisRealTy(body.GetTy().getOrThrow()))
                    }
                    if (!CheckReturnThisInFuncBody(fb) && !retType.GetTy().getOrThrow().IsNothing()) {
                        if (let Some(diagValue3) <- impl.diag) {
                            DiagMismatchedTypes(diagValue3, body, retType, because: "return type")
                        }
                        isWellTyped = false
                    }
                }
            }
            return isWellTyped
        }
    }

    private func ReplaceFuncRetTyWithThis(fb: FuncBody, ty: Ty): Unit {
        if (let Some(classTy) <- (ty as ClassTy)) {
            let refType = RefType()
            refType.curFile = fb.curFile
            if (let Some(classDecl) <- classTy.decl) {
                refType.ref.target = Some(classDecl)
            }
            refType.ref.identifier = SrcIdentifier("This")
            refType.SetTy(impl.typeManager.GetClassThisTy(classTy.declPtr.getOrThrow(), classTy.typeArgs.toArray()))
            refType.EnableAttr(Attribute.COMPILER_ADD)
            if (let Some(oldRetType) <- fb.retType) {
                fb.curFile.getOrThrow().trashBin.add(oldRetType)
            }
            fb.retType = Some(refType)
        }
    }

    private func CheckFuncBody(ctx: ASTContext, fb: FuncBody): Bool {
        if (let Some(retType) <- fb.retType) {
            let _ = SynthesizeNode(ctx, SynPos.NONE, retType)
        } else {
            AddRetTypeNode(fb)
        }

        if (let Some(funcDecl) <- fb.funcDecl) {
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                CheckCtorFuncBody(ctx, fb)
                return true
            }
        }

        if (!CheckThisTypeOfFuncBody(fb)) {
            if (let Some(diagValue) <- impl.diag) {
                let retType2 = fb.retType.getOrThrow()
                diagValue.Diagnose(
                    retType2.begin,
                    retType2.end,
                    BasicDiagKind.sema_invalid_position_of_this_type).Emit()
            }
        }
        let paramTys = ArrayList<Ty>()
        if (!CheckNormalFuncBody(ctx, fb, paramTys)) {
            return false
        }
        return true
    }

    private func AddRetTypeNode(fb: FuncBody): Unit {
        if (let None <- fb.retType) {
            fb.retType = Some(RefType())
        }
        let retType = fb.retType.getOrThrow()
        retType.EnableAttr(Attribute.COMPILER_ADD)
        retType.SetTy(TypeManager.GetQuestTy())
        retType.EnableAttr(Attribute.IS_CHECK_VISITED)
    }

    private func CheckNormalFuncBody(ctx: ASTContext, fb: FuncBody, paramTys: ArrayList<Ty>): Bool {
        if (fb.paramLists.isEmpty()) {
            return false
        }
        CheckFuncParamList(ctx, fb.paramLists[0])
        paramTys.clear()
        let funcBodyParamTys = GetFuncBodyParamTys(fb)
        for (paramTy in funcBodyParamTys) {
            paramTys.add(paramTy)
        }

        let isCFFIBackend = OptionIsUnsafeBackend(GlobalOptions().backend)
        var isCFunc = fb.TestAttr(Attribute.C)
        if (!isCFunc) {
            if (let Some(funcDecl) <- fb.funcDecl) {
                isCFunc = funcDecl.TestAttr(Attribute.FOREIGN) && isCFFIBackend
            }
        }
        var hasVariableLenArg = fb.paramLists[0].hasVariableLenArg
        if (let Some(funcDecl2) <- fb.funcDecl) {
            hasVariableLenArg = funcDecl2.hasVariableLenArg || hasVariableLenArg
        }
        let cfg = FuncTyConfig()
        cfg.isC = isCFunc
        cfg.hasVariableLenArg = hasVariableLenArg
        let retType = fb.retType.getOrThrow()
        if (!Ty.IsTyCorrect(retType.GetTy())) {
            if (!fb.TestAttr(Attribute.IS_CHECK_VISITED)) {
                fb.EnableAttr(Attribute.IS_CHECK_VISITED)
                let _ = Synthesize(ctx, SynPos.NONE, fb.body.getOrThrow())
            }
            fb.SetTy(impl.typeManager.GetFunctionTy(paramTys.toArray(), retType.GetTy().getOrThrow(), cfg: cfg))
            return false
        }

        var funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retType.GetTy().getOrThrow(), cfg: cfg)
        if (let Some(funcDecl3) <- fb.funcDecl) {
            funcDecl3.SetTy(funcTy)
        }
        fb.SetTy(funcTy)

        if (!CheckBodyRetType(ctx, fb)) {
            fb.SetTy(impl.typeManager.GetFunctionTy(paramTys.toArray(), retType.GetTy().getOrThrow(), cfg: cfg))
            return false
        }

        if (isCFFIBackend) {
            UnsafeCheck(fb)
        }

        funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retType.GetTy().getOrThrow(), cfg: cfg)
        if (let Some(funcDecl4) <- fb.funcDecl) {
            funcDecl4.SetTy(funcTy)
        }
        fb.SetTy(funcTy)
        return true
    }

    private func CheckReturnThisInFuncBody(fb: FuncBody): Bool {
        let checkExprType = Box<(Expr) -> Bool>({ _: Expr => false })
        checkExprType.value = { expr: Expr =>
            var curExpr = expr
            while (let Some(desugarExpr) <- curExpr.desugarExpr) {
                curExpr = desugarExpr
            }
            if (let Some(refExpr) <- (curExpr as RefExpr)) {
                return refExpr.isThis
            } else if (let Some(callExpr) <- (curExpr as CallExpr)) {
                if (let Some(resolvedFunction) <- callExpr.resolvedFunction) {
                    var isMemberCall = false
                    if (let Some(baseFunc) <- callExpr.baseFunc) {
                        isMemberCall = (baseFunc as RefExpr).isSome()
                        if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                                isMemberCall = IsThisOrSuper(baseExpr)
                            }
                        }
                    }
                    return isMemberCall && IsFuncReturnThisType(resolvedFunction)
                }
            } else if (let Some(parenExpr) <- (curExpr as ParenExpr)) {
                return checkExprType.value(parenExpr.expr.getOrThrow())
            }

            let returnThis = Box<Bool>(false)
            let walker = Walker(curExpr, visitPre: { node: Node =>
                if (node.astKind != ASTKind.RETURN_EXPR) {
                    return VisitAction.WALK_CHILDREN
                }
                let returnExpr = (node as ReturnExpr).getOrThrow()
                returnThis.value = checkExprType.value(returnExpr.expr.getOrThrow())
                VisitAction.SKIP_CHILDREN
            })
            let _ = walker.Walk()
            return returnThis.value
        }
        if (let Some(body) <- fb.body) {
            if (!body.body.isEmpty()) {
                let lastNode = body.body[body.body.size - 1]
                if (let Some(lastExpr) <- (lastNode as Expr)) {
                    var expr = lastExpr
                    while (let Some(desugarExpr) <- expr.desugarExpr) {
                        expr = desugarExpr
                    }
                    if (let Some(parentClassLike) <- fb.parentClassLike) {
                        return checkExprType.value(expr) && (parentClassLike as ClassDecl).isSome()
                    }
                }
            }
        }
        return false
    }

    private func CheckCtorFuncBody(ctx: ASTContext, fb: FuncBody): Unit {
        let funcDecl = fb.funcDecl.getOrThrow()
        if (let Some(parentClassLike) <- fb.parentClassLike) {
            if (let Some(attr) <- HasJavaAttr(parentClassLike)) {
                funcDecl.EnableAttr(attr)
            }
        }
        var ctorTy: Ty = TypeManager.GetInvalidTy()
        if (funcDecl.TestAttr(Attribute.STATIC)) {
            ctorTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        } else {
            if (let Some(parentStruct) <- fb.parentStruct) {
                ctorTy = parentStruct.GetTy() ?? TypeManager.GetInvalidTy()
            }
            if (let Some(parentClassLike2) <- fb.parentClassLike) {
                ctorTy = parentClassLike2.GetTy() ?? TypeManager.GetInvalidTy()
            }
        }
        if (!Ty.IsTyCorrect(ctorTy) || fb.paramLists.isEmpty()) {
            return
        }
        CheckFuncParamList(ctx, fb.paramLists[0])
        let paramTys = GetFuncBodyParamTys(fb)
        let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), ctorTy)
        fb.SetTy(funcTy)
        funcDecl.SetTy(funcTy)
        fb.retType.getOrThrow().SetTy(ctorTy)
        let _ = match (fb.body) {
            case Some(body) => SynthesizeBlock(ctx, SynPos.UNUSED, body)
            case None => TypeManager.GetInvalidTy()
        }
    }

    private func UnsafeCheck(fb: FuncBody): Unit {
        if (let Some(funcDecl) <- fb.funcDecl) {
            if (funcDecl.TestAttr(Attribute.FOREIGN) || funcDecl.TestAttr(Attribute.C)) {
                CJC_ASSERT(!fb.paramLists.isEmpty())
                if (let Some(diagValue) <- impl.diag) {
                    for (param in fb.paramLists[0].params) {
                        CheckCFuncParam(param, diagValue)
                    }
                    let retType = fb.retType.getOrThrow()
                    if (!Ty.IsTyCorrect(retType.GetTy())) {
                        return
                    }
                    let retTy = retType.GetTy().getOrThrow()
                    if (!Ty.IsMetCType(retTy)) {
                        let builder = diagValue.DiagnoseRefactor(
                            BasicDiagKindRefactor.sema_invalid_cfunc_return_type,
                            GetFuncBodyRange(fb, retType))
                        builder.AddNote("return type is " + retTy.String())
                        builder.Emit()
                    } else if ((retTy as VArrayTy).isSome()) {
                        let builder = diagValue.DiagnoseRefactor(
                            BasicDiagKindRefactor.sema_varray_in_cfunc,
                            GetFuncBodyRange(fb, retType))
                        builder.Emit()
                    }
                }
            }
        }
    }

    private func CheckFuncParamList(ctx: ASTContext, fpl: FuncParamList): Unit {
        let paramTys = ArrayList<Ty>()
        if (fpl.params.isEmpty()) {
            fpl.SetTy(impl.typeManager.GetTupleTy(paramTys.toArray()))
            return
        }
        for (param in fpl.params) {
            if (!Ty.IsTyCorrect(SynthesizeNode(ctx, SynPos.NONE, param))) {
                paramTys.add(TypeManager.GetInvalidTy())
                continue
            }
            let paramTy = param.GetTy() ?? TypeManager.GetInvalidTy()
            paramTys.add(paramTy)
            if (let Some(assignment) <- param.assignment) {
                var curExpr = assignment
                while (let Some(desugarExpr) <- curExpr.desugarExpr) {
                    curExpr = desugarExpr
                }
                let _ = Check(ctx, paramTy, curExpr)
                if (Ty.IsTyCorrect(curExpr.GetTy())) {
                    assignment.SetTy(curExpr.GetTy().getOrThrow())
                }
            }
        }
        fpl.SetTy(impl.typeManager.GetTupleTy(paramTys.toArray()))
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
        return fp.GetTy() ?? TypeManager.GetInvalidTy()
    }

    private func SynthesizePropDecl(ctx: ASTContext, pd: PropDecl): Ty {
        let propTy = CheckPropDecl(pd,
            { typeNode: Type =>
                SynthesizeTypeNode(ctx, Some(typeNode))
                typeNode.GetTy() ?? TypeManager.GetInvalidTy()
            },
            { decl: Decl => SynthesizeDecl(ctx, decl) },
            diag: impl.diag)
        BindLocalDeclIfNeeded(ctx, pd)
        return propTy
    }

    private func SynthesizeDecl(ctx: ASTContext, decl: Decl): Ty {
        // Mirrors C++ TypeChecker.cpp:740-748: imported decls with a correct loaded type are already checked.
        if (decl.TestAttr(Attribute.IMPORTED) && Ty.IsTyCorrect(decl.GetTy()) && decl.TyKind() != TypeKind.TYPE_QUEST) {
            return decl.GetTy() ?? TypeManager.GetInvalidTy()
        }
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
                    if (let Some(diagValue) <- impl.diag) {
                        TypeCheckDeclDiagUnableToInferDecl(diagValue, vd)
                    }
                    vd.SetTy(TypeManager.GetInvalidTy())
                }
                return vd.GetTy() ?? TypeManager.GetInvalidTy()
            }
            vd.EnableAttr(Attribute.IS_CHECK_VISITED)
            SynthesizeTypeNode(ctx, vd.typeNode)
            if (let Some(initializer) <- vd.initializer) {
                if (let Some(typeNode) <- vd.typeNode) {
                    if (let None <- typeNode.GetTy()) {
                        let _ = Synthesize(ctx, initializer)
                    }
                } else {
                    let _ = Synthesize(ctx, initializer)
                    if (!Ty.IsTyCorrect(initializer.GetTy()) && !IsGlobalOrMember(vd)) {
                        vd.DisableAttr(Attribute.IS_CHECK_VISITED)
                    }
                }
            }
            let declTy = TypeCheckDeclSynchronizeTypeAndInitializer(impl.typeManager, vd, diag: impl.diag,
                checker: Some({ targetTy: Ty, initializer: Expr =>
                    let isWellTyped = Check(ctx, targetTy, initializer)
                    if (!isWellTyped && !IsGlobalOrMember(vd)) {
                        vd.DisableAttr(Attribute.IS_CHECK_VISITED)
                    }
                    isWellTyped
                }))
            if (let Some(varDecl) <- (vd as VarDecl)) {
                if (let Some(initializer) <- varDecl.initializer) {
                    if (!Ty.IsInitialTy(initializer.GetTy())) {
                        if (let Some(diagValue) <- impl.diag) {
                            CheckStaticVarAccessNonStatic(diagValue, varDecl)
                        }
                    }
                }
            }
            BindLocalDeclIfNeeded(ctx, decl)
            return declTy
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                if (funcDecl.TestAttr(Attribute.IS_CHECK_VISITED)) {
                    return funcDecl.GetTy() ?? TypeManager.GetInvalidTy()
                }
                funcDecl.EnableAttr(Attribute.IS_CHECK_VISITED)
                let redefModifier = FindModifier(funcDecl, TokenKind.REDEF)
                let staticModifier = FindModifier(funcDecl, TokenKind.STATIC)
                if ((let Some(redef) <- redefModifier) && (let None <- staticModifier) &&
                    (let None <- funcDecl.propDecl)) {
                    if (let Some(diagValue) <- impl.diag) {
                        Diagnose(diagValue, redef, BasicDiagKind.sema_redef_modify_static_func,
                            args: [BasicDiagArgument("function")]).Emit()
                    }
                }
                SetFunctionBodyOwner(funcDecl, body)
                if (!Ty.IsTyCorrect(funcDecl.GetTy())) {
                    let _ = PrepareFuncBodySignature(ctx, body)
                }
                let funcTy = SynthesizeFuncBody(ctx, body)
                if (funcDecl.TestAttr(Attribute.MAIN_ENTRY)) {
                    CheckEntryFunc(funcDecl)
                } else if (funcDecl.TestAttr(Attribute.OPERATOR)) {
                    if (let Some(diagValue) <- impl.diag) {
                        let _ = TypeCheckDeclCheckOperatorOverloadFunc(diagValue, funcDecl)
                    }
                }
                return funcTy
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
            if (let Some(diagValue) <- impl.diag) {
                let _ = TypeCheckClassLikeCheckNominalAnnotationRules(diagValue, classDecl)
            }
            SynthesizeInheritedTypes(ctx, classDecl)
            for (inheritedType in classDecl.inheritedTypes) {
                if ((inheritedType as RefType).isSome() && inheritedType.GetTarget().isSome()) {
                    let diagValue = impl.diag.getOrThrow()
                    let _ = TypeCheckClassLikeCheckSealedInheritance(diagValue, classDecl, inheritedType)
                    let _ = TypeCheckClassLikeCheckThreadContextInheritance(diagValue, classDecl, inheritedType)
                }
            }
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
            for (constructor in enumDecl.constructors) {
                let _ = PrepareEnumConstructorSignature(ctx, enumDecl, constructor)
            }
            return CheckEnumDecl(impl.diag.getOrThrow(), impl.typeManager, enumDecl,
                { typeNode: Type =>
                    SynthesizeTypeNode(ctx, Some(typeNode))
                    typeNode.GetTy() ?? TypeManager.GetInvalidTy()
                },
                { member: Decl => SynthesizeDecl(ctx, member) })
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(diagValue) <- impl.diag) {
                let _ = CheckExtendDecl(
                    diagValue,
                    impl.typeManager,
                    ctx,
                    extendDecl,
                    { typeNode: Type =>
                        SynthesizeNode(ctx, SynPos.NONE, typeNode)
                    },
                    { member: Decl =>
                        SynthesizeDecl(ctx, member)
                    })
            } else {
                SynthesizeTypeNode(ctx, extendDecl.extendedType)
                for (inheritedType in extendDecl.inheritedTypes) {
                    impl.SetTypeTy(ctx, inheritedType)
                }
                SynthesizeDeclList(ctx, extendDecl.members)
            }
            return tyOrInvalid(extendDecl)
        }
        if (let Some(typeAlias) <- (decl as TypeAliasDecl)) {
            SynthesizeTypeNode(ctx, typeAlias.typeNode)
            return tyOrInvalid(typeAlias)
        }
        return tyOrInvalid(decl)
    }

    private func SynthesizeVarWithPatternDecl(ctx: ASTContext, vpd: VarWithPatternDecl): Ty {
        if (vpd.TestAttr(Attribute.IS_CHECK_VISITED)) {
            if (vpd.TestAttr(Attribute.GLOBAL) && Ty.IsInitialTy(vpd.GetTy())) {
                if (let Some(diagValue) <- impl.diag) {
                    TypeCheckDeclDiagUnableToInferDecl(diagValue, vpd)
                }
                vpd.SetTy(TypeManager.GetInvalidTy())
            }
            return vpd.GetTy() ?? TypeManager.GetInvalidTy()
        }
        vpd.EnableAttr(Attribute.IS_CHECK_VISITED)
        SynthesizeTypeNode(ctx, vpd.typeNode)
        if (let Some(initializer) <- vpd.initializer) {
            if (let Some(typeNode) <- vpd.typeNode) {
                if (let None <- typeNode.GetTy()) {
                    let _ = Synthesize(ctx, initializer)
                }
            } else {
                let _ = Synthesize(ctx, initializer)
            }
        }
        let declTy = TypeCheckDeclSynchronizeTypeAndInitializer(impl.typeManager, vpd, diag: impl.diag,
            checker: Some({ targetTy: Ty, initializer: Expr => Check(ctx, targetTy, initializer) }))
        BindLocalDeclIfNeeded(ctx, vpd)
        if (let Some(initializer2) <- vpd.initializer) {
            if (!Ty.IsTyCorrect(initializer2.GetTy())) {
                return declTy
            }
        }
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            if (Ty.IsTyCorrect(declTy)) {
                let ok = ChkPattern(impl.typeManager, ctx, declTy, pattern, isPatternInMatch: false,
                    exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                        Check(ctx, patternExpectedTy, patternExpr)
                    }), diag: impl.diag)
                if (ok && IsIrrefutablePattern(pattern)) {
                    BindPatternBindings(ctx, pattern)
                }
            }
        }
        return declTy
    }

    private func SynthesizeFuncBody(ctx: ASTContext, fb: FuncBody): Ty {
        if ((fb.funcDecl).isSome()) {
            let previousFuncBody = currentFuncBody
            currentFuncBody = Some(fb)
            let _ = CheckFuncBody(ctx, fb)
            currentFuncBody = previousFuncBody
            return fb.GetTy() ?? TypeManager.GetInvalidTy()
        }
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
        let joinRes = JoinAsVisibleTy(impl.typeManager, retTys, curFile: fb.curFile)
        let (optErrs, joinedRet) = SetJoinedType(retTy, joinRes)
        retTy = joinedRet
        if (let Some(errMsg) <- optErrs) {
            if (let Some(diagValue) <- impl.diag) {
                let builder = Diagnose(diagValue, lastNode,
                    BasicDiagKind.sema_incompatible_func_body_and_return_type)
                builder.AddNote(errMsg)
                builder.Emit()
            }
        }
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
        return SynthesizeBlock(ctx, SynPos.NONE, block)
    }

    private func SynthesizeBlock(ctx: ASTContext, pos: SynPos, block: Block): Ty {
        if (block.body.isEmpty()) {
            let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            block.SetTy(unitTy)
            return unitTy
        }
        MarkUnsafeBlockChildren(block)
        var existInvalid = false
        for (idx in 0..block.body.size) {
            let item = block.body[idx]
            let exprPos = if (idx == block.body.size - 1 && pos != SynPos.UNUSED) {
                SynPos.IMPLICIT_RETURN
            } else {
                SynPos.UNUSED
            }
            if (!SynthesizeAndReplaceIdealTy(ctx, exprPos, item)) {
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

    private func SynthesizeAndReplaceIdealTy(ctx: ASTContext, pos: SynPos, node: Node): Bool {
        var valid = false
        try (ds = DiagSuppressor(impl.diag)) {
            valid = Ty.IsTyCorrect(SynthesizeNode(ctx, pos, node)) &&
                ReplaceIdealTy(impl.typeManager, node, diag: impl.diag) &&
                !ds.HasError()
            ds.ReportDiag()
        }
        return valid
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
            return ChkBlock(impl.typeManager, target, block, diag: impl.diag)
        }
        MarkUnsafeBlockChildren(block)
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        var isWellTyped = true
        if (block.body.size > 1) {
            for (idx in 0..block.body.size - 1) {
                isWellTyped = SynthesizeAndReplaceIdealTy(ctx, SynPos.UNUSED, block.body[idx]) && isWellTyped
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
            if (nodeForCheck.IsDecl()) {
                let typeMatched = impl.typeManager.IsSubtype(unitTy, target)
                isWellTyped = SynthesizeAndReplaceIdealTy(ctx, SynPos.IMPLICIT_RETURN, nodeForCheck) && typeMatched &&
                    isWellTyped
                if (isWellTyped) {
                    block.SetTy(unitTy)
                    return true
                }
                if (!typeMatched) {
                    if (let Some(diagValue) <- impl.diag) {
                        DiagMismatchedTypesWithFoundTy(diagValue, nodeForCheck, target, unitTy,
                            note: "definitions and declarations are always of type 'Unit'")
                    }
                }
            } else {
                if (let Some(lastExpr) <- (nodeForCheck as Expr)) {
                    let checked = Check(ctx, target, lastExpr)
                    if (isWellTyped && checked) {
                        block.SetTy(lastExpr.GetTy() ?? TypeManager.GetInvalidTy())
                        return true
                    }
                }
            }
        }
        block.SetTy(TypeManager.GetInvalidTy())
        return false
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

    private func ResetLambdaForReinfer(ctx: ASTContext, le: LambdaExpr): Unit {
        if (let Some(funcBody) <- le.funcBody) {
            funcBody.retType = None
            AddRetTypeNode(funcBody)
            funcBody.Clear()
            if (let Some(body) <- funcBody.body) {
                let walker = Walker(body, visitPre: { node: Node =>
                    if (((node as Decl).isSome() || (node as Expr).isSome()) && !Ty.IsInitialTy(node.GetTy())) {
                        node.Clear()
                    }
                    VisitAction.WALK_CHILDREN
                })
                let _ = walker.Walk()
            }
            ctx.ClearTypeCheckCache(funcBody)
        }
    }

    private func DiagInferParamTyFail(le: LambdaExpr): Bool {
        if (let Some(funcBody) <- le.funcBody) {
            if (!funcBody.paramLists.isEmpty()) {
                for (param in funcBody.paramLists[0].params) {
                    if (let None <- param.typeNode) {
                        if (let Some(diagValue) <- impl.diag) {
                            let builder = diagValue.DiagnoseRefactor(
                                BasicDiagKindRefactor.sema_lambdaExpr_must_have_type_annotation, param.begin)
                            builder.Emit()
                        }
                        le.SetTy(TypeManager.GetInvalidTy())
                        return true
                    }
                }
            }
        }
        return false
    }

    private func FindCandidatesFromCall(
        ctx: ASTContext,
        callExpr: CallExpr,
        unsolvedParams: HashMap<String, FuncParam>
    ): (String, ArrayList<Decl>) {
        if (let Some(baseFunc) <- callExpr.baseFunc) {
            if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                if (let Some(baseExpr) <- memberAccess.baseExpr) {
                    if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                        let id = refExpr.ref.identifier.Val()
                        if (unsolvedParams.contains(id)) {
                            let sig = MemSig(memberAccess.field.Val(), false, UInt64(callExpr.args.size),
                                UInt64(memberAccess.typeArguments.size))
                            return (id, ctx.Mem2Decls(sig))
                        }
                    }
                }
            }
        }
        return ("", ArrayList<Decl>())
    }

    private func FindCandidatesFromAccess(
        ctx: ASTContext,
        memberAccess: MemberAccess,
        unsolvedParams: HashMap<String, FuncParam>
    ): (String, ArrayList<Decl>) {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                let id = refExpr.ref.identifier.Val()
                if (unsolvedParams.contains(id)) {
                    let sig = MemSig(memberAccess.field.Val(), true, 0u64, 0u64)
                    return (id, ctx.Mem2Decls(sig))
                }
            }
        }
        return ("", ArrayList<Decl>())
    }

    private func TryInferFromSyntaxInfo(ctx: ASTContext, le: LambdaExpr): Unit {
        if (impl.typeManager.GetInnermostUnsolvedTyVars().isEmpty()) {
            return
        }
        let unsolvedParams = HashMap<String, FuncParam>()
        if (let Some(funcBody) <- le.funcBody) {
            if (!funcBody.paramLists.isEmpty()) {
                for (param in funcBody.paramLists[0].params) {
                    if ((param.GetTy() ?? TypeManager.GetInvalidTy()).IsPlaceholder()) {
                        unsolvedParams[param.identifier.Val()] = param
                    }
                }
            }
        }
        if (unsolvedParams.isEmpty()) {
            return
        }

        let candidates = HashMap<String, ArrayList<Decl>>()
        let candidateIds = ArrayList<String>()
        let candiHandler = { candi: (String, ArrayList<Decl>) =>
            let id = candi[0]
            let decls = candi[1]
            if (id.isEmpty()) {
                false
            } else {
                if (!candidates.contains(id)) {
                    candidates[id] = decls
                    candidateIds.add(id)
                } else if (let Some(existing) <- candidates.get(id)) {
                    let kept = ArrayList<Decl>()
                    for (oldDecl in existing) {
                        var found = false
                        for (candidateDecl in decls) {
                            if (SameDecl(oldDecl, candidateDecl)) {
                                found = true
                                break
                            }
                        }
                        if (found) {
                            kept.add(oldDecl)
                        }
                    }
                    existing.clear()
                    for (keptDecl in kept) {
                        existing.add(keptDecl)
                    }
                }
                true
            }
        }
        let memberScanner = Box<(Node) -> VisitAction>({ _: Node => VisitAction.WALK_CHILDREN })
        memberScanner.value = { node: Node =>
            if (let Some(callExpr) <- (node as CallExpr)) {
                if (candiHandler(FindCandidatesFromCall(ctx, callExpr, unsolvedParams))) {
                    for (arg in callExpr.args) {
                        let argWalker = Walker(arg, visitPre: memberScanner.value)
                        let _ = argWalker.Walk()
                    }
                    return VisitAction.SKIP_CHILDREN
                }
            } else if (let Some(memberAccess) <- (node as MemberAccess)) {
                let _ = candiHandler(FindCandidatesFromAccess(ctx, memberAccess, unsolvedParams))
            }
            VisitAction.WALK_CHILDREN
        }
        if (let Some(funcBody2) <- le.funcBody) {
            let walker = Walker(funcBody2, visitPre: memberScanner.value)
            let _ = walker.Walk()
        }

        for (id in candidateIds) {
            if (let Some(param) <- unsolvedParams.get(id)) {
                if (let Some(tyVar) <- ((param.GetTy() ?? TypeManager.GetInvalidTy()) as GenericsTy)) {
                    TryEnforceCandidate(tyVar, candidates.get(id) ?? ArrayList<Decl>(), impl.typeManager)
                }
            }
        }
    }

    private func SolveLamExprParamTys(ctx: ASTContext, le: LambdaExpr): Bool {
        let tyVars = impl.typeManager.GetInnermostUnsolvedTyVars()
        let sol = LocalTypeArgumentSynthesis.SolveConstraints(impl.typeManager, impl.typeManager.constraints)
        var successful = false
        if (let Some(subst) <- sol) {
            if (!HasUnsolvedTyVars(subst, tyVars)) {
                ResetLambdaForReinfer(ctx, le)
                if (let Some(funcBody) <- le.funcBody) {
                    if (!funcBody.paramLists.isEmpty()) {
                        for (param in funcBody.paramLists[0].params) {
                            if (let Some(paramTy) <- param.GetTy()) {
                                param.SetTy(impl.typeManager.GetInstantiatedTy(paramTy, subst))
                            }
                        }
                    }
                    if (Ty.IsTyCorrect(SynthesizeNode(ctx, SynPos.EXPR_ARG, funcBody)) &&
                        (let Some(body) <- funcBody.body) && Ty.IsTyCorrect(body.GetTy())) {
                        le.SetTy(funcBody.GetTy() ?? TypeManager.GetInvalidTy())
                        successful = true
                    }
                }
            }
        }
        if (!successful && DiagInferParamTyFail(le)) {
            return false
        }
        return true
    }

    private func SynLamExpr(ctx: ASTContext, le: LambdaExpr): Ty {
        let funcBody = le.funcBody ?? return TypeManager.GetInvalidTy()
        if (funcBody.paramLists.isEmpty()) {
            return TypeManager.GetInvalidTy()
        }
        funcBody.retType = None
        AddRetTypeNode(funcBody)
        let retType = funcBody.retType.getOrThrow()
        retType.begin = le.begin
        retType.end = le.end

        let tyVarScope = BeginTyVarScope(impl.typeManager)
        for (param in funcBody.paramLists[0].params) {
            let paramTy = if (let Some(typeNode) <- param.typeNode) {
                SynthesizeNode(ctx, SynPos.NONE, typeNode)
            } else {
                TypeManager.GetInvalidTy()
            }
            if (Ty.IsTyCorrect(paramTy)) {
                param.SetTy(paramTy)
            } else if (!ctx.funcArgReachable.contains(le) && (let None <- param.typeNode)) {
                param.SetTy(impl.typeManager.AllocTyVar(srcId: "T-Lam", needSolving: true))
            } else {
                if (let Some(diagValue) <- impl.diag) {
                    let builder = diagValue.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_lambdaExpr_must_have_type_annotation, param.begin)
                    builder.Emit()
                }
                le.SetTy(TypeManager.GetInvalidTy())
                EndTyVarScope(tyVarScope)
                return le.GetTy() ?? TypeManager.GetInvalidTy()
            }
        }
        TryInferFromSyntaxInfo(ctx, le)
        let skipSolving = impl.typeManager.GetInnermostUnsolvedTyVars().isEmpty()
        var leTy: Ty = TypeManager.GetInvalidTy()
        try (ds = DiagSuppressor(impl.diag)) {
            leTy = SynthesizeNode(ctx, SynPos.EXPR_ARG, funcBody)
            if (skipSolving) {
                ds.ReportDiag()
            }
        }
        if (!Ty.IsTyCorrect(leTy) || (let None <- funcBody.body) ||
            !Ty.IsTyCorrect(funcBody.body.getOrThrow().GetTy())) {
            le.SetTy(TypeManager.GetInvalidTy())
            if (DiagInferParamTyFail(le)) {
                EndTyVarScope(tyVarScope)
                return le.GetTy() ?? TypeManager.GetInvalidTy()
            }
        } else {
            if (skipSolving) {
                le.SetTy(funcBody.GetTy() ?? TypeManager.GetInvalidTy())
            } else if (!SolveLamExprParamTys(ctx, le)) {
                EndTyVarScope(tyVarScope)
                return le.GetTy() ?? TypeManager.GetInvalidTy()
            }
        }
        if (let Some(funcTy) <- ((le.GetTy() ?? TypeManager.GetInvalidTy()) as FuncTy)) {
            retType.SetTy(funcTy.retTy)
        } else {
            retType.SetTy(TypeManager.GetInvalidTy())
        }
        EndTyVarScope(tyVarScope)
        return le.GetTy() ?? TypeManager.GetInvalidTy()
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

    private func CheckLambdaBody(ctx: ASTContext, funcBody: FuncBody): Bool {
        let _ = SynthesizeFuncBody(ctx, funcBody)
        if (Ty.IsTyCorrect(funcBody.GetTy() ?? TypeManager.GetInvalidTy())) {
            if (let Some(body) <- funcBody.body) {
                if (Ty.IsTyCorrect(body.GetTy() ?? TypeManager.GetInvalidTy())) {
                    return true
                }
            }
        }
        funcBody.SetTy(TypeManager.GetInvalidTy())
        return false
    }

    private func CheckLambdaExprWithTarget(ctx: ASTContext, target: Ty, le: LambdaExpr): Bool {
        if (let None <- le.funcBody) {
            let _ = TcInvalid(le)
            return false
        }
        let targetTy = UnboxOptionType(target)
        if (let Some(targetFuncTy) <- (targetTy as FuncTy)) {
            try (ds = DiagSuppressor(impl.diag)) {
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
                let funcBody = le.funcBody.getOrThrow()
                if (CheckLambdaBody(ctx, funcBody)) {
                    ds.ReportDiag()
                    var bodyRetTy = targetFuncTy.retTy
                    if (let Some(funcBodyTy) <- funcBody.GetTy()) {
                        if (let Some(bodyFuncTy) <- (funcBodyTy as FuncTy)) {
                            bodyRetTy = bodyFuncTy.retTy
                        }
                    }
                    let funcTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), bodyRetTy,
                        cfg: CloneLambdaTargetFuncCfg(targetFuncTy))
                    funcBody.SetTy(funcTy)
                    le.SetTy(funcTy)
                    return true
                }
                funcBody.SetTy(TypeManager.GetInvalidTy())
                le.SetTy(funcBody.GetTy() ?? TypeManager.GetInvalidTy())
            }
            let _ = TcInvalid(le)
            return false
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
        return CheckWithCache(ctx, target, arg)
    }

    private func LookupCoreDeclForSpawn(ctx: ASTContext, name: String): Option<Decl> {
        let _ = ctx
        if (let Some(manager) <- impl.importManager) {
            return manager.GetCoreDecl<Decl>(name)
        }
        return None
    }

    private func LookupCoreFutureForSpawn(ctx: ASTContext): Option<ClassDecl> {
        let _ = ctx
        if (let Some(manager) <- impl.importManager) {
            return manager.GetCoreDecl<ClassDecl>("Future")
        }
        return None
    }

    private func LookupCoreThreadContextTyForSpawn(ctx: ASTContext): Option<Ty> {
        if (let Some(decl) <- LookupCoreDeclForSpawn(ctx, "ThreadContext")) {
            return decl.GetTy()
        }
        return None
    }

    private func SynthesizeSpawnExpr(ctx: ASTContext, expr: SpawnExpr): Ty {
        var isWellTyped = true
        if (let Some(arg) <- expr.arg) {
            let _ = Synthesize(ctx, arg)
            isWellTyped = CheckSpawnArgValid(impl.typeManager, arg,
                threadContextTy: LookupCoreThreadContextTyForSpawn(ctx), diag: impl.diag) && isWellTyped
        }
        if (let Some(task) <- expr.task) {
            let taskTy = Synthesize(ctx, task)
            isWellTyped = (Ty.IsTyCorrect(taskTy) && taskTy.IsFunc()) && isWellTyped
        } else {
            isWellTyped = false
        }
        if (!isWellTyped) {
            expr.SetTy(TypeManager.GetInvalidTy())
            return TypeManager.GetInvalidTy()
        }
        let futureClass = LookupCoreFutureForSpawn(ctx)
        let spawnTy = SynSpawnExpr(impl.typeManager, expr, futureClass: futureClass,
            threadContextTy: LookupCoreThreadContextTyForSpawn(ctx), diag: impl.diag)
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
                    threadContextTy: LookupCoreThreadContextTyForSpawn(ctx), diag: impl.diag) && isWellTyped
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
        if (!TypeManager.IsCoreFutureType(target)) {
            if (let None <- LookupCoreFutureForSpawn(ctx)) {
                if (let Some(diagValue) <- impl.diag) {
                    let builder = diagValue.Diagnose(expr.begin, expr.end, BasicDiagKind.sema_no_core_object)
                    builder.Emit()
                }
                expr.SetTy(TypeManager.GetInvalidTy())
                return false
            }
        }
        let synTy = SynthesizeSpawnExpr(ctx, expr)
        if (Ty.IsTyCorrect(synTy) &&
            impl.typeManager.CheckTypeCompatibility(target, synTy) != TypeCompatibility.INCOMPATIBLE) {
            return true
        }
        expr.SetTy(TypeManager.GetInvalidTy())
        return false
    }

    private func replaceReturnClassThisOutsideClass(re: ReturnExpr, expr: Expr): Unit {
        if (let Some(fb) <- re.refFuncBody) {
            if (let Some(parent) <- fb.parentClassLike) {
                if (let Some(_) <- (parent as ClassDecl)) {
                    return
                }
            }
        }
        if (let Some(exprTy) <- expr.GetTy()) {
            if (let Some(classThisTy) <- (exprTy as ClassThisTy)) {
                if (let Some(classDecl) <- classThisTy.declPtr) {
                    if (let Some(classTy) <- classDecl.GetTy()) {
                        expr.SetTy(classTy)
                    }
                }
            }
        }
    }

    private func SynthesizeReturnExpr(ctx: ASTContext, re: ReturnExpr): Ty {
        if (let None <- re.refFuncBody) {
            return TcInvalid(re)
        }
        let fb = re.refFuncBody.getOrThrow()
        if (let None <- fb.retType) {
            return TcInvalid(re)
        }
        if (let None <- re.expr) {
            return TcInvalid(re)
        }
        let innerExpr = re.expr.getOrThrow()
        re.SetTy(TypeManager.GetInvalidTy())
        var isWellTyped = true
        if (let Some(retTy) <- fb.retType.getOrThrow().GetTy()) {
            if (Ty.IsTyCorrect(retTy) && !retTy.IsQuest()) {
                let targetTy = if (let Some(funcDecl) <- fb.funcDecl) {
                    if (IsInstanceConstructor(funcDecl)) {
                        TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                    } else {
                        retTy
                    }
                } else {
                    retTy
                }
                isWellTyped = Check(ctx, targetTy, innerExpr) && isWellTyped
                if (isWellTyped) {
                    typeCheckExprPutTargetType(ctx, innerExpr, innerExpr.GetTy() ?? targetTy)
                }
            } else {
                let exprTy = Synthesize(ctx, innerExpr)
                isWellTyped = Ty.IsTyCorrect(exprTy) &&
                    ReplaceIdealTy(impl.typeManager, innerExpr, diag: impl.diag) && isWellTyped
            }
        } else {
            let exprTy2 = Synthesize(ctx, innerExpr)
            isWellTyped = Ty.IsTyCorrect(exprTy2) &&
                ReplaceIdealTy(impl.typeManager, innerExpr, diag: impl.diag) && isWellTyped
        }
        replaceReturnClassThisOutsideClass(re, innerExpr)
        if (!isWellTyped && NeedCheckBodyReturn(fb)) {
            return TcInvalid(re)
        }
        let nothingTy = TypeManager.GetNothingTy()
        re.SetTy(nothingTy)
        return nothingTy
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
                diag: impl.diag,
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
        return ChkUnaryExpr(impl, target, unaryExpr)
    }

    private func SynthesizedIfHasMissingElse(ifExpr: IfExpr): Bool {
        if (let None <- ifExpr.elseBody) {
            return true
        }
        if (let Some(elseExpr) <- ifExpr.elseBody) {
            if (let Some(elseIf) <- (elseExpr as IfExpr)) {
                return SynthesizedIfHasMissingElse(elseIf)
            }
        }
        return false
    }

    private func JoinSynthesizedIfBranchTys(thenTy: Ty, elseTy: Ty, curFile: Option<File>): ErrOrTy {
        if (!Ty.IsTyCorrect(thenTy) || !Ty.IsTyCorrect(elseTy)) {
            return ErrOrTy.TY(TypeManager.GetInvalidTy())
        }
        if (thenTy.IsNothing()) {
            return ErrOrTy.TY(elseTy)
        }
        if (elseTy.IsNothing()) {
            return ErrOrTy.TY(thenTy)
        }
        let tys = TySet()
        tys.Add(thenTy)
        tys.Add(elseTy)
        return JoinAsVisibleTy(impl.typeManager, tys, curFile: curFile)
    }

    private func SynthesizeIfExpr(ctx: ASTContext, pos: SynPos, ifExpr: IfExpr): Ty {
        let conditionBindings = ArrayList<Decl>()
        var isWellTyped = true
        if (let Some(condExpr) <- ifExpr.condExpr) {
            isWellTyped = CheckConditionWithBindings(ctx, condExpr, conditionBindings, false) && isWellTyped
        } else {
            isWellTyped = false
        }
        if (let Some(thenBody) <- ifExpr.thenBody) {
            isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, thenBody)) && isWellTyped
        } else {
            isWellTyped = false
        }
        RemovePatternBindings(ctx, conditionBindings)
        if (SynthesizedIfHasMissingElse(ifExpr)) {
            if (let Some(elseBody) <- ifExpr.elseBody) {
                isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, elseBody)) && isWellTyped
            }
            let ifTy = if (isWellTyped) {
                TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            } else {
                TypeManager.GetInvalidTy()
            }
            ifExpr.SetTy(ifTy)
            return FinishSynthesize(ctx, ifExpr, ifTy)
        }
        if (let Some(elseBody2) <- ifExpr.elseBody) {
            isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, elseBody2)) && isWellTyped
        } else {
            isWellTyped = false
        }
        if (!isWellTyped) {
            let invalidTy = TypeManager.GetInvalidTy()
            ifExpr.SetTy(invalidTy)
            return FinishSynthesize(ctx, ifExpr, invalidTy)
        }
        if (let Some(thenBody2) <- ifExpr.thenBody) {
            if (let Some(elseBody3) <- ifExpr.elseBody) {
                let _ = ReplaceIdealTy(impl.typeManager, thenBody2, diag: impl.diag)
                let _ = ReplaceIdealTy(impl.typeManager, elseBody3, diag: impl.diag)
                let thenTy = impl.typeManager.GetThisRealTy(thenBody2.GetTy() ?? TypeManager.GetInvalidTy())
                let elseTy = impl.typeManager.GetThisRealTy(elseBody3.GetTy() ?? TypeManager.GetInvalidTy())
                thenBody2.SetTy(thenTy)
                elseBody3.SetTy(elseTy)
                if (pos == SynPos.UNUSED) {
                    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                    ifExpr.SetTy(unitTy)
                    return FinishSynthesize(ctx, ifExpr, unitTy)
                }
                let joinRes = JoinSynthesizedIfBranchTys(thenTy, elseTy, ifExpr.curFile)
                let (optErrs, joinedTy) = SetJoinedType(ifExpr.GetTy() ?? TypeManager.GetInvalidTy(), joinRes)
                ifExpr.SetTy(joinedTy)
                if (let Some(errMsg) <- optErrs) {
                    var diagMessage = "types " + Ty.ToString(Some(thenTy)) + " and " + Ty.ToString(Some(elseTy))
                    diagMessage += if (let Some(sourceExpr) <- ifExpr.sourceExpr) {
                        if (sourceExpr.astKind == ASTKind.IF_AVAILABLE_EXPR) {
                            " of the two lambda of this '@IfAvailable' expression mismatch"
                        } else {
                            " of the two branches of this 'if' expression mismatch"
                        }
                    } else {
                        " of the two branches of this 'if' expression mismatch"
                    }
                    if (let Some(diagValue) <- impl.diag) {
                        let builder = Diagnose(diagValue, ifExpr, BasicDiagKind.sema_diag_report_error_message,
                            args: [BasicDiagArgument(diagMessage)])
                        builder.AddNote(errMsg)
                        builder.Emit()
                    }
                }
                return FinishSynthesize(ctx, ifExpr, joinedTy)
            }
        }
        let invalidTy2 = TypeManager.GetInvalidTy()
        ifExpr.SetTy(invalidTy2)
        return FinishSynthesize(ctx, ifExpr, invalidTy2)
    }

    private func CheckIfExprNoElseWithTarget(ctx: ASTContext, target: Ty, ifExpr: IfExpr): Bool {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        ifExpr.SetTy(unitTy)
        var isWellTyped = true
        if (let Some(thenBody) <- ifExpr.thenBody) {
            isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, thenBody)) && isWellTyped
        } else {
            isWellTyped = false
        }
        if (let Some(elseBody) <- ifExpr.elseBody) {
            isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, elseBody)) && isWellTyped
        }
        let targetMatched = impl.typeManager.IsSubtype(unitTy, target)
        if (isWellTyped && !targetMatched) {
            if (let Some(diagValue) <- impl.diag) {
                DiagMismatchedTypesWithFoundTy(diagValue, ifExpr, target, unitTy,
                    note: "the type of an 'if' expression without an 'else' branch is always 'Unit'")
            }
        }
        return isWellTyped && targetMatched
    }

    private func CheckIfExprWithTarget(ctx: ASTContext, target: Ty, ifExpr: IfExpr): Bool {
        let conditionBindings = ArrayList<Decl>()
        var isWellTyped = true
        if (let Some(condExpr) <- ifExpr.condExpr) {
            isWellTyped = CheckConditionWithBindings(ctx, condExpr, conditionBindings, false)
        } else {
            isWellTyped = false
        }
        if (SynthesizedIfHasMissingElse(ifExpr)) {
            let branchOk = CheckIfExprNoElseWithTarget(ctx, target, ifExpr)
            RemovePatternBindings(ctx, conditionBindings)
            isWellTyped = branchOk && isWellTyped
        } else {
            if (let Some(thenBody) <- ifExpr.thenBody) {
                isWellTyped = Check(ctx, target, thenBody) && isWellTyped
            } else {
                isWellTyped = false
            }
            RemovePatternBindings(ctx, conditionBindings)
            if (let Some(elseBody) <- ifExpr.elseBody) {
                isWellTyped = Check(ctx, target, elseBody) && isWellTyped
            } else {
                isWellTyped = false
            }
            if (isWellTyped) {
                ifExpr.SetTy(target)
            }
        }
        if (!isWellTyped) {
            ifExpr.SetTy(TypeManager.GetInvalidTy())
        }
        return isWellTyped
    }

    private func SynthesizeMatchChildren(ctx: ASTContext, matchExpr: MatchExpr): ArrayList<Decl> {
        let allBoundDecls = ArrayList<Decl>()
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
                        }), desugarCallExpr: Some({ callExprForDesugar: CallExpr =>
                            DesugarCallExpr(callExprForDesugar)
                        }))
                    BindCollectedConditionDecls(ctx, matchCase.patterns, boundDecls)
                    for (decl in boundDecls) {
                        AddUniqueBoundDecl(allBoundDecls, decl)
                    }
                }
            }
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
        return allBoundDecls
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

    private func DiagnoseForInIterator(expr: Expr): Unit {
        if (CanSkipDiag(expr)) {
            return
        }
        if (let Some(diagValue) <- impl.diag) {
            let tyStr = (expr.GetTy() ?? TypeManager.GetInvalidTy()).String()
            let builder = diagValue.Diagnose(expr.begin, expr.end,
                BasicDiagKind.sema_expr_in_forin_must_has_iterator, args: [BasicDiagArgument(tyStr)])
            builder.Emit()
        }
    }

    private func DiagnoseForInGuard(expr: Expr): Unit {
        if (CanSkipDiag(expr)) {
            return
        }
        if (let Some(diagValue) <- impl.diag) {
            let builder = diagValue.Diagnose(expr.begin, expr.end, BasicDiagKind.sema_wrong_forin_guard)
            builder.Emit()
        }
    }

    private func DiagnoseForInPattern(forInExpr: ForInExpr): Unit {
        if (let Some(diagValue) <- impl.diag) {
            let builder = diagValue.Diagnose(forInExpr.begin, forInExpr.end,
                BasicDiagKind.sema_forin_pattern_must_be_irrefutable)
            builder.Emit()
        }
    }

    private func GetForInIterableTy(ctx: ASTContext, inTy: Ty): Ty {
        if (inTy.IsNothing()) {
            return TypeManager.GetInvalidTy()
        }
        let iterableDecl: Option<Decl> = if (let Some(manager) <- impl.importManager) {
            manager.GetCoreDecl<Decl>("Iterable")
        } else {
            None
        }
        if (let Some(genericTy) <- (inTy as GenericsTy)) {
            if (genericTy.isPlaceholder) {
                let iterableTy = iterableDecl.getOrThrow().GetTy().getOrThrow()
                return impl.typeManager.ConstrainByCtor(genericTy, iterableTy) ?? TypeManager.GetInvalidTy()
            }
        }
        if (let Some(interfaceDecl) <- iterableDecl) {
            let interfaceTy = interfaceDecl.GetTy().getOrThrow()
            let promotedTys = Promotion(impl.typeManager).Promote(inTy, interfaceTy)
            if (!promotedTys.values.isEmpty()) {
                return promotedTys.values[0]
            }
        }
        return TypeManager.GetInvalidTy()
    }

    private func SynthesizeForInExpr(ctx: ASTContext, forInExpr: ForInExpr): Ty {
        var isWellTyped = true
        var inPatternTy: Ty = TypeManager.GetInvalidTy()
        let boundDecls = ArrayList<Decl>()
        if (let Some(inExpression) <- forInExpr.inExpression) {
            let inTy = Synthesize(ctx, SynPos.EXPR_ARG, inExpression)
            isWellTyped = Ty.IsTyCorrect(inTy) &&
                ReplaceIdealTy(impl.typeManager, inExpression, diag: impl.diag) && isWellTyped
            if (let Some(realInTy) <- inExpression.GetTy()) {
                let iterableTy = GetForInIterableTy(ctx, realInTy)
                if (Ty.IsTyCorrect(iterableTy) && !iterableTy.typeArgs.isEmpty()) {
                    inPatternTy = iterableTy.typeArgs[0]
                } else {
                    isWellTyped = false
                    DiagnoseForInIterator(inExpression)
                }
            } else {
                isWellTyped = false
                DiagnoseForInIterator(inExpression)
            }
        } else {
            isWellTyped = false
        }
        if (let Some(pattern) <- forInExpr.pattern) {
            let patternOk = ChkPattern(impl.typeManager, ctx, inPatternTy, pattern, isPatternInMatch: false,
                exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                    Check(ctx, patternExpectedTy, patternExpr)
                }), diag: impl.diag)
            isWellTyped = patternOk && isWellTyped
            if (patternOk) {
                CollectPatternBinding(pattern, boundDecls)
                for (decl in boundDecls) {
                    BindLocalDeclIfAbsent(ctx, decl)
                }
            }
        } else {
            isWellTyped = false
        }
        if (let Some(patternGuard) <- forInExpr.patternGuard) {
            if (!Check(ctx, TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN), patternGuard)) {
                isWellTyped = false
                DiagnoseForInGuard(patternGuard)
            }
        }
        if (let Some(body) <- forInExpr.body) {
            isWellTyped = Ty.IsTyCorrect(SynthesizeBlock(ctx, SynPos.UNUSED, body)) && isWellTyped
        } else {
            isWellTyped = false
        }
        if (let Some(pattern2) <- forInExpr.pattern) {
            if (!IsIrrefutablePattern(pattern2)) {
                isWellTyped = false
                DiagnoseForInPattern(forInExpr)
            }
        }
        RemovePatternBindings(ctx, boundDecls)
        let ty = if (isWellTyped) {
            TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        } else {
            TypeManager.GetInvalidTy()
        }
        forInExpr.SetTy(ty)
        return ty
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
                if (let Some(target) <- refExpr.ref.target) {
                    if (let Some(cfunc) <- (target as BuiltInDecl)) {
                        if (cfunc.IsType(BuiltInType.CFUNC)) {
                            InferCFuncExpr(ctx, refExpr)
                            return refExpr.GetTy() ?? TypeManager.GetInvalidTy()
                        }
                    }
                }
            }
        }
        let ty = SynNameReferenceExpr(impl.typeManager, nameRef, diag: impl.diag)
        if (Ty.IsTyCorrect(ty)) {
            if (!nameRef.instTys.isEmpty() && ty.HasGeneric()) {
                if (let Some(targetForInstTys) <- nameRef.GetTarget()) {
                    if (targetForInstTys.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                        if (let Some(genericDeclForInstTys) <- targetForInstTys.outerDecl) {
                            let instTyMapping = GenerateTypeMapping(genericDeclForInstTys, nameRef.instTys)
                            let instTy = impl.typeManager.GetInstantiatedTy(ty, instTyMapping)
                            if (Ty.IsTyCorrect(instTy)) {
                                nameRef.SetTy(instTy)
                                return instTy
                            }
                        }
                    }
                }
            }
            let typeMapping = impl.GenerateGenericTypeMapping(ctx, nameRef)
            let tys = impl.typeManager.ApplySubstPackNonUniq(ty, typeMapping, ignoreUnsolved: true)
            if (let Some(targetForMapping) <- nameRef.GetTarget()) {
                let isFuncTarget = if (let Some(_) <- (targetForMapping as FuncDecl)) { true } else { false }
                if (tys.values.size != 1 && isFuncTarget && !ctx.HasTargetTy(nameRef)) {
                    if (let Some(diagValue) <- impl.diag) {
                        let builder = diagValue.Diagnose(nameRef.begin, nameRef.end,
                            BasicDiagKind.sema_ambiguous_func_ref,
                            args: [BasicDiagArgument(targetForMapping.identifier.Val())])
                        builder.Emit()
                    }
                }
            }
            nameRef.SetTy(tys.values[0])
            return tys.values[0]
        }
        return ty
    }

    private func InferCFuncExpr(ctx: ASTContext, re: RefExpr): Unit {
        if (re.typeArguments.size != 1) {
            if (let Some(diagValue) <- impl.diag) {
                // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
                diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_generic_argument_no_match, re.begin)
            }
            re.SetTy(TypeManager.GetInvalidTy())
            return
        }
        let typeArgument = re.typeArguments[0]
        let funcType = match (typeArgument as FuncType) {
            case Some(value) => value
            case None =>
                if (let Some(diagValue) <- impl.diag) {
                    // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
                    let _ = diagValue.Diagnose(typeArgument.begin, typeArgument.end, BasicDiagKind.sema_cfunc_type)
                }
                re.SetTy(TypeManager.GetInvalidTy())
                return
        }
        let paramTys = ArrayList<Ty>()
        for (paramType in funcType.paramTypes) {
            paramType.SetTy(GetTyFromASTType(impl.typeManager, ctx, paramType))
            paramTys.add(paramType.GetTy() ?? TypeManager.GetInvalidTy())
        }
        let retType = funcType.retType.getOrThrow()
        retType.SetTy(GetTyFromASTType(impl.typeManager, ctx, retType))
        let cfg = FuncTyConfig()
        cfg.isC = true
        let resTy = impl.typeManager.GetFunctionTy(paramTys.toArray(), retType.GetTy() ?? TypeManager.GetInvalidTy(),
            cfg: cfg)
        re.SetTy(resTy)
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
                diagValue, impl.typeManager, ctx, memberAccess, targets, importManager: impl.importManager)) {
                return
            }
        }
        if (targets.isEmpty()) {
            return
        }
        let target = GetAccessibleDecl(impl.typeManager, ctx, memberAccess, targets) ?? targets[0]
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
                    let _ = SynExprShallow(impl.typeManager, innerExpr, diag: impl.diag)
                }
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func FinishSynthesize(ctx: ASTContext, expr: Expr, ty: Ty): Ty {
        SynthesizeDesugarsInTree(ctx, expr)
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
        typeCheckExprClearTargetType(ctx, expr)
        return ok
    }

    private func IsNodeDesugared(node: Node): Bool {
        if (let Some(expr) <- (node as Expr)) {
            return expr.desugarExpr.isSome()
        }
        return false
    }

    private func GetDiagCacheKey(): Int64 {
        if (let Some(diagValue) <- impl.diag) {
            return DiagnosticCache.ExtractKey(diagValue)
        }
        return 0
    }

    private func GetCacheKeyForSyn(ctx: ASTContext, node: Node): CacheKey {
        let target = ctx.targetTypeMap.get(node)
        return CacheKey(target, IsNodeDesugared(node), GetDiagCacheKey())
    }

    private func GetCacheKeyForChk(ctx: ASTContext, node: Node, target: Ty): CacheKey {
        return CacheKey(Some(target), IsNodeDesugared(node), GetDiagCacheKey())
    }

    private func GetTypeCheckCache(ctx: ASTContext, node: Node): TypeCheckCache {
        if (let Some(cache) <- ctx.typeCheckCache.get(node)) {
            return cache
        }
        let newCache = TypeCheckCache()
        ctx.typeCheckCache[node] = newCache
        return newCache
    }

    private func RestoreCached(ctx: ASTContext, node: Node, cache: CacheEntry,
        recoverDiag!: Bool = true): Unit {
        if (Ty.IsInitialTy(node.GetTy())) {
            GetTypeCheckCache(ctx, node).lastKey = None
        }
        if (let Some(resultTy) <- cache.result) {
            node.SetTy(resultTy)
        } else {
            node.SetTy(Ty.GetInitialTy())
        }
        RestoreTargets(node, cache.targets)
        if (recoverDiag) {
            if (let Some(diagValue) <- impl.diag) {
                cache.diags.Restore(diagValue)
            }
        }
    }

    private func SynthesizeAndCache(ctx: ASTContext, pos: SynPos, expr: Expr, key: CacheKey): Ty {
        let dc = DiagnosticCache()
        if (let Some(diagValue) <- impl.diag) {
            dc.ToExclude(diagValue)
        }
        let ret = Synthesize(ctx, pos, expr)
        if (let Some(diagValue2) <- impl.diag) {
            dc.BackUp(diagValue2)
        }
        let entry = CacheEntry()
        entry.successful = Ty.IsTyCorrect(ret) && dc.NoError()
        entry.result = Some(ret)
        entry.diags = dc
        entry.targets = CollectTargets(expr)
        GetTypeCheckCache(ctx, expr).synCache[key] = entry
        return ret
    }

    private func CheckAndCache(ctx: ASTContext, target: Ty, expr: Expr, key: CacheKey): Bool {
        let dc = DiagnosticCache()
        if (let Some(diagValue) <- impl.diag) {
            dc.ToExclude(diagValue)
        }
        let ret = Check(ctx, target, expr)
        if (let Some(diagValue2) <- impl.diag) {
            dc.BackUp(diagValue2)
        }
        let entry = CacheEntry()
        entry.successful = ret
        entry.result = expr.GetTy()
        entry.diags = dc
        entry.targets = CollectTargets(expr)
        GetTypeCheckCache(ctx, expr).chkCache[key] = entry
        return ret
    }

    private func CheckAndCache(ctx: ASTContext, target: Ty, arg: FuncArg, key: CacheKey): Bool {
        let dc = DiagnosticCache()
        if (let Some(diagValue) <- impl.diag) {
            dc.ToExclude(diagValue)
        }
        GetTypeCheckCache(ctx, arg).lastKey = key
        let ret = ChkFuncArg(ctx, target, arg)
        if (let Some(diagValue2) <- impl.diag) {
            dc.BackUp(diagValue2)
        }
        let entry = CacheEntry()
        entry.successful = ret
        entry.result = arg.GetTy()
        entry.diags = dc
        entry.targets = CollectTargets(arg)
        GetTypeCheckCache(ctx, arg).chkCache[key] = entry
        return ret
    }

    private func SynthesizeWithCache(ctx: ASTContext, pos: SynPos, expr: Expr): Ty {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Synthesize(ctx, pos, expr)
        }
        let key = GetCacheKeyForSyn(ctx, expr)
        let nodeCache = GetTypeCheckCache(ctx, expr)
        if (let Some(cache) <- nodeCache.synCache.get(key)) {
            RestoreCached(ctx, expr, cache)
            return cache.result ?? TypeManager.GetInvalidTy()
        }
        return SynthesizeAndCache(ctx, pos, expr, key)
    }

    private func CheckWithCache(ctx: ASTContext, target: Ty, expr: Expr): Bool {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Check(ctx, target, expr)
        }
        let key = GetCacheKeyForChk(ctx, expr, target)
        let nodeCache = GetTypeCheckCache(ctx, expr)
        if (let Some(cache) <- nodeCache.chkCache.get(key)) {
            RestoreCached(ctx, expr, cache)
            return cache.successful
        }
        return CheckAndCache(ctx, target, expr, key)
    }

    private func CheckWithCache(ctx: ASTContext, target: Ty, arg: FuncArg): Bool {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            GetTypeCheckCache(ctx, arg).lastKey = GetCacheKeyForChk(ctx, arg, target)
            return ChkFuncArg(ctx, target, arg)
        }
        let key = GetCacheKeyForChk(ctx, arg, target)
        let nodeCache = GetTypeCheckCache(ctx, arg)
        if (let Some(cache) <- nodeCache.chkCache.get(key)) {
            RestoreCached(ctx, arg, cache)
            return cache.successful
        }
        return CheckAndCache(ctx, target, arg, key)
    }

    private func SynthesizeWithNegCache(ctx: ASTContext, pos: SynPos, expr: Expr): Ty {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Synthesize(ctx, pos, expr)
        }
        let key = GetCacheKeyForSyn(ctx, expr)
        let nodeCache = GetTypeCheckCache(ctx, expr)
        if (let Some(cache) <- nodeCache.synCache.get(key)) {
            if (!cache.successful) {
                RestoreCached(ctx, expr, cache)
                return cache.result ?? TypeManager.GetInvalidTy()
            }
        }
        return SynthesizeAndCache(ctx, pos, expr, key)
    }

    private func CheckWithNegCache(ctx: ASTContext, target: Ty, expr: Expr): Bool {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Check(ctx, target, expr)
        }
        let key = GetCacheKeyForChk(ctx, expr, target)
        let nodeCache = GetTypeCheckCache(ctx, expr)
        if (let Some(cache) <- nodeCache.chkCache.get(key)) {
            if (!cache.successful) {
                RestoreCached(ctx, expr, cache)
                return false
            }
        }
        return CheckAndCache(ctx, target, expr, key)
    }

    private func CheckWithEffectiveCache(ctx: ASTContext, target: Ty, expr: Expr,
        recoverDiag: Bool): Bool {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Check(ctx, target, expr)
        }
        let key = GetCacheKeyForChk(ctx, expr, target)
        if (!Ty.IsInitialTy(expr.GetTy())) {
            let nodeCache = GetTypeCheckCache(ctx, expr)
            if (let Some(lastKey) <- nodeCache.lastKey) {
                if (lastKey == key) {
                    if (let Some(cache) <- nodeCache.chkCache.get(key)) {
                        RestoreCached(ctx, expr, cache, recoverDiag: recoverDiag)
                        return cache.successful
                    }
                    return CheckAndCache(ctx, target, expr, key)
                }
            }
        }
        expr.Clear()
        return CheckAndCache(ctx, target, expr, key)
    }

    private func CheckWithEffectiveCache(ctx: ASTContext, target: Ty, arg: FuncArg,
        recoverDiag: Bool): Bool {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            GetTypeCheckCache(ctx, arg).lastKey = GetCacheKeyForChk(ctx, arg, target)
            return ChkFuncArg(ctx, target, arg)
        }
        let key = GetCacheKeyForChk(ctx, arg, target)
        if (!Ty.IsInitialTy(arg.GetTy())) {
            let nodeCache = GetTypeCheckCache(ctx, arg)
            if (let Some(lastKey) <- nodeCache.lastKey) {
                if (lastKey == key) {
                    if (let Some(cache) <- nodeCache.chkCache.get(key)) {
                        RestoreCached(ctx, arg, cache, recoverDiag: recoverDiag)
                        return cache.successful
                    }
                    return CheckAndCache(ctx, target, arg, key)
                }
            }
        }
        arg.Clear()
        return CheckAndCache(ctx, target, arg, key)
    }

    private func ChkFuncArg(ctx: ASTContext, target: Ty, arg: FuncArg): Bool {
        if (let None <- arg.expr) {
            arg.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        if (arg.withInout) {
            return ChkFuncArgWithInout(ctx, target, arg)
        }
        let expr = arg.expr.getOrThrow()
        if (!Check(ctx, target, expr)) {
            arg.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        arg.SetTy(expr.GetTy() ?? TypeManager.GetInvalidTy())
        return true
    }

    private func ChkFuncArgWithInout(ctx: ASTContext, target: Ty, arg: FuncArg): Bool {
        let expr = arg.expr.getOrThrow()
        var realTarget = target
        var exprTy = expr.GetTy() ?? TypeManager.GetInvalidTy()
        if (!Ty.IsTyCorrect(exprTy)) {
            exprTy = Synthesize(ctx, SynPos.EXPR_ARG, expr)
        }
        let argTy = exprTy as VArrayTy
        let ptrParamTy = target as PointerTy
        let varrParamTy = target as VArrayTy
        if (let Some(argVArray) <- argTy) {
            if (let Some(ptrTy) <- ptrParamTy) {
                if (!ptrTy.typeArgs.isEmpty()) {
                    realTarget = impl.typeManager.GetVArrayTy(ptrTy.typeArgs[0], argVArray.size)
                }
            } else if (let Some(_) <- varrParamTy) {
                realTarget = target
            }
        } else if (let Some(ptrTy2) <- ptrParamTy) {
            if (!ptrTy2.typeArgs.isEmpty()) {
                realTarget = ptrTy2.typeArgs[0]
            }
        }
        if (!Ty.IsTyCorrect(exprTy) || !impl.typeManager.IsSubtype(exprTy, realTarget)) {
            if (Ty.IsTyCorrect(exprTy)) {
                if (let Some(diagValue) <- impl.diag) {
                    DiagMismatchedTypes(diagValue, expr, realTarget)
                }
            }
            arg.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        if (!ChkInoutFuncArg(arg)) {
            arg.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        let pointerArgTy = if (let Some(vArrayTarget) <- (realTarget as VArrayTy)) {
            vArrayTarget.typeArgs[0]
        } else {
            realTarget
        }
        arg.SetTy(impl.typeManager.GetPointerTy(pointerArgTy))
        return true
    }

    private func ChkInoutFuncArg(arg: FuncArg): Bool {
        let expr = arg.expr.getOrThrow()
        match (expr.astKind) {
            case ASTKind.REF_EXPR =>
                return ChkInoutRefExpr((expr as RefExpr).getOrThrow(), isBase: false)
            case ASTKind.MEMBER_ACCESS =>
                return ChkInoutMemberAccess((expr as MemberAccess).getOrThrow())
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(diagValue) <- impl.diag) {
                    let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                        MakeRange(expr.begin, expr.end))
                    builder.AddMainHintArguments("literal")
                    builder.Emit()
                }
                return false
            case _ =>
                if (let Some(diagValue2) <- impl.diag) {
                    let builder2 = diagValue2.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                        MakeRange(expr.begin, expr.end))
                    builder2.AddMainHintArguments(INOUT_TEMP_VALUE)
                    builder2.Emit()
                }
                return false
        }
    }

    private func ChkInoutRefExpr(refExpr: RefExpr, isBase!: Bool = false): Bool {
        let target = GetRealTarget(refExpr.GetTarget())
        let thisOrSuper = refExpr.isThis || refExpr.isSuper
        if (isBase && thisOrSuper) {
            return true
        }
        let targetIsVarOrParam = if (let Some(targetDecl) <- target) {
            targetDecl.astKind == ASTKind.VAR_DECL || targetDecl.astKind == ASTKind.FUNC_PARAM
        } else {
            false
        }
        if (thisOrSuper || !targetIsVarOrParam) {
            if (let Some(diagValue) <- impl.diag) {
                let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                    MakeRange(refExpr.begin, refExpr.end))
                builder.AddMainHintArguments("not a variable")
                builder.Emit()
            }
            return false
        }
        let varDecl = (target.getOrThrow() as VarDeclAbstract).getOrThrow()
        if (!varDecl.isVar) {
            if (let Some(diagValue2) <- impl.diag) {
                let builder2 = diagValue2.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                    MakeRange(refExpr.begin, refExpr.end))
                builder2.AddMainHintArguments(INOUT_IMMUTABLE)
                builder2.Emit()
            }
            return false
        }
        if (let Some(outerDecl) <- varDecl.outerDecl) {
            if (outerDecl.IsNominalDecl() && outerDecl.astKind != ASTKind.STRUCT_DECL &&
                !varDecl.TestAttr(Attribute.STATIC)) {
                if (let Some(diagValue3) <- impl.diag) {
                    let builder3 = diagValue3.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_modify_heap_variable,
                        MakeRange(refExpr.begin, refExpr.end))
                    builder3.Emit()
                }
                return false
            }
        }
        return true
    }

    private func ChkInoutMemberAccess(memberAccess: MemberAccess): Bool {
        if (let Some(desugar) <- memberAccess.desugarExpr) {
            if (desugar.astKind == ASTKind.LIT_CONST_EXPR) {
                if (let Some(diagValue) <- impl.diag) {
                    let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                        MakeRange(memberAccess.begin, memberAccess.end))
                    builder.AddMainHintArguments(INOUT_IMMUTABLE)
                    builder.Emit()
                }
                return false
            }
        }
        let target = memberAccess.GetTarget()
        if (let None <- target) {
            return false
        }
        var meetConstraints = true
        if (let Some(varDecl) <- (target.getOrThrow() as VarDeclAbstract)) {
            if (!varDecl.isVar) {
                if (let Some(diagValue2) <- impl.diag) {
                    let builder2 = diagValue2.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                        MakeRange(memberAccess.field.Begin(), memberAccess.field.End()))
                    builder2.AddMainHintArguments(INOUT_IMMUTABLE)
                    builder2.Emit()
                }
                meetConstraints = false
            }
            if (varDecl.TestAttr(Attribute.STATIC)) {
                return meetConstraints
            }
        } else {
            if (let Some(diagValue3) <- impl.diag) {
                let builder3 = diagValue3.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                    MakeRange(memberAccess.begin, memberAccess.end))
                if (target.getOrThrow().astKind == ASTKind.FUNC_DECL) {
                    builder3.AddMainHintArguments("function declaration")
                } else {
                    builder3.AddMainHintArguments(INOUT_TEMP_VALUE)
                }
                builder3.Emit()
            }
            meetConstraints = false
        }
        let baseExpr = match (memberAccess.baseExpr) {
            case Some(value) => value
            case None => return false
        }
        if (Ty.IsTyCorrect(baseExpr.GetTy()) && (baseExpr.GetTy().getOrThrow()).IsClassLike()) {
            if (let Some(diagValue4) <- impl.diag) {
                let builder4 = diagValue4.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_modify_heap_variable,
                    MakeRange(baseExpr.begin, baseExpr.end))
                builder4.Emit()
            }
            return false
        }
        if (let Some(baseRef) <- (baseExpr as RefExpr)) {
            return ChkInoutRefExpr(baseRef, isBase: true) && meetConstraints
        }
        if (let Some(baseMember) <- (baseExpr as MemberAccess)) {
            if (let Some(beTarget) <- GetRealTarget(baseExpr.GetTarget())) {
                if (beTarget.astKind != ASTKind.PACKAGE_DECL) {
                    return ChkInoutMemberAccess(baseMember) && meetConstraints
                }
            }
            return false
        }
        if (let Some(diagValue5) <- impl.diag) {
            let builder5 = diagValue5.DiagnoseRefactor(BasicDiagKindRefactor.sema_inout_must_be_var_variable,
                MakeRange(baseExpr.begin, baseExpr.end))
            builder5.AddMainHintArguments(INOUT_TEMP_VALUE)
            builder5.Emit()
        }
        return false
    }

    private func SynthesizeWithEffectiveCache(ctx: ASTContext, pos: SynPos, expr: Expr,
        recoverDiag: Bool): Ty {
        if (!impl.typeManager.GetUnsolvedTyVars().isEmpty()) {
            return Synthesize(ctx, pos, expr)
        }
        let key = GetCacheKeyForSyn(ctx, expr)
        if (!Ty.IsInitialTy(expr.GetTy())) {
            let nodeCache = GetTypeCheckCache(ctx, expr)
            if (let Some(lastKey) <- nodeCache.lastKey) {
                if (lastKey == key) {
                    if (let Some(cache) <- nodeCache.synCache.get(key)) {
                        RestoreCached(ctx, expr, cache, recoverDiag: recoverDiag)
                        return cache.result ?? TypeManager.GetInvalidTy()
                    }
                    return SynthesizeAndCache(ctx, pos, expr, key)
                }
            }
        }
        return SynthesizeAndCache(ctx, pos, expr, key)
    }

    private func LookupCoreTy(ctx: ASTContext, name: String): Option<Ty> {
        let _ = ctx
        if (let Some(manager) <- impl.importManager) {
            if (let Some(decl) <- manager.GetCoreDecl<Decl>(name)) {
                return decl.GetTy()
            }
        }
        return None
    }

    private func LookupCoreEnumDecl(ctx: ASTContext, name: String): Option<EnumDecl> {
        let _ = ctx
        if (let Some(manager) <- impl.importManager) {
            return manager.GetCoreDecl<EnumDecl>(name)
        }
        return None
    }

    private func SynthesizeThrowExpr(ctx: ASTContext, throwExpr: ThrowExpr): Ty {
        if (let Some(innerExpr) <- throwExpr.expr) {
            let _ = Synthesize(ctx, innerExpr)
        }
        return FinishSynthesize(ctx, throwExpr, SynThrowExpr(impl.typeManager, throwExpr,
            exceptionTy: LookupCoreTy(ctx, "Exception"), errorTy: LookupCoreTy(ctx, "Error"), diag: impl.diag))
    }

    private func SynthesizeTryCatchPatternTypes(ctx: ASTContext, pattern: Pattern): Unit {
        if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            for (typeNode in exceptPattern.types) {
                SynthesizeTypeNode(ctx, Some(typeNode))
            }
            if (let Some(inner) <- exceptPattern.pattern) {
                let target = CatchPatternBindingTargetTy(ctx, exceptPattern)
                let _ = ChkPattern(impl.typeManager, ctx, target, inner, isPatternInMatch: false,
                    exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                        Check(ctx, patternExpectedTy, patternExpr)
                    }), diag: impl.diag)
            }
            return
        }
        if (let Some(commandPattern) <- (pattern as CommandTypePattern)) {
            for (typeNode in commandPattern.types) {
                SynthesizeTypeNode(ctx, Some(typeNode))
            }
            if (let Some(innerCommandPattern) <- commandPattern.pattern) {
                let commandTarget = if (let Some(patternTy) <- commandPattern.GetTy()) {
                    if (Ty.IsTyCorrect(patternTy)) {
                        patternTy
                    } else if (!commandPattern.types.isEmpty()) {
                        commandPattern.types[0].GetTy() ?? TypeManager.GetInvalidTy()
                    } else {
                        TypeManager.GetInvalidTy()
                    }
                } else if (!commandPattern.types.isEmpty()) {
                    commandPattern.types[0].GetTy() ?? TypeManager.GetInvalidTy()
                } else {
                    TypeManager.GetInvalidTy()
                }
                let _ = ChkPattern(impl.typeManager, ctx, commandTarget, innerCommandPattern,
                    isPatternInMatch: false,
                    exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                        Check(ctx, patternExpectedTy, patternExpr)
                    }), diag: impl.diag)
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
        let _ = ChkPattern(impl.typeManager, ctx, catchTarget, pattern, isPatternInMatch: false,
            exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                Check(ctx, patternExpectedTy, patternExpr)
            }), diag: impl.diag)
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
        let commandTy: Option<Ty> = if (let Some(commandDecl) <- lookupResolvedPackageDecl(ctx, "stdx.effect", "Command")) {
            commandDecl.GetTy()
        } else {
            None
        }
        return FinishSynthesize(ctx, tryExpr, SynTryExpr(impl.typeManager, tryExpr, impl.diag.getOrThrow(),
            exceptionTy: LookupCoreTy(ctx, "Exception"), errorTy: LookupCoreTy(ctx, "Error"),
            commandTy: commandTy,
            patternChecker: Some({ targetTy: Ty, pattern: Pattern =>
                ChkPattern(impl.typeManager, ctx, targetTy, pattern, isPatternInMatch: false,
                    exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                        Check(ctx, patternExpectedTy, patternExpr)
                    }), diag: impl.diag)
            })))
    }

    private func CheckArrayLit(ctx: ASTContext, target: Ty, arrayLit: ArrayLit): Bool {
        let targetTy = UnboxOptionType(target)
        var arrayStruct: Option<StructDecl> = None
        if (let Some(manager) <- impl.importManager) {
            arrayStruct = manager.GetCoreDecl<StructDecl>("Array")
        }
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
        if (!ChkArrayLit(impl.typeManager, target, arrayLit, arrayStruct: arrayStruct, diag: impl.diag)) {
            matched = false
        }
        return matched
    }

    private func CheckTupleLit(ctx: ASTContext, target: Ty, tupleLit: TupleLit): Bool {
        return ChkTupleLit(impl.typeManager, target, tupleLit,
            check: Some({ targetTy: Ty, child: Expr => Check(ctx, targetTy, child) }), diag: impl.diag)
    }

    private func SynMultipleAssignExpr(ctx: ASTContext, ae: AssignExpr): Ty {
        CJC_ASSERT(ae.desugarExpr.isSome() && ae.rightExpr.isSome() && ae.leftValue.isSome())
        let desugar = ae.desugarExpr.getOrThrow()
        let _ = Synthesize(ctx, SynPos.UNUSED, desugar)
        ae.SetTy(desugar.GetTy().getOrThrow())
        let rightExpr = ae.rightExpr.getOrThrow()
        let _ = Synthesize(ctx, SynPos.EXPR_ARG, rightExpr)
        if (!Ty.IsTyCorrect(rightExpr.GetTy())) {
            return ae.GetTy().getOrThrow()
        }
        rightExpr.SetTy(TcReplaceIdeal(impl.typeManager, rightExpr))
        try (ds = DiagSuppressor(impl.diag.getOrThrow())) {
            let _ = Synthesize(ctx, SynPos.LEFT_VALUE, ae.leftValue.getOrThrow())
        }
        CheckMultipleAssignExpr(impl.diag.getOrThrow(), impl.typeManager, ae)
        return ae.GetTy().getOrThrow()
    }

    private func SynAssignExpr(ctx: ASTContext, ae: AssignExpr): Ty {
        if (let Some(desugar) <- ae.desugarExpr) {
            if (ae.leftValue.isSome() && ae.leftValue.getOrThrow().astKind == ASTKind.TUPLE_LIT) {
                return SynMultipleAssignExpr(ctx, ae)
            }
            return desugar.GetTy().getOrThrow()
        }
        let diagsForOverload = ArrayList<Diagnostic>()
        if (let Some(overloadTy) <- InferAssignExprCheckCaseOverloading(impl.typeManager, ctx, ae,
            diagsForOverload, { pos: SynPos, expr: Expr => Synthesize(ctx, pos, expr) },
            impl.diag.getOrThrow())) {
            return overloadTy
        }
        CJC_ASSERT(ae.leftValue.isSome() && ae.rightExpr.isSome())
        ae.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        let leftExpr = ae.leftValue.getOrThrow()
        let rightExpr = ae.rightExpr.getOrThrow()
        if (leftExpr.astKind == ASTKind.WILDCARD_EXPR) {
            if (Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, rightExpr))) {
                rightExpr.SetTy(TcReplaceIdeal(impl.typeManager, rightExpr))
            } else {
                ae.SetTy(TypeManager.GetInvalidTy())
            }
            leftExpr.SetTy(rightExpr.GetTy().getOrThrow())
            return ae.GetTy().getOrThrow()
        }
        let leftTy = Synthesize(ctx, SynPos.LEFT_VALUE, leftExpr)
        if (leftTy.IsInvalid()) {
            ae.SetTy(TypeManager.GetInvalidTy())
            return TypeManager.GetInvalidTy()
        }
        let concreteLeftTy = Ty.GetPrimitiveUpperBound(TcReplaceIdeal(impl.typeManager, leftExpr))
        if (!IsAssignable(leftExpr, ae.isCompound, diagsForOverload.toArray(), impl.diag.getOrThrow())) {
            return TypeManager.GetInvalidTy()
        }
        if (!PreCheckCompoundAssign(ae, concreteLeftTy, diagsForOverload.toArray(),
            { pos2: SynPos, expr2: Expr => Synthesize(ctx, pos2, expr2) }, impl.diag.getOrThrow())) {
            return TypeManager.GetInvalidTy()
        }
        if (ae.op == TokenKind.EXP_ASSIGN) {
            if (!CheckExponentByBaseTy(impl, concreteLeftTy, leftExpr, rightExpr, ctx: Some(ctx),
                synthesizer: Some({ operand: Expr => Synthesize(ctx, SynPos.EXPR_ARG, operand) }),
                checker: Some({ targetTy: Ty, operand2: Expr => Check(ctx, targetTy, operand2) }),
                diag: impl.diag)) {
                if (ae.ShouldDiagnose()) {
                    Diagnose(impl.diag.getOrThrow(), ae, BasicDiagKind.sema_type_incompatible,
                        args: [BasicDiagArgument("assignment")]).Emit()
                }
                ae.SetTy(TypeManager.GetInvalidTy())
            }
            return ae.GetTy().getOrThrow()
        }
        if (!ae.isCompound && leftExpr.GetTy().getOrThrow().IsRune() && IsSingleRuneStringLiteral(rightExpr)) {
            rightExpr.SetTy(leftExpr.GetTy().getOrThrow())
        } else if (!ae.isCompound && leftExpr.TyKind() == TypeKind.TYPE_UINT8 &&
            IsSingleByteStringLiteral(rightExpr)) {
            rightExpr.SetTy(leftExpr.GetTy().getOrThrow())
            let _ = ChkLitConstExprRange((rightExpr as LitConstExpr).getOrThrow())
        } else if (!Check(ctx, concreteLeftTy, rightExpr)) {
            if (ae.ShouldDiagnose() && !CanSkipDiag(rightExpr)) {
                Diagnose(impl.diag.getOrThrow(), ae, BasicDiagKind.sema_type_incompatible,
                    args: [BasicDiagArgument("assignment")]).Emit()
            }
            return TypeManager.GetInvalidTy()
        }
        if (!IsShiftAssignValid(ae, concreteLeftTy)) {
            return TypeManager.GetInvalidTy()
        }
        return ae.GetTy().getOrThrow()
    }

    private func ChkAssignExpr(ctx: ASTContext, target: Ty, ae: AssignExpr): Bool {
        if (!Ty.IsTyCorrect(SynAssignExpr(ctx, ae))) {
            return false
        }
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        if (impl.typeManager.IsSubtype(ae.GetTy().getOrThrow(), target)) {
            return true
        }
        DiagMismatchedTypesWithFoundTy(impl.diag.getOrThrow(), ae, target, unitTy,
            note: "the type of an assignment expression is always 'Unit'")
        ae.SetTy(TypeManager.GetInvalidTy())
        return false
    }

    private func Synthesize(ctx: ASTContext, expr: Expr): Ty {
        return Synthesize(ctx, SynPos.NONE, expr)
    }

    private func Synthesize(ctx: ASTContext, pos: SynPos, expr: Expr): Ty {
        if (expr.TestAttr(Attribute.IS_BROKEN)) {
            expr.SetTy(TypeManager.GetInvalidTy())
            return expr.GetTy() ?? TypeManager.GetInvalidTy()
        }
        if (impl.typeManager.GetUnsolvedTyVars().isEmpty() && ctx.IsSynSkippedForCorrectTy(expr)) {
            return expr.GetTy() ?? TypeManager.GetInvalidTy()
        }
        GetTypeCheckCache(ctx, expr).lastKey = GetCacheKeyForSyn(ctx, expr)
        if (let Some(incOrDec) <- (expr as IncOrDecExpr)) {
            return FinishSynthesize(ctx, incOrDec, SynIncOrDecExpr(incOrDec,
                { leftValue: Expr => Synthesize(ctx, SynPos.LEFT_VALUE, leftValue) },
                { desugar: Expr => Synthesize(ctx, SynPos.UNUSED, desugar) },
                diag: impl.diag))
        }
        if (let Some(syncExpr) <- (expr as SynchronizedExpr)) {
            var lockTy: Option<Ty> = None
            if (let Some(manager) <- impl.importManager) {
                if (let Some(lockDecl) <- manager.GetSyncDecl("Lock")) {
                    lockTy = lockDecl.GetTy()
                }
            }
            return FinishSynthesize(ctx, syncExpr, SynSyncExpr(impl.typeManager, syncExpr, lockTy: lockTy,
                diag: impl.diag,
                checker: Some({ targetTy: Ty, mutexExpr: Expr => Check(ctx, targetTy, mutexExpr) }),
                synthesizer: Some({ node: Node => SynthesizeNode(ctx, SynPos.EXPR_ARG, node) }),
                trySynthesizer: Some({ tryExpr: TryExpr => Synthesize(ctx, tryExpr) })))
        }
        if (let Some(desugar) <- expr.desugarExpr) {
            let _ = Synthesize(ctx, pos, desugar)
        }
        if (let Some(block) <- (expr as Block)) {
            return SynthesizeBlock(ctx, pos, block)
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            SynthesizeCallChildren(ctx, callExpr)
            let callTy = SynCallExprWithArgChecker(impl.typeManager, callExpr,
                Some({ target: Ty, arg: FuncArg => CheckCallArgFromContext(ctx, target, arg) }), diag: impl.diag,
                declSynthesizer: Some({ fd: FuncDecl => Ty.IsTyCorrect(SynthesizeDecl(ctx, fd)) }), ctx: Some(ctx),
                variadicDesugar: Some({ vce: CallExpr, arity: Int64 => DesugarVariadicCallExpr(vce, arity) }),
                desugarCallExpr: Some({ callExprForDesugar: CallExpr => DesugarCallExpr(callExprForDesugar) }),
                importManager: impl.importManager,
                typeChecker: Some({ targetTy: Ty, typeNode: Type =>
                    if (!Ty.IsTyCorrect(targetTy)) {
                        typeNode.SetTy(TypeManager.GetInvalidTy())
                        false
                    } else {
                        typeCheckExprPutTargetType(ctx, typeNode, targetTy)
                        let checkRet = if (typeNode.TestAttr(Attribute.IS_BROKEN)) {
                            typeNode.SetTy(TypeManager.GetInvalidTy())
                            false
                        } else if (targetTy.HasQuestTy() && !IsQuestableNode(typeNode)) {
                            false
                        } else {
                            let _ = SynthesizeNode(ctx, SynPos.NONE, typeNode)
                            let _ = ReplaceIdealTy(impl.typeManager, typeNode, diag: impl.diag)
                            impl.typeManager.IsSubtype(typeNode.GetTy() ?? TypeManager.GetInvalidTy(), targetTy)
                        }
                        typeCheckExprClearTargetType(ctx, typeNode)
                        typeNode.SetTy(impl.typeManager.TryGreedySubst(typeNode.GetTy() ?? TypeManager.GetInvalidTy()))
                        checkRet
                    }
                }),
                typeSynthesizer: Some({ typeNode: Type => SynthesizeNode(ctx, SynPos.NONE, typeNode) }),
                argSynthesizer: Some({ arg: FuncArg => SynthesizeFuncArg(ctx, arg) }),
                exprSynthesizer: Some({ child: Expr => SynthesizeWithCache(ctx, SynPos.EXPR_ARG, child) }),
                effectiveArgChecker: Some({ expectedTy: Ty, arg: FuncArg =>
                    CheckWithEffectiveCache(ctx, expectedTy, arg, false)
                }))
            return FinishSynthesize(ctx, callExpr, callTy)
        }
        if (let Some(ifExpr) <- (expr as IfExpr)) {
            return SynthesizeIfExpr(ctx, pos, ifExpr)
        }
        if (let Some(matchExpr) <- (expr as MatchExpr)) {
            let boundDecls = SynthesizeMatchChildren(ctx, matchExpr)
            let matchTy = SynMatchExpr(impl.typeManager, ctx, matchExpr, diag: impl.diag,
                exprChecker: Some({ target: Ty, expr: Expr =>
                    Check(ctx, target, expr)
                }), desugarCallExpr: Some({ callExprForDesugar: CallExpr =>
                    DesugarCallExpr(callExprForDesugar)
                }))
            ctx.SkipSynForCorrectTy(matchExpr)
            RemovePatternBindings(ctx, boundDecls)
            return matchTy
        }
        if (let Some(jumpExpr) <- (expr as JumpExpr)) {
            return FinishSynthesize(ctx, jumpExpr, SynLoopControlExpr(ctx, jumpExpr))
        }
        if (let Some(forInExpr) <- (expr as ForInExpr)) {
            return FinishSynthesize(ctx, forInExpr, SynthesizeForInExpr(ctx, forInExpr))
        }
        if (let Some(whileExpr) <- (expr as WhileExpr)) {
            let conditionBindings = ArrayList<Decl>()
            var isWellTyped = true
            isWellTyped = CheckConditionWithBindings(ctx, whileExpr.condExpr.getOrThrow(),
                conditionBindings, false) && isWellTyped
            isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, SynPos.UNUSED, whileExpr.body.getOrThrow())) &&
                isWellTyped
            RemovePatternBindings(ctx, conditionBindings)
            let whileTy = if (isWellTyped) {
                TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            } else {
                TypeManager.GetInvalidTy()
            }
            whileExpr.SetTy(whileTy)
            return FinishSynthesize(ctx, whileExpr, whileTy)
        }
        if (let Some(doWhileExpr) <- (expr as DoWhileExpr)) {
            var isWellTyped2 = true
            isWellTyped2 = Ty.IsTyCorrect(Synthesize(ctx, SynPos.UNUSED, doWhileExpr.body.getOrThrow())) &&
                isWellTyped2
            let conditionBindings2 = ArrayList<Decl>()
            isWellTyped2 = CheckConditionWithBindings(ctx, doWhileExpr.condExpr.getOrThrow(),
                conditionBindings2, false) && isWellTyped2
            RemovePatternBindings(ctx, conditionBindings2)
            let doWhileTy = if (isWellTyped2) {
                TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            } else {
                TypeManager.GetInvalidTy()
            }
            doWhileExpr.SetTy(doWhileTy)
            return FinishSynthesize(ctx, doWhileExpr, doWhileTy)
        }
        if (let Some(returnExpr) <- (expr as ReturnExpr)) {
            if (let Some(fb) <- currentFuncBody) {
                returnExpr.refFuncBody = Some(fb)
            }
            return FinishSynthesize(ctx, returnExpr, SynthesizeReturnExpr(ctx, returnExpr))
        }
        if (let Some(lambdaExpr) <- (expr as LambdaExpr)) {
            return FinishSynthesize(ctx, lambdaExpr, SynLamExpr(ctx, lambdaExpr))
        }
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            return FinishSynthesize(ctx, parenExpr, SynParenExpr(impl.typeManager, parenExpr,
                synthesizer: Some({ innerExpr: Expr => Synthesize(ctx, pos, innerExpr) })))
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            if (typeCheckExprIsLogicalOperator(binaryExpr.op)) {
                if (let None <- binaryExpr.desugarExpr) {
                    return FinishSynthesize(ctx, binaryExpr, SynthesizeLogicalBinaryExpr(ctx, binaryExpr))
                }
            }
            SynthesizeBinaryChildren(ctx, binaryExpr)
            let binaryTy = SynBinaryExpr(impl, binaryExpr, ctx: Some(ctx),
                synthesizer: Some({ operand: Expr => SynthesizeWithNegCache(ctx, SynPos.EXPR_ARG, operand) }),
                checker: Some({ targetTy: Ty, operand2: Expr => CheckWithNegCache(ctx, targetTy, operand2) }),
                diag: impl.diag)
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
            return FinishSynthesize(ctx, subscript, SynSubscriptExpr(impl.typeManager, ctx, subscript,
                { subscriptPos: SynPos, child: Expr => Synthesize(ctx, subscriptPos, child) },
                { subscriptTarget: Ty, child2: Expr => Check(ctx, subscriptTarget, child2) },
                impl.diag.getOrThrow()))
        }
        if (let Some(assign) <- (expr as AssignExpr)) {
            return FinishSynthesize(ctx, assign, SynAssignExpr(ctx, assign))
        }
        if (let Some(throwExpr) <- (expr as ThrowExpr)) {
            return SynthesizeThrowExpr(ctx, throwExpr)
        }
        if (let Some(tryExpr) <- (expr as TryExpr)) {
            return SynthesizeTryExpr(ctx, tryExpr)
        }
        if (let Some(resumeExpr) <- (expr as ResumeExpr)) {
            return FinishSynthesize(ctx, resumeExpr, SynResumeExpr(impl.typeManager, resumeExpr,
                exceptionTy: LookupCoreTy(ctx, "Exception"), errorTy: LookupCoreTy(ctx, "Error"),
                synthesizer: Some({ innerExpr: Expr => Synthesize(ctx, SynPos.EXPR_ARG, innerExpr) }),
                checker: Some({ targetTy: Ty, innerExpr2: Expr => Check(ctx, targetTy, innerExpr2) }),
                diag: impl.diag))
        }
        if (let Some(typeConv) <- (expr as TypeConvExpr)) {
            return FinishSynthesize(ctx, typeConv, SynTypeConvExpr(impl.typeManager, typeConv,
                synthesizer: Some({ innerExpr: Expr => Synthesize(ctx, SynPos.EXPR_ARG, innerExpr) }),
                diag: impl.diag))
        }
        if (let Some(isExpr) <- (expr as IsExpr)) {
            SynthesizeTypeNode(ctx, isExpr.isType)
            if (let Some(leftExpr) <- isExpr.leftExpr) {
                let _ = Synthesize(ctx, leftExpr)
            }
            return FinishSynthesize(ctx, isExpr, SynExprShallow(impl.typeManager, isExpr, ctx: Some(ctx),
                diag: impl.diag, importManager: impl.importManager))
        }
        if (let Some(asExpr) <- (expr as AsExpr)) {
            SynthesizeTypeNode(ctx, asExpr.asType)
            if (let Some(leftExpr2) <- asExpr.leftExpr) {
                let _ = Synthesize(ctx, leftExpr2)
            }
            return FinishSynthesize(ctx, asExpr, SynAsExpr(impl.typeManager, asExpr,
                LookupCoreEnumDecl(ctx, "Option"), diag: impl.diag))
        }
        if (let Some(optionalChain) <- (expr as OptionalChainExpr)) {
            return FinishSynthesize(ctx, optionalChain, SynOptionalChainExpr(impl.typeManager, optionalChain,
                synthesizer: Some({ innerExpr: Expr => Synthesize(ctx, pos, innerExpr) })))
        }
        if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
            SynthesizeTypeNode(ctx, arrayExpr.typeNode)
            if (arrayExpr.isValueArray) {
                return FinishSynthesize(ctx, arrayExpr, SynVArrayExpr(impl.typeManager, arrayExpr,
                    checker: Some({ target: Ty, arg: FuncArg => CheckCallArgFromContext(ctx, target, arg) }),
                    diag: impl.diag))
            }
            for (arg in arrayExpr.args) {
                let _ = SynthesizeFuncArg(ctx, arg)
            }
            return FinishSynthesize(ctx, arrayExpr, SynArrayExpr(impl.typeManager, arrayExpr, diag: impl.diag))
        }
        if (let Some(pointerExpr) <- (expr as PointerExpr)) {
            return FinishSynthesize(ctx, pointerExpr, SynPointerExpr(impl.typeManager, pointerExpr,
                typeSynthesizer: Some({ typeNode: Type => SynthesizeNode(ctx, SynPos.NONE, typeNode) }),
                argSynthesizer: Some({ arg: FuncArg => SynthesizeFuncArg(ctx, arg) }), diag: impl.diag))
        }
        if (isStringLiteral(expr)) {
            if (let Some(lit) <- (expr as LitConstExpr)) {
                var stringTy: Option<Ty> = None
                if (let Some(manager) <- impl.importManager) {
                    if (let Some(stringDecl) <- manager.GetCoreDecl<Decl>("String")) {
                        stringTy = stringDecl.GetTy()
                    }
                }
                var toStringTy: Option<Ty> = None
                if (let Some(manager2) <- impl.importManager) {
                    if (let Some(toStringDecl) <- manager2.GetCoreDecl<Decl>("ToString")) {
                        toStringTy = toStringDecl.GetTy()
                    }
                }
                return FinishSynthesize(ctx, lit,
                    SynLitConstExpr(lit, stringTy: stringTy, toStringTy: toStringTy,
                        typeManager: Some(impl.typeManager), ctx: Some(ctx),
                        synthesizer: Some({ block: Block => Synthesize(ctx, SynPos.EXPR_ARG, block) }),
                        checker: Some({ targetTy: Ty, partExpr: Expr => Check(ctx, targetTy, partExpr) }),
                        diag: impl.diag))
            }
        }
        SynthesizeNodeChildren(ctx, expr)
        if (let Some(rangeExpr) <- (expr as RangeExpr)) {
            var rangeStruct: Option<StructDecl> = None
            if (let Some(manager3) <- impl.importManager) {
                rangeStruct = manager3.GetCoreDecl<StructDecl>("Range")
            }
            return FinishSynthesize(ctx, rangeExpr, SynRangeExpr(impl.typeManager, rangeExpr, rangeDecl: rangeStruct,
                ctx: Some(ctx), checker: Some({ targetTy: Ty, child: Expr => Check(ctx, targetTy, child) }),
                checkGenericDeclInstantiation: Some({ decl: Option<Decl>, typeArgs: ArrayList<Ty>, node: Node =>
                    impl.CheckGenericDeclInstantiation(decl, typeArgs, node)
                }), diag: impl.diag))
        }
        if (let Some(arrayLit) <- (expr as ArrayLit)) {
            var arrayStruct: Option<StructDecl> = None
            if (let Some(manager4) <- impl.importManager) {
                arrayStruct = manager4.GetCoreDecl<StructDecl>("Array")
            }
            let arrayTy = SynArrayLit(impl.typeManager, arrayLit, arrayStruct, diag: impl.diag)
            return FinishSynthesize(ctx, arrayLit, arrayTy)
        }
        if (let Some(spawnExpr) <- (expr as SpawnExpr)) {
            return SynthesizeSpawnExpr(ctx, spawnExpr)
        }
        return FinishSynthesize(ctx, expr,
            SynExprShallow(impl.typeManager, expr, diag: impl.diag, importManager: impl.importManager))
    }

    private func SynthesizeLogicalBinaryExpr(ctx: ASTContext, be: BinaryExpr): Ty {
        if (let None <- be.leftExpr) {
            let invalidTy = TypeManager.GetInvalidTy()
            be.SetTy(invalidTy)
            return invalidTy
        }
        if (let None <- be.rightExpr) {
            let invalidTy2 = TypeManager.GetInvalidTy()
            be.SetTy(invalidTy2)
            return invalidTy2
        }
        let leftExpr = be.leftExpr.getOrThrow()
        let rightExpr = be.rightExpr.getOrThrow()
        let leftTy = Synthesize(ctx, leftExpr)
        let rightTy = Synthesize(ctx, rightExpr)
        if (!Ty.IsTyCorrect(leftTy) || !Ty.IsTyCorrect(rightTy)) {
            let invalidTy3 = TypeManager.GetInvalidTy()
            be.SetTy(invalidTy3)
            return invalidTy3
        }
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        if (impl.typeManager.IsSubtype(leftTy, boolTy) && impl.typeManager.IsSubtype(rightTy, boolTy)) {
            be.SetTy(boolTy)
            return boolTy
        }
        let invalidTy4 = TypeManager.GetInvalidTy()
        be.SetTy(invalidTy4)
        return invalidTy4
    }

    private func CheckLogicalBinaryExpr(ctx: ASTContext, target: Ty, be: BinaryExpr): Bool {
        if (let None <- be.leftExpr) {
            be.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        if (let None <- be.rightExpr) {
            be.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        if (!target.IsBoolean()) {
            if (!impl.typeManager.IsLitBoxableType(boolTy, target)) {
                be.SetTy(TypeManager.GetInvalidTy())
                return false
            }
        }
        let leftExpr = be.leftExpr.getOrThrow()
        let rightExpr = be.rightExpr.getOrThrow()
        var ok = true
        if (!CheckWithNegCache(ctx, boolTy, leftExpr)) {
            ok = false
        }
        if (!CheckWithNegCache(ctx, boolTy, rightExpr)) {
            ok = false
        }
        if (ok) {
            be.SetTy(boolTy)
            return true
        }
        be.SetTy(TypeManager.GetInvalidTy())
        return false
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
            let leftOk = CheckWithNegCache(ctx, candidateTy, leftExpr)
            let rightOk = CheckWithNegCache(ctx, candidateTy, rightExpr)
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
        return ChkBinaryExpr(impl, target, be, ctx: Some(ctx),
            synthesizer: Some({ operand: Expr => SynthesizeWithNegCache(ctx, SynPos.EXPR_ARG, operand) }),
            checker: Some({ targetTy: Ty, operand2: Expr => CheckWithNegCache(ctx, targetTy, operand2) }),
            diag: impl.diag)
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
        DesugarOperatorOverloadExpr(be, ctx: Some(ctx))
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
        DesugarOperatorOverloadExpr(be, ctx: Some(ctx))
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

    private func Check(ctx: ASTContext, target: Ty, expr: Expr, clearInferredCallTypes!: Bool = true): Bool {
        if (!Ty.IsTyCorrect(target)) {
            expr.SetTy(TypeManager.GetInvalidTy())
            typeCheckExprClearTargetType(ctx, expr)
            return false
        }
        typeCheckExprPutTargetType(ctx, expr, target)
        if (expr.TestAttr(Attribute.IS_BROKEN)) {
            expr.SetTy(TypeManager.GetInvalidTy())
            typeCheckExprClearTargetType(ctx, expr)
            return false
        }
        if (target.HasQuestTy() && !IsQuestableNode(expr)) {
            return false
        }
        GetTypeCheckCache(ctx, expr).lastKey = GetCacheKeyForChk(ctx, expr, target)
        if (let Some(lambda) <- (expr as LambdaExpr)) {
            return FinishCheck(ctx, lambda, CheckLambdaExprWithTarget(ctx, target, lambda))
        }
        if (let Some(block) <- (expr as Block)) {
            let ok = CheckBlock(ctx, target, block)
            typeCheckExprClearTargetType(ctx, expr)
            return ok
        }
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            typeCheckExprPutTargetType(ctx, nameRef, target)
            let _ = SynthesizeNameReference(ctx, nameRef)
            let ok = ChkNameReferenceExpr(impl.typeManager, target, nameRef, diag: impl.diag)
            if (ok) {
                ctx.SkipSynForCorrectTy(nameRef)
            }
            return FinishCheck(ctx, expr, ok)
        }
        if (let Some(subscript) <- (expr as SubscriptExpr)) {
            return FinishCheck(ctx, subscript, ChkSubscriptExpr(impl.typeManager, ctx, Some(target), subscript,
                { subscriptPos: SynPos, child: Expr => Synthesize(ctx, subscriptPos, child) },
                { subscriptTarget: Ty, child2: Expr => Check(ctx, subscriptTarget, child2) },
                impl.diag.getOrThrow()))
        }
        if (let Some(assign) <- (expr as AssignExpr)) {
            return FinishCheck(ctx, assign, ChkAssignExpr(ctx, target, assign))
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            typeCheckExprPutTargetType(ctx, callExpr, target)
            SynthesizeCallChildren(ctx, callExpr)
            let ok = ChkCallExprWithArgChecker(impl.typeManager, impl.diag, Some(target), callExpr,
                Some({ paramTy: Ty, arg: FuncArg => CheckCallArgFromContext(ctx, paramTy, arg) }),
                desugarChecker: Some({ target2: Ty, expr2: Expr => Check(ctx, target2, expr2) }),
                clearInferredForTarget: clearInferredCallTypes,
                declSynthesizer: Some({ fd: FuncDecl => Ty.IsTyCorrect(SynthesizeDecl(ctx, fd)) }), ctx: Some(ctx),
                variadicDesugar: Some({ vce: CallExpr, arity: Int64 => DesugarVariadicCallExpr(vce, arity) }),
                desugarCallExpr: Some({ callExprForDesugar: CallExpr => DesugarCallExpr(callExprForDesugar) }),
                importManager: impl.importManager,
                typeChecker: Some({ targetTy: Ty, typeNode: Type =>
                    if (!Ty.IsTyCorrect(targetTy)) {
                        typeNode.SetTy(TypeManager.GetInvalidTy())
                        false
                    } else {
                        typeCheckExprPutTargetType(ctx, typeNode, targetTy)
                        let checkRet = if (typeNode.TestAttr(Attribute.IS_BROKEN)) {
                            typeNode.SetTy(TypeManager.GetInvalidTy())
                            false
                        } else if (targetTy.HasQuestTy() && !IsQuestableNode(typeNode)) {
                            false
                        } else {
                            let _ = SynthesizeNode(ctx, SynPos.NONE, typeNode)
                            let _ = ReplaceIdealTy(impl.typeManager, typeNode, diag: impl.diag)
                            impl.typeManager.IsSubtype(typeNode.GetTy() ?? TypeManager.GetInvalidTy(), targetTy)
                        }
                        typeCheckExprClearTargetType(ctx, typeNode)
                        typeNode.SetTy(impl.typeManager.TryGreedySubst(typeNode.GetTy() ?? TypeManager.GetInvalidTy()))
                        checkRet
                    }
                }),
                typeSynthesizer: Some({ typeNode: Type => SynthesizeNode(ctx, SynPos.NONE, typeNode) }),
                argSynthesizer: Some({ arg: FuncArg => SynthesizeFuncArg(ctx, arg) }),
                exprSynthesizer: Some({ child: Expr => SynthesizeWithCache(ctx, SynPos.EXPR_ARG, child) }),
                effectiveArgChecker: Some({ expectedTy: Ty, arg: FuncArg =>
                    CheckWithEffectiveCache(ctx, expectedTy, arg, false)
                }))
            return FinishCheck(ctx, callExpr, ok)
        }
        if (let Some(ifExpr) <- (expr as IfExpr)) {
            return FinishCheck(ctx, ifExpr, CheckIfExprWithTarget(ctx, target, ifExpr))
        }
        if (let Some(matchExpr) <- (expr as MatchExpr)) {
            let boundDecls = SynthesizeMatchChildren(ctx, matchExpr)
            let matchOk = ChkMatchExpr(impl.typeManager, ctx, target, matchExpr, diag: impl.diag,
                exprChecker: Some({ target2: Ty, expr: Expr =>
                    Check(ctx, target2, expr)
                }), desugarCallExpr: Some({ callExprForDesugar: CallExpr =>
                    DesugarCallExpr(callExprForDesugar)
                }))
            if (matchOk) {
                ctx.SkipSynForCorrectTy(matchExpr)
            }
            typeCheckExprClearTargetType(ctx, matchExpr)
            RemovePatternBindings(ctx, boundDecls)
            return matchOk
        }
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            return FinishCheck(ctx, parenExpr, ChkParenExpr(impl.typeManager, target, parenExpr,
                checker: Some({ targetTy: Ty, innerExpr: Expr => Check(ctx, targetTy, innerExpr) })))
        }
        if (let Some(jumpExpr) <- (expr as JumpExpr)) {
            return FinishCheck(ctx, jumpExpr, ChkLoopControlExpr(ctx, jumpExpr))
        }
        if (let Some(forInExpr) <- (expr as ForInExpr)) {
            let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            var isWellTyped = impl.typeManager.IsSubtype(unitTy, target)
            if (!isWellTyped) {
                if (let Some(diagValue) <- impl.diag) {
                    DiagMismatchedTypesWithFoundTy(diagValue, forInExpr, target, unitTy)
                }
            }
            isWellTyped = Ty.IsTyCorrect(SynthesizeForInExpr(ctx, forInExpr)) && isWellTyped
            return FinishCheck(ctx, forInExpr, isWellTyped)
        }
        if (let Some(whileExpr) <- (expr as WhileExpr)) {
            let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            var isWellTyped = impl.typeManager.IsSubtype(unitTy, target)
            if (!isWellTyped) {
                if (let Some(diagValue) <- impl.diag) {
                    DiagMismatchedTypesWithFoundTy(diagValue, whileExpr, target, unitTy)
                }
            }
            isWellTyped = Ty.IsTyCorrect(Synthesize(ctx, whileExpr)) && isWellTyped
            return FinishCheck(ctx, whileExpr, isWellTyped)
        }
        if (let Some(doWhileExpr) <- (expr as DoWhileExpr)) {
            let unitTy2 = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            var isWellTyped2 = impl.typeManager.IsSubtype(unitTy2, target)
            if (!isWellTyped2) {
                if (let Some(diagValue2) <- impl.diag) {
                    DiagMismatchedTypesWithFoundTy(diagValue2, doWhileExpr, target, unitTy2)
                }
            }
            isWellTyped2 = Ty.IsTyCorrect(Synthesize(ctx, doWhileExpr)) && isWellTyped2
            return FinishCheck(ctx, doWhileExpr, isWellTyped2)
        }
        if (let Some(rangeExpr) <- (expr as RangeExpr)) {
            var rangeStruct: Option<StructDecl> = None
            if (let Some(manager) <- impl.importManager) {
                rangeStruct = manager.GetCoreDecl<StructDecl>("Range")
            }
            return FinishCheck(ctx, rangeExpr, ChkRangeExpr(impl.typeManager, target, rangeExpr,
                rangeDecl: rangeStruct, ctx: Some(ctx),
                checker: Some({ targetTy: Ty, child: Expr => Check(ctx, targetTy, child) }),
                checkGenericDeclInstantiation: Some({ decl: Option<Decl>, typeArgs: ArrayList<Ty>, node: Node =>
                    impl.CheckGenericDeclInstantiation(decl, typeArgs, node)
                }), diag: impl.diag))
        }
        if (let Some(lit) <- (expr as LitConstExpr)) {
            var stringTy: Option<Ty> = None
            var toStringTy: Option<Ty> = None
            if (isStringLiteral(lit)) {
                if (let Some(manager2) <- impl.importManager) {
                    if (let Some(stringDecl) <- manager2.GetCoreDecl<Decl>("String")) {
                        stringTy = stringDecl.GetTy()
                    }
                }
                if (let Some(manager3) <- impl.importManager) {
                    if (let Some(toStringDecl) <- manager3.GetCoreDecl<Decl>("ToString")) {
                        toStringTy = toStringDecl.GetTy()
                    }
                }
            }
            return FinishCheck(ctx, lit, ChkLitConstExpr(impl.typeManager, target, lit, stringTy: stringTy,
                toStringTy: toStringTy, ctx: Some(ctx),
                synthesizer: Some({ block: Block => Synthesize(ctx, SynPos.EXPR_ARG, block) }),
                checker: Some({ targetTy: Ty, partExpr: Expr => Check(ctx, targetTy, partExpr) }),
                diag: impl.diag))
        }
        if (let Some(arrayLit) <- (expr as ArrayLit)) {
            return FinishCheck(ctx, arrayLit, CheckArrayLit(ctx, target, arrayLit))
        }
        if (let Some(tupleLit) <- (expr as TupleLit)) {
            return FinishCheck(ctx, tupleLit, CheckTupleLit(ctx, target, tupleLit))
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            return FinishCheck(ctx, binaryExpr, CheckBinaryExpr(ctx, target, binaryExpr))
        }
        if (let Some(incOrDec) <- (expr as IncOrDecExpr)) {
            return FinishCheck(ctx, incOrDec, ChkIncOrDecExpr(impl.typeManager, target, incOrDec,
                { leftValue: Expr => Synthesize(ctx, SynPos.LEFT_VALUE, leftValue) },
                { desugar: Expr => Synthesize(ctx, SynPos.UNUSED, desugar) },
                diag: impl.diag))
        }
        if (let Some(unaryExpr) <- (expr as UnaryExpr)) {
            return FinishCheck(ctx, unaryExpr, CheckUnaryExprWithTarget(ctx, target, unaryExpr))
        }
        if (let Some(returnExpr) <- (expr as ReturnExpr)) {
            if (let Some(fb) <- currentFuncBody) {
                returnExpr.refFuncBody = Some(fb)
            }
            return FinishCheck(ctx, returnExpr, Ty.IsTyCorrect(SynthesizeReturnExpr(ctx, returnExpr)))
        }
        if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
            let _ = SynthesizeNameReference(ctx, nameRef)
            return FinishCheck(ctx, expr, ChkExprShallow(impl.typeManager, target, expr, ctx: Some(ctx),
                diag: impl.diag, importManager: impl.importManager))
        }
        if (let Some(throwExpr) <- (expr as ThrowExpr)) {
            let throwTy = SynthesizeThrowExpr(ctx, throwExpr)
            return FinishCheck(ctx, throwExpr, Ty.IsTyCorrect(throwTy) &&
                impl.typeManager.CheckTypeCompatibility(target, throwTy) != TypeCompatibility.INCOMPATIBLE)
        }
        if (let Some(tryExpr) <- (expr as TryExpr)) {
            SynthesizeTryExprChildren(ctx, tryExpr)
            let commandTy: Option<Ty> = if (let Some(commandDecl) <- lookupResolvedPackageDecl(ctx, "stdx.effect", "Command")) {
                commandDecl.GetTy()
            } else {
                None
            }
            return FinishCheck(ctx, tryExpr, ChkTryExpr(impl.typeManager, target, tryExpr,
                exceptionTy: LookupCoreTy(ctx, "Exception"), errorTy: LookupCoreTy(ctx, "Error"),
                commandTy: commandTy, diag: impl.diag,
                patternChecker: Some({ targetTy: Ty, pattern: Pattern =>
                    ChkPattern(impl.typeManager, ctx, targetTy, pattern, isPatternInMatch: false,
                        exprChecker: Some({ patternExpectedTy: Ty, patternExpr: Expr =>
                            Check(ctx, patternExpectedTy, patternExpr)
                        }), diag: impl.diag)
                })))
        }
        if (let Some(typeConv) <- (expr as TypeConvExpr)) {
            return FinishCheck(ctx, typeConv, ChkTypeConvExpr(impl.typeManager, target, typeConv,
                synthesizer: Some({ innerExpr: Expr => Synthesize(ctx, SynPos.EXPR_ARG, innerExpr) }),
                diag: impl.diag))
        }
        if (let Some(syncExpr) <- (expr as SynchronizedExpr)) {
            var lockTy: Option<Ty> = None
            if (let Some(manager4) <- impl.importManager) {
                if (let Some(lockDecl) <- manager4.GetSyncDecl("Lock")) {
                    lockTy = lockDecl.GetTy()
                }
            }
            return FinishCheck(ctx, syncExpr, ChkSyncExpr(impl.typeManager, syncExpr, lockTy: lockTy,
                targetTy: Some(target), diag: impl.diag,
                checker: Some({ targetTy2: Ty, mutexExpr: Expr => Check(ctx, targetTy2, mutexExpr) }),
                synthesizer: Some({ node: Node => SynthesizeNode(ctx, SynPos.EXPR_ARG, node) }),
                tryChecker: Some({ targetTy3: Ty, tryExpr2: TryExpr => Check(ctx, targetTy3, tryExpr2) })))
        }
        if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
            SynthesizeTypeNode(ctx, arrayExpr.typeNode)
            if (arrayExpr.isValueArray) {
                return FinishCheck(ctx, arrayExpr, ChkVArrayExpr(impl.typeManager, target, arrayExpr,
                    checker: Some({ targetTy: Ty, arg: FuncArg => CheckCallArgFromContext(ctx, targetTy, arg) }),
                    diag: impl.diag))
            }
            for (arg in arrayExpr.args) {
                let _ = SynthesizeFuncArg(ctx, arg)
            }
            return FinishCheck(ctx, arrayExpr, ChkArrayExpr(impl.typeManager, target, arrayExpr, diag: impl.diag))
        }
        if (let Some(pointerExpr) <- (expr as PointerExpr)) {
            return FinishCheck(ctx, pointerExpr, ChkPointerExpr(impl.typeManager, target, pointerExpr,
                typeChecker: Some({ targetTy: Ty, typeNode: Type =>
                    if (!Ty.IsTyCorrect(targetTy)) {
                        typeNode.SetTy(TypeManager.GetInvalidTy())
                        false
                    } else {
                        typeCheckExprPutTargetType(ctx, typeNode, targetTy)
                        let checkRet = if (typeNode.TestAttr(Attribute.IS_BROKEN)) {
                            typeNode.SetTy(TypeManager.GetInvalidTy())
                            false
                        } else if (targetTy.HasQuestTy() && !IsQuestableNode(typeNode)) {
                            false
                        } else {
                            let _ = SynthesizeNode(ctx, SynPos.NONE, typeNode)
                            let _ = ReplaceIdealTy(impl.typeManager, typeNode, diag: impl.diag)
                            impl.typeManager.IsSubtype(typeNode.GetTy() ?? TypeManager.GetInvalidTy(), targetTy)
                        }
                        typeCheckExprClearTargetType(ctx, typeNode)
                        typeNode.SetTy(impl.typeManager.TryGreedySubst(typeNode.GetTy() ?? TypeManager.GetInvalidTy()))
                        checkRet
                    }
                }), argSynthesizer: Some({ arg: FuncArg => SynthesizeFuncArg(ctx, arg) }), diag: impl.diag))
        }
        if (let Some(spawnExpr) <- (expr as SpawnExpr)) {
            return FinishCheck(ctx, spawnExpr, CheckSpawnExprWithTarget(ctx, target, spawnExpr))
        }
        if (let Some(asExpr) <- (expr as AsExpr)) {
            SynthesizeTypeNode(ctx, asExpr.asType)
            if (let Some(leftExpr) <- asExpr.leftExpr) {
                let _ = Synthesize(ctx, leftExpr)
            }
            return FinishCheck(ctx, asExpr, ChkAsExpr(impl.typeManager, target, asExpr,
                LookupCoreEnumDecl(ctx, "Option"), diag: impl.diag))
        }
        if (let Some(optionalChain) <- (expr as OptionalChainExpr)) {
            return FinishCheck(ctx, optionalChain, ChkOptionalChainExpr(impl.typeManager, target, optionalChain,
                synthesizer: Some({ innerExpr: Expr => Synthesize(ctx, SynPos.EXPR_ARG, innerExpr) }),
                diag: impl.diag))
        }
        let _ = Synthesize(ctx, expr)
        return FinishCheck(ctx, expr, ChkExprShallow(impl.typeManager, target, expr, ctx: Some(ctx),
            diag: impl.diag, importManager: impl.importManager))
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
            for (target in impl.Lookup(ctx, refExpr.ref.identifier.Val(), scopeNameOf(refExpr), refExpr,
                isSetter: refExpr.TestAttr(Attribute.LEFT_VALUE))) {
                targets.add(target)
            }
        }
        if (!refExpr.TestAttr(Attribute.MACRO_INVOKE_BODY) && typeCheckExprAllMacroFuncDecls(targets)) {
            let checker = EnumSugarChecker(impl, ctx, refExpr)
            let (resolved, resolvedTargets) = checker.Resolve()
            if (resolved) {
                if (resolvedTargets.isEmpty()) {
                    refExpr.SetTy(TypeManager.GetInvalidTy())
                }
                return
            }
            targets.clear()
            for (target in resolvedTargets) {
                targets.add(target)
            }
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
        var decl = GetAccessibleDecl(impl.typeManager, ctx, refExpr, targets)
        if (let None <- decl) {
            decl = Some(targets[0])
        }
        ModifyTargetOfRef(refExpr, decl.getOrThrow(), targets)
    }
}
