package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.Range as BasicRange
import cjcj::modules.ImportManager
import cjcj::utils.{CJC_ASSERT, INTEROP_JAVA_LANG_PACKAGE, INTEROP_JOBJECT_NAME, OBJ_C_ID_IDENT,
    OBJ_C_LANG_PACKAGE_IDENT}

private func TypeCheckClassLikeRange(node: Node): BasicRange {
    var rangeEnd = node.end
    if (node.begin.fileID != node.end.fileID) {
        rangeEnd = node.begin + 1
    }
    return MakeRange(node.begin, rangeEnd)
}

private func TypeCheckClassLikeIdentifierRange(decl: Decl): BasicRange {
    let beginPos = decl.identifier.Begin()
    if (!beginPos.IsZero()) {
        let endPos = decl.identifier.End()
        if (!endPos.IsZero()) {
            return MakeRange(beginPos, endPos)
        }
    }
    return TypeCheckClassLikeRange(decl)
}

private func TypeCheckClassLikeEmitOld(
    diag: BasicDiagnosticEngine,
    node: Node,
    kind: BasicDiagKind,
    args!: Array<BasicDiagArgument> = Array<BasicDiagArgument>()
): Unit {
    let builder = Diagnose(diag, node, kind, args: args)
    builder.Emit()
}

private func TypeCheckClassLikeAddUniqueSubDecl(owner: ClassLikeDecl, child: Decl): Unit {
    for (value in owner.subDecls) {
        if (SameDecl(value, child)) {
            return
        }
    }
    owner.subDecls.add(child)
}

private func TypeCheckClassLikeFindCorrespondingCommonDecl(specificDecl: Decl): Option<Decl> {
    if (let Some(file) <- specificDecl.curFile) {
        if (let Some(pkg) <- file.curPackage) {
            for (pkgFile in pkg.files) {
                for (decl in pkgFile.decls) {
                    if (let Some(specificImpl) <- decl.specificImplementation) {
                        if (SameDecl(specificImpl, specificDecl)) {
                            return Some(decl)
                        }
                    }
                }
            }
        }
    }
    return None
}

private func TypeCheckClassLikeIsDeclOpenToMock(decl: Decl): Bool {
    return decl.TestAttr(Attribute.OPEN) && decl.TestAttr(Attribute.OPEN_TO_MOCK)
}

private func TypeCheckClassLikeDeclPackageName(decl: Decl): String {
    if (let Some(file) <- decl.curFile) {
        if (let Some(pkg) <- file.curPackage) {
            return pkg.fullPackageName
        }
    }
    return decl.fullPackageName
}

public func TypeCheckClassLikeCheckAnnotationHasConstInit(
    diag: BasicDiagnosticEngine,
    classDecl: ClassDecl
): Bool {
    if (let Some(body) <- classDecl.body) {
        for (decl in body.decls) {
            if (IsInstanceConstructor(decl) && decl.IsConst()) {
                return true
            }
        }
    }
    let builder = diag.DiagnoseRefactor(
        BasicDiagKindRefactor.sema_annotation_no_const_init,
        TypeCheckClassLikeIdentifierRange(classDecl))
    builder.Emit()
    return false
}

public func TypeCheckClassLikeCheckAnnotationVisibility(
    diag: BasicDiagnosticEngine,
    classDecl: ClassDecl
): Bool {
    if (classDecl.TestAttr(Attribute.PUBLIC)) {
        return true
    }
    for (annotation in classDecl.annotations) {
        if (annotation.kind == AstAnnotationKind.ANNOTATION) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_annotation_non_public,
                TypeCheckClassLikeIdentifierRange(classDecl))
            builder.Emit()
            return false
        }
    }
    return true
}

public func TypeCheckClassLikeCheckSealedInheritance(
    diag: BasicDiagnosticEngine,
    child: Decl,
    parent: Type
): Bool {
    if (let None <- parent.GetTarget()) {
        return true
    }
    let target = parent.GetTarget().getOrThrow()
    if (!target.TestAttr(Attribute.SEALED)) {
        return true
    }
    var valid = true
    if (target.TestAttr(Attribute.IMPORTED) && !child.TestAttr(Attribute.IMPORTED)) {
        TypeCheckClassLikeDiagCannotInheritSealed(diag, child, parent, false)
        valid = false
    }
    if (target.TestAttr(Attribute.SPECIFIC)) {
        if (let Some(commonDecl) <- TypeCheckClassLikeFindCorrespondingCommonDecl(target)) {
            if (commonDecl.TestAttr(Attribute.SEALED)) {
                if (!child.TestAttr(Attribute.FROM_COMMON_PART) && !child.TestAttr(Attribute.SPECIFIC)) {
                    TypeCheckClassLikeDiagCannotInheritSealed(diag, child, parent, true)
                    valid = false
                }
            }
        }
    }
    return valid
}

private func TypeCheckClassLikeDiagCannotInheritSealed(diag: BasicDiagnosticEngine, child: Decl,
    parent: Type, isCommon: Bool): Unit {
    let target = parent.GetTarget().getOrThrow()
    var isImplement = child.astKind == ASTKind.CLASS_DECL && target.astKind == ASTKind.INTERFACE_DECL
    var range = TypeCheckClassLikeIdentifierRange(child)
    if (let Some(extendDecl) <- (child as ExtendDecl)) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (let Some(extendedDecl) <- extendedType.GetTarget()) {
                if (extendedDecl.astKind != ASTKind.INTERFACE_DECL) {
                    isImplement = true
                }
            }
            range = TypeCheckClassLikeRange(extendedType)
        }
    }
    let inheritOrImplement = if (isImplement) { "implement" } else { "inherit" }
    let importedOrCommon = if (isCommon) { "common-defined" } else { "imported" }
    let classOrInterface = if (target.astKind == ASTKind.CLASS_DECL) { "class" } else { "interface" }
    let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_cannot_inherit_sealed, child, range,
        arguments: [inheritOrImplement, importedOrCommon, classOrInterface, target.identifier.Val()])
    let declaredPos = if (isCommon) {
        "common package part"
    } else {
        "package '" + target.fullPackageName + "'"
    }
    AddHint(builder, parent, arguments: ["sealed " + classOrInterface + " declared in " + declaredPos])
    builder.Emit()
}

public func TypeCheckClassLikeCheckThreadContextInheritance(
    diag: BasicDiagnosticEngine,
    decl: Decl,
    parent: Type
): Bool {
    if (let None <- parent.GetTarget()) {
        return true
    }
    let target = parent.GetTarget().getOrThrow()
    if (target.fullPackageName != "std.core" || target.identifier.Val() != "ThreadContext") {
        return true
    }
    if (decl.TestAttr(Attribute.OPEN)) {
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_inherit_thread_context_not_open,
            TypeCheckClassLikeRange(decl),
            arguments: [decl.identifier.Val()])
        builder.Emit()
        return false
    }
    var whitelisted = false
    let packageName = TypeCheckClassLikeDeclPackageName(decl)
    if (decl.identifier.Val() == "ThreadContext" && packageName == "std.core") {
        whitelisted = true
    } else if (decl.identifier.Val() == "MainThreadContext" && packageName == "ohos.base") {
        whitelisted = true
    }
    if (!whitelisted) {
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_inherit_thread_context_invalid,
            TypeCheckClassLikeRange(decl),
            arguments: [decl.identifier.Val()])
        builder.Emit()
        return false
    }
    return true
}

public class TypeCheckClassLikeSuperResult {
    public var hasSuperClass: Bool = false
    public var classLikeCount: Int64 = 0
    public var valid: Bool = true

    public init() {}
}

public func TypeCheckClassLikeCheckAndAddSubDecls(
    diag: BasicDiagnosticEngine,
    typeNode: Type,
    classDecl: ClassDecl,
    result: TypeCheckClassLikeSuperResult
): Unit {
    let targetOpt = if (Ty.IsTyCorrect(typeNode.GetTy())) {
        Ty.GetDeclPtrOfTy(typeNode.GetTy())
    } else {
        typeNode.GetTarget()
    }
    if (let Some(targetDecl) <- targetOpt) {
        if (let Some(interfaceDecl) <- (targetDecl as InterfaceDecl)) {
            TypeCheckClassLikeAddUniqueSubDecl(interfaceDecl, classDecl)
            result.classLikeCount++
            return
        }
        if (let Some(superClass) <- (targetDecl as ClassDecl)) {
            if (result.hasSuperClass) {
                TypeCheckClassLikeEmitOld(diag, typeNode, BasicDiagKind.sema_illegal_multi_inheritance,
                    args: [BasicDiagArgument(classDecl.identifier.Val())])
                result.valid = false
            } else if (result.classLikeCount != 0) {
                TypeCheckClassLikeEmitOld(diag, typeNode, BasicDiagKind.sema_superclass_must_be_placed_at_first,
                    args: [BasicDiagArgument(superClass.identifier.Val())])
                result.valid = false
            }
            TypeCheckClassLikeAddUniqueSubDecl(superClass, classDecl)
            if ((!superClass.TestAttr(Attribute.ABSTRACT) && !superClass.TestAttr(Attribute.OPEN)) ||
                TypeCheckClassLikeIsDeclOpenToMock(superClass)) {
                TypeCheckClassLikeEmitOld(diag, typeNode, BasicDiagKind.sema_non_inheritable_super_class,
                    args: [BasicDiagArgument(superClass.identifier.Val())])
                result.valid = false
            }
            result.hasSuperClass = true
            result.classLikeCount++
            return
        }
        if (let Some(aliasDecl) <- (targetDecl as TypeAliasDecl)) {
            if (let Some(aliasType) <- aliasDecl.typeNode) {
                TypeCheckClassLikeCheckAndAddSubDecls(diag, aliasType, classDecl, result)
                return
            }
        }
    }
    TypeCheckClassLikeEmitOld(diag, typeNode, BasicDiagKind.sema_class_inherit_non_class_nor_interface,
        args: [BasicDiagArgument(classDecl.identifier.Val())])
    result.valid = false
}

public func TypeCheckClassLikeHasSuperClass(diag: BasicDiagnosticEngine, classDecl: ClassDecl): Bool {
    let result = TypeCheckClassLikeSuperResult()
    for (typeNode in classDecl.inheritedTypes) {
        TypeCheckClassLikeCheckAndAddSubDecls(diag, typeNode, classDecl, result)
    }
    return result.hasSuperClass
}

public func AddJObjectSuperClassJavaInterop(
    importManager: ImportManager,
    diag: BasicDiagnosticEngine,
    ctx: ASTContext,
    classDecl: ClassDecl
): Bool {
    if (ctx.fullPackageName == INTEROP_JAVA_LANG_PACKAGE && classDecl.identifier.Val() == INTEROP_JOBJECT_NAME) {
        return false
    }
    if (let Some(objectDecl) <- importManager.GetImportedDecl(INTEROP_JAVA_LANG_PACKAGE, INTEROP_JOBJECT_NAME)) {
        CJC_ASSERT(objectDecl.astKind == ASTKind.CLASS_DECL)
        let classObject = (objectDecl as ClassDecl).getOrThrow()
        let typeNode = CreateRefType(classObject)
        typeNode.curFile = classDecl.curFile
        classDecl.inheritedTypes.add(typeNode, at: 0)
        classDecl.EnableAttr(Attribute.JAVA_MIRROR_SUBTYPE)
    } else {
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_member_not_imported,
            classDecl.identifier.Begin(), arguments: [INTEROP_JAVA_LANG_PACKAGE + "." + INTEROP_JOBJECT_NAME])
        builder.Emit()
    }
    return true
}

public func AddObjCIdSuperInterfaceObjCInterop(
    importManager: ImportManager,
    diag: BasicDiagnosticEngine,
    ctx: ASTContext,
    classLikeDecl: ClassLikeDecl
): Unit {
    if (ctx.fullPackageName == OBJ_C_LANG_PACKAGE_IDENT && classLikeDecl.identifier.Val() == OBJ_C_ID_IDENT) {
        return
    }
    if (let Some(idDecl) <- importManager.GetImportedDecl(OBJ_C_LANG_PACKAGE_IDENT, OBJ_C_ID_IDENT)) {
        CJC_ASSERT(idDecl.astKind == ASTKind.INTERFACE_DECL)
        let idInterface = (idDecl as InterfaceDecl).getOrThrow()
        let typeNode = CreateRefType(idInterface)
        typeNode.curFile = classLikeDecl.curFile
        classLikeDecl.inheritedTypes.add(typeNode)
    } else {
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_member_not_imported,
            classLikeDecl.identifier.Begin(), arguments: [OBJ_C_LANG_PACKAGE_IDENT + "." + OBJ_C_ID_IDENT])
        builder.Emit()
    }
}

public func TypeCheckClassLikeCheckClassInheritedTypes(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    classDecl: ClassDecl
): Bool {
    var valid = true
    for (inheritedType in classDecl.inheritedTypes) {
        if (!TypeCheckTypeCheckReferenceTypeLegality(diag, tm, inheritedType)) {
            valid = false
        }
        if (!TypeCheckClassLikeCheckSealedInheritance(diag, classDecl, inheritedType)) {
            valid = false
        }
        if (!TypeCheckClassLikeCheckThreadContextInheritance(diag, classDecl, inheritedType)) {
            valid = false
        }
    }
    return valid
}

public func TypeCheckClassLikeCheckInterfaceInheritedTypes(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    interfaceDecl: InterfaceDecl
): Bool {
    var valid = true
    for (interfaceType in interfaceDecl.inheritedTypes) {
        if (!TypeCheckTypeCheckReferenceTypeLegality(diag, tm, interfaceType)) {
            valid = false
        }
        var hasInterfaceTy = false
        if (let Some(rawTy) <- interfaceType.GetTy()) {
            if (let Some(interfaceTy) <- (rawTy as InterfaceTy)) {
                hasInterfaceTy = true
                if (let Some(parentDecl) <- interfaceTy.declPtr) {
                    TypeCheckClassLikeAddUniqueSubDecl(parentDecl, interfaceDecl)
                }
                if (!TypeCheckClassLikeCheckSealedInheritance(diag, interfaceDecl, interfaceType)) {
                    valid = false
                }
                if (!TypeCheckClassLikeCheckThreadContextInheritance(diag, interfaceDecl, interfaceType)) {
                    valid = false
                }
            }
        }
        if (!hasInterfaceTy) {
            TypeCheckClassLikeEmitOld(diag, interfaceDecl, BasicDiagKind.sema_interface_inherit_non_interface,
                args: [BasicDiagArgument(interfaceDecl.identifier.Val())])
            valid = false
        }
    }
    return valid
}

public func TypeCheckClassLikeCheckNominalAnnotationRules(
    diag: BasicDiagnosticEngine,
    classDecl: ClassDecl
): Bool {
    var valid = TypeCheckClassLikeCheckAnnotationVisibility(diag, classDecl)
    if (classDecl.TestAttr(Attribute.IS_ANNOTATION)) {
        if (!TypeCheckClassLikeCheckAnnotationHasConstInit(diag, classDecl)) {
            valid = false
        }
    }
    return valid
}
