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
    private let usedExtends: ArrayList<ExtendDecl> = ArrayList<ExtendDecl>()

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
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
            RecordExtendForTarget(memberAccess.GetTarget())
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                RecordExtendForTy(baseExpr.GetTy())
            }
        }
        RecordExtendForTy(node.GetTy())
    }

    private func RecordExtendForTarget(target: Option<Decl>): Unit {
        if (let Some(decl) <- target) {
            if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                let _ = addExtendUnique(usedExtends, extendDecl)
                return
            }
            if (let Some(outerDecl) <- decl.outerDecl) {
                if (let Some(extendDecl) <- (outerDecl as ExtendDecl)) {
                    let _ = addExtendUnique(usedExtends, extendDecl)
                }
            }
        }
    }

    private func RecordExtendForTy(ty: Option<Ty>): Unit {
        if (let Some(value) <- ty) {
            for (extendDecl in typeManager.GetAllExtendsByTy(value)) {
                let _ = addExtendUnique(usedExtends, extendDecl)
            }
        }
    }
}
