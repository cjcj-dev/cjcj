package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

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

public func IsLegalAccess(accessSite: Node, target: Decl): Bool {
    if (target.TestAttr(Attribute.PUBLIC)) {
        return true
    }
    if (target.TestAttr(Attribute.PRIVATE)) {
        return IsSameFile(accessSite, target)
    }
    if (target.TestAttr(Attribute.PROTECTED)) {
        return IsSamePackage(accessSite, target) || IsInsideNominalRelatedTo(accessSite, target)
    }
    return IsSamePackage(accessSite, target)
}

public func IsTargetMemberVisibleToNode(target: Decl, node: Node): Bool {
    if (IsSameFile(node, target)) {
        return true
    }
    return IsLegalAccess(node, target)
}

public func GetAccessibleDecls(accessSite: Expr, targets: ArrayList<Decl>): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (target in targets) {
        if (IsLegalAccess(accessSite, target)) {
            out.add(target)
        }
    }
    return out
}

public func GetAccessibleDecl(accessSite: Expr, targets: ArrayList<Decl>): Option<Decl> {
    let accessible = GetAccessibleDecls(accessSite, targets)
    if (accessible.isEmpty()) {
        return None
    }
    return Some(accessible[0])
}

public func CheckFuncAccessControl(accessSite: Expr, targets: ArrayList<Decl>): (Option<Decl>, Option<TypeAccessIssue>) {
    let accessibleDecl = GetAccessibleDecl(accessSite, targets)
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

public func CheckNonFuncAccessControl(accessSite: Expr, target: Decl): Option<TypeAccessIssue> {
    if (IsLegalAccess(accessSite, target)) {
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

private func IsSamePackage(accessSite: Node, target: Decl): Bool {
    let leftPackage = AccessSitePackage(accessSite)
    if (leftPackage.isEmpty() || target.fullPackageName.isEmpty()) {
        return false
    }
    return leftPackage == target.fullPackageName
}

private func AccessSitePackage(node: Node): String {
    if (let Some(file) <- node.curFile) {
        if (let Some(pkg) <- file.curPackage) {
            return pkg.fullPackageName
        }
    }
    return node.GetFullPackageName()
}

private func IsInsideNominalRelatedTo(accessSite: Node, target: Decl): Bool {
    if (!IsSamePackage(accessSite, target)) {
        return false
    }
    if (let Some(targetOuter) <- target.outerDecl) {
        let targetOuterKey = AccessDeclKey(targetOuter)
        let found = BoolBox(false)
        let walker = Walker(accessSite, visitPre: { node: Node =>
            if (let Some(decl) <- (node as Decl)) {
                if (decl.IsNominalDecl() && AccessDeclKey(decl) == targetOuterKey) {
                    found.value = true
                    return VisitAction.STOP_NOW
                }
                if (decl.IsNominalDecl()) {
                    return VisitAction.SKIP_CHILDREN
                }
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        return found.value
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
