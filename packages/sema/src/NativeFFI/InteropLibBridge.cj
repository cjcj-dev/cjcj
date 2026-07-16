package cjcj::sema.NativeFFI

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::modules.ImportManager
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
import cjcj::sema.TypeManager
import cjcj::utils.*

private let INTEROPLIB_VERSION_FIELD_ID: String = "INTEROPLIB_VERSION"
private let JAVA_CONSTRUCTOR: String = "<init>"
private let INTEROPLIB_JNI_ENV_PTR_ID: String = "JNIEnv_ptr"
private let INTEROPLIB_JNI_JLONG_ID: String = "jlong"
private let INTEROPLIB_JNI_JOBJECT_ID: String = "jobject"
private let INTEROPLIB_JAVA_ENTITY_KIND: String = "Java_CFFI_JavaEntityKind"
private let INTEROPLIB_JAVA_ENTITY_KIND_JOBJECT: String = "JOBJECT"
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

public class InteropLibBridge {
    private static let INTEROPLIB_VERSION: Int64 = 10
    private static let INTEROPLIB_PACKAGE_NAME: String = "java.internal"

    private let importManager: ImportManager
    private let typeManager: TypeManager
    private let diag: BasicDiagnosticEngine
    private let utils: Utils

    public init(importManager: ImportManager, typeManager: TypeManager,
        diag: BasicDiagnosticEngine, utils: Utils) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.diag = diag
        this.utils = utils
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
