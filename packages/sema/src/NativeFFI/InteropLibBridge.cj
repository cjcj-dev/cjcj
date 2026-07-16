package cjcj::sema.NativeFFI

import std.collection.*
import std.convert.*
import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::modules.ImportManager
import cjcj::modules.SemaImportManager
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
import cjcj::sema.TypeManager
import cjcj::sema.CreateThrowException
import cjcj::sema.GenerateTypeMapping
import cjcj::utils.*

private let INTEROPLIB_VERSION_FIELD_ID: String = "INTEROPLIB_VERSION"
private let JAVA_CONSTRUCTOR: String = "<init>"
private let INTEROPLIB_JNI_ENV_PTR_ID: String = "JNIEnv_ptr"
private let INTEROPLIB_JNI_JLONG_ID: String = "jlong"
private let INTEROPLIB_JNI_JOBJECT_ID: String = "jobject"
private let INTEROPLIB_JAVA_ENTITY_KIND: String = "Java_CFFI_JavaEntityKind"
private let INTEROPLIB_JAVA_ENTITY_KIND_JOBJECT: String = "JOBJECT"
private let INTEROPLIB_JAVA_ENTITY_KIND_JBYTE: String = "JBYTE"
private let INTEROPLIB_JAVA_ENTITY_KIND_JSHORT: String = "JSHORT"
private let INTEROPLIB_JAVA_ENTITY_KIND_JCHAR: String = "JCHAR"
private let INTEROPLIB_JAVA_ENTITY_KIND_JINT: String = "JINT"
private let INTEROPLIB_JAVA_ENTITY_KIND_JLONG: String = "JLONG"
private let INTEROPLIB_JAVA_ENTITY_KIND_JFLOAT: String = "JFLOAT"
private let INTEROPLIB_JAVA_ENTITY_KIND_JDOUBLE: String = "JDOUBLE"
private let INTEROPLIB_JAVA_ENTITY_KIND_JBOOLEAN: String = "JBOOLEAN"
private let INTEROPLIB_JNI_GET_ENV_ID: String = "Java_CFFI_get_env"
private let INTEROPLIB_CFFI_NEW_GLOBAL_REF_ID: String = "Java_CFFI_newGlobalReference"
private let INTEROPLIB_CFFI_DELETE_GLOBAL_REF_ID: String = "Java_CFFI_deleteGlobalReference"
private let INTEROPLIB_CFFI_NEW_JAVA_OBJECT_ID: String = "Java_CFFI_newJavaObject"
private let INTEROPLIB_CFFI_NEW_JAVA_ARRAY_ID: String = "Java_CFFI_newJavaArray"
private let INTEROPLIB_CFFI_NEW_JAVA_PROXY_OBJECT_FOR_CJMAPPING_ID: String =
    "Java_CFFI_newJavaProxyObjectForCJMapping"
private let INTEROPLIB_CFFI_JAVA_ARRAY_GET_ID: String = "Java_CFFI_arrayGet"
private let INTEROPLIB_CFFI_JAVA_ARRAY_SET_ID: String = "Java_CFFI_arraySet"
private let INTEROPLIB_CFFI_JAVA_ARRAY_GET_LENGTH: String = "Java_CFFI_arrayGetLength"
private let INTEROPLIB_CFFI_JAVA_ENTITY_JOBJECT_ID: String = "Java_CFFI_JavaEntityJobject"
private let INTEROPLIB_CFFI_JAVA_ENTITY_NULL_ID: String = "Java_CFFI_JavaEntityJobjectNull"
private let INTEROPLIB_JNI_PUT_TO_REGISTRY_DECL_ID: String = "Java_CFFI_put_to_registry_1"
private let INTEROPLIB_JNI_PUT_SET_TO_REGISTRY_DECL_ID: String = "Java_CFFI_putToRegistry"
private let INTEROPLIB_JNI_REMOVE_FROM_REGISTRY_DECL_ID: String = "Java_CFFI_removeFromRegistry"
private let INTEROPLIB_CFFI_CALL_METHOD_DECL_ID: String = "Java_CFFI_callVirtualMethod"
private let INTEROPLIB_CFFI_NON_VIRT_CALL_METHOD_DECL_ID: String = "Java_CFFI_callMethod"
private let INTEROPLIB_CFFI_CALL_STATIC_METHOD_DECL_ID: String = "Java_CFFI_callStaticMethod"
private let INTEROPLIB_CFFI_UNWRAP_JAVA_ENTITY_METHOD_DECL_ID: String = "Java_CFFI_unwrapJavaEntityAsValue"
private let INTEROPLIB_CFFI_GET_FROM_REGISTRY_METHOD_DECL_ID: String = "Java_CFFI_getFromRegistry"
private let INTEROPLIB_CFFI_GET_FROM_REGISTRY_OPTION_METHOD_DECL_ID: String = "Java_CFFI_getFromRegistryOption"
private let INTEROPLIB_CFFI_GET_FIELD_METHOD_DECL_ID: String = "Java_CFFI_getField"
private let INTEROPLIB_CFFI_GET_STATIC_FIELD_METHOD_DECL_ID: String = "Java_CFFI_getStaticField"
private let INTEROPLIB_CFFI_SET_FIELD_METHOD_DECL_ID: String = "Java_CFFI_setField"
private let INTEROPLIB_CFFI_SET_STATIC_FIELD_METHOD_DECL_ID: String = "Java_CFFI_setStaticField"
private let INTEROPLIB_CFFI_ENSURE_NOT_NULL_METHOD_DECL_ID: String = "Java_CFFI_ensure_not_null"
private let INTEROPLIB_CFFI_GET_JAVA_ENTITY_OR_NULL_METHOD_DECL_ID: String = "Java_CFFI_getJavaEntityOrNull"
private let INTEROPLIB_CFFI_IS_INSTANCE_OF_DECL_ID: String = "Java_CFFI_isInstanceOf"
private let INTEROPLIB_CFFI_GET_FROM_REGISTRY_BY_ENTITY_OPTION_DECL_ID: String =
    "Java_CFFI_getFromRegistryByObjOption"
private let INTEROPLIB_CFFI_GET_FROM_REGISTRY_BY_ENTITY_DECL_ID: String = "Java_CFFI_getFromRegistryByObj"
private let INTEROPLIB_CFFI_GET_REGISTRY_ID: String = "Java_CFFI_getRegistryId"
private let INTEROPLIB_CFFI_GET_REGISTRY_ID_OR_NONE: String = "Java_CFFI_getRegistryIdOrNone"
private let INTEROPLIB_CFFI_JAVA_STRING_TO_CANGJIE: String = "Java_CFFI_JavaStringToCangjie"
private let INTEROPLIB_CFFI_CANGJIE_STRING_TO_JAVA: String = "Java_CFFI_CangjieStringToJava"
private let INTEROPLIB_CFFI_WITH_EXCEPTION_HANDLING_ID: String = "withExceptionHandling"
private let INTEROPLIB_CFFI_JAVA_CFFI_CLASS_ID: String = "Java_CFFI_ClassInit"
private let INTEROPLIB_CFFI_PARSE_METHOD_SIGNATURE_ID: String = "Java_CFFI_parseMethodSignature"
private let INTEROPLIB_CFFI_PARSE_COMPONENT_SIGNATURE_ID: String = "Java_CFFI_parseComponentSignature"
private let INTEROPLIB_CFFI_JAVA_CALLNEST_ID: String = "Java_CFFI_JavaCallNestInit"
private let INTEROPLIB_CFFI_JAVA_METHODID_CONSTR_ID: String = "Java_CFFI_MethodIDConstr"
private let INTEROPLIB_CFFI_JAVA_METHODID_CONSTR_STATIC_ID: String = "Java_CFFI_MethodIDConstrStatic"
private let INTEROPLIB_CFFI_JAVA_FIELDID_CONSTR_ID: String = "Java_CFFI_FieldIDConstr"
private let INTEROPLIB_CFFI_JAVA_FIELDID_CONSTR_STATIC_ID: String = "Java_CFFI_FieldIDConstrStatic"
private let INTEROPLIB_JAVA_OBJECT_CONTROLLER: String = "JavaObjectController"
private let DELETE_LOCAL_REF: String = "deleteLocalRef"
private let DETACH_CJ_OBJECT: String = "detachCJObject"
private let ATTACH_CJ_OBJECT: String = "attachCJObject"
private let GET_JAVALAMBDA_OBJECT_DECL_ID: String = "getJavaLambdaObject"
private let GET_JAVALAMBDA_ENTITY_DECL_ID: String = "getJavaLambdaEntity"
private let JAVA_ARRAY_GET_FOR_REF_TYPES: String = "$javaarrayget"
private let JAVA_ARRAY_SET_FOR_REF_TYPES: String = "$javaarrayset"

public class MemberJNISignature {
    public var classTypeSignature: String
    public var name: String
    public var signature: String

    public init(classTypeSignature: String, name: String, signature: String) {
        this.classTypeSignature = classTypeSignature
        this.name = name
        this.signature = signature
    }

    public init(utils: Utils, member: FuncDecl) {
        let jobject = (member.outerDecl.getOrThrow() as ClassLikeDecl).getOrThrow()
        var ty = jobject.GetTy().getOrThrow()
        if (IsSynthetic(jobject)) {
            if (jobject.inheritedTypes.size > 1) {
                ty = jobject.inheritedTypes[1].GetTy().getOrThrow()
            } else {
                CJC_ASSERT_WITH_MSG(!jobject.inheritedTypes.isEmpty(), "JObject must inherit Cangjie Object")
                ty = jobject.inheritedTypes[0].GetTy().getOrThrow()
            }
        }
        classTypeSignature = utils.GetJavaClassNormalizeSignature(ty)
        name = GetJavaMemberName(member)
        CJC_ASSERT(member.astKind == ASTKind.FUNC_DECL)
        let body = member.funcBody.getOrThrow()
        signature = utils.GetJavaTypeSignature(body.retType.getOrThrow().GetTy().getOrThrow(),
            GetParamTys(body.paramLists[0]), fullPackageName: member.fullPackageName)
    }

    public init(utils: Utils, member: FuncDecl, genericConfig: GenericConfigInfo) {
        let jobject = (member.outerDecl.getOrThrow() as ClassLikeDecl).getOrThrow()
        classTypeSignature = ReplaceClassName(
            utils.GetJavaClassNormalizeSignature(jobject.GetTy().getOrThrow()), genericConfig.declInstName)
        name = GetJavaMemberName(member)
        CJC_ASSERT(member.astKind == ASTKind.FUNC_DECL)
        let body = member.funcBody.getOrThrow()
        signature = utils.GetJavaTypeSignature(body.retType.getOrThrow().GetTy().getOrThrow(),
            GetParamTys(body.paramLists[0]), fullPackageName: member.fullPackageName)
    }

    public init(utils: Utils, member: PropDecl) {
        let jobject = (member.outerDecl.getOrThrow() as ClassLikeDecl).getOrThrow()
        var ty = jobject.GetTy().getOrThrow()
        if (IsSynthetic(jobject)) {
            if (jobject.inheritedTypes.size > 1) {
                ty = jobject.inheritedTypes[1].GetTy().getOrThrow()
            } else {
                CJC_ASSERT_WITH_MSG(!jobject.inheritedTypes.isEmpty(), "JObject must inherit Cangjie Object")
                ty = jobject.inheritedTypes[0].GetTy().getOrThrow()
            }
        }
        classTypeSignature = utils.GetJavaClassNormalizeSignature(ty)
        name = GetJavaMemberName(member)
        CJC_ASSERT(member.astKind == ASTKind.PROP_DECL)
        signature = utils.GetJavaTypeSignature(member.GetTy().getOrThrow(),
            fullPackageName: member.fullPackageName)
    }

    public init(utils: Utils, member: Decl, jobject: ClassLikeDecl) {
        var ty = jobject.GetTy().getOrThrow()
        if (IsSynthetic(jobject)) {
            if (jobject.inheritedTypes.size > 1) {
                ty = jobject.inheritedTypes[1].GetTy().getOrThrow()
            } else {
                CJC_ASSERT_WITH_MSG(!jobject.inheritedTypes.isEmpty(), "JObject must inherit Cangjie Object")
                ty = jobject.inheritedTypes[0].GetTy().getOrThrow()
            }
        }
        classTypeSignature = utils.GetJavaClassNormalizeSignature(ty)
        name = GetJavaMemberName(member)
        CJC_ASSERT(member.astKind == ASTKind.FUNC_DECL || member.astKind == ASTKind.PROP_DECL)
        signature = utils.GetJavaTypeSignature(member.GetTy().getOrThrow(),
            fullPackageName: member.fullPackageName)
    }
}

private func GetJavaEntityIsNullCall(entityDecl: StructDecl): Option<PropDecl> {
    for (member in entityDecl.GetMemberDecls()) {
        if (let Some(propDecl) <- (member as PropDecl)) {
            if (propDecl.identifier == "isNull") {
                return Some(propDecl)
            }
        }
    }
    return None
}

private func CreateJavaEntityIsNullExpr(entity: Expr, entityDecl: StructDecl): Option<Expr> {
    let isNullProp = GetJavaEntityIsNullCall(entityDecl)
    if (let None <- isNullProp) {
        return None
    }
    CJC_ASSERT_WITH_MSG(!isNullProp.getOrThrow().getters.isEmpty(), "getters cannot be empty")
    let getter = isNullProp.getOrThrow().getters[0]
    let access = CreateMemberAccess(entity, getter)
    CopyBasicInfo(access.baseExpr.getOrThrow(), access)
    let call = CreateCallExpr(access, ArrayList<FuncArg>(), Some(getter),
        isNullProp.getOrThrow().GetTy().getOrThrow(), CallKind.CALL_DECLARED_FUNCTION)
    CopyBasicInfo(call.baseFunc.getOrThrow(), call)
    return Some(call)
}

private func IsWrappingConstructorOfJavaImpl(refWrapperMember: Decl): Bool {
    if (!refWrapperMember.TestAttr(Attribute.CONSTRUCTOR) ||
        !refWrapperMember.TestAttr(Attribute.COMPILER_ADD)) {
        return false
    }
    if (let Some(ctor) <- (refWrapperMember as FuncDecl)) {
        if (let Some(body) <- ctor.funcBody) {
            if (!body.paramLists.isEmpty() && body.paramLists[0].params.size == 2) {
                let params = body.paramLists[0].params
                return InteropLibBridge.IsJavaEntityTy(params[0].GetTy().getOrThrow()) &&
                    params[1].GetTy().getOrThrow().kind == TypeKind.TYPE_INT64
            }
        }
    }
    return false
}

private func GetJavaImplWrappingConstructor(refWrapper: ClassDecl): FuncDecl {
    CJC_ASSERT(IsImplReferenceWrapper(refWrapper))
    for (member in refWrapper.GetMemberDeclPtrs()) {
        if (IsWrappingConstructorOfJavaImpl(member)) {
            return (member as FuncDecl).getOrThrow()
        }
    }
    CJC_ABORT()
    return FuncDecl()
}

public class InteropLibBridge {
    private static let INTEROPLIB_VERSION: Int64 = 10
    private static let INTEROPLIB_PACKAGE_NAME: String = "java.internal"

    private let importManager: ImportManager
    private let typeManager: TypeManager
    private let diag: BasicDiagnosticEngine
    private let utils: Utils
    private let supportedArrayPrimitiveElementType: Array<TypeKind> = [
        TypeKind.TYPE_BOOLEAN, TypeKind.TYPE_INT8, TypeKind.TYPE_UINT16, TypeKind.TYPE_INT16,
        TypeKind.TYPE_INT32, TypeKind.TYPE_INT64, TypeKind.TYPE_FLOAT32, TypeKind.TYPE_FLOAT64
    ]

    public init(importManager: ImportManager, typeManager: TypeManager,
        diag: BasicDiagnosticEngine, utils: Utils) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.diag = diag
        this.utils = utils
    }

    public static func IsInteropLibAccessible(importManager: SemaImportManager): Bool {
        return importManager.GetPackageDecl(InteropLibBridge.INTEROPLIB_PACKAGE_NAME).isSome()
    }

    private func ImportDecl<T>(packageName: String, declName: String,
        silent!: Bool = false): Option<T> where T <: Decl {
        if (let Some(decl) <- importManager.GetImportedDecl(packageName, declName)) {
            return DynamicCast<T>(decl)
        }
        if (!silent) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_member_not_imported,
                DEFAULT_POSITION, packageName + "." + declName)
        }
        return None
    }

    private func GetInteropLibDecl<T>(declName: String,
        silent!: Bool = false): Option<T> where T <: Decl {
        return ImportDecl<T>(InteropLibBridge.INTEROPLIB_PACKAGE_NAME, declName, silent: silent)
    }

    private func GetJavaLangDecl<T>(declName: String): Option<T> where T <: Decl {
        return ImportDecl<T>(INTEROP_JAVA_LANG_PACKAGE, declName)
    }

    public func GetJobjectDecl(): Option<TypeAliasDecl> {
        return GetInteropLibDecl<TypeAliasDecl>(INTEROPLIB_JNI_JOBJECT_ID)
    }

    public func GetJavaEntityDecl(): Option<StructDecl> {
        return GetInteropLibDecl<StructDecl>(INTEROPLIB_CFFI_JAVA_ENTITY)
    }

    public func GetJavaObjectControllerDecl(): Option<ClassDecl> {
        return GetInteropLibDecl<ClassDecl>(INTEROPLIB_JAVA_OBJECT_CONTROLLER)
    }

    public func GetJniEnvPtrDecl(): Option<TypeAliasDecl> {
        return GetInteropLibDecl<TypeAliasDecl>(INTEROPLIB_JNI_ENV_PTR_ID)
    }

    public func GetJavaEntityKindDecl(): Option<EnumDecl> {
        return GetInteropLibDecl<EnumDecl>(INTEROPLIB_JAVA_ENTITY_KIND)
    }

    public func GetJavaEntityKindJObject(): Decl {
        return LookupEnumMember(GetJavaEntityKindDecl().getOrThrow(),
            INTEROPLIB_JAVA_ENTITY_KIND_JOBJECT).getOrThrow()
    }

    public func GetNewGlobalRefDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_NEW_GLOBAL_REF_ID)
    }

    public func GetDeleteGlobalRefDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_DELETE_GLOBAL_REF_ID)
    }

    public func GetGetJniEnvDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_JNI_GET_ENV_ID)
    }

    public func GetCreateJavaEntityJobjectDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_ENTITY_JOBJECT_ID)
    }

    public func GetCreateJavaEntityNullDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_ENTITY_NULL_ID)
    }

    public func GetNewJavaObjectDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_NEW_JAVA_OBJECT_ID)
    }

    public func GetNewJavaArrayDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_NEW_JAVA_ARRAY_ID)
    }

    public func GetNewJavaProxyObjectForCJMappingDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_NEW_JAVA_PROXY_OBJECT_FOR_CJMAPPING_ID)
    }

    public func GetJavaArrayGetDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_ARRAY_GET_ID)
    }

    public func GetJavaArraySetDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_ARRAY_SET_ID)
    }

    public func GetJavaArrayGetLengthDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_ARRAY_GET_LENGTH)
    }

    public func GetCallMethodDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_CALL_METHOD_DECL_ID)
    }

    public func GetNonVirtualCallMethodDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_NON_VIRT_CALL_METHOD_DECL_ID)
    }

    public func GetCallStaticMethodDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_CALL_STATIC_METHOD_DECL_ID)
    }

    public func GetRemoveFromRegistryDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_JNI_REMOVE_FROM_REGISTRY_DECL_ID)
    }

    public func GetPutToRegistryDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_JNI_PUT_TO_REGISTRY_DECL_ID)
    }

    public func GetPutSetToRegistryDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_JNI_PUT_SET_TO_REGISTRY_DECL_ID)
    }

    public func GetUnwrapJavaEntityDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_UNWRAP_JAVA_ENTITY_METHOD_DECL_ID)
    }

    public func GetGetRegistryIdDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_GET_REGISTRY_ID)
    }

    public func GetGetRegistryIdOrNoneDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_GET_REGISTRY_ID_OR_NONE)
    }

    public func GetGetFromRegistryByEntityOptionDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_GET_FROM_REGISTRY_BY_ENTITY_OPTION_DECL_ID)
    }

    public func GetGetFromRegistryByEntityDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_GET_FROM_REGISTRY_BY_ENTITY_DECL_ID)
    }

    public func GetJavaStringToCangjie(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_STRING_TO_CANGJIE)
    }

    public func GetCangjieStringToJava(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_CANGJIE_STRING_TO_JAVA)
    }

    public func GetGetFromRegistryDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_GET_FROM_REGISTRY_METHOD_DECL_ID)
    }

    public func GetGetFromRegistryOptionDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_GET_FROM_REGISTRY_OPTION_METHOD_DECL_ID)
    }

    public func GetGetFieldDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_GET_FIELD_METHOD_DECL_ID)
    }

    public func GetGetStaticFieldDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_GET_STATIC_FIELD_METHOD_DECL_ID)
    }

    public func GetSetFieldDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_SET_FIELD_METHOD_DECL_ID)
    }

    public func GetSetStaticFieldDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_SET_STATIC_FIELD_METHOD_DECL_ID)
    }

    public func GetInteropLibVersionVarDecl(): Option<VarDecl> {
        return GetInteropLibDecl<VarDecl>(INTEROPLIB_VERSION_FIELD_ID, silent: true)
    }

    public func GetEnsureNotNullDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_ENSURE_NOT_NULL_METHOD_DECL_ID)
    }

    public func GetGetJavaEntityOrNullDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_GET_JAVA_ENTITY_OR_NULL_METHOD_DECL_ID)
    }

    public func GetIsInstanceOf(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_IS_INSTANCE_OF_DECL_ID)
    }

    public func GetWithExceptionHandlingDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_WITH_EXCEPTION_HANDLING_ID)
    }

    public func GetJClassDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_CFFI_CLASS_ID)
    }

    public func GetParseMethodSignatureDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_PARSE_METHOD_SIGNATURE_ID)
    }

    public func GetParseComponentSignatureDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_PARSE_COMPONENT_SIGNATURE_ID)
    }

    public func GetCallNestDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_CALLNEST_ID)
    }

    public func GetMethodIdConstr(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_METHODID_CONSTR_ID)
    }

    public func GetMethodIdConstrStatic(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_METHODID_CONSTR_STATIC_ID)
    }

    public func GetFieldIdConstr(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_FIELDID_CONSTR_ID)
    }

    public func GetFieldIdConstrStatic(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(INTEROPLIB_CFFI_JAVA_FIELDID_CONSTR_STATIC_ID)
    }

    public func GetJavaLambdaObjectDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(GET_JAVALAMBDA_OBJECT_DECL_ID)
    }

    public func GetJavaLambdaEntityDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(GET_JAVALAMBDA_ENTITY_DECL_ID)
    }

    private func GetJavaObjectControllerMethodDecl(methodName: String): Option<FuncDecl> {
        if (let Some(classDecl) <- GetJavaObjectControllerDecl()) {
            for (member in classDecl.GetMemberDecls()) {
                if (let Some(funcDecl) <- (member as FuncDecl)) {
                    if (funcDecl.identifier.Val() == methodName) {
                        return Some(funcDecl)
                    }
                }
            }
        }
        CJC_ASSERT_WITH_MSG(false, "JavaObjectController doesn't have method")
        return None
    }

    public func GetJavaObjectControllerInitDecl(): Option<FuncDecl> {
        return GetJavaObjectControllerMethodDecl("init")
    }

    public func GetAttachCJObjectDecl(): Option<FuncDecl> {
        return GetJavaObjectControllerMethodDecl(ATTACH_CJ_OBJECT)
    }

    public func GetDetachCJObjectDecl(): Option<FuncDecl> {
        return GetJavaObjectControllerMethodDecl(DETACH_CJ_OBJECT)
    }

    public func GetDeleteLocalRefDecl(): Option<FuncDecl> {
        return GetInteropLibDecl<FuncDecl>(DELETE_LOCAL_REF)
    }

    public func GetJNIEnvPtrTy(): Option<Ty> {
        if (let Some(decl) <- GetJniEnvPtrDecl()) {
            if (let Some(typeNode) <- decl.typeNode) {
                return typeNode.GetTy()
            }
        }
        return None
    }

    public func GetJavaEntityTy(): Option<Ty> {
        if (let Some(decl) <- GetJavaEntityDecl()) {
            return decl.GetTy()
        }
        return None
    }

    public func GetJniJobjectTy(): Ty {
        return typeManager.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
    }

    public func GetJlongTy(): Ty {
        return TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    }

    public func CreateJobjectType(): Option<Type> {
        if (let Some(decl) <- GetJobjectDecl()) {
            if (let Some(typeNode) <- decl.typeNode) {
                return ASTCloner.Clone(typeNode) as Type
            }
        }
        return None
    }

    public func CreateJlongType(): Option<Type> {
        if (let Some(decl) <- GetInteropLibDecl<TypeAliasDecl>(INTEROPLIB_JNI_JLONG_ID)) {
            if (let Some(typeNode) <- decl.typeNode) {
                return ASTCloner.Clone(typeNode) as Type
            }
        }
        return None
    }

    public func CreateJobjectNull(): PointerExpr {
        let pointerExpr = PointerExpr()
        let typeNode = Type()
        typeNode.SetTy(GetJniJobjectTy())
        pointerExpr.typeNode = Some(typeNode)
        pointerExpr.SetTy(typeNode.GetTy().getOrThrow())
        return pointerExpr
    }

    public func CreateEnvFuncParam(): FuncParam {
        let typeNode = GetJniEnvPtrDecl().getOrThrow().typeNode.getOrThrow()
        return CreateFuncParam("env", ASTCloner.Clone(typeNode) as Type, None, typeNode.GetTy())
    }

    public func CreateJClassOrJObjectFuncParam(name!: String = "_"): FuncParam {
        return CreateFuncParam(name, CreateJobjectType(), None, Some(GetJniJobjectTy()))
    }

    public func CreateSelfFuncParam(): FuncParam {
        return CreateFuncParam("self", CreateJlongType(), None, Some(GetJlongTy()))
    }

    public func CreateGetJniEnvCall(curFile: Option<File>): Option<CallExpr> {
        return CreateCall(GetGetJniEnvDecl(), curFile)
    }

    public func CreateJavaEntityCall(file: Option<File>): Option<CallExpr> {
        let javaEntityDecl = GetJavaEntityDecl()
        if (let None <- javaEntityDecl) {
            return None
        }
        var suitableCtor: Option<FuncDecl> = None
        for (decl in javaEntityDecl.getOrThrow().body.getOrThrow().decls) {
            if (let Some(ctor) <- (decl as FuncDecl)) {
                CJC_ASSERT_WITH_MSG(!ctor.funcBody.getOrThrow().paramLists.isEmpty(),
                    "at least one paramLists expected")
                if (ctor.funcBody.getOrThrow().paramLists[0].params.isEmpty()) {
                    suitableCtor = Some(ctor)
                    break
                }
            }
        }
        if (let None <- suitableCtor) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_member_not_imported,
                DEFAULT_POSITION, INTEROPLIB_CFFI_JAVA_ENTITY)
        }
        if (let Some(call) <- CreateCall(suitableCtor, file)) {
            call.callKind = CallKind.CALL_STRUCT_CREATION
            return Some(call)
        }
        return None
    }

    public func CreateJavaEntityJobjectCall(arg: Expr): Option<Expr> {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(arg))
        if (let Some(call) <- CreateCall(GetCreateJavaEntityJobjectDecl(), arg.curFile, args: args)) {
            return Some(call)
        }
        return None
    }

    public func CreateJavaEntityNullCall(curFile: Option<File>): Option<Expr> {
        if (let Some(call) <- CreateCall(GetCreateJavaEntityNullDecl(), curFile)) {
            return Some(call)
        }
        return None
    }

    public func CreateJavaEntityFromOptionMirror(option: Expr, mirror: ClassLikeDecl): Expr {
        let curFile = option.curFile.getOrThrow()
        let optionTy = option.GetTy().getOrThrow()
        CJC_ASSERT_WITH_MSG(!optionTy.typeArgs.isEmpty(), "Option type must be generic")
        let mirrorTy = optionTy.typeArgs[0]
        let vp = CreateVarPattern(V_COMPILER, Some(mirrorTy))
        vp.curFile = Some(curFile)
        vp.varDecl.getOrThrow().curFile = Some(curFile)
        let javarefAccess = CreateJavaRefCall(
            WithinFile<RefExpr>(CreateRefExpr(vp.varDecl.getOrThrow()), curFile), mirror)

        let somePattern = EnumPattern()
        somePattern.SetTy(utils.GetOptionTy(mirrorTy))
        somePattern.constructor = Some(utils.CreateOptionSomeRef(mirrorTy))
        somePattern.patterns.add(vp)
        somePattern.curFile = Some(curFile)
        let caseSome = CreateMatchCase(somePattern, javarefAccess)

        let nonePattern = EnumPattern()
        nonePattern.constructor = Some(utils.CreateOptionNoneRef(mirrorTy))
        nonePattern.SetTy(nonePattern.constructor.getOrThrow().GetTy().getOrThrow())
        nonePattern.curFile = Some(curFile)
        let caseNone = CreateMatchCase(nonePattern, CreateJavaEntityNullCall(Some(curFile)).getOrThrow())
        let cases = ArrayList<MatchCase>()
        cases.add(caseSome)
        cases.add(caseNone)
        return WithinFile<MatchExpr>(
            CreateMatchExpr(option, cases, GetJavaEntityTy().getOrThrow()), curFile)
    }

    public func CreateMatchWithTypeCast(exprToCast: Expr, castTy: Ty): Option<MatchExpr> {
        let exceptionDecl: Option<ClassDecl> = if (let Some(decl) <- importManager.GetCoreDecl(CLASS_EXCEPTION)) {
            decl as ClassDecl
        } else {
            None
        }
        if (let None <- exceptionDecl) {
            return None
        }
        let castType = Type()
        castType.SetTy(castTy)
        let varPattern = CreateVarPattern(V_COMPILER, castType.GetTy())
        let curFile = exprToCast.curFile.getOrThrow()
        varPattern.curFile = Some(curFile)
        varPattern.varDecl.getOrThrow().curFile = Some(curFile)
        let varPatternRef = WithinFile<RefExpr>(
            CreateRefExpr(varPattern.varDecl.getOrThrow()), curFile)

        let typePattern = CreateTypePattern(varPattern, castType, exprToCast)
        typePattern.matchBeforeRuntime = false
        let exceptionCallArgs = ArrayList<Expr>()
        let message = CreateLitConstExpr(LitConstKind.STRING,
            "internal error: CreateMatchWithTypeCast(" + Ty.KindName(exprToCast.TyKind()) + " -> " +
                Ty.KindName(castTy.kind) + ")", utils.GetStringDecl().GetTy().getOrThrow())
        message.curFile = Some(curFile)
        exceptionCallArgs.add(message)

        let cases = ArrayList<MatchCase>()
        let castCase = CreateMatchCase(typePattern, varPatternRef)
        castCase.curFile = Some(curFile)
        cases.add(castCase)
        let throwCase = CreateMatchCase(WildcardPattern(),
            CreateThrowException(exceptionDecl.getOrThrow(), exceptionCallArgs, curFile, typeManager))
        throwCase.curFile = Some(curFile)
        cases.add(throwCase)
        return Some(WithinFile<MatchExpr>(CreateMatchExpr(exprToCast, cases, castTy), curFile))
    }

    public static func IsJavaEntityTy(ty: Ty): Bool {
        if (let Some(javaEntityTy) <- (ty as StructTy)) {
            if (let Some(javaEntity) <- javaEntityTy.decl) {
                return javaEntity.fullPackageName == InteropLibBridge.INTEROPLIB_PACKAGE_NAME &&
                    javaEntity.identifier.Val() == INTEROPLIB_CFFI_JAVA_ENTITY
            }
        }
        return false
    }

    public func CheckInteropLibVersion(): Unit {
        let versionDecl = GetInteropLibVersionVarDecl()
        if (let None <- versionDecl) {
            if (let None <- importManager.GetPackageDecl(InteropLibBridge.INTEROPLIB_PACKAGE_NAME)) {
                diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_java_mirror_interoplib_must_be_imported, DEFAULT_POSITION).Emit()
                return
            }
        }
        if (let Some(decl) <- versionDecl) {
            if (let Some(initializer) <- decl.initializer) {
                if (initializer.astKind == ASTKind.LIT_CONST_EXPR && initializer.TyKind() == TypeKind.TYPE_INT64) {
                    let libVersionLit = (initializer as LitConstExpr).getOrThrow()
                    let libVersion = Int64.parse(libVersionLit.stringValue)
                    if (libVersion != InteropLibBridge.INTEROPLIB_VERSION) {
                        diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_java_interoplib_version_mismatch,
                            DEFAULT_POSITION, libVersionLit.stringValue,
                            InteropLibBridge.INTEROPLIB_VERSION.toString()).Emit()
                    }
                    return
                }
            }
        }
        diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_java_interoplib_version_too_old,
            DEFAULT_POSITION, InteropLibBridge.INTEROPLIB_VERSION.toString()).Emit()
    }

    public func CreateNewGlobalRefCall(env: Expr, obj: Expr, isWeak: Bool): Option<CallExpr> {
        let isWeakBoolValue = CreateBoolLit(isWeak)
        isWeakBoolValue.curFile = obj.curFile
        isWeakBoolValue.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(env))
        args.add(CreateFuncArg(obj))
        args.add(CreateFuncArg(isWeakBoolValue))
        return CreateCall(GetNewGlobalRefDecl(), obj.curFile, args: args)
    }

    public func CreateCFFINewJavaCFFINewJavaProxyObjectForCJMappingCall(jniEnv: Expr,
        entity: Expr, name: String, withMarkerParam: Bool): Option<CallExpr> {
        let funcDecl = GetNewJavaProxyObjectForCJMappingDecl()
        if (let None <- funcDecl) {
            return None
        }
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(jniEnv))
        args.add(CreateFuncArg(entity))
        args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.STRING, name,
            utils.GetStringDecl().GetTy().getOrThrow())))
        args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.BOOL,
            if (withMarkerParam) { "true" } else { "false" },
            TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))))
        return CreateCall(funcDecl, entity.curFile, args: args)
    }

    public func CreateJavaEntityCall(arg: Expr): Option<Expr> {
        let javaEntityDecl = GetJavaEntityDecl()
        if (let None <- javaEntityDecl) {
            return None
        }
        let argTy = arg.GetTy().getOrThrow()
        if (let Some(classLikeTy) <- (argTy as ClassLikeTy)) {
            if (let Some(decl) <- classLikeTy.commonDecl) {
                if (decl.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
                    return Some(CreateJavaRefCall(arg))
                }
            }
        } else if (argTy.IsCoreOptionType()) {
            CJC_ASSERT_WITH_MSG(!argTy.typeArgs.isEmpty(), "Option type must be generic")
            if (let Some(classLikeTy) <- (argTy.typeArgs[0] as ClassLikeTy)) {
                if (let Some(decl) <- classLikeTy.commonDecl) {
                    if (decl.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
                        return Some(CreateJavaEntityFromOptionMirror(arg, decl))
                    }
                }
            }
        }
        if (argTy.IsTuple()) {
            let curFile = arg.curFile.getOrThrow()
            let className = (curFile.GetFullPackageName() + "." + GetCjMappingTupleName(argTy)).replace(".", "/")
            let entity = CreateCFFINewJavaCFFINewJavaProxyObjectForCJMappingCall(
                CreateGetJniEnvCall(Some(curFile)).getOrThrow(), arg, className, true).getOrThrow()
            return CreateJavaEntityJobjectCall(entity)
        }
        var suitableCtor: Option<FuncDecl> = None
        for (decl in javaEntityDecl.getOrThrow().body.getOrThrow().decls) {
            if (let Some(ctor) <- (decl as FuncDecl)) {
                if (ctor.TestAttr(Attribute.CONSTRUCTOR)) {
                    let body = ctor.funcBody.getOrThrow()
                    CJC_ASSERT_WITH_MSG(!body.paramLists.isEmpty(), "paramLists cannot be empty")
                    if (body.paramLists[0].params.size == 1 &&
                        typeManager.IsTyEqual(argTy, body.paramLists[0].params[0].GetTy().getOrThrow())) {
                        suitableCtor = Some(ctor)
                    }
                }
            }
        }
        if (let None <- suitableCtor) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_java_interop_not_supported,
                arg.begin, "Type " + argTy.name).Emit()
            return None
        }
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(arg))
        if (let Some(call) <- CreateCall(suitableCtor, arg.curFile, args: args)) {
            call.callKind = CallKind.CALL_STRUCT_CREATION
            return Some(call)
        }
        return None
    }

    public func JObjectToString(jobjectExpr: Expr, curFile: Option<File>): Option<Expr> {
        let entity = CreateJavaEntityJobjectCall(WithinFile<Expr>(jobjectExpr, curFile))
        if (let None <- entity) {
            return None
        }
        if (let Some(call) <- CreateJavaStringToCangjieCall(
            CreateGetJniEnvCall(curFile).getOrThrow(), entity.getOrThrow())) {
            return Some(call)
        }
        return None
    }

    public func OptionStringToJObject(optionExpr: Expr, jniEnv: FuncParam, outerDecl: Decl): Expr {
        let curFile = optionExpr.curFile.getOrThrow()
        return utils.CreateOptionMatch(optionExpr,
            { value: VarDecl =>
                let inner = WithinFile<RefExpr>(CreateRefExpr(value), curFile)
                let env = WithinFile<RefExpr>(CreateRefExpr(jniEnv), curFile)
                let entity = CreateCangjieStringToJavaCall(env, inner).getOrThrow()
                UnwrapJavaEntity(entity, GetJniJobjectTy(), outerDecl, toRaw: true).getOrThrow()
            },
            { => CreateJobjectNull() }, GetJniJobjectTy())
    }

    public func StringToJObject(cjStringExpr: Expr, curFile: Option<File>,
        jniEnvParam: FuncParam, outerDecl: Decl): Option<Expr> {
        let env = WithinFile<RefExpr>(CreateRefExpr(jniEnvParam), curFile)
        let entity = CreateCangjieStringToJavaCall(
            env, WithinFile<Expr>(cjStringExpr, curFile))
        if (let None <- entity) {
            return None
        }
        return UnwrapJavaEntity(WithinFile<Expr>(entity.getOrThrow(), curFile),
            GetJniJobjectTy(), outerDecl, toRaw: true)
    }

    public func WrapJavaEntity(cjExpr: Expr): Option<Expr> {
        let curFile = cjExpr.curFile.getOrThrow()
        if (cjExpr.TyKind() == TypeKind.TYPE_UNIT) {
            if (let Some(call) <- CreateJavaEntityCall(Some(curFile))) {
                return Some(call)
            }
            return None
        }
        if (IsOptionOfString(cjExpr.GetTy().getOrThrow())) {
            let matchExpr = utils.CreateOptionMatch(cjExpr,
                { value: VarDecl => WrapJavaEntity(
                    WithinFile<RefExpr>(CreateRefExpr(value), curFile)).getOrThrow() },
                { => CreateJavaEntityNullCall(Some(curFile)).getOrThrow() },
                GetJavaEntityTy().getOrThrow())
            return Some(WithinFile<Expr>(matchExpr, curFile))
        }
        if (cjExpr.GetTy().getOrThrow().IsString()) {
            if (let Some(call) <- CreateCangjieStringToJavaCall(
                CreateGetJniEnvCall(Some(curFile)).getOrThrow(), cjExpr)) {
                return Some(call)
            }
            return None
        }
        return CreateJavaEntityCall(cjExpr)
    }

    public func SelectEntityWrapperByTypeKind(kind: TypeKind, ty: Ty,
        param: FuncParam, file: Option<File>): Expr {
        let paramRef = CreateRefExpr(param)
        paramRef.curFile = file
        return WrapJavaEntity(CreateMatchWithTypeCast(paramRef, ty).getOrThrow()).getOrThrow()
    }

    public func CreateDeleteGlobalRefCall(env: Expr, obj: Expr): Option<CallExpr> {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(env))
        args.add(CreateFuncArg(obj))
        return CreateCall(GetDeleteGlobalRefDecl(), obj.curFile, args: args)
    }

    public func CreateRemoveFromRegistryCall(registryId: Expr): Option<CallExpr> {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(registryId))
        return CreateCall(GetRemoveFromRegistryDecl(), registryId.curFile, args: args)
    }

    public func CreatePutToRegistryCall(obj: Expr): Option<CallExpr> {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(obj))
        return CreateCall(GetPutToRegistryDecl(), obj.curFile, args: args)
    }

    public func CreatePutSetToRegistryCall(env: Expr, entity: Expr, obj: Expr): Option<CallExpr> {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(env))
        args.add(CreateFuncArg(entity))
        args.add(CreateFuncArg(obj))
        return CreateCall(GetPutSetToRegistryDecl(), entity.curFile, args: args)
    }

    public func CreateGetRegistryIdCall(env: Expr, entity: Expr,
        nullable!: Bool = false): Option<CallExpr> {
        let decl = if (nullable) { GetGetRegistryIdOrNoneDecl() } else { GetGetRegistryIdDecl() }
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(env))
        args.add(CreateFuncArg(entity))
        return CreateCall(decl, entity.curFile, args: args)
    }

    public func CreateGetFromRegistryByEntityCall(env: Expr, obj: Expr, ty: Ty,
        retAsOption: Bool): Option<CallExpr> {
        let funcDecl = if (retAsOption) {
            GetGetFromRegistryByEntityOptionDecl()
        } else {
            GetGetFromRegistryByEntityDecl()
        }
        if (let None <- funcDecl) {
            return None
        }
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(env))
        args.add(CreateFuncArg(obj))
        let fdRef = WithinFile<RefExpr>(CreateRefExpr(funcDecl.getOrThrow()), obj.curFile)
        fdRef.instTys.add(ty)
        fdRef.SetTy(typeManager.GetInstantiatedTy(funcDecl.getOrThrow().GetTy().getOrThrow(),
            GenerateTypeMapping(funcDecl.getOrThrow(), fdRef.instTys)))
        let retTy = if (retAsOption) { utils.GetOptionTy(ty) } else { ty }
        return Some(CreateCallExpr(fdRef, args, funcDecl, retTy, CallKind.CALL_DECLARED_FUNCTION))
    }

    public func CreateCangjieStringToJavaCall(env: Expr, string: Expr): Option<CallExpr> {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(env))
        args.add(CreateFuncArg(string))
        return CreateCall(GetCangjieStringToJava(), string.curFile, args: args)
    }

    public func CreateJavaStringToCangjieCall(env: Expr, jstring: Expr): Option<CallExpr> {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(env))
        args.add(CreateFuncArg(jstring))
        return CreateCall(GetJavaStringToCangjie(), jstring.curFile, args: args)
    }

    public func CreateGetFromRegistryCall(env: Expr, self: Expr, ty: Ty): Option<CallExpr> {
        let funcDecl = GetGetFromRegistryDecl()
        if (let None <- funcDecl) {
            return None
        }
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(env))
        args.add(CreateFuncArg(self))
        let fdRef = WithinFile<RefExpr>(CreateRefExpr(funcDecl.getOrThrow()), self.curFile)
        fdRef.instTys.add(ty)
        fdRef.SetTy(typeManager.GetInstantiatedTy(funcDecl.getOrThrow().GetTy().getOrThrow(),
            GenerateTypeMapping(funcDecl.getOrThrow(), fdRef.instTys)))
        return Some(CreateCallExpr(fdRef, args, funcDecl, ty, CallKind.CALL_DECLARED_FUNCTION))
    }

    public func CreateGetFromRegistryOptionCall(self: Expr, ty: Ty): Option<CallExpr> {
        CJC_ASSERT(ty.IsCoreOptionType())
        let funcDecl = GetGetFromRegistryOptionDecl()
        if (let None <- funcDecl) {
            return None
        }
        CJC_ASSERT_WITH_MSG(!ty.typeArgs.isEmpty(), "Option type expected to be generic")
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(self))
        let fdRef = WithinFile<RefExpr>(CreateRefExpr(funcDecl.getOrThrow()), self.curFile)
        fdRef.instTys.add(ty.typeArgs[0])
        fdRef.SetTy(typeManager.GetInstantiatedTy(funcDecl.getOrThrow().GetTy().getOrThrow(),
            GenerateTypeMapping(funcDecl.getOrThrow(), fdRef.instTys)))
        return Some(CreateCallExpr(fdRef, args, funcDecl, ty, CallKind.CALL_DECLARED_FUNCTION))
    }

    public func CreateEnsureNotNullCall(entity: Expr): Option<Expr> {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(entity))
        if (let Some(call) <- CreateCall(GetEnsureNotNullDecl(), entity.curFile, args: args)) {
            return Some(call)
        }
        return None
    }

    public func CreateGetJavaEntityOrNullCall(entity: Expr): Option<Expr> {
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(entity))
        if (let Some(call) <- CreateCall(GetGetJavaEntityOrNullDecl(), entity.curFile, args: args)) {
            return Some(call)
        }
        return None
    }

    public func CreateGetFieldCall(env: Expr, obj: Expr, typeSignature: String,
        fieldName: String, fieldSignature: String): Option<CallExpr> {
        let funcDecl = GetGetFieldDecl()
        let jclassInitFuncDecl = GetJClassDecl()
        let parseSignatureFuncDecl = GetParseComponentSignatureDecl()
        let fieldIDFuncDecl = GetFieldIdConstr()
        if (funcDecl.isNone() || jclassInitFuncDecl.isNone() ||
            parseSignatureFuncDecl.isNone() || fieldIDFuncDecl.isNone()) {
            return None
        }
        let curFile = obj.curFile.getOrThrow()
        let body = jclassInitFuncDecl.getOrThrow().funcBody.getOrThrow()
        CJC_ASSERT_WITH_MSG(!body.paramLists.isEmpty(), "paramLists cannot be empty")
        CJC_ASSERT_WITH_MSG(body.paramLists[0].params.size > 1,
            "at least 2 parameters expected for classInit function")
        let strTy = body.paramLists[0].params[1].GetTy().getOrThrow()
        let jclass = CreateCall(jclassInitFuncDecl.getOrThrow(), curFile,
            (ASTCloner.Clone(env) as Expr).getOrThrow(),
            CreateLitConstExpr(LitConstKind.STRING, typeSignature, strTy))
        let fieldSig = CreateCall(parseSignatureFuncDecl.getOrThrow(), curFile,
            CreateLitConstExpr(LitConstKind.STRING, fieldSignature, strTy))
        let fieldIDArgs = ArrayList<FuncArg>()
        fieldIDArgs.add(CreateFuncArg((ASTCloner.Clone(env) as Expr).getOrThrow()))
        fieldIDArgs.add(CreateFuncArg(jclass))
        fieldIDArgs.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.STRING, fieldName, strTy)))
        fieldIDArgs.add(CreateFuncArg(fieldSig))
        let fieldID = CreateCall(fieldIDFuncDecl.getOrThrow(), curFile, args: fieldIDArgs)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg((ASTCloner.Clone(env) as Expr).getOrThrow()))
        args.add(CreateFuncArg(obj))
        args.add(CreateFuncArg(fieldID))
        return Some(CreateCall(funcDecl.getOrThrow(), curFile, args: args))
    }

    public func CreateGetStaticFieldCall(env: Expr, typeSignature: String,
        fieldName: String, fieldSignature: String): Option<CallExpr> {
        let funcDecl = GetGetStaticFieldDecl()
        let jclassInitFuncDecl = GetJClassDecl()
        let parseSignatureFuncDecl = GetParseComponentSignatureDecl()
        let fieldIDFuncDecl = GetFieldIdConstrStatic()
        if (funcDecl.isNone() || jclassInitFuncDecl.isNone() || parseSignatureFuncDecl.isNone() ||
            fieldIDFuncDecl.isNone() || GetJavaEntityTy().isNone()) {
            return None
        }
        let curFile = env.curFile.getOrThrow()
        let body = jclassInitFuncDecl.getOrThrow().funcBody.getOrThrow()
        CJC_ASSERT_WITH_MSG(!body.paramLists.isEmpty(), "paramLists cannot be empty")
        CJC_ASSERT_WITH_MSG(body.paramLists[0].params.size > 1,
            "at least 2 parameters expected for classInit function")
        let strTy = body.paramLists[0].params[1].GetTy().getOrThrow()
        let jclass = CreateCall(jclassInitFuncDecl.getOrThrow(), curFile,
            (ASTCloner.Clone(env) as Expr).getOrThrow(),
            CreateLitConstExpr(LitConstKind.STRING, typeSignature, strTy))
        let fieldSig = CreateCall(parseSignatureFuncDecl.getOrThrow(), curFile,
            CreateLitConstExpr(LitConstKind.STRING, fieldSignature, strTy))
        let fieldIDArgs = ArrayList<FuncArg>()
        fieldIDArgs.add(CreateFuncArg((ASTCloner.Clone(env) as Expr).getOrThrow()))
        fieldIDArgs.add(CreateFuncArg((ASTCloner.Clone(jclass) as Expr).getOrThrow()))
        fieldIDArgs.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.STRING, fieldName, strTy)))
        fieldIDArgs.add(CreateFuncArg(fieldSig))
        let fieldID = CreateCall(fieldIDFuncDecl.getOrThrow(), curFile, args: fieldIDArgs)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg((ASTCloner.Clone(env) as Expr).getOrThrow()))
        args.add(CreateFuncArg(jclass))
        args.add(CreateFuncArg(fieldID))
        return Some(CreateCall(funcDecl.getOrThrow(), curFile, args: args))
    }

    public func CreateSetFieldCall(env: Expr, obj: Expr, signature: MemberJNISignature,
        value: Expr): Option<CallExpr> {
        let funcDecl = GetSetFieldDecl()
        let jclassInitFuncDecl = GetJClassDecl()
        let parseSignatureFuncDecl = GetParseComponentSignatureDecl()
        let fieldIDFuncDecl = GetFieldIdConstr()
        if (funcDecl.isNone() || jclassInitFuncDecl.isNone() ||
            parseSignatureFuncDecl.isNone() || fieldIDFuncDecl.isNone()) {
            return None
        }
        let curFile = value.curFile.getOrThrow()
        let body = jclassInitFuncDecl.getOrThrow().funcBody.getOrThrow()
        CJC_ASSERT_WITH_MSG(!body.paramLists.isEmpty(), "paramLists cannot be empty")
        CJC_ASSERT_WITH_MSG(body.paramLists[0].params.size > 1,
            "at least 2 parameters expected for classInit function")
        let strTy = body.paramLists[0].params[1].GetTy().getOrThrow()
        let typeExpr = CreateLitConstExpr(LitConstKind.STRING, signature.classTypeSignature, strTy)
        typeExpr.curFile = Some(curFile)
        let nameExpr = CreateLitConstExpr(LitConstKind.STRING, signature.name, strTy)
        nameExpr.curFile = Some(curFile)
        let signatureExpr = CreateLitConstExpr(LitConstKind.STRING, signature.signature, strTy)
        signatureExpr.curFile = Some(curFile)
        let jclass = CreateCall(jclassInitFuncDecl.getOrThrow(), curFile,
            (ASTCloner.Clone(env) as Expr).getOrThrow(), typeExpr)
        let fieldSignature = CreateCall(parseSignatureFuncDecl.getOrThrow(), curFile, signatureExpr)
        let idArgs = ArrayList<FuncArg>()
        idArgs.add(CreateFuncArg((ASTCloner.Clone(env) as Expr).getOrThrow()))
        idArgs.add(CreateFuncArg(jclass))
        idArgs.add(CreateFuncArg(nameExpr))
        idArgs.add(CreateFuncArg(fieldSignature))
        let fieldID = CreateCall(fieldIDFuncDecl.getOrThrow(), curFile, args: idArgs)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg((ASTCloner.Clone(env) as Expr).getOrThrow()))
        args.add(CreateFuncArg(obj))
        args.add(CreateFuncArg(fieldID))
        args.add(CreateFuncArg(WrapJavaEntity(value).getOrThrow()))
        return Some(CreateCall(funcDecl.getOrThrow(), curFile, args: args))
    }

    public func CreateSetStaticFieldCall(env: Expr, typeSignature: String, fieldName: String,
        fieldSignature: String, value: Expr): Option<CallExpr> {
        let funcDecl = GetSetStaticFieldDecl()
        let jclassInitFuncDecl = GetJClassDecl()
        let parseSignatureFuncDecl = GetParseComponentSignatureDecl()
        let fieldIDFuncDecl = GetFieldIdConstrStatic()
        if (funcDecl.isNone() || jclassInitFuncDecl.isNone() ||
            parseSignatureFuncDecl.isNone() || fieldIDFuncDecl.isNone()) {
            return None
        }
        let curFile = value.curFile.getOrThrow()
        let body = jclassInitFuncDecl.getOrThrow().funcBody.getOrThrow()
        CJC_ASSERT_WITH_MSG(!body.paramLists.isEmpty(), "paramLists cannot be empty")
        CJC_ASSERT_WITH_MSG(body.paramLists[0].params.size > 1,
            "at least 2 parameters expected for classInit function")
        let strTy = body.paramLists[0].params[1].GetTy().getOrThrow()
        let typeExpr = CreateLitConstExpr(LitConstKind.STRING, typeSignature, strTy)
        typeExpr.curFile = Some(curFile)
        let nameExpr = CreateLitConstExpr(LitConstKind.STRING, fieldName, strTy)
        nameExpr.curFile = Some(curFile)
        let signatureExpr = CreateLitConstExpr(LitConstKind.STRING, fieldSignature, strTy)
        signatureExpr.curFile = Some(curFile)
        let jclass = CreateCall(jclassInitFuncDecl.getOrThrow(), curFile,
            (ASTCloner.Clone(env) as Expr).getOrThrow(), typeExpr)
        let parsedSignature = CreateCall(parseSignatureFuncDecl.getOrThrow(), curFile, signatureExpr)
        let idArgs = ArrayList<FuncArg>()
        idArgs.add(CreateFuncArg((ASTCloner.Clone(env) as Expr).getOrThrow()))
        idArgs.add(CreateFuncArg((ASTCloner.Clone(jclass) as Expr).getOrThrow()))
        idArgs.add(CreateFuncArg(nameExpr))
        idArgs.add(CreateFuncArg(parsedSignature))
        let fieldID = CreateCall(fieldIDFuncDecl.getOrThrow(), curFile, args: idArgs)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg((ASTCloner.Clone(env) as Expr).getOrThrow()))
        args.add(CreateFuncArg(jclass))
        args.add(CreateFuncArg(fieldID))
        args.add(CreateFuncArg(WrapJavaEntity(value).getOrThrow()))
        return Some(CreateCall(funcDecl.getOrThrow(), curFile, args: args))
    }

    public func WrapExceptionHandling(env: Expr, action: LambdaExpr): Expr {
        let curFile = env.curFile.getOrThrow()
        let retTy = action.funcBody.getOrThrow().GetTy().getOrThrow()
        let fd = GetWithExceptionHandlingDecl().getOrThrow()
        let fdRef = WithinFile<RefExpr>(CreateRefExpr(fd), curFile)
        fdRef.instTys.add(retTy)
        fdRef.SetTy(typeManager.GetInstantiatedTy(fd.GetTy().getOrThrow(), GenerateTypeMapping(fd, fdRef.instTys)))
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(env))
        args.add(CreateFuncArg(action))
        return CreateCallExpr(fdRef, args, None, retTy, CallKind.CALL_DECLARED_FUNCTION)
    }

    public func CreateJavaObjectControllerCall(javaEntity: Expr, className: Expr,
        classDecl: ClassDecl): CallExpr {
        let funcDecl = GetJavaObjectControllerInitDecl().getOrThrow()
        let javaObjectControllerDecl = GetJavaObjectControllerDecl().getOrThrow()
        let curFile = classDecl.curFile.getOrThrow()
        let instantiationRefType = CreateRefType(classDecl)
        let instantiationTy = typeManager.GetClassTy(classDecl,
            classDecl.GetTy().getOrThrow().typeArgs.toArray())
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(javaEntity))
        args.add(CreateFuncArg(className))
        let fdRef = CreateRefExpr(funcDecl)
        fdRef.ref.identifier = javaObjectControllerDecl.identifier
        fdRef.typeArguments.add(instantiationRefType)
        fdRef.curFile = Some(curFile)
        let callTy = typeManager.GetClassTy(javaObjectControllerDecl, [instantiationTy])
        return CreateCallExpr(fdRef, args, Some(funcDecl), callTy, CallKind.CALL_OBJECT_CREATION)
    }

    public func FindGetTypeForTypeParamDecl(file: File): FuncDecl {
        for (decl in file.curPackage.getOrThrow().files[0].decls) {
            if (decl.identifier.Val() == GET_TYPE_FOR_TYPE_PARAMETER_FUNC_NAME) {
                return (decl as FuncDecl).getOrThrow()
            }
        }
        CJC_ABORT()
        return FuncDecl()
    }

    public func FindCStringToStringDecl(): FuncDecl {
        for (extendDecl in typeManager.GetAllExtendsByTy(TypeManager.GetCStringTy())) {
            for (member in extendDecl.GetMemberDecls()) {
                if (member.identifier == "toString") {
                    return (member as FuncDecl).getOrThrow()
                }
            }
        }
        CJC_ABORT()
        return FuncDecl()
    }

    public func FindStringEqualsDecl(): FuncDecl {
        for (decl in utils.GetStringDecl().GetMemberDeclPtrs()) {
            if (decl.identifier == "==") {
                return (decl as FuncDecl).getOrThrow()
            }
        }
        CJC_ABORT()
        return FuncDecl()
    }

    public func FindStringStartsWithDecl(): FuncDecl {
        for (decl in utils.GetStringDecl().GetMemberDeclPtrs()) {
            if (decl.identifier == "startsWith") {
                return (decl as FuncDecl).getOrThrow()
            }
        }
        CJC_ABORT()
        return FuncDecl()
    }

    public func SelectJSigByTypeKind(kind: TypeKind, ty: Ty): Expr {
        return CreateLitConstExpr(LitConstKind.STRING, utils.GetJavaTypeSignature(ty),
            utils.GetStringDecl().GetTy().getOrThrow())
    }

    public func SelectJPrimitiveNameByTypeKind(kind: TypeKind, ty: Ty): Expr {
        let typeName = match (kind) {
            case TypeKind.TYPE_INT8 => INTEROPLIB_JAVA_ENTITY_KIND_JBYTE
            case TypeKind.TYPE_INT16 => INTEROPLIB_JAVA_ENTITY_KIND_JSHORT
            case TypeKind.TYPE_UINT16 => INTEROPLIB_JAVA_ENTITY_KIND_JCHAR
            case TypeKind.TYPE_INT32 => INTEROPLIB_JAVA_ENTITY_KIND_JINT
            case TypeKind.TYPE_INT64 => INTEROPLIB_JAVA_ENTITY_KIND_JLONG
            case TypeKind.TYPE_FLOAT32 => INTEROPLIB_JAVA_ENTITY_KIND_JFLOAT
            case TypeKind.TYPE_FLOAT64 => INTEROPLIB_JAVA_ENTITY_KIND_JDOUBLE
            case TypeKind.TYPE_BOOLEAN => INTEROPLIB_JAVA_ENTITY_KIND_JBOOLEAN
            case TypeKind.TYPE_ENUM => INTEROPLIB_JAVA_ENTITY_KIND_JOBJECT
            case _ =>
                CJC_ABORT()
                ""
        }
        return CreateRefExpr(LookupEnumMember(GetJavaEntityKindDecl().getOrThrow(), typeName).getOrThrow())
    }

    public func GenerateTypeMappingWithSelector(selector: (TypeKind, Ty) -> Expr): HashMap<String, Expr> {
        let typeMapping = HashMap<String, Expr>()
        for (kind in supportedArrayPrimitiveElementType) {
            let ty = TypeManager.GetPrimitiveTy(kind)
            typeMapping.add(Ty.ToString(ty), selector(kind, ty))
        }
        return typeMapping
    }

    public func FindArrayJavaEntityGetDecl(jArrayDecl: ClassDecl): Option<FuncDecl> {
        for (member in jArrayDecl.body.getOrThrow().decls) {
            if (member.identifier == JAVA_ARRAY_GET_FOR_REF_TYPES) {
                return member as FuncDecl
            }
        }
        return None
    }

    public func FindArrayJavaEntitySetDecl(jArrayDecl: ClassDecl): Option<FuncDecl> {
        for (member in jArrayDecl.body.getOrThrow().decls) {
            if (member.identifier == JAVA_ARRAY_SET_FOR_REF_TYPES) {
                return member as FuncDecl
            }
        }
        return None
    }

    public func SelectEntityUnwrapperByTypeKind(kind: TypeKind, ty: Ty,
        entity: Expr, mirror: ClassLikeDecl): Expr {
        let clonedEntity = (ASTCloner.Clone(entity) as Expr).getOrThrow()
        clonedEntity.curFile = entity.curFile
        return CreateMatchWithTypeCast(
            UnwrapJavaEntity(clonedEntity, ty, mirror).getOrThrow(), ty).getOrThrow()
    }

    public func UnwrapJavaMirrorOption(entity: Expr, ty: Ty, mirror: ClassLikeDecl,
        toRaw!: Bool = false): Expr {
        CJC_ASSERT(ty.IsCoreOptionType())
        CJC_ASSERT_WITH_MSG(!ty.typeArgs.isEmpty(), "Option type must be generic")
        let curFile = entity.curFile.getOrThrow()
        let declTy = ty.typeArgs[0]
        let decl = Ty.GetDeclOfTy(declTy)
        CJC_ASSERT((decl.isSome() && IsMirror(decl.getOrThrow())) || declTy.IsString() ||
            (toRaw && decl.isSome() && IsImpl(decl.getOrThrow())))
        let actualTy = if (toRaw) { GetJniJobjectTy() } else { ty }
        return utils.CreateOptionMatch(CreateGetJavaEntityOrNullCall(entity).getOrThrow(),
            { value: VarDecl =>
                UnwrapJavaEntity(WithinFile<RefExpr>(CreateRefExpr(value), curFile),
                    declTy, mirror, toRaw: toRaw).getOrThrow()
            },
            { => if (toRaw) { CreateJobjectNull() } else { utils.CreateOptionNoneRef(declTy) } },
            actualTy)
    }

    public func UnwrapJavaImplOption(env: Expr, entityOption: Expr, ty: Ty,
        mirror: ClassLikeDecl, toRaw!: Bool = false): Expr {
        CJC_ASSERT_WITH_MSG(!ty.typeArgs.isEmpty(), "Option type must be generic")
        let implTy = ty.typeArgs[0]
        CJC_ASSERT(implTy.IsClass())
        let actualTy = if (toRaw) { GetJniJobjectTy() } else { ty }
        let curFile = entityOption.curFile.getOrThrow()
        return utils.CreateOptionMatch(CreateGetJavaEntityOrNullCall(entityOption).getOrThrow(),
            { value: VarDecl =>
                let entityRef = WithinFile<RefExpr>(CreateRefExpr(value), curFile)
                if (toRaw) {
                    UnwrapJavaEntity(entityRef, implTy, mirror, toRaw: true).getOrThrow()
                } else {
                    UnwrapJavaImpl(env, entityRef, implTy)
                }
            },
            { => if (toRaw) { CreateJobjectNull() } else { utils.CreateOptionNoneRef(implTy) } },
            actualTy)
    }

    public func UnwrapJavaImpl(env: Expr, entity: Expr, ty: Ty): Expr {
        let classTy = (ty as ClassTy).getOrThrow()
        let classDecl = classTy.decl.getOrThrow()
        CJC_ASSERT(IsImplReferenceWrapper(classDecl))
        let ctor = GetJavaImplWrappingConstructor(classDecl)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg((ASTCloner.Clone(entity) as Expr).getOrThrow()))
        args.add(CreateFuncArg(CreateGetRegistryIdCall(env, entity).getOrThrow()))
        return CreateCallExpr(WithinFile<RefExpr>(CreateRefExpr(ctor), entity.curFile),
            args, Some(ctor), ty, CallKind.CALL_OBJECT_CREATION)
    }

    public func UnwrapJavaArrayEntity(entity: Expr, ty: Ty, mirror: ClassLikeDecl): Expr {
        if (ty == TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)) {
            return CreateUnitExpr()
        }
        CJC_ASSERT_WITH_MSG(mirror.generic.isSome() &&
            !mirror.generic.getOrThrow().typeParameters.isEmpty(), "JArray type must be generic")
        let genericParam = mirror.generic.getOrThrow().typeParameters[0]
        let mapping = GenerateTypeMappingWithSelector(
            { kind: TypeKind, selectedTy: Ty =>
                SelectEntityUnwrapperByTypeKind(kind, selectedTy, entity, mirror)
            })
        return CreateMatchByTypeArgument(genericParam, mapping, ty,
            CreateMatchWithTypeCast(entity, ty).getOrThrow())
    }

    public func UnwrapJavaPrimitiveEntity(entity: Expr, ty: Ty): Option<Expr> {
        let funcDecl = GetUnwrapJavaEntityDecl()
        if (let None <- funcDecl) {
            return None
        }
        let actualEntityTy = if (ty.IsPrimitive()) {
            ty
        } else {
            typeManager.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        }
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(entity))
        let fdRef = WithinFile<RefExpr>(CreateRefExpr(funcDecl.getOrThrow()), entity.curFile)
        fdRef.instTys.add(actualEntityTy)
        fdRef.SetTy(typeManager.GetInstantiatedTy(funcDecl.getOrThrow().GetTy().getOrThrow(),
            GenerateTypeMapping(funcDecl.getOrThrow(), fdRef.instTys)))
        let callExpr = CreateCallExpr(fdRef, args, funcDecl, actualEntityTy, CallKind.CALL_DECLARED_FUNCTION)
        callExpr.curFile = entity.curFile
        return Some(callExpr)
    }

    public func UnwrapJavaEntity(entity: Expr, ty: Ty, outerDecl: Decl,
        toRaw!: Bool = false): Option<Expr> {
        let curFile = entity.curFile
        if (ty.IsPrimitive() || (toRaw && !ty.IsCoreOptionType())) {
            return UnwrapJavaPrimitiveEntity(entity, ty)
        }
        if (IsJArray(outerDecl) && ty.IsGeneric()) {
            return Some(UnwrapJavaArrayEntity(entity, ty, (outerDecl as ClassLikeDecl).getOrThrow()))
        } else if (let Some(javaEntityTy) <- GetJavaEntityTy()) {
            if (ty == javaEntityTy) {
                return Some(entity)
            }
        }
        if (ty.IsString()) {
            let notNull = CreateEnsureNotNullCall(entity).getOrThrow()
            if (let Some(call) <- CreateJavaStringToCangjieCall(
                CreateGetJniEnvCall(curFile).getOrThrow(), notNull)) {
                return Some(call)
            }
            return None
        }
        if (ty.IsCoreOptionType()) {
            let classLikeDecl = (outerDecl as ClassLikeDecl).getOrThrow()
            CJC_ASSERT_WITH_MSG(!ty.typeArgs.isEmpty(), "Option type must be generic")
            let actualTy = ty.typeArgs[0]
            let actualDecl = Ty.GetDeclOfTy(actualTy)
            if ((actualDecl.isSome() && IsMirror(actualDecl.getOrThrow())) || actualTy.IsString()) {
                return Some(UnwrapJavaMirrorOption(entity, ty, classLikeDecl, toRaw: toRaw))
            }
            return Some(UnwrapJavaImplOption(CreateGetJniEnvCall(curFile).getOrThrow(),
                entity, ty, classLikeDecl, toRaw: toRaw))
        }
        if (ty.IsTuple()) {
            if (let Some(call) <- CreateGetFromRegistryByEntityCall(
                CreateGetJniEnvCall(curFile).getOrThrow(), entity, ty, false)) {
                return Some(call)
            }
            return None
        }
        if (let None <- (ty as ClassLikeTy)) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_java_interop_not_supported,
                DEFAULT_POSITION, "type " + ty.name).Emit()
            return None
        }
        let decl = (ty as ClassLikeTy).getOrThrow().commonDecl
        if (let None <- decl) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_java_interop_not_supported,
                DEFAULT_POSITION, "unknown decl " + ty.name).Emit()
            return None
        }
        if (IsMirror(decl.getOrThrow())) {
            return CreateMirrorConstructorCall(importManager, entity, ty)
        }
        CJC_ASSERT(IsImpl(decl.getOrThrow()))
        return Some(UnwrapJavaImpl(CreateGetJniEnvCall(curFile).getOrThrow(), entity, ty))
    }

    public func CreateGetTypeForTypeParameterCall(genericParam: GenericParamDecl): Expr {
        let getTypeForTypeParamDecl = FindGetTypeForTypeParamDecl(genericParam.curFile.getOrThrow())
        let refExpr = WithinFile<RefExpr>(CreateRefExpr(getTypeForTypeParamDecl), genericParam.curFile)
        refExpr.instTys.add(genericParam.GetTy().getOrThrow())
        let callExpr = CreateCallExpr(refExpr, ArrayList<FuncArg>(), Some(getTypeForTypeParamDecl),
            getTypeForTypeParamDecl.funcBody.getOrThrow().retType.getOrThrow().GetTy().getOrThrow(),
            CallKind.CALL_INTRINSIC_FUNCTION)
        callExpr.curFile = genericParam.curFile
        return callExpr
    }

    public func CreateMatchByTypeArgument(genericParam: GenericParamDecl,
        typeToCaseMap: HashMap<String, Expr>, retTy: Ty, defaultCase: Expr): MatchExpr {
        let strTy = utils.GetStringDecl().GetTy().getOrThrow()
        let cStrToStringDecl = FindCStringToStringDecl()
        let strEqualsDecl = FindStringEqualsDecl()
        let strStartsWithDecl = FindStringStartsWithDecl()
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let file = genericParam.curFile
        let cStrToStringCall = CallExpr()
        let cStrToStringMa = CreateMemberAccess(CreateGetTypeForTypeParameterCall(genericParam), "toString")
        cStrToStringMa.SetTy(cStrToStringDecl.GetTy().getOrThrow())
        cStrToStringMa.target = Some(cStrToStringDecl)
        cStrToStringMa.callOrPattern = Some(cStrToStringCall)
        cStrToStringCall.SetTy(strTy)
        cStrToStringCall.resolvedFunction = Some(cStrToStringDecl)
        cStrToStringCall.baseFunc = Some(cStrToStringMa)
        cStrToStringCall.callKind = CallKind.CALL_DECLARED_FUNCTION
        cStrToStringCall.curFile = file
        let cases = ArrayList<MatchCase>()
        for ((typeDesc, expr) in typeToCaseMap) {
            let isOption = typeDesc.startsWith(CORE_PACKAGE_NAME + ":" + OPTION_NAME)
            let selectedDecl = if (isOption) { strStartsWithDecl } else { strEqualsDecl }
            let caseCall = CallExpr()
            let caseName: String = if (isOption) { "startsWith" } else { "==" }
            let caseMa = CreateMemberAccess(
                (ASTCloner.Clone(cStrToStringCall) as Expr).getOrThrow(), caseName)
            caseMa.SetTy(selectedDecl.GetTy().getOrThrow())
            caseMa.target = Some(selectedDecl)
            caseMa.callOrPattern = Some(caseCall)
            caseCall.SetTy(boolTy)
            caseCall.resolvedFunction = Some(selectedDecl)
            caseCall.baseFunc = Some(caseMa)
            caseCall.args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.STRING, typeDesc, strTy)))
            caseCall.callKind = CallKind.CALL_DECLARED_FUNCTION
            caseCall.curFile = file
            let patternForType = ConstPattern()
            patternForType.SetTy(strTy)
            patternForType.literal = CreateLitConstExpr(LitConstKind.STRING, typeDesc, strTy)
            patternForType.operatorCallExpr = caseCall
            cases.add(CreateMatchCase(patternForType, expr))
        }
        cases.add(CreateMatchCase(WildcardPattern(), defaultCase))
        let matchExpr = CreateMatchExpr(cStrToStringCall, cases, retTy)
        matchExpr.curFile = file
        return matchExpr
    }

    public func CreateGetJavaLambdaObjectCall(refExpr: RefExpr, classSign: String,
        curFile: Option<File>): CallExpr {
        return CreateGetJavaLambdaCall(GetJavaLambdaObjectDecl(), refExpr, classSign, curFile)
    }

    public func CreateGetJavaLambdaEntityCall(refExpr: RefExpr, classSign: String,
        curFile: Option<File>): CallExpr {
        return CreateGetJavaLambdaCall(GetJavaLambdaEntityDecl(), refExpr, classSign, curFile)
    }

    public func CreateGetJavaLambdaCall(fd: Option<FuncDecl>, refExpr: RefExpr,
        classSign: String, curFile: Option<File>): CallExpr {
        let funcDecl = fd.getOrThrow()
        let body = funcDecl.funcBody.getOrThrow()
        let strTy = body.paramLists[0].params[1].GetTy().getOrThrow()
        let classSignExpr = CreateLitConstExpr(LitConstKind.STRING, classSign, strTy)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(refExpr))
        args.add(CreateFuncArg(classSignExpr))
        return CreateCall(fd, curFile, args: args).getOrThrow()
    }
}
