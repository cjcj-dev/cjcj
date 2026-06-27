package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::modules.GetMainPartPkgNameForTestPkg as ModulesGetMainPartPkgNameForTestPkg
import cangjie_compiler::modules.GetPackageRelation as ModulesGetPackageRelation
import cangjie_compiler::modules.IsTestPackage as ModulesIsTestPackage
import cangjie_compiler::modules.PackageRelation as ModulesPackageRelation

public enum TypeAccessIssueKind {
    | INVALID_ACCESS_CONTROL
    | INVALID_FUNCTION_ACCESS
    | IMMUTABLE_ACCESS_MUT_FUNC
    | INOUT_MODIFY_HEAP_VARIABLE
    | USE_MUTABLE_FUNC_ALONE
    | CANNOT_MODIFY_STRUCT_VAR
}

private func TypeAccessIssueKindIndex(kind: TypeAccessIssueKind): Int64 {
    return match (kind) {
        case TypeAccessIssueKind.INVALID_ACCESS_CONTROL => 0
        case TypeAccessIssueKind.INVALID_FUNCTION_ACCESS => 1
        case TypeAccessIssueKind.IMMUTABLE_ACCESS_MUT_FUNC => 2
        case TypeAccessIssueKind.INOUT_MODIFY_HEAP_VARIABLE => 3
        case TypeAccessIssueKind.USE_MUTABLE_FUNC_ALONE => 4
        case TypeAccessIssueKind.CANNOT_MODIFY_STRUCT_VAR => 5
    }
}

extend TypeAccessIssueKind <: Equatable<TypeAccessIssueKind> {
    public operator func ==(right: TypeAccessIssueKind): Bool {
        return TypeAccessIssueKindIndex(this) == TypeAccessIssueKindIndex(right)
    }

    public operator func !=(right: TypeAccessIssueKind): Bool {
        return !(this == right)
    }
}

public class TypeAccessIssue {
    public var kind: TypeAccessIssueKind
    public var node: Node
    public var target: Option<Decl>
    public var message: String

    public init(kind: TypeAccessIssueKind, node: Node, target: Option<Decl>, message: String) {
        this.kind = kind
        this.node = node
        this.target = target
        this.message = message
    }
}

private class InoutUseCacheEntry {
    public var declKey: String
    public var value: Bool

    public init(declKey: String, value: Bool) {
        this.declKey = declKey
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

public func CheckFuncAccessControl(typeManager: TypeManager, ctx: ASTContext, accessSite: Expr,
    targets: ArrayList<Decl>): (Option<Decl>, Option<TypeAccessIssue>) {
    let accessibleDecl = GetAccessibleDecl(typeManager, ctx, accessSite, targets)
    if (let Some(_) <- accessibleDecl) {
        return (accessibleDecl, None)
    }
    if (!targets.isEmpty() && targets[0].astKind == ASTKind.FUNC_DECL) {
        return (
            None,
            Some(TypeAccessIssue(
                TypeAccessIssueKind.INVALID_FUNCTION_ACCESS,
                accessSite,
                Some(targets[0]),
                "function '${targets[0].identifier.Val()}' is not accessible"
            ))
        )
    }
    return (None, None)
}

public func CheckNonFuncAccessControl(typeManager: TypeManager, ctx: ASTContext, accessSite: Expr,
    target: Decl): Option<TypeAccessIssue> {
    let sym = GetCurStructSymbol(ctx, accessSite.scopeName)
    if (IsLegalAccess(typeManager, sym, target, accessSite)) {
        return None
    }
    return Some(TypeAccessIssue(
        TypeAccessIssueKind.INVALID_ACCESS_CONTROL,
        accessSite,
        Some(target),
        "declaration '${target.identifier.Val()}' is not accessible"
    ))
}

public func CheckIfUseInout(decl: FuncDecl): Bool {
    let key = AccessDeclKey(decl)
    for (entry in inoutUseCache) {
        if (entry.declKey == key) {
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
    inoutUseCache.add(InoutUseCacheEntry(key, result.value))
    return result.value
}

public func CheckLetInstanceAccessMutableFunc(memberAccess: MemberAccess, target: Decl): ArrayList<TypeAccessIssue> {
    let issues = ArrayList<TypeAccessIssue>()
    if (!target.TestAttr(Attribute.MUT) || target.astKind != ASTKind.FUNC_DECL) {
        return issues
    }
    if (let None <- memberAccess.baseExpr) {
        return issues
    }
    let baseExpr = memberAccess.baseExpr.getOrThrow()
    if (let None <- baseExpr.GetTy()) {
        return issues
    }
    if (!MaybeStruct(baseExpr.GetTy().getOrThrow())) {
        return issues
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
                    issues.add(TypeAccessIssue(
                        TypeAccessIssueKind.INOUT_MODIFY_HEAP_VARIABLE,
                        currentBase,
                        currentBase.GetTarget(),
                        "inout argument may modify a heap variable through '${currentBase.ToString()}'"
                    ))
                }
            }
        }

        if (let Some(baseTarget) <- currentBase.GetTarget()) {
            if (let Some(varDecl) <- (baseTarget as VarDecl)) {
                let immutableAccessMutableFunc = (varDecl.astKind == ASTKind.PROP_DECL || !varDecl.isVar) &&
                    (if (let Some(varTy) <- varDecl.GetTy()) { !varTy.IsClassLike() } else { false })
                if (immutableAccessMutableFunc) {
                    issues.add(TypeAccessIssue(
                        TypeAccessIssueKind.IMMUTABLE_ACCESS_MUT_FUNC,
                        memberAccess,
                        Some(target),
                        "immutable value '${varDecl.identifier.Val()}' cannot access mutable function '${target.identifier.Val()}'"
                    ))
                    return issues
                }
            }
        }

        if (let Some(nextMember) <- (currentBase as MemberAccess)) {
            currentMember = Some(nextMember)
        } else {
            if (let Some(baseTy) <- currentBase.GetTy()) {
                if (!baseTy.IsClassLike() && currentBase.astKind != ASTKind.REF_EXPR) {
                    issues.add(TypeAccessIssue(
                        TypeAccessIssueKind.IMMUTABLE_ACCESS_MUT_FUNC,
                        memberAccess,
                        Some(target),
                        "non-reference value cannot access mutable function '${target.identifier.Val()}'"
                    ))
                    return issues
                }
            }
            currentMember = None
        }
    }

    if (let None <- memberAccess.callOrPattern) {
        issues.add(TypeAccessIssue(
            TypeAccessIssueKind.USE_MUTABLE_FUNC_ALONE,
            memberAccess,
            Some(target),
            "mutable function '${target.identifier.Val()}' must be called immediately"
        ))
    }
    return issues
}

public func CheckMutationInStructNonMut(structDecl: StructDecl, expr: Expr): ArrayList<TypeAccessIssue> {
    let issues = ArrayList<TypeAccessIssue>()
    let forbiddenVars = CollectStructValueVars(structDecl)
    if (forbiddenVars.isEmpty()) {
        return issues
    }
    var current: Option<Expr> = Some(expr)
    while (let Some(currentExpr) <- current) {
        if (let Some(target) <- currentExpr.GetTarget()) {
            if (ContainsDeclKey(forbiddenVars, target)) {
                issues.add(TypeAccessIssue(
                    TypeAccessIssueKind.CANNOT_MODIFY_STRUCT_VAR,
                    expr,
                    Some(target),
                    "cannot modify non-static value member '${target.identifier.Val()}' in a non-mut function"
                ))
                return issues
            }
        }
        if (let Some(memberAccess) <- (currentExpr as MemberAccess)) {
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                if (let Some(baseTy) <- baseExpr.GetTy()) {
                    if (baseTy.IsClassLike()) {
                        break
                    }
                }
                current = Some(baseExpr)
                continue
            }
        }
        current = None
    }
    return issues
}

private func InoutExprTouchesReceiver(expr: Expr, decl: FuncDecl): Bool {
    var current: Option<Expr> = Some(expr)
    while (let Some(currentExpr) <- current) {
        if (let Some(target) <- currentExpr.GetTarget()) {
            if (let Some(targetOuter) <- target.outerDecl) {
                if (let Some(declOuter) <- decl.outerDecl) {
                    if (AccessDeclKey(targetOuter) == AccessDeclKey(declOuter)) {
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

private func CollectStructValueVars(structDecl: StructDecl): HashSet<String> {
    let out = HashSet<String>()
    if (let Some(body) <- structDecl.body) {
        for (decl in body.decls) {
            if (let Some(varDecl) <- (decl as VarDecl)) {
                if (!varDecl.TestAttr(Attribute.STATIC)) {
                    if (let Some(varTy) <- varDecl.GetTy()) {
                        if (!varTy.IsArray()) {
                            out.add(AccessDeclKey(varDecl))
                        }
                    }
                }
            }
        }
    }
    return out
}

private func ContainsDeclKey(keys: HashSet<String>, decl: Decl): Bool {
    return keys.contains(AccessDeclKey(decl))
}

private func IsSameFile(accessSite: Node, target: Decl): Bool {
    if (let Some(left) <- accessSite.curFile) {
        if (let Some(right) <- target.curFile) {
            return left.fileHash == right.fileHash && left.filePath == right.filePath
        }
    }
    return false
}

private func AccessDeclKey(decl: Decl): String {
    return "${ASTKindIndex(decl.astKind)}:${decl.fullPackageName}:${decl.identifier.Val()}:" +
        "${decl.begin.ToString()}:${decl.end.ToString()}"
}

public func SelfhostPortStatus_TypeCheckAccess(): Bool {
    return true
}
