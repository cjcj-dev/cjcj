package cangjie_compiler::sema.GenericInstantiation

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func containsExtend(values: ArrayList<ExtendDecl>, extendDecl: ExtendDecl): Bool {
    for (value in values) {
        if (SameDecl(value, extendDecl)) {
            return true
        }
    }
    return false
}

private func addExtendUnique(values: ArrayList<ExtendDecl>, extendDecl: ExtendDecl): Bool {
    if (containsExtend(values, extendDecl)) {
        return false
    }
    values.add(extendDecl)
    return true
}

public class InstantiatedExtendRecorder {
    private var typeManager: TypeManager
    private var promotion: Promotion
    private let usedExtends: ArrayList<ExtendDecl> = ArrayList<ExtendDecl>()

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
        promotion = Promotion(typeManager)
    }

    public func Record(node: Node): Unit {
        let walker = Walker(node, visitPre: { current: Node =>
            RecordUsedExtendDecl(current)
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    public func GetUsedExtends(): ArrayList<ExtendDecl> {
        let out = ArrayList<ExtendDecl>()
        for (extendDecl in usedExtends) {
            out.add(extendDecl)
        }
        return out
    }

    public func Clear(): Unit {
        usedExtends.clear()
    }

    private func RecordUsedExtendDecl(node: Node): Unit {
        if (let Some(refExpr) <- (node as RefExpr)) {
            RecordExtendForTarget(refExpr.GetTarget())
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            RecordExtendForMemberAccess(memberAccess)
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                RecordExtendForTy(baseExpr.GetTy())
            }
        }
        RecordExtendForTy(node.GetTy())
    }

    private func RememberExtend(extendDecl: ExtendDecl): Unit {
        let _ = addExtendUnique(usedExtends, extendDecl)
    }

    private func RecordExactUsedExtend(baseTy: Ty, extendDecl: ExtendDecl): Unit {
        RememberExtend(extendDecl)
        if (let Some(extendTy) <- GetDeclTy(extendDecl)) {
            let promotedTys = promotion.Promote(baseTy, extendTy)
            if (!promotedTys.IsEmpty()) {
                typeManager.RecordUsedGenericExtend(promotedTys.values[0], extendDecl: extendDecl)
                return
            }
        }
        typeManager.RecordUsedGenericExtend(baseTy, extendDecl: extendDecl)
    }

    private func RecordFallbackUsedExtend(extendDecl: ExtendDecl): Unit {
        RememberExtend(extendDecl)
        if (let Some(extendTy) <- GetDeclTy(extendDecl)) {
            typeManager.RecordUsedGenericExtend(extendTy, extendDecl: extendDecl)
        }
    }

    private func RecordExtendForMemberAccess(memberAccess: MemberAccess): Unit {
        if (let Some(target) <- memberAccess.GetTarget()) {
            if (let Some(outerDecl) <- target.outerDecl) {
                if (let Some(extendDecl) <- (outerDecl as ExtendDecl)) {
                    if (let Some(baseExpr) <- memberAccess.baseExpr) {
                        if (let Some(baseTy) <- baseExpr.GetTy()) {
                            if (!baseTy.HasGeneric()) {
                                RecordExactUsedExtend(baseTy, extendDecl)
                                return
                            }
                        }
                    }
                    RecordFallbackUsedExtend(extendDecl)
                    return
                }
            }
        }
        RecordExtendForTarget(memberAccess.GetTarget())
    }

    private func RecordExtendForTarget(target: Option<Decl>): Unit {
        if (let Some(decl) <- target) {
            if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                RecordFallbackUsedExtend(extendDecl)
                return
            }
            if (let Some(outerDecl) <- decl.outerDecl) {
                if (let Some(extendDecl) <- (outerDecl as ExtendDecl)) {
                    RecordFallbackUsedExtend(extendDecl)
                }
            }
        }
    }

    private func RecordExtendForTy(ty: Option<Ty>): Unit {
        if (let Some(value) <- ty) {
            for (extendDecl in typeManager.GetAllExtendsByTy(value)) {
                RememberExtend(extendDecl)
                typeManager.RecordUsedGenericExtend(value, extendDecl: extendDecl)
            }
        }
    }
}
