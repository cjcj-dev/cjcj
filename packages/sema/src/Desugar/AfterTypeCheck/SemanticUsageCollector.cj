package cjcj::sema.Desugar.AfterTypeCheck

import std.collection.*
import cjcj::ast.*
import cjcj::incremental_compilation.{NameUsage, SemanticInfo, SemaRelation, SemaUsage, UseInfo}
import cjcj::mangle.ASTMangler
import cjcj::sema.*
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK}

// C++ src/Sema/Desugar/AfterTypeCheck/SemanticUsageCollector.cpp:25-385.
@When[backend == "cjnative"]
private class SemanticUsageCollector {
    private let tyMgr: TypeManager
    private let pkgs: ArrayList<Package>
    private let info: SemanticInfo = SemanticInfo()
    private var currentTypeDecl: Option<InheritableDecl> = None

    public init(typeManager: TypeManager, pkgs: ArrayList<Package>) {
        tyMgr = typeManager
        this.pkgs = pkgs
        tyMgr.ClearRecordUsedExtends()
    }

    public func CollectInfoUsages(): SemanticInfo {
        for (pkg in pkgs) {
            IterateToplevelDecls(pkg, { decl: Decl => CollectForDecl(decl) })
        }
        return info
    }

    private func CollectForDecl(decl: Decl): Unit {
        if (decl.TestAnyAttr(Attribute.MACRO_INVOKE_FUNC, Attribute.IMPLICIT_ADD, Attribute.ENUM_CONSTRUCTOR)) {
            return
        }
        if (decl.TestAttr(Attribute.INCRE_COMPILE)) {
            if (!info.usages.contains(decl)) {
                info.usages[decl] = SemaUsage()
            }
            return
        }
        if (let Some(varDecl) <- (decl as VarDecl)) {
            CollectAPIUsage(varDecl)
            CollectNameUsage(varDecl)
        } else if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(desugarDecl) <- mainDecl.desugarDecl) {
                CollectForDecl(desugarDecl)
            }
        } else if (let Some(funcDecl) <- (decl as FuncDecl)) {
            CollectAPIUsage(funcDecl)
            CollectNameUsage(funcDecl)
        } else if (let Some(inheritableDecl) <- (decl as InheritableDecl)) {
            currentTypeDecl = Some(inheritableDecl)
            CollectAPIUsage(inheritableDecl)
            if (!info.usages.contains(inheritableDecl)) {
                info.usages[inheritableDecl] = SemaUsage()
            }
            CollectAnnotationUsage(inheritableDecl, info.usages[inheritableDecl])
            CollectRelation(inheritableDecl)
            for (member in inheritableDecl.GetMemberDeclPtrs()) {
                if (let Some(propDecl) <- (member as PropDecl)) {
                    CollectAPIUsage(propDecl)
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
            currentTypeDecl = None
        }
    }

    private static func GetName(node: Node): String {
        if (let Some(refType) <- (node as RefType)) {
            return refType.ref.identifier.Val()
        } else if (let Some(refExpr) <- (node as RefExpr)) {
            return refExpr.ref.identifier.Val()
        } else if (let Some(qualifiedType) <- (node as QualifiedType)) {
            return qualifiedType.field.Val()
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            return memberAccess.field.Val()
        }
        return ""
    }

    private func CollectUseOfParentByTy(ty: Ty, usage: UseInfo, nameUsage: NameUsage): Unit {
        if (let Some(typeDecl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
            nameUsage.parentDecls.add(typeDecl.rawMangleName)
            usage.usedDecls.add(typeDecl.rawMangleName)
        } else if (Ty.IsTyCorrect(ty)) {
            nameUsage.parentDecls.add(ASTMangler.MangleBuiltinType(Ty.KindName(ty.kind)))
        }
    }

    private func CollectUseOfUnqualifedMember(decl: Decl, usage: UseInfo): Unit {
        if (decl.IsTypeDecl() || decl.outerDecl.isNone() || !decl.outerDecl.getOrThrow().IsNominalDecl() ||
            decl.TestAttr(Attribute.CONSTRUCTOR)) {
            return
        }
        let outerDecl = decl.outerDecl.getOrThrow()
        CJC_NULLPTR_CHECK(outerDecl.GetTy())
        let name = decl.identifier.Val()
        if (!usage.usedNames.contains(name)) {
            usage.usedNames[name] = NameUsage()
        }
        let nameUsage = usage.usedNames[name]
        CollectUseOfParentByTy(outerDecl.GetTy().getOrThrow(), usage, nameUsage)
        if (let Some(typeDecl) <- currentTypeDecl) {
            if (Ty.IsTyCorrect(typeDecl.GetTy())) {
                CollectUseOfParentByTy(typeDecl.GetTy().getOrThrow(), usage, nameUsage)
            }
        }
    }

    private func CollectUseOfQualifedMember(memberAccess: MemberAccess, target: Decl, usage: UseInfo,
        nameUsage: NameUsage): Unit {
        CJC_NULLPTR_CHECK(target.outerDecl)
        let accessedTy = if (memberAccess.isExposedAccess) {
            target.outerDecl.getOrThrow().GetTy()
        } else {
            memberAccess.baseExpr.getOrThrow().GetTy()
        }
        if (Ty.IsTyCorrect(accessedTy)) {
            CollectUseOfParentByTy(accessedTy.getOrThrow(), usage, nameUsage)
        }
    }

    private func CollectForEnumAndStructTypeUse(node: Node, usage: UseInfo): Unit {
        if (!Ty.IsTyCorrect(node.GetTy())) {
            return
        }
        let ty = node.GetTy().getOrThrow()
        if (!ty.IsEnum() && !ty.IsStruct()) {
            return
        }
        let enumOrStructDecl = Ty.GetDeclPtrOfTy(Some(ty))
        CJC_NULLPTR_CHECK(enumOrStructDecl)
        usage.usedDecls.add(enumOrStructDecl.getOrThrow().rawMangleName)
    }

    private func CollectUseInfo(node: Node, usage: UseInfo): VisitAction {
        CollectForEnumAndStructTypeUse(node, usage)
        let target = if ((node as Type).isSome()) {
            Ty.GetDeclPtrOfTy(node.GetTy())
        } else {
            node.GetTarget()
        }
        if (target.isNone() || target.getOrThrow().IsBuiltIn() ||
            target.getOrThrow().astKind == ASTKind.PACKAGE_DECL) {
            return VisitAction.WALK_CHILDREN
        }
        let targetDecl = target.getOrThrow()
        if (!targetDecl.rawMangleName.isEmpty()) {
            usage.usedDecls.add(targetDecl.rawMangleName)
        }
        if (IsClassOrEnumConstructor(targetDecl)) {
            let outerDecl = targetDecl.outerDecl.getOrThrow()
            usage.usedDecls.add(outerDecl.rawMangleName)
            usage.usedDecls.add(outerDecl.rawMangleName)
            if (targetDecl.TestAttr(Attribute.IMPLICIT_ADD)) {
                usage.usedDecls.add(outerDecl.rawMangleName + "<init>")
            }
        }
        let name = SemanticUsageCollector.GetName(node)
        if (name.isEmpty()) {
            return VisitAction.WALK_CHILDREN
        }
        if (!usage.usedNames.contains(name)) {
            usage.usedNames[name] = NameUsage()
        }
        let nameUsage = usage.usedNames[name]
        if (node.astKind == ASTKind.REF_TYPE || node.astKind == ASTKind.REF_EXPR) {
            if (targetDecl.TestAttr(Attribute.IMPORTED)) {
                nameUsage.hasUnqualifiedUsageOfImported = true
            } else {
                nameUsage.hasUnqualifiedUsage = true
            }
            CollectUseOfUnqualifedMember(targetDecl, usage)
        } else if (let Some(qualifiedType) <- (node as QualifiedType)) {
            let qualifier = ASTContext.GetPackageName(qualifiedType.baseType.getOrThrow())
            nameUsage.packageQualifiers.add(qualifier)
            return VisitAction.SKIP_CHILDREN
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            CJC_NULLPTR_CHECK(memberAccess.baseExpr)
            if (targetDecl.TestAttr(Attribute.GLOBAL)) {
                let qualifier = ASTContext.GetPackageName(memberAccess.baseExpr.getOrThrow())
                nameUsage.packageQualifiers.add(qualifier)
                return VisitAction.SKIP_CHILDREN
            }
            CollectUseOfQualifedMember(memberAccess, targetDecl, usage, nameUsage)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func CollectAPIUsage(varDecl: VarDecl): Unit {
        if (let Some(typeNode) <- varDecl.typeNode) {
            CJC_ASSERT(!varDecl.rawMangleName.isEmpty())
            if (!info.usages.contains(varDecl)) {
                info.usages[varDecl] = SemaUsage()
            }
            CollectAPIUsage(typeNode, info.usages[varDecl].apiUsages)
        }
    }

    private func CollectAPIUsage(typeNode: Type, usage: UseInfo): Unit {
        let walker = Walker(typeNode, visitPre: { node: Node =>
            if (node.TestAttr(Attribute.IMPLICIT_ADD)) {
                return VisitAction.SKIP_CHILDREN
            }
            return CollectUseInfo(node, usage)
        })
        let _ = walker.Walk()
    }

    private func CollectGenericUsage(generic: Generic, usage: UseInfo): Unit {
        for (constraint in generic.genericConstraints) {
            for (upperBound in constraint.upperBounds) {
                if (let Some(decl) <- Ty.GetDeclPtrOfTy(upperBound.GetTy())) {
                    if (!decl.rawMangleName.isEmpty()) {
                        usage.usedDecls.add(decl.rawMangleName)
                    }
                }
            }
        }
    }

    private func CollectAPIUsage(funcDecl: FuncDecl): Unit {
        CJC_NULLPTR_CHECK(funcDecl.funcBody)
        let funcBody = funcDecl.funcBody.getOrThrow()
        CJC_ASSERT(funcBody.paramLists.size == 1 && !funcDecl.rawMangleName.isEmpty())
        if (!info.usages.contains(funcDecl)) {
            info.usages[funcDecl] = SemaUsage()
        }
        let usage = info.usages[funcDecl].apiUsages
        for (param in funcBody.paramLists[0].params) {
            CJC_NULLPTR_CHECK(param.typeNode)
            CollectAPIUsage(param.typeNode.getOrThrow(), usage)
        }
        if (let Some(retType) <- funcBody.retType) {
            if (!retType.TestAttr(Attribute.COMPILER_ADD)) {
                CollectAPIUsage(retType, usage)
            }
        }
        if (let Some(generic) <- funcBody.generic) {
            CollectGenericUsage(generic, usage)
        }
    }

    private func CollectAPIUsage(inheritableDecl: InheritableDecl): Unit {
        CJC_ASSERT(!inheritableDecl.rawMangleName.isEmpty())
        if (!info.usages.contains(inheritableDecl)) {
            info.usages[inheritableDecl] = SemaUsage()
        }
        let usage = info.usages[inheritableDecl].apiUsages
        for (typeNode in inheritableDecl.inheritedTypes) {
            CollectAPIUsage(typeNode, usage)
        }
        if (let Some(generic) <- inheritableDecl.generic) {
            CollectGenericUsage(generic, usage)
        }
        if (let Some(enumDecl) <- (inheritableDecl as EnumDecl)) {
            for (ctor in enumDecl.constructors) {
                if (let Some(funcDecl) <- (ctor as FuncDecl)) {
                    let funcBody = funcDecl.funcBody.getOrThrow()
                    CJC_ASSERT(funcBody.paramLists.size == 1)
                    for (param in funcBody.paramLists[0].params) {
                        CJC_NULLPTR_CHECK(param.typeNode)
                        CollectAPIUsage(param.typeNode.getOrThrow(), usage)
                    }
                }
            }
        }
    }

    private func CollectRelation(inheritableDecl: InheritableDecl): Unit {
        if (inheritableDecl.inheritedTypes.isEmpty() && inheritableDecl.astKind != ASTKind.EXTEND_DECL) {
            return
        }
        CJC_ASSERT(!inheritableDecl.rawMangleName.isEmpty())
        CJC_NULLPTR_CHECK(inheritableDecl.GetTy())
        let decl = Ty.GetDeclPtrOfTy(inheritableDecl.GetTy())
        CJC_ASSERT(decl.isNone() || !decl.getOrThrow().rawMangleName.isEmpty())
        let relation = if (let Some(typeDecl) <- decl) {
            if (!info.relations.contains(typeDecl.rawMangleName)) {
                info.relations[typeDecl.rawMangleName] = SemaRelation()
            }
            info.relations[typeDecl.rawMangleName]
        } else {
            let builtInName = ASTMangler.MangleBuiltinType(Ty.KindName(inheritableDecl.TyKind()))
            if (!info.builtInTypeRelations.contains(builtInName)) {
                info.builtInTypeRelations[builtInName] = SemaRelation()
            }
            info.builtInTypeRelations[builtInName]
        }
        var isExtend = false
        if ((inheritableDecl as ExtendDecl).isSome()) {
            relation.extends.add(inheritableDecl.rawMangleName)
            isExtend = true
        }
        let inherited = if (isExtend) { relation.extendedInterfaces } else { relation.inherits }
        for (typeNode in inheritableDecl.inheritedTypes) {
            let target = Ty.GetDeclPtrOfTy(typeNode.GetTy())
            CJC_ASSERT(target.isSome() && !target.getOrThrow().rawMangleName.isEmpty())
            inherited.add(target.getOrThrow().rawMangleName)
        }
    }

    private func CollectAnnotationUsage(decl: Decl, usage: SemaUsage): Unit {
        if (let Some(annotationsArray) <- decl.annotationsArray) {
            for (child in annotationsArray.children) {
                CollectNameUsage(child, usage)
            }
        }
    }

    private func CollectNameUsage(varDecl: VarDecl): Unit {
        if (!info.usages.contains(varDecl)) {
            info.usages[varDecl] = SemaUsage()
        }
        let usage = info.usages[varDecl]
        if (varDecl.initializer.isSome()) {
            CollectNameUsage(varDecl, usage)
        }
        CollectAnnotationUsage(varDecl, usage)
    }

    private func CollectNameUsage(funcDecl: FuncDecl): Unit {
        CJC_NULLPTR_CHECK(funcDecl.funcBody)
        let funcBody = funcDecl.funcBody.getOrThrow()
        CJC_ASSERT(funcBody.paramLists.size == 1 && !funcDecl.rawMangleName.isEmpty())
        if (!info.usages.contains(funcDecl)) {
            info.usages[funcDecl] = SemaUsage()
        }
        let usage = info.usages[funcDecl]
        for (param in funcBody.paramLists[0].params) {
            if (let Some(assignment) <- param.assignment) {
                CollectNameUsage(assignment, usage)
            }
            CollectAnnotationUsage(param, usage)
        }
        if (let Some(body) <- funcBody.body) {
            CollectNameUsage(body, usage)
        }
        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            AddUsedBySpecificMemberVars(funcDecl, funcDecl.TestAttr(Attribute.STATIC))
        }
        if (let Some(propDecl) <- funcDecl.propDecl) {
            CollectAnnotationUsage(propDecl, usage)
        } else {
            CollectAnnotationUsage(funcDecl, usage)
        }
    }

    private func CollectNameUsage(node: Node, usage: SemaUsage): Unit {
        synchronized(ExtendBoxMarker.mtx) {
            let _ = Walker(node, visitPre: ExtendBoxMarker.GetMarkExtendBoxFunc(tyMgr)).Walk()
        }
        let boxedTys = tyMgr.GetAllBoxedTys()
        tyMgr.ClearRecordUsedExtends()
        for (ty in boxedTys) {
            usage.boxedTypes.add(GetTypeRawMangleName(ty))
        }
        var nodePtr: Node = node
        if (node.astKind == ASTKind.VAR_DECL) {
            nodePtr = (node as VarDecl).getOrThrow().initializer.getOrThrow()
        }
        let walker = Walker(nodePtr, visitPre: { current: Node =>
            if (current.TestAttr(Attribute.HAS_INITIAL) && current.astKind == ASTKind.FUNC_ARG) {
                return VisitAction.SKIP_CHILDREN
            }
            return CollectUseInfo(current, usage.bodyUsages)
        })
        let _ = walker.Walk()
    }

    private func AddUsedBySpecificMemberVars(ctor: FuncDecl, isStatic: Bool): Unit {
        CJC_NULLPTR_CHECK(ctor.outerDecl)
        for (member in ctor.outerDecl.getOrThrow().GetMemberDecls()) {
            if (member.astKind != ASTKind.VAR_DECL || member.TestAttr(Attribute.STATIC) != isStatic) {
                continue
            }
            let varDecl = (member as VarDecl).getOrThrow()
            if (!varDecl.isMemberParam && varDecl.initializer.isNone()) {
                if (!info.usages.contains(varDecl)) {
                    info.usages[varDecl] = SemaUsage()
                }
                info.usages[varDecl].bodyUsages.usedDecls.add(ctor.rawMangleName)
            }
        }
    }
}

// C++ src/Sema/Desugar/AfterTypeCheck/SemanticUsageCollector.cpp:389-396.
@When[backend == "cjnative"]
public func GetSemanticUsage(typeManager: TypeManager, pkgs: ArrayList<Package>): SemanticInfo {
    let collector = SemanticUsageCollector(typeManager, pkgs)
    return collector.CollectInfoUsages()
}

@When[backend != "cjnative"]
public func GetSemanticUsage(typeManager: TypeManager, pkgs: ArrayList<Package>): SemanticInfo {
    let _ = typeManager
    let _ = pkgs
    return SemanticInfo()
}
