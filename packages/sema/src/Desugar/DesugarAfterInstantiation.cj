package cjcj::sema.Desugar

import std.collection.*
import cjcj::ast.*
import cjcj::sema.*

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

private func IterateTyWithArgs(ty: Option<Ty>, fn: (Ty) -> Unit): Unit {
    if (let Some(value) <- ty) {
        if (!Ty.IsTyCorrect(value)) {
            return
        }
        fn(value)
        for (typeArg in value.typeArgs) {
            IterateTyWithArgs(Some(typeArg), fn)
        }
    }
}

private class UsedImportMarker {
    private let typeManager: TypeManager
    private let walkerId: UInt32

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
        walkerId = GetNextWalkerID()
    }

    private func MarkTy(ty: Option<Ty>): Unit {
        IterateTyWithArgs(ty, { value: Ty =>
            if (let Some(decl) <- Ty.GetDeclOfTy(Some(value))) {
                MarkUsedNode(decl)
            }
        })
    }

    private func MarkUsedDecl(decl: Decl): VisitAction {
        if (decl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            if (let Some(genericDecl) <- decl.genericDecl) {
                if (genericDecl.TestAttr(Attribute.IMPORTED)) {
                    MarkUsedNode(genericDecl)
                }
            }
        }
        if (!decl.TestAttr(Attribute.IMPORTED)) {
            return VisitAction.WALK_CHILDREN
        }
        if (decl.isUsedImports) {
            return VisitAction.SKIP_CHILDREN
        }
        decl.isUsedImports = true
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(propDecl) <- funcDecl.propDecl) {
                propDecl.isUsedImports = true
            }
        }
        if (let Some(outerDecl) <- decl.outerDecl) {
            MarkUsedNode(outerDecl)
        }
        if (!decl.IsNominalDecl()) {
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(declTy) <- decl.GetTy()) {
            for (extendDecl in typeManager.GetAllExtendsByTy(declTy)) {
                if (!SameDecl(extendDecl, decl) && extendDecl.TestAttr(Attribute.IMPORTED)) {
                    MarkUsedNode(extendDecl)
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func CollectUsed(node: Node): VisitAction {
        MarkTy(node.GetTy())
        if (let Some(typeNode) <- (node as Type)) {
            if (!Ty.IsInitialTy(typeNode.aliasTy)) {
                MarkTy(typeNode.aliasTy)
            }
        } else if (let Some(decl) <- (node as Decl)) {
            return MarkUsedDecl(decl)
        } else if (let Some(arrayExpr) <- (node as ArrayExpr)) {
            if (let Some(initFunc) <- arrayExpr.initFunc) {
                MarkUsedNode(initFunc)
            }
        }

        var target = node.GetTarget()
        if (let Some(callExpr) <- (node as CallExpr)) {
            if (let Some(resolved) <- callExpr.resolvedFunction) {
                target = resolved
            }
        }
        if (let Some(targetDecl) <- target) {
            MarkUsedNode(targetDecl)
        }
        return VisitAction.WALK_CHILDREN
    }

    public func MarkUsedNode(node: Node): Unit {
        let walker = Walker(node, walkerId, visitPre: { current: Node =>
            CollectUsed(current)
        })
        let _ = walker.Walk()
    }
}

private func EraseUnusedImportedDecls(values: ArrayList<Decl>): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (!values[idx].isUsedImports) {
            values.remove(at: idx)
            continue
        }
        idx++
    }
}

private func EraseUnusedImportedFuncDecls(values: ArrayList<FuncDecl>): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (!values[idx].isUsedImports) {
            values.remove(at: idx)
            continue
        }
        idx++
    }
}

private func MarkUsedPackageInFile(typeManager: TypeManager, pkg: Package, implicitUsedDecls: ArrayList<Decl>): Unit {
    let marker = UsedImportMarker(typeManager)
    for (decl in implicitUsedDecls) {
        marker.MarkUsedNode(decl)
    }
    for (entry in typeManager.builtinTyToExtendMap) {
        for (extendDecl in entry.extends) {
            marker.MarkUsedNode(extendDecl)
        }
    }
    for (file in pkg.files) {
        marker.MarkUsedNode(file)
    }
    for (decl in pkg.genericInstantiatedDecls) {
        marker.MarkUsedNode(decl)
    }
    EraseUnusedImportedDecls(pkg.srcImportedNonGenericDecls)
    EraseUnusedImportedFuncDecls(pkg.inlineFuncDecls)
}

private func DesugarAfterInstantiationCore(pkg: Package, exportForTest: Bool, enableCoverage: Bool): Unit {
    UpdateDeclAttributes(pkg, exportForTest)
    if (enableCoverage) {
        ClearLineInfoAfterSema(pkg)
    }
}

public func DesugarAfterInstantiation(typeManager: TypeManager, importedPkgs: ArrayList<PackageDecl>, pkg: Package,
    exportForTest!: Bool = false, enableCoverage!: Bool = false,
    implicitUsedDecls!: Option<ArrayList<Decl>> = None): Unit {
    if (pkg.files.isEmpty()) {
        return
    }
    PerformRecursiveTypesElimination(importedPkgs, typeManager)
    DesugarAfterInstantiationCore(pkg, exportForTest, enableCoverage)
    if (let Some(decls) <- implicitUsedDecls) {
        MarkUsedPackageInFile(typeManager, pkg, decls)
    }
}
