package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.Range as BasicRange
import cjcj::modules.GetMainPartPkgNameForTestPkg as ModulesGetMainPartPkgNameForTestPkg
import cjcj::modules.GetPackageRelation as ModulesGetPackageRelation
import cjcj::modules.IsTestPackage as ModulesIsTestPackage
import cjcj::modules.PackageRelation as ModulesPackageRelation

private class InoutUseCacheEntry {
    public var decl: Decl
    public var value: Bool

    public init(decl: Decl, value: Bool) {
        this.decl = decl
        this.value = value
    }
}

private class BoolBox {
    public var value: Bool

    public init(value: Bool) {
        this.value = value
    }
}

private let inoutUseCache: ArrayList<InoutUseCacheEntry> = ArrayList<InoutUseCacheEntry>()

public func MaybeStruct(ty: Ty): Bool {
    if (!Ty.IsTyCorrect(ty)) {
        return false
    }
    if (ty.IsStruct()) {
        return true
    }
    if (!ty.IsGeneric()) {
        return false
    }
    if (let Some(genericsTy) <- (ty as GenericsTy)) {
        var hasNonInterfaceBound = false
        for (upperBound in genericsTy.upperBounds) {
            if (MaybeStruct(upperBound)) {
                return true
            }
            if (!upperBound.IsInterface()) {
                hasNonInterfaceBound = true
            }
        }
        return !hasNonInterfaceBound
    }
    return false
}

private func AccessAddSearchCandidate(values: ArrayList<InheritableDecl>, candidate: InheritableDecl): Unit {
    for (value in values) {
        if (SameDecl(value, candidate)) {
            return
        }
    }
    values.add(candidate)
}

private func AccessIsVisible(decl: Decl, relation: ModulesPackageRelation): Bool {
    return decl.TestAttr(Attribute.PUBLIC) || relation == ModulesPackageRelation.SAME_PACKAGE ||
        (decl.TestAttr(Attribute.PROTECTED) && relation != ModulesPackageRelation.NONE) ||
        (decl.TestAttr(Attribute.INTERNAL) &&
            (relation == ModulesPackageRelation.CHILD || relation == ModulesPackageRelation.SAME_PACKAGE))
}

public func GetCurStructSymbol(ctx: ASTContext, scopeName: String): Option<Symbol> {
    var scopeGateName = GetScopeGateName(scopeName)
    while (!scopeGateName.isEmpty()) {
        if (let Some(symbol) <- GetScopeGate(ctx, scopeGateName)) {
            if (let Some(node) <- symbol.node) {
                if (node.IsNominalDecl()) {
                    return Some(symbol)
                }
            }
        }
        scopeGateName = GetScopeGateName(scopeGateName)
    }
    return None
}

private func TypeCheckAccessRange(node: Node): BasicRange {
    var rangeEnd = node.end
    if (node.begin.fileID != node.end.fileID) {
        rangeEnd = node.begin + 1
    }
    return MakeRange(node.begin, rangeEnd)
}

private func TypeCheckAccessDeclIdentifierRange(decl: Decl): BasicRange {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            if (let Some(outerDecl) <- funcDecl.outerDecl) {
                if (funcDecl.identifier.Begin().IsZero()) {
                    return MakeRange(outerDecl.identifier.Begin(), outerDecl.identifier.End())
                }
                if (funcDecl.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) {
                    return MakeRange(funcDecl.identifier.Begin(), outerDecl.identifier.End())
                }
            }
            return MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.End())
        }
        if (funcDecl.isGetter || funcDecl.isSetter) {
            return MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.Begin() + 3)
        }
    }
    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        if (extendDecl.TestAttr(Attribute.FROM_COMMON_PART)) {
            return MakeRange(extendDecl.begin, extendDecl.end)
        }
        if (let Some(extendedType) <- extendDecl.extendedType) {
            return MakeRange(extendedType.begin, extendedType.end)
        }
    }
    if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            return MakeRange(pattern.begin, pattern.end)
        }
    }
    if (decl.identifier.Begin().IsZero()) {
        return TypeCheckAccessRange(decl)
    }
    return MakeRange(decl.identifier.Begin(), decl.identifier.End())
}

public func SearchTargetDeclForProtectMember(typeManager: TypeManager, curComposite: Node,
    outerDeclOfTarget: Decl): Bool {
    var startOpt: Option<InheritableDecl> = curComposite as InheritableDecl
    if (let Some(extendDecl) <- (curComposite as ExtendDecl)) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (let Some(decl) <- Ty.GetDeclPtrOfTy(extendedType.GetTy())) {
                if (SameDecl(decl, outerDeclOfTarget)) {
                    return true
                }
                startOpt = decl as InheritableDecl
            }
        }
    }
    if (let None <- startOpt) {
        return false
    }
    let queue = ArrayList<InheritableDecl>()
    AccessAddSearchCandidate(queue, startOpt.getOrThrow())
    var idx: Int64 = 0
    while (idx < queue.size) {
        let current = queue[idx]
        if (SameDecl(current, outerDeclOfTarget)) {
            return true
        }
        for (extendDecl in typeManager.GetDeclExtends(current)) {
            AccessAddSearchCandidate(queue, extendDecl)
        }
        if (let Some(classDecl) <- (current as ClassDecl)) {
            if (let Some(superClass) <- classDecl.GetSuperClassDecl()) {
                AccessAddSearchCandidate(queue, superClass)
            }
        }
        idx++
    }
    return false
}

private func IsNormalCtorRef(node: Node): Bool {
    if (let Some(refExpr) <- (node as RefExpr)) {
        return !refExpr.isThis && !refExpr.isSuper
    }
    return true
}

private func AccessGetRealTarget(declOpt: Option<Decl>): Option<Decl> {
    if (let Some(decl) <- declOpt) {
        if (let Some(typeAliasDecl) <- (decl as TypeAliasDecl)) {
            if (let Some(typeNode) <- typeAliasDecl.typeNode) {
                if (!typeAliasDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                    if (let Some(target) <- typeNode.GetTarget()) {
                        return AccessGetRealTarget(Some(target))
                    }
                }
            }
        }
    }
    return declOpt
}

private func AccessIsTypeAccessible(typeManager: TypeManager, file: File, typeNode: Type): Bool {
    let targetOpt = AccessGetRealTarget(typeNode.GetTarget())
    if (let Some(target) <- targetOpt) {
        return typeManager.IsDeclAccessible(file, target)
    }
    return true
}

private func AccessIsExtendAllUpperBoundsImported(typeManager: TypeManager, extendDecl: ExtendDecl,
    file: File): Bool {
    if (let None <- extendDecl.generic) {
        return true
    }
    let generic = extendDecl.generic.getOrThrow()
    for (constraint in generic.genericConstraints) {
        for (upperBound in constraint.upperBounds) {
            if (!AccessIsTypeAccessible(typeManager, file, upperBound)) {
                return false
            }
        }
    }
    return true
}

private func AccessIsExtendAccessible(typeManager: TypeManager, file: File, extendDecl: ExtendDecl): Bool {
    if (let None <- file.curPackage) {
        return true
    }
    let filePackage = file.curPackage.getOrThrow()
    if (extendDecl.fullPackageName == filePackage.fullPackageName) {
        return true
    }
    if (typeManager.compileTestsOnly && extendDecl.TestAttr(Attribute.FOR_TEST) &&
        ModulesIsTestPackage(filePackage.fullPackageName) &&
        ModulesGetMainPartPkgNameForTestPkg(filePackage.fullPackageName) == extendDecl.fullPackageName) {
        return true
    }
    let allUpperBoundsImported = AccessIsExtendAllUpperBoundsImported(typeManager, extendDecl, file)
    var hasAnyInterfacesImported = false
    var extendedTypeAccessible = false
    let extendedDecl = Ty.GetInheritableDeclPtrOfTy(extendDecl.GetTy())
    let inSamePackage = if (let Some(realExtendedDecl) <- extendedDecl) {
        extendDecl.fullPackageName == realExtendedDecl.fullPackageName
    } else {
        extendDecl.fullPackageName == "std.core"
    }
    if (!inSamePackage) {
        for (inheritedType in extendDecl.inheritedTypes) {
            if (AccessIsTypeAccessible(typeManager, file, inheritedType)) {
                hasAnyInterfacesImported = true
            }
        }
        if (let Some(extendedType) <- extendDecl.extendedType) {
            extendedTypeAccessible = AccessIsTypeAccessible(typeManager, file, extendedType)
        }
    } else {
        hasAnyInterfacesImported = true
        if (let Some(realExtendedDecl) <- extendedDecl) {
            let relation = ModulesGetPackageRelation(filePackage.fullPackageName, realExtendedDecl.fullPackageName)
            extendedTypeAccessible = AccessIsVisible(realExtendedDecl, relation)
        } else {
            extendedTypeAccessible = true
        }
    }
    return extendDecl.IsExportedDecl() && allUpperBoundsImported && hasAnyInterfacesImported && extendedTypeAccessible
}

private func AccessFindImplementInterface(typeManager: TypeManager, file: File, member: Decl,
    interfaceType: Type): Option<Type> {
    let _ = file
    let targetDecl = Ty.GetInheritableDeclPtrOfTy(interfaceType.GetTy())
    if (let None <- targetDecl) {
        return None
    }
    let inheritableDecl = targetDecl.getOrThrow()
    for (superType in inheritableDecl.inheritedTypes) {
        if (let Some(implInterface) <- AccessFindImplementInterface(typeManager, file, member, superType)) {
            return Some(implInterface)
        }
    }
    for (candidate in inheritableDecl.GetMemberDecls()) {
        if (typeManager.PairIsOverrideOrImpl(member, candidate)) {
            return Some(interfaceType)
        }
    }
    return None
}

private func AccessIsExtendMemberImported(typeManager: TypeManager, extendDecl: ExtendDecl, file: File,
    member: Decl): Bool {
    if (extendDecl.inheritedTypes.isEmpty()) {
        return true
    }
    let extendedDecl = Ty.GetInheritableDeclPtrOfTy(extendDecl.GetTy())
    let inSamePackage = if (let Some(realExtendedDecl) <- extendedDecl) {
        extendDecl.fullPackageName == realExtendedDecl.fullPackageName
    } else {
        extendDecl.fullPackageName == "std.core"
    }
    if (inSamePackage) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            return AccessIsTypeAccessible(typeManager, file, extendedType)
        }
        return true
    }
    for (superType in extendDecl.inheritedTypes) {
        if (let Some(implInterface) <- AccessFindImplementInterface(typeManager, file, member, superType)) {
            return AccessIsTypeAccessible(typeManager, file, implInterface)
        }
    }
    return false
}

private func AccessIsExtendMemberAccessible(typeManager: TypeManager, file: File, member: Decl,
    baseTy: Ty): Bool {
    if (let None <- file.curPackage) {
        return true
    }
    if (let None <- typeManager.GetExtendDeclByMember(member, baseTy)) {
        return true
    }
    let extendDecl = typeManager.GetExtendDeclByMember(member, baseTy).getOrThrow()
    let filePackage = file.curPackage.getOrThrow()
    if (typeManager.compileTestsOnly && !member.TestAttr(Attribute.PRIVATE) &&
        extendDecl.TestAttr(Attribute.FOR_TEST) && ModulesIsTestPackage(filePackage.fullPackageName) &&
        ModulesGetMainPartPkgNameForTestPkg(filePackage.fullPackageName) == member.fullPackageName) {
        return true
    }
    if (extendDecl.fullPackageName == filePackage.fullPackageName) {
        return true
    }
    if (!AccessIsExtendAccessible(typeManager, file, extendDecl)) {
        return false
    }
    if (!member.IsExportedDecl()) {
        return false
    }
    return AccessIsExtendMemberImported(typeManager, extendDecl, file, member)
}

private func AccessCurCompositeDecl(curComposite: Option<Symbol>): Option<Decl> {
    if (let Some(symbol) <- curComposite) {
        if (let Some(node) <- symbol.node) {
            return node as Decl
        }
    }
    return None
}

public func IsLegalAccess(typeManager: TypeManager, curComposite: Option<Symbol>, target: Decl, accessSite: Node): Bool {
    if ((let None <- (target as VarDecl)) && (let None <- (target as FuncDecl)) &&
        (let None <- (target as ClassLikeDecl))) {
        return true
    }
    if (accessSite.TestAnyAttr(Attribute.IN_CORE, Attribute.IN_MACRO)) {
        return true
    }
    if (!accessSite.IsSamePackage(target)) {
        if (let Some(file) <- accessSite.curFile) {
            if (let Some(memberAccess) <- (accessSite as MemberAccess)) {
                if (let Some(baseExpr) <- memberAccess.baseExpr) {
                    if (let Some(baseTy) <- baseExpr.GetTy()) {
                        if (!AccessIsExtendMemberAccessible(typeManager, file, target, baseTy)) {
                            return false
                        }
                    }
                }
            }
        }
    }
    if (target.TestAttr(Attribute.PUBLIC)) {
        return true
    }
    var relation = ModulesPackageRelation.NONE
    if (let Some(file) <- accessSite.curFile) {
        if (let Some(pkg) <- file.curPackage) {
            relation = ModulesGetPackageRelation(pkg.fullPackageName, target.fullPackageName)
        }
    }
    let curCompositeDecl = AccessCurCompositeDecl(curComposite)
    let flag = IsClassOrEnumConstructor(target) && !target.TestAttr(Attribute.PRIVATE) && IsNormalCtorRef(accessSite) &&
        (if (let Some(curDecl) <- curCompositeDecl) {
            if (let Some(outer) <- target.outerDecl) {
                !SearchTargetDeclForProtectMember(typeManager, curDecl, outer)
            } else {
                true
            }
        } else {
            true
        })
    if (target.TestAttr(Attribute.GLOBAL) || flag) {
        if (target.TestAttr(Attribute.PRIVATE)) {
            return IsSameFile(accessSite, target)
        }
        return AccessIsVisible(target, relation)
    }
    let outerDeclOfTarget = target.outerDecl
    if (let None <- outerDeclOfTarget) {
        return true
    }
    if (!outerDeclOfTarget.getOrThrow().IsNominalDecl()) {
        return true
    }
    let targetOuter = outerDeclOfTarget.getOrThrow()
    if (target.TestAttr(Attribute.INTERNAL)) {
        return AccessIsVisible(target, relation)
    } else if (target.TestAttr(Attribute.PROTECTED)) {
        if (AccessIsVisible(target, relation)) {
            return true
        }
        if (let Some(curDecl2) <- curCompositeDecl) {
            return SameDecl(curDecl2, targetOuter) ||
                SearchTargetDeclForProtectMember(typeManager, curDecl2, targetOuter)
        }
        return false
    }
    var expectedOuter = targetOuter
    if (let Some(specific) <- targetOuter.specificImplementation) {
        expectedOuter = specific
    }
    if (let Some(curDecl3) <- curCompositeDecl) {
        return SameDecl(curDecl3, expectedOuter)
    }
    return false
}

public func IsTargetMemberVisibleToNode(typeManager: TypeManager, ctx: ASTContext, target: Decl, node: Node): Bool {
    if (IsSameFile(node, target)) {
        return true
    }
    let sym = GetCurStructSymbol(ctx, node.scopeName)
    return IsLegalAccess(typeManager, sym, target, node)
}

public func GetAccessibleDecls(typeManager: TypeManager, ctx: ASTContext, accessSite: Expr,
    targets: ArrayList<Decl>): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    let sym = GetCurStructSymbol(ctx, accessSite.scopeName)
    for (target in targets) {
        if (IsLegalAccess(typeManager, sym, target, accessSite)) {
            out.add(target)
        }
    }
    return out
}

public func GetAccessibleDecl(typeManager: TypeManager, ctx: ASTContext, accessSite: Expr,
    targets: ArrayList<Decl>): Option<Decl> {
    let accessible = GetAccessibleDecls(typeManager, ctx, accessSite, targets)
    if (accessible.isEmpty()) {
        return None
    }
    return Some(accessible[0])
}

public func CheckFuncAccessControl(diag: BasicDiagnosticEngine, typeManager: TypeManager, ctx: ASTContext, accessSite: Expr,
    targets: ArrayList<Decl>): Option<Decl> {
    let accessibleDecl = GetAccessibleDecl(typeManager, ctx, accessSite, targets)
    if (let Some(_) <- accessibleDecl) {
        return accessibleDecl
    }
    if (!targets.isEmpty() && targets[0].astKind == ASTKind.FUNC_DECL) {
        let builder = Diagnose(diag, accessSite,
            BasicDiagKind.sema_invalid_access_function,
            args: [BasicDiagArgument(targets[0].identifier.Val())])
        builder.Emit()
    }
    return None
}

public func CheckNonFuncAccessControl(diag: BasicDiagnosticEngine, typeManager: TypeManager, ctx: ASTContext,
    accessSite: Expr, target: Decl): Bool {
    let sym = GetCurStructSymbol(ctx, accessSite.scopeName)
    if (IsLegalAccess(typeManager, sym, target, accessSite)) {
        return true
    }
    let builder = diag.Diagnose(accessSite.begin, accessSite.end,
        BasicDiagKind.sema_invalid_access_control,
        args: [BasicDiagArgument(target.identifier.Val())])
    builder.Emit()
    return false
}

public func CheckIfUseInout(decl: FuncDecl): Bool {
    for (entry in inoutUseCache) {
        if (entry.decl == decl) {
            return entry.value
        }
    }
    let result = BoolBox(false)
    if (let Some(body) <- decl.funcBody) {
        let walker = Walker(body, visitPre: { node: Node =>
            if (let Some(callExpr) <- (node as CallExpr)) {
                if (let Some(_) <- callExpr.desugarExpr) {
                    return VisitAction.WALK_CHILDREN
                }
                for (arg in callExpr.args) {
                    if (!arg.withInout) {
                        continue
                    }
                    if (let Some(expr) <- arg.expr) {
                        if (InoutExprTouchesReceiver(expr, decl)) {
                            result.value = true
                            return VisitAction.STOP_NOW
                        }
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }
    inoutUseCache.add(InoutUseCacheEntry(decl, result.value))
    return result.value
}

private func CheckMutationInStruct(diag: BasicDiagnosticEngine, ctx: ASTContext, expr: Expr): Unit {
    if (let None <- expr.GetTarget()) {
        return
    }
    let target = expr.GetTarget().getOrThrow()
    if (target.astKind != ASTKind.VAR_DECL || target.TestAttr(Attribute.STATIC)) {
        return
    }
    if (let None <- ScopeManager.GetOutMostSymbol(ctx, SymbolKind.FUNC_LIKE, expr.scopeName)) {
        return
    }
    let outFuncSymbol = ScopeManager.GetOutMostSymbol(ctx, SymbolKind.FUNC_LIKE, expr.scopeName).getOrThrow()
    if (let None <- outFuncSymbol.node) {
        return
    }
    let outFuncNode = outFuncSymbol.node.getOrThrow()
    if (outFuncNode.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.MUT)) {
        return
    }
    if (let None <- ScopeManager.GetCurOuterDeclOfScopeLevelX(ctx, expr, 0u32)) {
        return
    }
    let outDeclSymbol = ScopeManager.GetCurOuterDeclOfScopeLevelX(ctx, expr, 0u32).getOrThrow()
    if (let None <- outDeclSymbol.node) {
        return
    }
    let outDeclNode = outDeclSymbol.node.getOrThrow()
    if (let Some(outDeclTy) <- outDeclNode.GetTy()) {
        if (Ty.IsTyCorrect(outDeclTy) && outDeclTy.IsStruct()) {
            if (let Some(structTy) <- (outDeclTy as StructTy)) {
                if (let Some(structDecl) <- structTy.declPtr) {
                    CheckMutationInStructNonMut(diag, structDecl, expr)
                }
            }
        }
    }
}

private func DiagImmutableAccessMutableFunc(diag: BasicDiagnosticEngine, outerMa: MemberAccess, ma: MemberAccess): Unit {
    if (let None <- ma.baseExpr) {
        return
    }
    let maBaseExpr = ma.baseExpr.getOrThrow()
    let builder = DiagnoseRefactor(diag,
        BasicDiagKindRefactor.sema_immutable_access_mutable_func,
        maBaseExpr)
    let mutFuncPos = outerMa.GetFieldPos()
    if (!mutFuncPos.IsZero() && !IsFieldOperator(ma.field.Val())) {
        builder.AddHint(MakeRange(mutFuncPos, outerMa.field.Val()), arguments: ["is a mutable function"])
    }
    if (let Some(maBaseTarget) <- maBaseExpr.GetTarget()) {
        if (let Some(varDecl) <- (maBaseTarget as VarDecl)) {
            if (!varDecl.isVar && !varDecl.identifier.ZeroPos()) {
                let letOrConst = if (varDecl.IsConst()) { "const" } else { "let" }
                builder.AddNote(
                    MakeRange(varDecl.identifier.Begin(), varDecl.identifier.End()),
                    "'" + varDecl.identifier.Val() + "' is a variable declared with '" + letOrConst + "'")
            } else if (let Some(propDecl) <- (varDecl as PropDecl)) {
                if (propDecl.getters.size == 1 && !propDecl.getters[0].begin.IsZero()) {
                    let getter = propDecl.getters[0]
                    let getterRange = if (!getter.identifier.Begin().IsZero() && !getter.identifier.End().IsZero()) {
                        MakeRange(getter.identifier.Begin(), getter.identifier.End())
                    } else {
                        MakeRange(getter.begin, getter.end)
                    }
                    builder.AddNote(getterRange, "property getter returns immutable value")
                }
            }
        }
    }
    builder.Emit()
}

public func CheckLetInstanceAccessMutableFunc(
    diag: BasicDiagnosticEngine,
    ctx: ASTContext,
    memberAccess: MemberAccess,
    target: Decl
): Unit {
    if (!target.TestAttr(Attribute.MUT) || target.astKind != ASTKind.FUNC_DECL) {
        return
    }
    if (let None <- memberAccess.baseExpr) {
        return
    }
    let baseExpr = memberAccess.baseExpr.getOrThrow()
    if (let None <- baseExpr.GetTy()) {
        return
    }
    if (!MaybeStruct(baseExpr.GetTy().getOrThrow())) {
        return
    }

    let useInout = if (let Some(funcDecl) <- (target as FuncDecl)) { CheckIfUseInout(funcDecl) } else { false }
    var currentMember: Option<MemberAccess> = Some(memberAccess)
    while (let Some(current) <- currentMember) {
        if (let None <- current.baseExpr) {
            break
        }
        let currentBase = PeelParenExpr(current.baseExpr.getOrThrow())
        if (useInout) {
            if (let Some(baseTy) <- currentBase.GetTy()) {
                if (baseTy.IsClassLike()) {
                    let builder = DiagnoseRefactor(diag,
                        BasicDiagKindRefactor.sema_inout_modify_heap_variable,
                        currentBase)
                    builder.Emit()
                }
            }
        }

        if (let Some(baseTarget) <- currentBase.GetTarget()) {
            if (let Some(varDecl) <- (baseTarget as VarDecl)) {
                let immutableAccessMutableFunc = (varDecl.astKind == ASTKind.PROP_DECL || !varDecl.isVar) &&
                    (if (let Some(varTy) <- varDecl.GetTy()) { Ty.IsTyCorrect(varTy) && !varTy.IsClassLike() } else { false })
                if (immutableAccessMutableFunc) {
                    DiagImmutableAccessMutableFunc(diag, memberAccess, current)
                    return
                }
            }
        }

        if (let Some(nextMember) <- (currentBase as MemberAccess)) {
            currentMember = Some(nextMember)
        } else if (currentBase.astKind == ASTKind.REF_EXPR) {
            if (useInout) {
                if (let Some(refTarget) <- currentBase.GetTarget()) {
                    if (let Some(varDecl) <- (refTarget as VarDecl)) {
                        if (let Some(outerDecl) <- varDecl.outerDecl) {
                            if (let Some(outerTy) <- outerDecl.GetTy()) {
                                if (outerTy.IsClassLike()) {
                                    let builder = DiagnoseRefactor(diag,
                                        BasicDiagKindRefactor.sema_inout_modify_heap_variable,
                                        currentBase)
                                    builder.Emit()
                                }
                            }
                        }
                    }
                }
            }
            currentMember = None
        } else {
            if (let Some(baseTy) <- currentBase.GetTy()) {
                if (Ty.IsTyCorrect(baseTy) && !baseTy.IsClassLike()) {
                    DiagImmutableAccessMutableFunc(diag, memberAccess, current)
                    return
                }
            }
            currentMember = None
        }
    }

    if (let None <- memberAccess.callOrPattern) {
        let range = if (memberAccess.field.ZeroPos()) {
            MakeRange(memberAccess.begin, memberAccess.end)
        } else {
            MakeRange(memberAccess.field.Begin(), memberAccess.field.End())
        }
        let builder = DiagnoseRefactor(diag,
            BasicDiagKindRefactor.sema_use_mutable_func_alone,
            memberAccess,
            range,
            arguments: [memberAccess.field.Val()])
        AddNote(builder,
            target,
            TypeCheckAccessDeclIdentifierRange(target),
            "'" + target.identifier.Val() + "' is a mutable funciton")
        builder.Emit()
    } else {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            CheckMutationInStruct(diag, ctx, baseExpr)
        }
    }
}

public func CheckMutationInStructNonMut(diag: BasicDiagnosticEngine, structDecl: StructDecl, expr: Expr): Unit {
    let forbiddenVars = CollectStructValueVars(structDecl)
    if (forbiddenVars.isEmpty()) {
        return
    }
    var current: Option<Expr> = Some(expr)
    while (let Some(currentExpr) <- current) {
        if (let Some(refExpr) <- (currentExpr as RefExpr)) {
            if (let Some(target) <- refExpr.GetTarget()) {
                if (ContainsDeclKey(forbiddenVars, target)) {
                    let builder = diag.Diagnose(expr.begin, expr.end,
                        BasicDiagKind.sema_cannot_modify_var,
                        args: [BasicDiagArgument(target.identifier.Val())])
                    builder.Emit()
                    return
                }
            }
            return
        }
        if (let Some(memberAccess) <- (currentExpr as MemberAccess)) {
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                if (let Some(baseTy) <- baseExpr.GetTy()) {
                    if (baseTy.IsClassLike()) {
                        break
                    }
                }
                if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                    if (refExpr.isThis) {
                        if (let Some(target) <- memberAccess.GetTarget()) {
                            if (ContainsDeclKey(forbiddenVars, target)) {
                                let builder = diag.Diagnose(expr.begin, expr.end,
                                    BasicDiagKind.sema_cannot_modify_var,
                                    args: [BasicDiagArgument(target.identifier.Val())])
                                builder.Emit()
                                return
                            }
                        }
                    }
                }
                current = Some(baseExpr)
                continue
            }
        }
        current = None
    }
}

private func InoutExprTouchesReceiver(expr: Expr, decl: FuncDecl): Bool {
    var current: Option<Expr> = Some(expr)
    while (let Some(currentExpr) <- current) {
        if (let Some(target) <- currentExpr.GetTarget()) {
            if (let Some(targetOuter) <- target.outerDecl) {
                if (let Some(declOuter) <- decl.outerDecl) {
                    if (targetOuter == declOuter) {
                        return true
                    }
                }
            }
        }
        if (let Some(refExpr) <- (currentExpr as RefExpr)) {
            return refExpr.isThis
        }
        if (let Some(memberAccess) <- (currentExpr as MemberAccess)) {
            current = memberAccess.baseExpr
        } else {
            current = None
        }
    }
    return false
}

private func PeelParenExpr(expr: Expr): Expr {
    var current = expr
    var keepGoing = true
    while (keepGoing) {
        keepGoing = false
        if (let Some(parenExpr) <- (current as ParenExpr)) {
            if (let Some(inner) <- parenExpr.expr) {
                current = inner
                keepGoing = true
            }
        }
    }
    return current
}

private func CollectStructValueVars(structDecl: StructDecl): HashSet<Node> {
    let out = HashSet<Node>()
    if (let Some(body) <- structDecl.body) {
        for (decl in body.decls) {
            if (let Some(varDecl) <- (decl as VarDecl)) {
                if (!varDecl.TestAttr(Attribute.STATIC) && (if (let Some(varTy) <- varDecl.GetTy()) {
                    Ty.IsTyCorrect(varTy) && !varTy.IsArray()
                } else {
                    false
                })) {
                    out.add(varDecl)
                }
            }
        }
    }
    return out
}

private func ContainsDeclKey(keys: HashSet<Node>, decl: Decl): Bool {
    return keys.contains(decl)
}

private func IsSameFile(accessSite: Node, target: Decl): Bool {
    if (let Some(left) <- accessSite.curFile) {
        if (let Some(right) <- target.curFile) {
            return left.fileHash == right.fileHash && left.filePath == right.filePath
        }
    }
    return false
}

public func SelfhostPortStatus_TypeCheckAccess(): Bool {
    return true
}
