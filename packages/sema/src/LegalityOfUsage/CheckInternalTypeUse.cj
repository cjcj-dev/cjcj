package cjcj::sema.LegalityOfUsage

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.{DiagLowerAccessLevelTypesUse, DiagPatternInternalTypesUse}
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK}

private func AccessRank(level: AccessLevel): Int64 {
    return match (level) {
        case AccessLevel.PRIVATE => 0
        case AccessLevel.INTERNAL => 1
        case AccessLevel.PROTECTED => 2
        case AccessLevel.PUBLIC => 3
    }
}

public func IsCompatibleAccessLevel(srcLevel: AccessLevel, targetLevel: AccessLevel): Bool {
    return AccessRank(srcLevel) <= AccessRank(targetLevel)
}

private func IsAccessible(typeValue: Option<Ty>, srcLevel: AccessLevel): (Option<Decl>, Bool) {
    if (!Ty.IsTyCorrect(typeValue)) {
        return (None, true)
    }
    let tyValue = typeValue.getOrThrow()
    for (ty in tyValue.typeArgs) {
        if (!Ty.IsTyCorrect(ty)) {
            continue
        }
        let (decl, accessible) = IsAccessible(Some(ty), srcLevel)
        if (!accessible) {
            return (decl, false)
        }
    }
    if (tyValue.IsNominal()) {
        if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(tyValue))) {
            if (!IsCompatibleAccessLevel(srcLevel, GetAccessLevel(decl))) {
                return (Some(decl), false)
            }
        }
    }
    return (None, true)
}

private func CollectGenericTyAccessibility(decl: Decl, limitedDecls: ArrayList<(Node, Decl)>): Unit {
    if (let Some(generic) <- decl.GetGeneric()) {
        let declLevel = GetAccessLevel(decl)
        for (constraint in generic.genericConstraints) {
            for (upperBound in constraint.upperBounds) {
                if (let Some(upperTy) <- upperBound.GetTy()) {
                    let (ubDecl, accessible) = IsAccessible(Some(upperTy), declLevel)
                    if (!accessible) {
                        limitedDecls.add((upperBound, ubDecl.getOrThrow()))
                    }
                }
            }
        }
    }
}

public func CheckAccessLevelValidity(pkg: Package, diag: BasicDiagnosticEngine): Unit {
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (decl.TestAttr(Attribute.PRIVATE)) {
                continue
            }
            if (decl.TestAttr(Attribute.FROM_COMMON_PART)) {
                continue
            }
            CheckNonPrivateDeclAccessLevelValidity(decl, diag)
        }
    }
}

public func CheckNonPrivateDeclAccessLevelValidity(decl: Decl, diag: BasicDiagnosticEngine): Unit {
    if (!Ty.IsTyCorrect(decl.GetTy())) {
        return
    }
    if (let Some(id) <- (decl as InheritableDecl)) {
        CheckNominalDeclAccessLevelValidity(id, diag)
    } else if (let Some(fd) <- (decl as FuncDecl)) {
        CheckFuncAccessLevelValidity(fd, diag)
    } else if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
        CJC_NULLPTR_CHECK(vpd.irrefutablePattern)
        CheckPatternVarAccessLevelValidity(vpd.irrefutablePattern.getOrThrow(), diag)
    } else if (let Some(tad) <- (decl as TypeAliasDecl)) {
        let limitedDecls = ArrayList<(Node, Decl)>()
        CJC_NULLPTR_CHECK(tad.typeNode)
        let typeNode = tad.typeNode.getOrThrow()
        let (inDecl, accessible) = IsAccessible(typeNode.GetTy(), GetAccessLevel(tad))
        if (!accessible) {
            limitedDecls.add((typeNode, inDecl.getOrThrow()))
        }
        CollectGenericTyAccessibility(tad, limitedDecls)
        DiagLowerAccessLevelTypesUse(diag, tad, limitedDecls)
    } else if (let Some(pd) <- (decl as PropDecl)) {
        CJC_NULLPTR_CHECK(pd.typeNode)
        let (inDecl, accessible) = IsAccessible(pd.GetTy(), GetAccessLevel(pd))
        if (!accessible) {
            let limitedDecls = ArrayList<(Node, Decl)>()
            limitedDecls.add((pd.typeNode.getOrThrow(), inDecl.getOrThrow()))
            DiagLowerAccessLevelTypesUse(diag, pd, limitedDecls)
        }
    } else if (let Some(vd) <- (decl as VarDecl)) {
        let (inDecl, accessible) = IsAccessible(vd.GetTy(), GetAccessLevel(vd))
        if (accessible) {
            return
        }
        let limitedDecls = ArrayList<(Node, Decl)>()
        if (let Some(typeNode) <- vd.typeNode) {
            limitedDecls.add((typeNode, inDecl.getOrThrow()))
            DiagLowerAccessLevelTypesUse(diag, vd, limitedDecls)
        } else {
            let hintDecls = ArrayList<Decl>()
            hintDecls.add(inDecl.getOrThrow())
            DiagLowerAccessLevelTypesUse(diag, vd, limitedDecls, hintDecls: hintDecls)
        }
    }
}

public func CheckNominalDeclAccessLevelValidity(id: InheritableDecl, diag: BasicDiagnosticEngine): Unit {
    if (id.astKind == ASTKind.EXTEND_DECL) {
        return
    }
    let limitedDecls = ArrayList<(Node, Decl)>()
    CollectGenericTyAccessibility(id, limitedDecls)
    DiagLowerAccessLevelTypesUse(diag, id, limitedDecls)
    for (member in id.GetMemberDeclPtrs()) {
        if (!member.TestAttr(Attribute.PRIVATE) && !member.TestAttr(Attribute.FROM_COMMON_PART)) {
            CheckNonPrivateDeclAccessLevelValidity(member, diag)
        }
    }
}

public func CheckFuncAccessLevelValidity(fd: FuncDecl, diag: BasicDiagnosticEngine): Unit {
    CJC_NULLPTR_CHECK(fd.funcBody)
    let body = fd.funcBody.getOrThrow()
    let limitedDecls = ArrayList<(Node, Decl)>()
    let hintDecls = ArrayList<Decl>()
    if (let Some(retType) <- body.retType) {
        let (decl, accessible) = IsAccessible(retType.GetTy(), GetAccessLevel(fd))
        if (!accessible) {
            if (!retType.TestAttr(Attribute.COMPILER_ADD)) {
                limitedDecls.add((retType, decl.getOrThrow()))
            } else {
                hintDecls.add(decl.getOrThrow())
            }
        }
    }
    for (param in body.paramLists[0].params) {
        if (fd.TestAttr(Attribute.FROM_COMMON_PART)) {
            continue
        }
        CJC_ASSERT(param.typeNode.isSome())
        let (inDecl, accessible) = IsAccessible(param.GetTy(), GetAccessLevel(fd))
        if (!accessible) {
            limitedDecls.add((param.typeNode.getOrThrow(), inDecl.getOrThrow()))
        }
    }
    CollectGenericTyAccessibility(fd, limitedDecls)
    DiagLowerAccessLevelTypesUse(diag, fd, limitedDecls, hintDecls: hintDecls)
}

public func CheckPatternVarAccessLevelValidity(pattern: Pattern, diag: BasicDiagnosticEngine): Unit {
    let limitedDecls = ArrayList<(Node, Decl)>()
    let walker = Walker(pattern, visitPre: { node: Node =>
        if (let Some(vd) <- (node as VarDecl)) {
            let (inDecl, accessible) = IsAccessible(vd.GetTy(), GetAccessLevel(vd))
            if (!accessible) {
                limitedDecls.add((vd, inDecl.getOrThrow()))
            }
            return VisitAction.SKIP_CHILDREN
        }
        return VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    DiagPatternInternalTypesUse(diag, limitedDecls)
}
