package cjcj::sema.GenericInstantiation

import cjcj::ast.*
import cjcj::sema.*
import cjcj::utils.{BOX_DECL_PREFIX, CJC_ASSERT, InternalError}

class InstantiatedExtendRecorder {
    private var gim: GenericInstantiationManagerImpl
    private var typeManager: TypeManager
    private var promotion: Promotion
    private let recorderId: UInt32 = GetNextWalkerID()

    init(gim: GenericInstantiationManagerImpl, typeManager: TypeManager) {
        this.gim = gim
        this.typeManager = typeManager
        promotion = Promotion(typeManager)
    }

    public func Record(node: Node): Unit {
        if (let Some(pkg) <- (node as Package)) {
            for (file in pkg.files) {
                Record(file)
            }
            for (decl in pkg.srcImportedNonGenericDecls) {
                Record(decl)
            }
            return
        }
        let walker = Walker(node, recorderId, visitPre: { current: Node =>
            RecordUsedExtendDecl(current)
        }, visitPost: { current: Node =>
            gim.PopStructContext(current)
        })
        let _ = walker.Walk()
    }

    private func ShouldSkipRecordNode(node: Node): Bool {
        if (node.astKind == ASTKind.GENERIC_PARAM_DECL || node.astKind == ASTKind.GENERIC_CONSTRAINT ||
            node.astKind == ASTKind.PRIMARY_CTOR_DECL || node.astKind == ASTKind.MODIFIER) {
            return true
        }
        if (node.astKind == ASTKind.FUNC_ARG && node.TestAttr(Attribute.HAS_INITIAL)) {
            return true
        }
        if (let Some(decl) <- (node as Decl)) {
            if (decl.TestAttr(Attribute.GENERIC)) {
                return true
            }
            if (decl.astKind == ASTKind.CLASS_DECL && decl.identifier.Val().startsWith(BOX_DECL_PREFIX)) {
                return true
            }
        }
        return false
    }

    private func RecordUsedExtendDecl(node: Node): VisitAction {
        if (ShouldSkipRecordNode(node)) {
            return VisitAction.SKIP_CHILDREN
        }
        gim.PushStructContext(node)
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(desugarExpr) <- expr.desugarExpr) {
                Record(desugarExpr)
                return VisitAction.SKIP_CHILDREN
            }
        }
        if (let Some(refExpr) <- (node as RefExpr)) {
            RecordExtendForRefExpr(refExpr)
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            RecordExtendForMemberAccess(memberAccess)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func RecordExtendForRefExpr(refExpr: RefExpr): Unit {
        let target = if (let Some(value) <- refExpr.ref.target) {
            value
        } else {
            return
        }
        let ignored = !Ty.IsTyCorrect(refExpr.GetTy()) || target.IsBuiltIn() ||
            !target.TestAttr(Attribute.IN_EXTEND)
        if (ignored) {
            return
        }
        let extendDecl = if (let Some(value) <- target.outerDecl) {
            value
        } else {
            return
        }
        CJC_ASSERT(extendDecl.astKind == ASTKind.EXTEND_DECL)
        let structDecl = if (let Some(value) <- gim.GetStructDeclByContext()) {
            value
        } else {
            return
        }
        let baseTy = if (let Some(value) <- GetDeclTy(structDecl)) {
            value
        } else {
            return
        }
        let extendTy = if (let Some(value) <- extendDecl.GetTy()) {
            value
        } else {
            return
        }
        if (!Ty.IsTyCorrect(baseTy) || !Ty.IsTyCorrect(extendTy) || baseTy.HasGeneric()) {
            return
        }
        let promoteRes = promotion.Promote(baseTy, extendTy)
        if (promoteRes.IsEmpty()) {
            InternalError("generic instantiation failed")
            return
        }
        if (let Some(ed) <- (extendDecl as ExtendDecl)) {
            typeManager.RecordUsedGenericExtend(promoteRes.values[0], extendDecl: ed)
        }
    }

    private func RecordExtendForMemberAccess(memberAccess: MemberAccess): Unit {
        let target = if (let Some(value) <- memberAccess.GetTarget()) {
            value
        } else {
            return
        }
        let baseExpr = if (let Some(value) <- memberAccess.baseExpr) {
            value
        } else {
            return
        }
        let baseTy = if (let Some(value) <- baseExpr.GetTy()) {
            value
        } else {
            return
        }
        if (!Ty.IsTyCorrect(baseTy) || baseTy.HasGeneric()) {
            return
        }
        let outerDecl = if (let Some(value) <- target.outerDecl) {
            value
        } else {
            return
        }
        if (let Some(funcDecl) <- (target as FuncDecl)) {
            if (outerDecl.astKind == ASTKind.INTERFACE_DECL) {
                RecordImplExtendDecl(baseTy, funcDecl, memberAccess.matchedParentTy)
                return
            }
        }
        if (outerDecl.astKind == ASTKind.EXTEND_DECL) {
            let promoteRes = promotion.Promote(baseTy, outerDecl.GetTy().getOrThrow())
            if (promoteRes.IsEmpty()) {
                InternalError("generic instantiation failed")
                return
            }
            typeManager.RecordUsedGenericExtend(promoteRes.values[0], extendDecl: (outerDecl as ExtendDecl))
        }
    }

    private func RecordImplExtendDecl(ty: Ty, fd: FuncDecl, upperTy: Option<Ty>): Unit {
        let baseTy = typeManager.GetTyForExtendMap(ty)
        let genericFdDecl = gim.GetGeneralDecl(fd)
        CJC_ASSERT(genericFdDecl.astKind == ASTKind.FUNC_DECL)
        let genericFd = if (let Some(value) <- (genericFdDecl as FuncDecl)) {
            value
        } else {
            return
        }
        let declMap = if (let Some(value) <- gim.abstractFuncToDeclMap.Find(baseTy, genericFd)) {
            value
        } else {
            return
        }
        var selectedExtend: Option<Decl> = None
        for ((baseDecl, _) in declMap) {
            if (baseDecl.astKind != ASTKind.EXTEND_DECL) {
                continue
            }
            if (let Some(upperTyValue) <- upperTy) {
                if (Ty.IsTyCorrect(upperTyValue)) {
                    if (let Some(inheritableDecl) <- (baseDecl as InheritableDecl)) {
                        var isImplemented = false
                        for (typeNode in inheritableDecl.inheritedTypes) {
                            if (let Some(inheritedTy) <- typeNode.GetTy()) {
                                if (typeManager.IsSubtype(inheritedTy, upperTyValue)) {
                                    isImplemented = true
                                    break
                                }
                            }
                        }
                        if (isImplemented) {
                            selectedExtend = baseDecl
                            break
                        }
                    }
                }
            }
            selectedExtend = baseDecl
        }
        if (let Some(extendDecl) <- selectedExtend) {
            if (let Some(ed) <- (extendDecl as ExtendDecl)) {
                typeManager.RecordUsedGenericExtend(ty, extendDecl: ed)
            }
        }
    }
}
