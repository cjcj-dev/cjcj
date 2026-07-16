package cjcj::sema.NativeFFI

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::mangle.BaseMangler
import cjcj::modules.ImportManager
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
import cjcj::sema.TypeManager
import cjcj::utils.*

private let NATIVE_CONSTRUCTOR_MARKER_CLASS_NAME: String = "$$NativeConstructorMarker"
private let NATIVE_CONSTRUCTOR_MARKER_PACKAGE_NAME: String = "cangjie.lang.internal"
public let JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR: String = "$obj"

public class Utils {
    private let importManager: ImportManager
    private let typeManager: TypeManager
    private let pkg: Package

    public init(importManager: ImportManager, typeManager: TypeManager, pkg: Package) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.pkg = pkg
    }

    public func GetOptionTy(ty: Ty): Ty {
        return typeManager.GetEnumTy(GetOptionDecl(), typeArgs: [ty])
    }

    public func GetOptionDecl(): EnumDecl {
        return (importManager.GetCoreDecl(STD_LIB_OPTION).getOrThrow() as EnumDecl).getOrThrow()
    }

    private func GetOptionSomeDecl(): Decl {
        return LookupEnumMember(GetOptionDecl(), OPTION_VALUE_CTOR).getOrThrow()
    }

    private func GetOptionNoneDecl(): Decl {
        return LookupEnumMember(GetOptionDecl(), OPTION_NONE_CTOR).getOrThrow()
    }

    public func CreateOptionSomeRef(ty: Ty): Expr {
        let someDeclRef = CreateRefExpr(GetOptionSomeDecl())
        let optionActualTy = GetOptionTy(ty)
        someDeclRef.SetTy(typeManager.GetFunctionTy([ty], optionActualTy))
        return someDeclRef
    }

    public func CreateOptionNoneRef(ty: Ty): Expr {
        let noneDeclRef = CreateRefExpr(GetOptionNoneDecl())
        noneDeclRef.SetTy(GetOptionTy(ty))
        return noneDeclRef
    }

    public func CreateOptionSomeCall(expr: Expr, ty: Ty): Expr {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(expr))
        let call = CreateCallExpr(CreateOptionSomeRef(ty), args)
        call.SetTy(GetOptionTy(ty))
        call.resolvedFunction = (GetOptionSomeDecl() as FuncDecl)
        call.callKind = CallKind.CALL_DECLARED_FUNCTION
        return call
    }

    public func GetJObjectDecl(): Option<ClassLikeDecl> {
        return GetJavaLangDecl(INTEROP_JOBJECT_NAME)
    }

    public func GetJStringDecl(): Option<ClassLikeDecl> {
        return GetJavaLangDecl(INTEROP_JSTRING_NAME)
    }

    public func GetJavaLangDecl(identifier: String): Option<ClassLikeDecl> {
        if (let Some(decl) <- importManager.GetImportedDecl(INTEROP_JAVA_LANG_PACKAGE, identifier)) {
            if (let Some(classLikeDecl) <- (decl as ClassLikeDecl)) {
                return Some(classLikeDecl)
            }
        }
        importManager.GetDiagnosticEngine().DiagnoseRefactor(BasicDiagKindRefactor.sema_member_not_imported,
            DEFAULT_POSITION, INTEROP_JAVA_LANG_PACKAGE + "." + identifier)
        return None
    }

    public func GetStringDecl(): StructDecl {
        return GetStringDecl(importManager)
    }

    public func GetJavaObjectTypeName(ty: Ty): String {
        if (ty.IsCoreOptionType()) {
            return GetJavaObjectTypeName(ty.typeArgs[0])
        }
        return match (ty.kind) {
            case TypeKind.TYPE_BOOLEAN => "java.lang.Boolean"
            case TypeKind.TYPE_INT8 => "java.lang.Byte"
            case TypeKind.TYPE_UINT16 => "java.lang.Character"
            case TypeKind.TYPE_INT16 => "java.lang.Short"
            case TypeKind.TYPE_INT32 => "java.lang.Integer"
            case TypeKind.TYPE_INT64 => "java.lang.Long"
            case TypeKind.TYPE_FLOAT32 => "java.lang.Float"
            case TypeKind.TYPE_FLOAT64 => "java.lang.Double"
            case TypeKind.TYPE_CLASS | TypeKind.TYPE_INTERFACE =>
                let classDecl = (ty as ClassLikeTy).getOrThrow().commonDecl.getOrThrow()
                if (IsJArray(classDecl)) {
                    CJC_ASSERT_WITH_MSG(!ty.typeArgs.isEmpty(), "JArray type must be generic")
                    GetJavaObjectTypeName(ty.typeArgs[0]) + "[]"
                } else {
                    GetJavaFQName(classDecl)
                }
            case _ =>
                if (ty.IsString()) {
                    GetJavaFQName(GetJStringDecl().getOrThrow())
                } else {
                    "unknown type"
                }
        }
    }

    public func GetJavaClassNormalizeSignature(cjtype: Ty): String {
        CJC_ASSERT(!IsJArray(cjtype))
        let decl = (cjtype as ClassLikeTy).getOrThrow().commonDecl.getOrThrow()
        return NormalizeJavaSignature(GetJavaFQName(decl))
    }

    public func GetJavaTypeSignature(cjtype: Ty, fullPackageName!: String = ""): String {
        var jsig = ""
        match (cjtype.kind) {
            case TypeKind.TYPE_UNIT => jsig = "V"
            case TypeKind.TYPE_BOOLEAN => jsig = "Z"
            case TypeKind.TYPE_INT8 => jsig = "B"
            case TypeKind.TYPE_UINT16 => jsig = "C"
            case TypeKind.TYPE_INT16 => jsig = "S"
            case TypeKind.TYPE_INT32 => jsig = "I"
            case TypeKind.TYPE_INT64 => jsig = "J"
            case TypeKind.TYPE_FLOAT32 => jsig = "F"
            case TypeKind.TYPE_FLOAT64 => jsig = "D"
            case TypeKind.TYPE_STRUCT =>
                if (cjtype.IsString()) {
                    jsig = "L" + NormalizeJavaSignature(GetJavaFQName(GetJStringDecl().getOrThrow())) + ";"
                } else if (cjtype.IsStructArray()) {
                    jsig = "[" + GetJavaTypeSignature(cjtype.typeArgs[0])
                }
            case TypeKind.TYPE_ARRAY => jsig = "[" + GetJavaTypeSignature(cjtype.typeArgs[0])
            case TypeKind.TYPE_ENUM =>
                if (cjtype.IsCoreOptionType()) {
                    CJC_ASSERT_WITH_MSG(!cjtype.typeArgs.isEmpty(), "Option type must be generic")
                    let argTy = cjtype.typeArgs[0]
                    if (IsJArray(argTy)) {
                        jsig = GetJavaTypeSignature(argTy)
                    } else {
                        jsig = "L" + NormalizeJavaSignature(GetJavaObjectTypeName(argTy)) + ";"
                    }
                }
            case TypeKind.TYPE_CLASS | TypeKind.TYPE_INTERFACE =>
                let decl = (cjtype as ClassLikeTy).getOrThrow().commonDecl.getOrThrow()
                if (IsJArray(decl)) {
                    jsig = "[" + GetJavaTypeSignature(cjtype.typeArgs[0])
                } else {
                    jsig = "L" + NormalizeJavaSignature(GetJavaFQName(decl)) + ";"
                }
            case TypeKind.TYPE_FUNC =>
                let funcTy = (cjtype as FuncTy).getOrThrow()
                jsig = "("
                for (paramTy in funcTy.paramTys) {
                    jsig += GetParamJavaSignature(paramTy, fullPackageName)
                }
                jsig += ")" + GetParamJavaSignature(funcTy.retTy, fullPackageName)
            case TypeKind.TYPE_TUPLE =>
                jsig = "L" + NormalizeJavaSignature(pkg.fullPackageName + "." + GetCjMappingTupleName(cjtype)) + ";"
            case _ => CJC_ABORT()
        }
        return jsig
    }

    public func GetParamJavaSignature(ty: Ty, fullPackageName: String): String {
        if (ty.kind == TypeKind.TYPE_FUNC) {
            CJC_ASSERT(!fullPackageName.isEmpty())
            return "L" + NormalizeJavaSignature(fullPackageName + "." + GetLambdaJavaClassName(ty)) + ";"
        }
        return GetJavaTypeSignature(ty, fullPackageName: fullPackageName)
    }

    public func GetJavaTypeSignature(retTy: Ty, params: ArrayList<Ty>, fullPackageName!: String = ""): String {
        return GetJavaTypeSignature(typeManager.GetFunctionTy(params.toArray(), retTy),
            fullPackageName: fullPackageName)
    }

    public func CreateOptionMatch(selector: Expr, someBranch: (VarDecl) -> Expr,
        noneBranch: () -> Expr, ty: Ty): Expr {
        let curFile = selector.curFile.getOrThrow()
        let optTy = selector.GetTy().getOrThrow()
        CJC_ASSERT(optTy.IsCoreOptionType())
        CJC_ASSERT_WITH_MSG(!optTy.typeArgs.isEmpty(), "Option type must be generic")
        let optArgTy = optTy.typeArgs[0]

        let vp = CreateVarPattern(V_COMPILER, Some(optArgTy))
        vp.curFile = Some(curFile)
        let someArgVar = vp.varDecl.getOrThrow()
        someArgVar.curFile = Some(curFile)
        let somePattern = EnumPattern()
        somePattern.SetTy(optTy)
        somePattern.constructor = Some(CreateOptionSomeRef(optArgTy))
        somePattern.patterns.add(vp)
        somePattern.curFile = Some(curFile)
        let caseSome = CreateMatchCase(somePattern, someBranch(someArgVar))

        let nonePattern = EnumPattern()
        nonePattern.constructor = Some(CreateOptionNoneRef(optArgTy))
        nonePattern.SetTy(nonePattern.constructor.getOrThrow().GetTy().getOrThrow())
        nonePattern.curFile = Some(curFile)
        let caseNone = CreateMatchCase(nonePattern, noneBranch())
        let cases = ArrayList<MatchCase>()
        cases.add(caseSome)
        cases.add(caseNone)
        return WithinFile<MatchExpr>(CreateMatchExpr(selector, cases, ty), curFile)
    }
}

public func GetJavaRefField(mirrorLike: ClassDecl): VarDecl {
    if (mirrorLike.TestAttr(Attribute.JAVA_MIRROR_SUBTYPE)) {
        if (let Some(superClass) <- mirrorLike.GetSuperClassDecl()) {
            if (!superClass.GetTy().getOrThrow().IsObject() &&
                superClass.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
                return GetJavaRefField(superClass)
            }
        }
        let superClass = mirrorLike.GetSuperClassDecl().getOrThrow()
        if (!superClass.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
            CJC_ABORT()
        }
        return GetJavaRefField(superClass)
    }
    CJC_ASSERT(mirrorLike.TestAttr(Attribute.JAVA_MIRROR) ||
        mirrorLike.TestAttr(Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD))
    CJC_ASSERT(IsJObject(mirrorLike) || IsFwdClass(mirrorLike))
    let body = mirrorLike.body.getOrThrow()
    for (member in body.decls) {
        if (let Some(varDecl) <- (member as VarDecl)) {
            if (varDecl.identifier.Val() == JAVA_REF_FIELD_NAME) {
                return varDecl
            }
        }
    }
    CJC_ABORT()
    return VarDecl()
}

public func GetJavaRefField(mirror: ClassLikeDecl): VarDecl {
    if (let Some(mirrorClass) <- (mirror as ClassDecl)) {
        return GetJavaRefField(mirrorClass)
    }
    CJC_ABORT()
    return VarDecl()
}

public func IsJavaRefGetter(fd: Decl): Bool {
    return (fd as FuncDecl).isSome() && fd.TestAttr(Attribute.COMPILER_ADD) &&
        fd.identifier.Val() == JAVA_REF_GETTER_FUNC_NAME
}

public func GetJavaRefGetter(mirror: ClassLikeDecl): FuncDecl {
    CJC_ASSERT(mirror.TestAnyAttr(Attribute.JAVA_MIRROR_SUBTYPE, Attribute.JAVA_MIRROR))
    if (let Some(classDecl) <- (mirror as ClassDecl)) {
        if (!IsJObject(mirror)) {
            return GetJavaRefGetter(classDecl.GetSuperClassDecl().getOrThrow())
        }
    }
    for (member in mirror.GetMemberDecls()) {
        if (IsJavaRefGetter(member)) {
            return (member as FuncDecl).getOrThrow()
        }
    }
    CJC_ABORT()
    return FuncDecl()
}

public func CreateJavaRefCall(mirrorLike: ClassLikeDecl, javaRefGetter: FuncDecl,
    curFile: Option<File>): Expr {
    CJC_ASSERT(mirrorLike.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE,
        Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD))
    return CreateJavaRefCall(CreateThisRef(Some(mirrorLike), mirrorLike.GetTy(), curFile), javaRefGetter)
}

public func CreateJavaRefCall(mirrorLike: ClassLikeDecl, javaref: VarDecl,
    curFile: Option<File>): Expr {
    CJC_ASSERT((mirrorLike as ClassDecl).isSome())
    CJC_ASSERT(mirrorLike.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE,
        Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD))
    return CreateJavaRefCall(CreateThisRef(Some(mirrorLike), mirrorLike.GetTy(), curFile), javaref)
}

public func CreateJavaRefCall(expr: Expr, javaRefGetter: FuncDecl): Expr {
    let exprTy = expr.GetTy().getOrThrow()
    CJC_ASSERT(exprTy.IsClassLike())
    let commonDecl = (exprTy as ClassLikeTy).getOrThrow().commonDecl.getOrThrow()
    CJC_ASSERT(commonDecl.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE))
    let curFile = expr.curFile.getOrThrow()
    let args = ArrayList<FuncArg>()
    let retTy = (javaRefGetter.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
    return CreateCallExpr(WithinFile<MemberAccess>(CreateMemberAccess(expr, javaRefGetter), curFile), args,
        Some(javaRefGetter), retTy, CallKind.CALL_DECLARED_FUNCTION)
}

public func CreateJavaRefCall(expr: Expr, javaref: VarDecl): Expr {
    let exprTy = expr.GetTy().getOrThrow()
    CJC_ASSERT(exprTy.IsClassLike())
    let commonDecl = (exprTy as ClassLikeTy).getOrThrow().commonDecl.getOrThrow()
    CJC_ASSERT(commonDecl.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE,
        Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD))
    return WithinFile<MemberAccess>(CreateMemberAccess(expr, javaref), expr.curFile.getOrThrow())
}

public func CreateJavaRefCall(expr: Expr, mirrorLike: ClassLikeDecl): Expr {
    CJC_ASSERT(mirrorLike.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE,
        Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD))
    if (let Some(mirrorClass) <- (mirrorLike as ClassDecl)) {
        return CreateJavaRefCall(expr, GetJavaRefField(mirrorClass))
    }
    return CreateJavaRefCall(expr, GetJavaRefGetter(mirrorLike))
}

public func CreateJavaRefCall(mirrorLike: ClassLikeDecl, curFile: Option<File>): Expr {
    return CreateJavaRefCall(CreateThisRef(Some(mirrorLike), mirrorLike.GetTy(), curFile), mirrorLike)
}

public func CreateJavaRefCall(expr: Expr): Expr {
    let classLikeTy = (expr.GetTy().getOrThrow() as ClassLikeTy).getOrThrow()
    return CreateJavaRefCall(expr, classLikeTy.commonDecl.getOrThrow())
}

public func IsGeneratedJavaMirrorConstructor(ctor: FuncDecl): Bool {
    return ctor.TestAttr(Attribute.JAVA_MIRROR) && ctor.TestAttr(Attribute.CONSTRUCTOR) &&
        ctor.TestAttr(Attribute.COMPILER_ADD)
}

public func GetGeneratedConstructorInMirror(mirror: ClassDecl): Option<FuncDecl> {
    CJC_ASSERT(mirror.TestAttr(Attribute.JAVA_MIRROR))
    for (member in mirror.GetMemberDecls()) {
        if (let Some(fd) <- (member as FuncDecl)) {
            if (IsGeneratedJavaMirrorConstructor(fd)) {
                return Some(fd)
            }
        }
    }
    return None
}

public func GetGeneratedJavaMirrorConstructor(mirror: ClassLikeDecl): FuncDecl {
    CJC_ASSERT((mirror as ClassDecl).isSome())
    if (mirror.TestAttr(Attribute.JAVA_MIRROR_SUBTYPE) && !mirror.TestAttr(Attribute.JAVA_MIRROR)) {
        for (superType in mirror.inheritedTypes) {
            if (superType.TyKind() != TypeKind.TYPE_CLASS) {
                continue
            }
            let superTy = (superType.GetTy().getOrThrow() as ClassLikeTy).getOrThrow()
            let superDecl = superTy.commonDecl.getOrThrow()
            if (superDecl.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
                return GetGeneratedJavaMirrorConstructor(superDecl)
            }
        }
        CJC_ABORT()
    }
    CJC_ASSERT(mirror.TestAttr(Attribute.JAVA_MIRROR))
    return GetGeneratedConstructorInMirror((mirror as ClassDecl).getOrThrow()).getOrThrow()
}

public func IsGeneratedJavaImplConstructor(ctor: FuncDecl): Bool {
    if (!ctor.TestAttr(Attribute.CONSTRUCTOR)) {
        return false
    }
    let body = ctor.funcBody.getOrThrow()
    if (body.paramLists.isEmpty() || body.paramLists[0].params.isEmpty()) {
        return false
    }
    return body.paramLists[0].params[0].identifier.Val() == JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR
}

public func GetJavaMemberName(decl: Decl): String {
    for (anno in decl.annotations) {
        if (anno.kind != AstAnnotationKind.FOREIGN_NAME) {
            continue
        }
        CJC_ASSERT(anno.args.size == 1)
        return (anno.args[0].expr.getOrThrow() as LitConstExpr).getOrThrow().stringValue
    }
    return decl.identifier.Val()
}

public func HasPredefinedJavaName(decl: ClassLikeDecl): Bool {
    for (anno in decl.annotations) {
        if (anno.kind == AstAnnotationKind.JAVA_MIRROR || anno.kind == AstAnnotationKind.JAVA_IMPL) {
            return !anno.args.isEmpty()
        }
    }
    return false
}

public func GetJavaMirrorAnnoAttr(decl: ClassLikeDecl): Option<String> {
    for (anno in decl.annotations) {
        if (anno.kind != AstAnnotationKind.JAVA_MIRROR && anno.kind != AstAnnotationKind.JAVA_IMPL) {
            continue
        }
        CJC_ASSERT(anno.args.size < 2)
        if (anno.args.isEmpty()) {
            break
        }
        return Some((anno.args[0].expr.getOrThrow() as LitConstExpr).getOrThrow().stringValue)
    }
    return None
}

private func GetFQNameParts(name: String): ArrayList<String> {
    let result = ArrayList<String>()
    result.add("")
    var wasBackslash = false
    for (rune in name.runes()) {
        let ch = rune.toString()
        if (ch == "\\") {
            if (wasBackslash) {
                result[result.size - 1] += "\\"
            }
            wasBackslash = true
        } else if (ch == "$") {
            if (wasBackslash) {
                result[result.size - 1] += "$"
            } else {
                result.add("")
            }
            wasBackslash = false
        } else {
            if (wasBackslash) {
                result[result.size - 1] += "\\"
            }
            result[result.size - 1] += ch
            wasBackslash = false
        }
    }
    if (wasBackslash) {
        result[result.size - 1] += "\\"
    }
    return result
}

private func GetFQNameJoinBy(name: String, separator: String): String {
    return JoinVector(GetFQNameParts(name), separator)
}

public func GetJavaFQNameFromExtendDecl(extendDecl: ExtendDecl): String {
    let refType = (extendDecl.extendedType.getOrThrow() as RefType).getOrThrow()
    return GetJavaFQName(refType.ref.target.getOrThrow())
}

public func GetJavaFQName(decl: Decl, genericActualName!: Option<String> = None): String {
    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        return GetJavaFQNameFromExtendDecl(extendDecl)
    }
    if (let Some(classLikeDecl) <- (decl as ClassLikeDecl)) {
        if (let Some(attr) <- GetJavaMirrorAnnoAttr(classLikeDecl)) {
            return GetFQNameJoinBy(attr, "$")
        }
    }
    if (let Some(actualName) <- genericActualName) {
        if (!actualName.isEmpty()) {
            return decl.GetFullPackageName() + "." + actualName
        }
    }
    return decl.GetFullPackageName() + "." + decl.identifier.Val()
}

public func GetJavaFQSourceCodeName(decl: ClassLikeDecl): String {
    if (let Some(attr) <- GetJavaMirrorAnnoAttr(decl)) {
        return GetFQNameJoinBy(attr, ".")
    }
    return decl.GetFullPackageName() + "." + decl.identifier.Val()
}

public func GetJavaPackage(decl: Decl): String {
    for (anno in decl.annotations) {
        if (anno.kind != AstAnnotationKind.JAVA_MIRROR && anno.kind != AstAnnotationKind.JAVA_IMPL) {
            continue
        }
        CJC_ASSERT_WITH_MSG(anno.args.size < 2,
            "@JavaMirror or @JavaImpl could accept maximum one argument")
        if (anno.args.isEmpty()) {
            break
        }
        var fqname = (anno.args[0].expr.getOrThrow() as LitConstExpr).getOrThrow().stringValue
        if (let Some(pos) <- fqname.lastIndexOf(".")) {
            fqname = fqname[0..pos]
            return fqname
        }
        return ""
    }
    return decl.GetFullPackageName()
}

public func MangleJNIName(name: String): String {
    return name.replace("_", "_1").replace(".", "_")
}

public func GetMangledJniInitCjObjectFuncName(mangler: BaseMangler, params: ArrayList<FuncParam>,
    isGeneratedCtor: Bool): String {
    var name = "initCJObject"
    var toSkip = if (isGeneratedCtor) { 1 } else { 0 }
    for (param in params) {
        if (toSkip > 0) {
            toSkip--
            continue
        }
        name += mangler.MangleAstSemanticType(param.GetTy().getOrThrow()).replace(".", "_")
    }
    return name
}

public func GetMangledJniInitCjObjectFuncName(mangler: BaseMangler, types: ArrayList<Ty>): String {
    var name = "initCJObject"
    for (ty in types) {
        name += mangler.MangleAstSemanticType(ty).replace(".", "_")
    }
    return name
}

public func GetMangledJniInitCjObjectFuncNameForEnum(mangler: BaseMangler, params: ArrayList<FuncParam>,
    funcName: String): String {
    var name = funcName + "initCJObject"
    for (param in params) {
        name += mangler.MangleAstSemanticType(param.GetTy().getOrThrow()).replace(".", "_")
    }
    return name
}

public func GetSyntheticClass(importManager: ImportManager, cld: ClassLikeDecl): ClassDecl {
    let name = GetSyntheticNameFromClassLike(cld)
    return (importManager.GetImportedDecl(cld.fullPackageName, name).getOrThrow() as ClassDecl).getOrThrow()
}

public func ReplaceClassName(classTypeSignature: String, newSegment: String): String {
    let hasSemicolon = classTypeSignature.endsWith(";")
    var base = if (hasSemicolon) {
        classTypeSignature[0..classTypeSignature.size - 1]
    } else {
        classTypeSignature
    }
    if (let Some(lastSlash) <- classTypeSignature.lastIndexOf("/")) {
        base = base[0..lastSlash + 1] + newSegment
    } else {
        base = newSegment
    }
    return if (hasSemicolon) { base + ";" } else { base }
}

public func NormalizeJavaSignature(sig: String): String {
    return sig.replace(".", "/")
}

public func CreateMirrorConstructorCall(importManager: ImportManager, entity: Expr,
    mirrorTy: Ty): Option<Expr> {
    let curFile = entity.curFile
    if (let Some(classLikeTy) <- (mirrorTy as ClassLikeTy)) {
        if (let Some(decl) <- classLikeTy.commonDecl) {
            if (decl.TestAttr(Attribute.JAVA_MIRROR)) {
                var mirrorCtor: Option<FuncDecl> = None
                if ((decl as InterfaceDecl).isSome() ||
                    ((decl as ClassDecl).isSome() && decl.TestAttr(Attribute.ABSTRACT))) {
                    mirrorCtor = GetGeneratedConstructorInMirror(GetSyntheticClass(importManager, decl))
                } else if ((decl as ClassDecl).isSome()) {
                    mirrorCtor = Some(GetGeneratedJavaMirrorConstructor(decl))
                } else {
                    CJC_ABORT()
                }
                let args = ArrayList<FuncArg>()
                args.add(CreateFuncArg(entity))
                if (let Some(call) <- CreateCall(mirrorCtor, curFile, args: args)) {
                    call.callKind = CallKind.CALL_OBJECT_CREATION
                    call.SetTy(mirrorTy)
                    return Some(call)
                }
                return None
            }
        }
    }
    CJC_ABORT()
    return None
}

public func IsSynthetic(node: Node): Bool {
    return (node as ClassDecl).isSome() && node.TestAttr(Attribute.JAVA_MIRROR_SYNTHETIC_WRAPPER)
}

public func IsOptionOfString(ty: Ty): Bool {
    return ty.IsCoreOptionType() && !ty.typeArgs.isEmpty() && ty.typeArgs[0].IsString()
}

public func GetConstructorMarkerFQName(): String {
    return NATIVE_CONSTRUCTOR_MARKER_PACKAGE_NAME + "." + NATIVE_CONSTRUCTOR_MARKER_CLASS_NAME
}

public func GetConstructorMarkerClassName(): String {
    return NATIVE_CONSTRUCTOR_MARKER_CLASS_NAME
}

public func CreateConstructorMarkerClassDecl(): ClassDecl {
    let markerClassDecl = ClassDecl()
    markerClassDecl.identifier = SrcIdentifier(NATIVE_CONSTRUCTOR_MARKER_CLASS_NAME)
    markerClassDecl.fullPackageName = NATIVE_CONSTRUCTOR_MARKER_PACKAGE_NAME
    return markerClassDecl
}
