package cjcj::frontend

import std.collection.*

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

func IsUnexpandedMacroInput(node: Node): Bool {
    return node.astKind == ASTKind.MACRO_EXPAND_DECL || node.astKind == ASTKind.MACRO_EXPAND_EXPR ||
        node.astKind == ASTKind.MACRO_EXPAND_PARAM
}

func FirstSurvivingLocalPosition(root: Node): Option<Position> {
    let hits = ArrayList<Position>()
    let walker = Walker(root, visitPre: { node: Node =>
        if (IsUnexpandedMacroInput(node)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (NodeNeedsLocalLowering(node)) {
            hits.add(node.begin)
            return VisitAction.STOP_NOW
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    if (hits.isEmpty()) {
        return None
    }
    return Some(hits[0])
}

func StoredDiagPosition(file: File, hit: Position): Position {
    if (hit != DEFAULT_POSITION && !hit.IsZero()) {
        return hit
    }
    if (file.begin != DEFAULT_POSITION && !file.begin.IsZero()) {
        return file.begin
    }
    for (decl in file.decls) {
        if (decl.begin != DEFAULT_POSITION && !decl.begin.IsZero()) {
            return decl.begin
        }
    }
    return DEFAULT_POSITION
}

func FileForHit(pkg: Package, hit: Position): Option<File> {
    if (hit.fileID != 0) {
        for (file in pkg.files) {
            if (file.begin.fileID == hit.fileID) { return Some(file) }
        }
    }
    if (!pkg.files.isEmpty()) { return Some(pkg.files[0]) }
    return None
}

func DiagnoseLocalTarget(ci: CompilerInstance, pkg: Package, hit: Position): Unit {
    let pos = if (let Some(file) <- FileForHit(pkg, hit)) {
        StoredDiagPosition(file, hit)
    } else if (hit != DEFAULT_POSITION && !hit.IsZero()) {
        hit
    } else {
        PackageDiagnosticPosition(pkg)
    }
    ci.diag.Diagnose(DiagCategory.SEMA, pos, "local mode lowering is only supported on Linux x86_64 GNU targets")
}

func DeclHasTranslatedBody(decl: Decl): Bool {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(body) <- funcDecl.funcBody) {
            return body.body.isSome()
        }
        return false
    }
    if (let Some(varDecl) <- (decl as VarDecl)) {
        return varDecl.isConst && varDecl.initializer.isSome()
    }
    return false
}

func ImportedBodyEntersTranslation(decl: Decl, optOverO2: Bool): Bool {
    if (decl.TestAttr(Attribute.INTRINSIC) || decl.TestAttr(Attribute.FOREIGN)) {
        return false
    }
    if (!decl.TestAttr(Attribute.IMPORTED) || !decl.isUsedImports) {
        return false
    }
    if (!DeclHasTranslatedBody(decl)) {
        return false
    }
    if (decl.IsConst()) {
        return true
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        return optOverO2 && funcDecl.isFrozen && !funcDecl.TestAttr(Attribute.ABSTRACT)
    }
    return false
}

func FirstImportedDeclLocal(decl: Decl, optOverO2: Bool): Option<Position> {
    if (decl.TestAttr(Attribute.INTRINSIC) || decl.TestAttr(Attribute.FOREIGN)) {
        return None
    }
    if (decl.TestAttr(Attribute.IMPORTED) && !decl.isUsedImports) {
        return None
    }
    if (decl.IsNominalDecl()) {
        for (member in decl.GetMemberDecls()) {
            if (let Some(hit) <- FirstImportedDeclLocal(member, optOverO2)) {
                return Some(hit)
            }
        }
        return None
    }
    if (let Some(propDecl) <- (decl as PropDecl)) {
        for (getter in propDecl.getters) {
            if (let Some(hit) <- FirstImportedDeclLocal(getter, optOverO2)) {
                return Some(hit)
            }
        }
        for (setter in propDecl.setters) {
            if (let Some(hit) <- FirstImportedDeclLocal(setter, optOverO2)) {
                return Some(hit)
            }
        }
        return None
    }
    if (ImportedBodyEntersTranslation(decl, optOverO2)) {
        return FirstSurvivingLocalPosition(decl)
    }
    return None
}

func FirstImportedPackageLocal(pkg: Package, optOverO2: Bool): Option<Position> {
    for (decl in pkg.srcImportedNonGenericDecls) {
        if (ImportedBodyEntersTranslation(decl, optOverO2)) {
            if (let Some(hit) <- FirstSurvivingLocalPosition(decl)) {
                return Some(hit)
            }
        }
    }
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(hit) <- FirstImportedDeclLocal(decl, optOverO2)) {
                return Some(hit)
            }
        }
        for (decl in file.exportedInternalDecls) {
            if (let Some(hit) <- FirstImportedDeclLocal(decl, optOverO2)) {
                return Some(hit)
            }
        }
    }
    return None
}

func CheckLocalModeLoweringTarget(ci: CompilerInstance): Bool {
    let opts = ci.invocation.globalOptions
    if (!opts.enableLocalMode || opts.SupportsLocalModeLowering()) { return true }
    let sourceNames = HashSet<String>()
    for (pkg in ci.GetSourcePackages()) {
        sourceNames.add(pkg.fullPackageName)
        if (let Some(hit) <- FirstSurvivingLocalPosition(pkg)) {
            DiagnoseLocalTarget(ci, pkg, hit)
            return false
        }
    }
    if (let Some(manager) <- ci.importManager) {
        let optOverO2 = opts.IsCHIROptimizationLevelOverO2()
        for (pkg in manager.GetAllImportedPackages()) {
            if (sourceNames.contains(pkg.fullPackageName)) { continue }
            if (!pkg.TestAttr(Attribute.IMPORTED)) { continue }
            if (let Some(hit) <- FirstImportedPackageLocal(pkg, optOverO2)) {
                DiagnoseLocalTarget(ci, pkg, hit)
                return false
            }
        }
    }
    return true
}
