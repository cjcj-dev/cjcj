package cjcj::sema.Desugar.AfterTypeCheck

import std.collection.*
import cjcj::ast.*
import cjcj::incremental_compilation.GetTypeRawMangleName
import cjcj::sema.*

private func AddDeclUsage(info: SemanticInfo, decl: Decl): Unit {
    if (decl.IsBuiltIn() || decl.astKind == ASTKind.PACKAGE_DECL) {
        return
    }
    if (!decl.rawMangleName.isEmpty()) {
        info.usedMangles.add(decl.rawMangleName)
    } else if (!decl.mangledName.isEmpty()) {
        info.usedMangles.add(decl.mangledName)
    }
    if (IsClassOrEnumConstructor(decl)) {
        if (let Some(outer) <- decl.outerDecl) {
            if (!outer.rawMangleName.isEmpty()) {
                info.usedMangles.add(outer.rawMangleName)
            } else if (!outer.mangledName.isEmpty()) {
                info.usedMangles.add(outer.mangledName)
            }
            if (decl.TestAttr(Attribute.IMPLICIT_ADD) && !outer.rawMangleName.isEmpty()) {
                info.usedMangles.add(outer.rawMangleName + "<init>")
            }
        }
    }
}

private func AddTypeUsage(info: SemanticInfo, ty: Option<Ty>): Unit {
    if (let Some(value) <- ty) {
        if (!Ty.IsTyCorrect(value)) {
            return
        }
        if (let Some(decl) <- Ty.GetDeclPtrOfTy(value)) {
            AddDeclUsage(info, decl)
        } else if (value.IsBuiltin()) {
            info.usedMangles.add(GetTypeRawMangleName(value))
        }
        for (arg in value.typeArgs) {
            AddTypeUsage(info, arg)
        }
    }
}

private func AddNodeUsage(info: SemanticInfo, node: Node): VisitAction {
    if (node.TestAttr(Attribute.IMPLICIT_ADD)) {
        return VisitAction.SKIP_CHILDREN
    }
    if (let Some(arg) <- (node as FuncArg)) {
        if (arg.TestAttr(Attribute.HAS_INITIAL)) {
            return VisitAction.SKIP_CHILDREN
        }
    }
    AddTypeUsage(info, node.GetTy())
    if (let Some(typeNode) <- (node as Type)) {
        AddTypeUsage(info, typeNode.GetTy())
        if (let Some(target) <- typeNode.GetTarget()) {
            AddDeclUsage(info, target)
        }
    } else if (let Some(target) <- node.GetTarget()) {
        AddDeclUsage(info, target)
    }
    for (target in node.GetTargets()) {
        AddDeclUsage(info, target.getOrThrow())
    }
    return VisitAction.WALK_CHILDREN
}

private class SemanticUsageCollector {
    private var typeManager: TypeManager
    private let packages: ArrayList<Package>
    private let info: SemanticInfo = SemanticInfo()

    public init(typeManager: TypeManager, pkgs: ArrayList<Package>) {
        this.typeManager = typeManager
        packages = pkgs
        this.typeManager.ClearRecordUsedExtends()
    }

    public func CollectInfoUsages(): SemanticInfo {
        for (pkg in packages) {
            CollectCompilerAddedDeclUsage(pkg, info)
            for (file in pkg.files) {
                for (decl in file.decls) {
                    CollectForDecl(decl)
                }
            }
        }
        return info
    }

    private func CollectForDecl(decl: Decl): Unit {
        if (decl.TestAnyAttr(Attribute.MACRO_INVOKE_FUNC, Attribute.IMPLICIT_ADD) ||
            decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            return
        }
        if (decl.TestAttr(Attribute.INCRE_COMPILE)) {
            AddDeclUsage(info, decl)
            return
        }
        AddDeclUsage(info, decl)
        if (let Some(varDecl) <- (decl as VarDecl)) {
            CollectVarDecl(varDecl)
        } else if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(desugarDecl) <- mainDecl.desugarDecl) {
                CollectForDecl(desugarDecl)
            } else if (let Some(body) <- mainDecl.funcBody) {
                CollectNode(body)
            }
        } else if (let Some(funcDecl) <- (decl as FuncDecl)) {
            CollectFuncDecl(funcDecl)
        } else if (let Some(typeDecl) <- (decl as InheritableDecl)) {
            CollectInheritableDecl(typeDecl)
        } else {
            CollectNode(decl)
        }
        CollectAnnotationUsage(decl)
    }

    private func CollectVarDecl(varDecl: VarDecl): Unit {
        if (let Some(typeNode) <- varDecl.typeNode) {
            CollectNode(typeNode)
        }
        if (let Some(initializer) <- varDecl.initializer) {
            CollectBodyUsage(initializer)
        }
    }

    private func CollectFuncDecl(funcDecl: FuncDecl): Unit {
        if (let Some(body) <- funcDecl.funcBody) {
            for (paramList in body.paramLists) {
                for (param in paramList.params) {
                    CollectVarDecl(param)
                    CollectAnnotationUsage(param)
                }
            }
            if (let Some(retType) <- body.retType) {
                if (!retType.TestAttr(Attribute.COMPILER_ADD)) {
                    CollectNode(retType)
                }
            }
            if (let Some(generic) <- body.generic) {
                CollectGenericUsage(generic)
            }
            if (let Some(block) <- body.body) {
                CollectBodyUsage(block)
            }
        }
        if (let Some(propDecl) <- funcDecl.propDecl) {
            CollectAnnotationUsage(propDecl)
        }
    }

    private func CollectInheritableDecl(decl: InheritableDecl): Unit {
        for (inheritedType in decl.inheritedTypes) {
            CollectNode(inheritedType)
        }
        if (let Some(generic) <- decl.generic) {
            CollectGenericUsage(generic)
        }
        for (member in decl.GetMemberDeclPtrs()) {
            if (let Some(propDecl) <- (member as PropDecl)) {
                CollectVarDecl(propDecl)
                for (getter in propDecl.getters) {
                    CollectForDecl(getter)
                }
                for (setter in propDecl.setters) {
                    CollectForDecl(setter)
                }
            } else {
                CollectForDecl(member)
            }
        }
    }

    private func CollectGenericUsage(generic: Generic): Unit {
        for (constraint in generic.genericConstraints) {
            for (upperBound in constraint.upperBounds) {
                CollectNode(upperBound)
            }
        }
    }

    private func CollectAnnotationUsage(decl: Decl): Unit {
        if (let Some(arrayLit) <- decl.annotationsArray) {
            CollectBodyUsage(arrayLit)
        }
        for (annotation in decl.annotations) {
            CollectNode(annotation)
        }
    }

    private func CollectBodyUsage(node: Node): Unit {
        ExtendBoxMarker.Mark(typeManager, node)
        for (boxedTy in typeManager.GetAllBoxedTys()) {
            info.usedMangles.add(GetTypeRawMangleName(boxedTy))
        }
        typeManager.ClearRecordUsedExtends()
        CollectNode(node)
    }

    private func CollectNode(node: Node): Unit {
        let walker = Walker(node, visitPre: { current: Node =>
            AddNodeUsage(info, current)
        })
        let _ = walker.Walk()
    }
}

public func GetSemanticUsage(typeManager: TypeManager, pkgs: ArrayList<Package>): SemanticInfo {
    let collector = SemanticUsageCollector(typeManager, pkgs)
    return collector.CollectInfoUsages()
}
