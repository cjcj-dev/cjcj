package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::option.{InteropLanguage, MaybeString}
import cjcj::sema.{MemberMap, TypeManager}
import cjcj::sema.NativeFFI.{GetJavaFQName, IsJArray}

// C++ src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:36-60.
private func IsJavaMirrorSubtype(ty: Ty): Bool {
    if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(superClassTy) <- classTy.GetSuperClassTy()) {
            if (!superClassTy.IsObject()) {
                if (!IsJavaMirrorSubtype(superClassTy) &&
                    !(superClassTy.decl.isSome() && IsMirror(superClassTy.decl.getOrThrow()))) {
                    return false
                }
                return true
            }
        }
    }
    if (let Some(classLikeTy) <- (ty as ClassLikeTy)) {
        let parents = classLikeTy.GetSuperInterfaceTys()
        if (parents.isEmpty()) {
            return false
        }
        for (parent in parents) {
            if (parent.decl.isSome() && IsMirror(parent.decl.getOrThrow())) {
                return true
            }
        }
    }
    return false
}

// C++ src/Sema/NativeFFI/Java/AfterTypeCheck/EscapeChecks.cpp:24-42.
private func CollectJavaTypes(ty: Ty, javaDecls: ArrayList<Decl>): Unit {
    if (ty.IsTuple()) {
        for (typeArg in ty.typeArgs) {
            CollectJavaTypes(typeArg, javaDecls)
        }
    }
    if (ty.IsCoreOptionType()) {
        CollectJavaTypes(ty.typeArgs[0], javaDecls)
    }
    if (let Some(decl) <- Ty.GetDeclOfTy(Some(ty))) {
        if (IsMirror(decl) || IsImpl(decl)) {
            javaDecls.add(decl)
        }
    }
}

// C++ src/Sema/NativeFFI/Java/AfterTypeCheck/DiagsInterop.cpp:136-154.
private func DiagJavaTypesAsGenericParam(diag: DiagnosticEngine, expr: Node,
    javaDecls: ArrayList<Decl>): Unit {
    if (javaDecls.isEmpty()) {
        return
    }
    // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
    // src/Sema/NativeFFI/Java/AfterTypeCheck/DiagsInterop.cpp:142-153.
}

// C++ src/Sema/NativeFFI/Java/AfterTypeCheck/EscapeChecks.cpp:44-60.
private func CollectJavaTypesAndDiag(diag: DiagnosticEngine, expr: NameReferenceExpr): Unit {
    let javaDecls = ArrayList<Decl>()
    for (ty in expr.instTys) {
        CollectJavaTypes(ty, javaDecls)
    }
    DiagJavaTypesAsGenericParam(diag, expr, javaDecls)
}

private func CollectJavaTypesAndDiag(diag: DiagnosticEngine, typeNode: RefType): Unit {
    let javaDecls = ArrayList<Decl>()
    for (typeArg in typeNode.typeArguments) {
        if (let Some(ty) <- typeArg.GetTy()) {
            CollectJavaTypes(ty, javaDecls)
        }
    }
    DiagJavaTypesAsGenericParam(diag, typeNode, javaDecls)
}

// C++ src/Sema/NativeFFI/Java/AfterTypeCheck/EscapeChecks.cpp:62-82.
private func IsInstantiationWithJavaTypeAllowed(ty: Ty): Bool {
    return ty.IsCoreOptionType() || IsJArray(ty)
}

private func IsInstantiationWithJavaTypeAllowed(expr: NameReferenceExpr): Bool {
    let target = expr.GetTarget()
    if (let None <- target) {
        return true
    }
    let targetDecl = target.getOrThrow()
    if (let Some(ty) <- targetDecl.GetTy()) {
        if (IsInstantiationWithJavaTypeAllowed(ty)) {
            return true
        }
    }
    if (let Some(outerDecl) <- targetDecl.outerDecl) {
        if (let Some(ty) <- outerDecl.GetTy()) {
            if (IsInstantiationWithJavaTypeAllowed(ty)) {
                return true
            }
        }
    }
    return false
}

// C++ src/Sema/NativeFFI/Java/AfterTypeCheck/JavaInteropManager.h:23-80.
public class JavaInteropManager {
    private let importManager: SemaImportManager
    private let typeManager: TypeManager
    private let diag: DiagnosticEngine
    private let mangler: BaseMangler
    private let javagenOutputPath: MaybeString
    private let outputPath: String
    private var hasMirrorOrImpl: Bool = false
    private let targetInteropLanguage: InteropLanguage

    public init(importManager: SemaImportManager, typeManager: TypeManager, diag: DiagnosticEngine,
        mangler: BaseMangler, javagenOutputPath: MaybeString, outputPath: String,
        targetInteropLanguage: InteropLanguage) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.diag = diag
        this.mangler = mangler
        this.javagenOutputPath = javagenOutputPath
        this.outputPath = outputPath
        this.targetInteropLanguage = targetInteropLanguage
    }

    // C++ TypeCheckJavaInterop.cpp:351-375.
    public func CheckImplRedefinition(pkg: Package): Unit {
        let javaNameToDecl = HashMap<String, ClassLikeDecl>()
        for (file in pkg.files) {
            for (decl in file.decls) {
                let classLikeDecl = decl as ClassLikeDecl
                if (classLikeDecl.isNone() || decl.TestAttr(Attribute.IS_BROKEN)) {
                    continue
                }
                let value = classLikeDecl.getOrThrow()
                if (!IsImpl(value)) {
                    continue
                }
                let name = GetJavaFQName(value)
                if (javaNameToDecl.contains(name)) {
                    // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
                    // src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:367-370.
                    continue
                }
                javaNameToDecl[name] = value
            }
        }
    }

    // C++ TypeCheckJavaInterop.cpp:280-287.
    public func CheckInheritance(decl: ClassLikeDecl): Unit {
        CheckJavaMirrorSubtypeAttrClassLikeDecl(decl)
        if (IsMirror(decl) || IsImpl(decl)) {
            CheckNonJavaSuperType(decl)
        }
    }

    // C++ TypeCheckJavaInterop.cpp:289-308.
    private func CheckNonJavaSuperType(decl: ClassLikeDecl): Unit {
        // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
        // src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:291-307.
    }

    // C++ TypeCheckJavaInterop.cpp:310-318.
    private func CheckJavaMirrorSubtypeAttrClassLikeDecl(decl: ClassLikeDecl): Unit {
        if (IsJavaMirrorSubtype(decl.GetTy().getOrThrow())) {
            if (!decl.TestAnyAttr(Attribute.JAVA_MIRROR_SUBTYPE, Attribute.JAVA_MIRROR)) {
                // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
                // src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:314-315.
            }
        }
    }

    // C++ TypeCheckJavaInterop.cpp:320-331.
    private func CheckExtendDecl(decl: ExtendDecl): Unit {
        let ty = decl.extendedType.getOrThrow().GetTy().getOrThrow()
        if (!IsMirror(ty) && !IsImpl(ty)) {
            return
        }
        // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
        // src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:327-330.
    }

    // C++ TypeCheckJavaInterop.cpp:377-390.
    public func CheckTypes(file: File): Unit {
        for (decl in file.decls) {
            if (let Some(classLikeDecl) <- (decl as ClassLikeDecl)) {
                CheckInheritance(classLikeDecl)
                CheckTypes(classLikeDecl)
            } else if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                CheckExtendDecl(extendDecl)
            }
            CheckCJMappingType(decl)
            CheckGenericsInstantiation(decl)
        }
    }

    // C++ TypeCheckJavaInterop.cpp:392-418.
    public func CheckTypes(classLikeDecl: ClassLikeDecl): Unit {
        if (!classLikeDecl.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
            return
        }
        hasMirrorOrImpl = true
        // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
        // src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:400-417.
    }

    // C++ TypeCheckJavaInterop.cpp:436-460.
    private func CheckCJMappingType(decl: Decl): Unit {
        if (!IsCJMapping(decl)) {
            return
        }
        // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
        // src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:442-459.
    }

    // C++ EscapeChecks.cpp:86-100.
    private func CheckGenericsInstantiation(decl: Decl): Unit {
        Walker(decl, visitPre: { node: Node =>
            if (let Some(nameRefExpr) <- (node as NameReferenceExpr)) {
                if (!IsInstantiationWithJavaTypeAllowed(nameRefExpr)) {
                    CollectJavaTypesAndDiag(diag, nameRefExpr)
                }
            } else if (let Some(refType) <- (node as RefType)) {
                if (let Some(ty) <- refType.GetTy()) {
                    if (!IsInstantiationWithJavaTypeAllowed(ty)) {
                        CollectJavaTypesAndDiag(diag, refType)
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
    }

    // C++ DesugarPackage.cpp:75-112.
    public func DesugarPackage(pkg: Package, memberMap: HashMap<InheritableDecl, MemberMap>,
        desugarPropRef: (Node) -> Unit): Unit {
        if (!(hasMirrorOrImpl || targetInteropLanguage == InteropLanguage.Java)) {
            return
        }
        // FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY): C++
        // src/Sema/NativeFFI/Java/AfterTypeCheck/DesugarPackage.cpp:83-111.
    }
}
