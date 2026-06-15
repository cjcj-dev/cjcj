package cangjie_compiler::sema

import std.collection.*
import std.sort.*
import cangjie_compiler::ast.*

private let ENUM_SUGAR_CORE_PACKAGE_NAME: String = "std.core"

private func EnumSugarNodeHash(node: Node): Int64 {
    return node.begin.hashCode() ^ (node.end.hashCode() << 1) ^ ASTKindIndex(node.astKind)
}

private func IsAllEnumSugarFuncDecl(values: ArrayList<Decl>): Bool {
    for (decl in values) {
        if (decl.astKind != ASTKind.FUNC_DECL && decl.astKind != ASTKind.MACRO_DECL) {
            return false
        }
    }
    return true
}

private func CloneDeclList(values: ArrayList<Decl>): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (decl in values) {
        out.add(decl)
    }
    return out
}

private func AddDeclIfAbsent(values: ArrayList<Decl>, decl: Decl): Unit {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
}

private func RemoveDuplicateDecls(values: ArrayList<Decl>): Unit {
    let unique = ArrayList<Decl>()
    for (decl in values) {
        AddDeclIfAbsent(unique, decl)
    }
    values.clear()
    for (decl in unique) {
        values.add(decl)
    }
}

private func SortDeclsByPosition(values: ArrayList<Decl>): Unit {
    sort(values, by: { left: Decl, right: Decl =>
        if (left.begin < right.begin) {
            Ordering.LT
        } else if (right.begin < left.begin) {
            Ordering.GT
        } else if (left.end < right.end) {
            Ordering.LT
        } else if (right.end < left.end) {
            Ordering.GT
        } else if (left.identifier.Val() < right.identifier.Val()) {
            Ordering.LT
        } else if (left.identifier.Val() > right.identifier.Val()) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)
}

private func GetOuterEnumDecl(decl: Decl): Option<EnumDecl> {
    if (let Some(outer) <- decl.outerDecl) {
        return outer as EnumDecl
    }
    return None
}

private func HasMismatchedEnumSugarTypeArgs(refExpr: RefExpr, decl: Decl): Bool {
    if (refExpr.typeArguments.isEmpty()) {
        return false
    }
    if (let Some(enumDecl) <- GetOuterEnumDecl(decl)) {
        if (let Some(generic) <- enumDecl.generic) {
            return refExpr.typeArguments.size != generic.typeParameters.size
        }
        return true
    }
    return true
}

private func TargetTypeOf(ctx: ASTContext, refExpr: RefExpr): Option<Ty> {
    let key = EnumSugarNodeHash(refExpr)
    return ctx.targetTypeMap.get(key)
}

private func PutTargetType(ctx: ASTContext, refExpr: RefExpr, ty: Ty): Unit {
    let key = EnumSugarNodeHash(refExpr)
    ctx.targetTypeMap[key] = ty
}

private func RefineAgainstInterface(typeManager: TypeManager, currentTy: Ty, target: Decl): Option<Ty> {
    if (let Some(currentInterfaceTy) <- (currentTy as InterfaceTy)) {
        if (let Some(outer) <- target.outerDecl) {
            if (let Some(outerTy) <- outer.GetTy()) {
                let allSuperTys = typeManager.GetAllSuperTys(outerTy)
                if (allSuperTys.Contains(currentInterfaceTy)) {
                    return outerTy
                }
                for (superTy in allSuperTys.values) {
                    if (let Some(superInterfaceTy) <- (superTy as InterfaceTy)) {
                        if (let Some(superDecl) <- superInterfaceTy.declPtr) {
                            if (let Some(currentDecl) <- currentInterfaceTy.declPtr) {
                                if (SameDecl(superDecl, currentDecl)) {
                                    return outerTy
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return None
}

private func RefineEnumSugarTargetTy(typeManager: TypeManager, targetTy: Ty, target: Decl): Option<Ty> {
    var currentTy = targetTy
    var keepCheckingEnum = true
    while (keepCheckingEnum) {
        if (let Some(targetEnumTy) <- (currentTy as EnumTy)) {
            if (let Some(targetEnumDecl) <- targetEnumTy.declPtr) {
                if (let Some(outerEnumDecl) <- GetOuterEnumDecl(target)) {
                    if (SameDecl(targetEnumDecl, outerEnumDecl)) {
                        return currentTy
                    }
                }
            }
            if (targetEnumTy.IsCoreOptionType() && targetEnumTy.typeArgs.size == 1) {
                currentTy = targetEnumTy.typeArgs[0]
            } else {
                return None
            }
        } else {
            keepCheckingEnum = false
        }
    }
    return RefineAgainstInterface(typeManager, currentTy, target)
}

public class EnumSugarTargetsFinder {
    private var typeManager: TypeManager
    private var ctx: ASTContext
    private var refExpr: RefExpr
    private let enumSugarTargets: ArrayList<Decl> = ArrayList<Decl>()

    public init(typeManager: TypeManager, ctx: ASTContext, refExpr: RefExpr) {
        this.typeManager = typeManager
        this.ctx = ctx
        this.refExpr = refExpr
    }

    public func FindEnumSugarTargets(): ArrayList<Decl> {
        if (refExpr.TestAttr(Attribute.MACRO_INVOKE_BODY)) {
            return ArrayList<Decl>()
        }
        if (IsAllEnumSugarFuncDecl(enumSugarTargets)) {
            enumSugarTargets.clear()
        } else {
            RefineTargets()
        }
        if (enumSugarTargets.isEmpty()) {
            FindGlobalEnumConstructors()
            RefineTargets()
        }
        RemoveDuplicateDecls(enumSugarTargets)
        SortDeclsByPosition(enumSugarTargets)
        return CloneDeclList(enumSugarTargets)
    }

    public static func RefineTargetTy(typeManager: TypeManager, targetTy: Ty, target: Decl): Option<Ty> {
        return RefineEnumSugarTargetTy(typeManager, targetTy, target)
    }

    public static func RefineTargetTy(typeManager: TypeManager, targetTy: Option<Ty>, target: Option<Decl>): Option<Ty> {
        if (let Some(realTargetTy) <- targetTy) {
            if (let Some(realTarget) <- target) {
                return RefineEnumSugarTargetTy(typeManager, realTargetTy, realTarget)
            }
        }
        return None
    }

    private func FindGlobalEnumConstructors(): Unit {
        let argSize = refExpr.OuterArgSize()
        let decls = ctx.FindEnumConstructor(refExpr.ref.identifier.Val(), UInt64(argSize))
        if (argSize != 0) {
            let varDecls = ctx.FindEnumConstructor(refExpr.ref.identifier.Val(), 0u64)
            for (decl in varDecls) {
                decls.add(decl)
            }
        }
        var idx: Int64 = 0
        while (idx < decls.size) {
            if (HasMismatchedEnumSugarTypeArgs(refExpr, decls[idx])) {
                decls.remove(at: idx)
            } else {
                idx++
            }
        }
        if (refExpr.TestAttr(Attribute.IN_CORE)) {
            for (decl in decls) {
                if (decl.fullPackageName == ENUM_SUGAR_CORE_PACKAGE_NAME) {
                    enumSugarTargets.add(decl)
                }
            }
            return
        }
        for (decl in decls) {
            if (ctx.HasTargetTy(refExpr) || decl.IsSamePackage(refExpr)) {
                enumSugarTargets.add(decl)
            }
        }
        if (enumSugarTargets.isEmpty()) {
            for (decl in decls) {
                enumSugarTargets.add(decl)
            }
        }
    }

    private func RefineTargets(): Unit {
        if (!ctx.HasTargetTy(refExpr)) {
            return
        }
        if (let Some(_) <- refExpr.callOrPattern) {
            return
        }
        let inCandidates = CloneDeclList(enumSugarTargets)
        var idx: Int64 = 0
        while (idx < enumSugarTargets.size) {
            if (let Some(targetTy) <- TargetTypeOf(ctx, refExpr)) {
                if (let Some(refinedTargetTy) <- RefineEnumSugarTargetTy(typeManager, targetTy, enumSugarTargets[idx])) {
                    PutTargetType(ctx, refExpr, refinedTargetTy)
                    idx++
                } else {
                    enumSugarTargets.remove(at: idx)
                }
            } else {
                return
            }
        }
        if (enumSugarTargets.isEmpty()) {
            var hasTargetInCurrentPkg = false
            for (candidate in inCandidates) {
                if (!candidate.TestAttr(Attribute.IMPORTED)) {
                    hasTargetInCurrentPkg = true
                    break
                }
            }
            if (hasTargetInCurrentPkg) {
                for (candidate in inCandidates) {
                    if (!candidate.TestAttr(Attribute.IMPORTED)) {
                        enumSugarTargets.add(candidate)
                    }
                }
            } else {
                for (candidate in inCandidates) {
                    enumSugarTargets.add(candidate)
                }
            }
        }
    }
}
