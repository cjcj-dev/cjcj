package cangjie_compiler::sema.Desugar

import cangjie_compiler::ast.*

private func IsExtendMember(funcDecl: FuncDecl): Bool {
    if (let Some(outer) <- funcDecl.outerDecl) {
        if (let Some(_) <- (outer as ExtendDecl)) {
            return true
        }
    }
    return false
}

private func IsCompilerAddedExtendMember(funcDecl: FuncDecl): Bool {
    if (let Some(outer) <- funcDecl.outerDecl) {
        if (let Some(_) <- (outer as ExtendDecl)) {
            return outer.TestAttr(Attribute.COMPILER_ADD)
        }
    }
    return false
}

private func MarkForTest(funcDecl: FuncDecl): Unit {
    if (let Some(outer) <- funcDecl.outerDecl) {
        if (let Some(_) <- (outer as ExtendDecl)) {
            outer.EnableAttr(Attribute.FOR_TEST)
            return
        }
    }
    funcDecl.EnableAttr(Attribute.FOR_TEST)
}

private func UpdateDeclAttributes(pkg: Package, exportForTest: Bool): Unit {
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (let Some(varDecl) <- (node as VarDecl)) {
            if (let Some(_) <- varDecl.initializer) {
                varDecl.EnableAttr(Attribute.DEFAULT)
            }
        }
        if (!exportForTest) {
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(funcDecl) <- (node as FuncDecl)) {
            if (funcDecl.TestAttr(Attribute.PRIVATE)) {
                return VisitAction.WALK_CHILDREN
            }
            let isExtend = IsExtendMember(funcDecl)
            let isForeignFunc = funcDecl.TestAttr(Attribute.FOREIGN)
            if (!isExtend && !isForeignFunc) {
                return VisitAction.WALK_CHILDREN
            }
            if (isExtend && IsCompilerAddedExtendMember(funcDecl)) {
                return VisitAction.WALK_CHILDREN
            }
            funcDecl.linkage = Linkage.EXTERNAL
            if (let Some(propDecl) <- funcDecl.propDecl) {
                propDecl.linkage = Linkage.EXTERNAL
            }
            MarkForTest(funcDecl)
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func ClearLineInfo(root: Node): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        node.begin.line = 0
        node.begin.column = 0
        node.begin.Mark(PositionStatus.IGNORE)
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func ClearLineInfoAfterSema(pkg: Package): Unit {
    for (decl in pkg.genericInstantiatedDecls) {
        ClearLineInfo(decl)
    }
}

public func DesugarAfterInstantiation(pkg: Package, exportForTest!: Bool = false,
    enableCoverage!: Bool = false): Unit {
    if (pkg.files.isEmpty()) {
        return
    }
    UpdateDeclAttributes(pkg, exportForTest)
    if (enableCoverage) {
        ClearLineInfoAfterSema(pkg)
    }
}

public func SelfhostPortStatus_Desugar_DesugarAfterInstantiation(): Bool {
    return false
}
