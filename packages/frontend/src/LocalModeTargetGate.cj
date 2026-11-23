package cjcj::frontend

func ModalSurvives(modal: Option<ASTModalInfo>): Bool {
    if (let Some(info) <- modal) {
        return info.local != ASTMode.NOT
    }
    return false
}

func NodeNeedsLocalLowering(node: Node): Bool {
    if (node.resolvedMode != ASTMode.NOT) { return true }
    if (node.astKind == ASTKind.EXCLAVE_EXPR) { return true }
    if (let Some(ty) <- (node as Type)) {
        if (ModalSurvives(ty.modal)) { return true }
    }
    if (let Some(call) <- (node as CallExpr)) {
        if (ModalSurvives(call.modal)) { return true }
    }
    if (let Some(list) <- (node as FuncParamList)) {
        if (ModalSurvives(list.receiverModal)) { return true }
        if (let Some(thisParam) <- list.thisParam) {
            if (thisParam.resolvedMode != ASTMode.NOT) { return true }
            if (let Some(ty) <- thisParam.typeNode) {
                if (ty.resolvedMode != ASTMode.NOT || ModalSurvives(ty.modal)) { return true }
            }
        }
    }
    if (let Some(modifier) <- (node as Modifier)) {
        if (modifier.modifier == TokenKind.EXCLAVE || modifier.modifier == TokenKind.DEMODE) { return true }
    }
    return false
}

func FileHasSurvivingLocalMode(file: File): Bool {
    let hits = ArrayList<Int64>()
    let walker = Walker(file, visitPre: { node: Node =>
        if (NodeNeedsLocalLowering(node)) {
            hits.add(1)
            return VisitAction.STOP_NOW
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    return !hits.isEmpty()
}

func CheckLocalModeLoweringTarget(ci: CompilerInstance): Bool {
    let opts = ci.invocation.globalOptions
    if (!opts.enableLocalMode || opts.SupportsLocalModeLowering()) { return true }
    for (pkg in ci.GetSourcePackages()) {
        for (file in pkg.files) {
            if (FileHasSurvivingLocalMode(file)) {
                ci.diag.Diagnose(DiagCategory.SEMA, DEFAULT_POSITION,
                    "local mode lowering is only supported on Linux x86_64 GNU targets")
                return false
            }
        }
    }
    return true
}
