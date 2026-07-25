package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.{DEFAULT_POSITION, DiagKindRefactor, DiagnosticEngine}
import cjcj::modules.SemaImportManager
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, OBJ_C_BLOCK_IDENT, OBJ_C_FUNC_IDENT,
    OBJ_C_LANG_PACKAGE_IDENT, OBJ_C_POINTER_IDENT}

private let INTEROPLIB_PACKAGE_NAME: String = "objc.internal"
private let INTEROPLIB_OBJ_C_ID: String = "ObjCId"
private let INTEROPLIB_NATIVE_OBJ_C_ID: String = "NativeObjCId"
private let INTEROPLIB_NATIVE_OBJ_C_SEL: String = "NativeObjCSel"
private let INTEROPLIB_NATIVE_OBJ_C_SUPER_PTR: String = "NativeObjCSuperPtr"
private let INTEROPLIB_NATIVE_OBJ_C_CLASS: String = "NativeObjCClass"
private let INTEROPLIB_REGISTRY_ID: String = "RegistryId"
private let INTEROPLIB_OBJ_C_UNREACHABLE_CODE_EXCEPTION: String = "ObjCUnreachableCodeException"
private let INTEROPLIB_OBJ_C_OPTIONAL_METHOD_UNIMPLEMENTED_EXCEPTION: String = "ObjCOptionalMethodUnimplementedException"
private let INTEROPLIB_OBJ_C_STATIC_METHOD_CALL_ON_INTERFACE_EXCEPTION: String = "ObjCStaticMethodCallOnInterfaceException"
private let INTEROPLIB_NATIVE_BLOCK_ABI: String = "NativeBlockABI"
private let INTEROPLIB_CANGJIE_BLOCK_ABI: String = "CangjieBlockABI"
private let INTEROPLIB_OBJ_C_GET_FROM_REGISTRY_BY_NATIVE_HANDLE: String = "getFromRegistryByNativeHandle"
private let INTEROPLIB_OBJ_C_GET_FROM_REGISTRY_BY_ID: String = "getFromRegistryById"
private let INTEROPLIB_OBJ_C_PUT_TO_REGISTRY: String = "putToRegistry"
private let INTEROPLIB_OBJ_C_REMOVE_FROM_REGISTRY: String = "removeFromRegistry"
private let INTEROPLIB_OBJ_C_ALLOC: String = "alloc"
private let INTEROPLIB_OBJ_C_WITH_AUTORELEASE_POOL: String = "withAutoreleasePool"
private let INTEROPLIB_OBJ_C_WITH_AUTORELEASE_POOL_OBJ: String = "withAutoreleasePoolObj"
private let INTEROPLIB_OBJ_C_REGISTER_NAME: String = "registerName"
private let INTEROPLIB_OBJ_C_GET_INSTANCE_VARIABLE_OBJ: String = "getInstanceVariableObj"
private let INTEROPLIB_OBJ_C_SET_INSTANCE_VARIABLE_OBJ: String = "setInstanceVariableObj"
private let INTEROPLIB_OBJ_C_GET_INSTANCE_VARIABLE: String = "getInstanceVariable"
private let INTEROPLIB_OBJ_C_SET_INSTANCE_VARIABLE: String = "setInstanceVariable"
private let INTEROPLIB_OBJ_C_GET_CLASS: String = "getClass"
private let INTEROPLIB_OBJ_C_GET_PROTOCOL: String = "getProtocol"
private let INTEROPLIB_OBJ_C_GET_SUPER_CLASS: String = "getSuperClass"
private let INTEROPLIB_OBJ_C_WITH_OBJ_C_SUPER: String = "withObjCSuper"
private let INTEROPLIB_OBJ_C_MSG_SEND: String = "objCMsgSend"
private let INTEROPLIB_OBJ_C_MSG_SEND_SUPER: String = "objCMsgSendSuper"
private let INTEROPLIB_OBJ_C_RELEASE: String = "objCRelease"
private let INTEROPLIB_OBJ_C_RESPONSE_TO_SELECTOR: String = "respondsToSelector"
private let INTEROPLIB_OBJ_C_AUTO_RELEASE: String = "objCAutorelease"
private let INTEROPLIB_OBJ_C_RETAIN: String = "objCRetain"
private let INTEROPLIB_FORWARDER_MUTEX: String = "ForwarderMutex"
private let MUTEX_LOCK_IDENT: String = "lock"
private let MUTEX_UNLOCK_IDENT: String = "unlock"
private let INTEROPLIB_OBJC_STORE_LAMBDA_AS_BLOCK: String = "registerCangjieLambdaAsBlock"
private let INTEROPLIB_OBJC_GET_LAMBDA_FROM_BLOCK: String = "getCangjieLambdaFromBlock"
private let INTEROPLIB_OBJ_C_OBJECT_GET_CLASS: String = "objectGetClass"
private let INTEROPLIB_OBJ_C_IS_KIND_OF_CLASS: String = "isKindOfClass"
private let INTEROPLIB_OBJ_C_CONFORMS_TO_PROTOCOL: String = "conformsToProtocol"
private let INTEROPLIB_OBJ_C_CONVERT_TO_NSSTRING: String = "convertToNSString"
private let INTEROPLIB_OBJ_C_DESCRIPTION_AS_STRING: String = "descriptionAsString"
private let INTEROPLIB_OBJ_C_RETAIN_AUTORELEASED_RETURN_VALUE: String = "objCRetainAutoreleasedReturnValue"
private let OBJ_C_FUNC_GET_FPOINTER: String = "unsafeGetFunctionPointer"
private let OBJ_C_BLOCK_GET_ABI_POINTER: String = "unsafeGetNativeABIPointer"

private func GetMemberOfDecl<T>(decl: Decl, pred: (Decl) -> Bool): Option<T> where T <: Decl {
    for (member in decl.GetMemberDeclPtrs()) {
        if (pred(member)) {
            return member as T
        }
    }
    return None
}

public class InteropLibBridge {
    private static var mutexLock: Option<FuncDecl> = None
    private static var mutexUnlock: Option<FuncDecl> = None
    private static var mutexConstructor: Option<FuncDecl> = None
    // C++ InteropLibBridge.cpp:89-230 uses function-local statics. Cangjie only supports static
    // members, so the outer Option is initialization state and the inner Option caches a failed lookup.
    private static var forwarderMutexDecl: Option<Option<TypeAliasDecl>> = None
    private static var nativeObjCIdDecl: Option<Option<TypeAliasDecl>> = None
    private static var objCIdDecl: Option<Option<InterfaceDecl>> = None
    private static var nativeObjCSelDecl: Option<Option<TypeAliasDecl>> = None
    private static var nativeObjCClassDecl: Option<Option<TypeAliasDecl>> = None
    private static var nativeObjCSuperPtrDecl: Option<Option<TypeAliasDecl>> = None
    private static var registryIdDecl: Option<Option<TypeAliasDecl>> = None
    private static var objCUnreachableCodeExceptionDecl: Option<Option<ClassDecl>> = None
    private static var objCOptionalMethodUnimplementedExceptionDecl: Option<Option<ClassDecl>> = None
    private static var objCStaticMethodCallOnIntefaceExceptionDecl: Option<Option<ClassDecl>> = None
    private static var getFromRegistryByNativeHandleDecl: Option<Option<FuncDecl>> = None
    private static var getFromRegistryByIdDecl: Option<Option<FuncDecl>> = None
    private static var putToRegistryDecl: Option<Option<FuncDecl>> = None
    private static var removeFromRegistryDecl: Option<Option<FuncDecl>> = None
    private static var allocDecl: Option<Option<FuncDecl>> = None
    private static var withAutoreleasePoolDecl: Option<Option<FuncDecl>> = None
    private static var withAutoreleasePoolObjDecl: Option<Option<FuncDecl>> = None
    private static var registerNameDecl: Option<Option<FuncDecl>> = None
    private static var getInstanceVariableObjDecl: Option<Option<FuncDecl>> = None
    private static var setInstanceVariableObjDecl: Option<Option<FuncDecl>> = None
    private static var getInstanceVariableDecl: Option<Option<FuncDecl>> = None
    private static var setInstanceVariableDecl: Option<Option<FuncDecl>> = None
    private static var getClassDecl: Option<Option<FuncDecl>> = None
    private static var getProtoDecl: Option<Option<FuncDecl>> = None
    private static var getSuperClassDecl: Option<Option<FuncDecl>> = None
    private static var objCMsgSendDecl: Option<Option<FuncDecl>> = None
    private static var objCMsgSendSuperDecl: Option<Option<FuncDecl>> = None
    private static var objCReleaseDecl: Option<Option<FuncDecl>> = None
    private static var objCRespondsToSelectorDecl: Option<Option<FuncDecl>> = None
    private static var getProtocolDecl: Option<Option<FuncDecl>> = None
    private static var objCRetainDecl: Option<Option<FuncDecl>> = None
    private static var objCAutoReleaseDecl: Option<Option<FuncDecl>> = None
    private static var withObjCSuperDecl: Option<Option<FuncDecl>> = None
    private static var objCIsKindOfClassDecl: Option<Option<FuncDecl>> = None
    private static var objCConformsToProtocolDecl: Option<Option<FuncDecl>> = None
    private static var convertToNSStringDecl: Option<Option<FuncDecl>> = None
    private static var descriptionAsStringDecl: Option<Option<FuncDecl>> = None
    private static var objCRetainAutoreleasedReturnValue: Option<Option<FuncDecl>> = None
    private static var objCPointerDecl: Option<Option<StructDecl>> = None
    private static var objCFuncDecl: Option<Option<StructDecl>> = None
    private static var objCBlockDecl: Option<Option<ClassDecl>> = None
    private static var objCPointerConstructor: Option<FuncDecl> = None
    private static var objCPointerPointerField: Option<VarDecl> = None
    private static var objCFuncConstructor: Option<FuncDecl> = None
    private static var objCFuncFPointerAccessor: Option<FuncDecl> = None
    private static var objCBlockConstructorFromObjC: Option<FuncDecl> = None
    private static var objCBlockConstructorFromCangjie: Option<FuncDecl> = None
    private static var objCBlockFPointerAccessor: Option<FuncDecl> = None
    private static var objCBlockAbiPointerAccessor: Option<FuncDecl> = None
    private static var objectGetClassDecl: Option<Option<FuncDecl>> = None
    private let importManager: SemaImportManager
    private let diag: DiagnosticEngine

    public init(importManager: SemaImportManager, diag: DiagnosticEngine) {
        this.importManager = importManager
        this.diag = diag
    }

    private func GetInteropLibDecl<T>(ident: String, kind: ASTKind): Option<T> where T <: Decl {
        if (let Some(decl) <- importManager.GetImportedDecl(INTEROPLIB_PACKAGE_NAME, ident)) {
            CJC_ASSERT(decl.astKind == kind)
            return decl as T
        }
        diag.DiagnoseRefactor(DiagKindRefactor.sema_member_not_imported, DEFAULT_POSITION,
            INTEROPLIB_PACKAGE_NAME + "." + ident).Emit()
        return None
    }

    private func GetObjCLangDecl<T>(ident: String, kind: ASTKind): Option<T> where T <: Decl {
        if (let Some(decl) <- importManager.GetImportedDecl(OBJ_C_LANG_PACKAGE_IDENT, ident)) {
            CJC_ASSERT(decl.astKind == kind)
            return decl as T
        }
        diag.DiagnoseRefactor(DiagKindRefactor.sema_member_not_imported, DEFAULT_POSITION, ident).Emit()
        return None
    }

    public func GetForwarderMutexDecl(): Option<TypeAliasDecl> {
        if (let Some(result) <- InteropLibBridge.forwarderMutexDecl) { return result }
        let result = GetInteropLibDecl<TypeAliasDecl>(INTEROPLIB_FORWARDER_MUTEX, ASTKind.TYPE_ALIAS_DECL)
        InteropLibBridge.forwarderMutexDecl = Some(result)
        return result
    }

    public func GetForwarderMutexTy(): Option<Ty> {
        if (let Some(decl) <- GetForwarderMutexDecl()) {
            if (let Some(typeNode) <- decl.typeNode) { return typeNode.GetTy() }
        }
        return None
    }

    public func GetMutexLock(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.mutexLock) { return result }
        let decl = Ty.GetDeclOfTy(GetForwarderMutexTy())
        CJC_NULLPTR_CHECK(decl)
        InteropLibBridge.mutexLock = GetMemberOfDecl<FuncDecl>(decl.getOrThrow(), { mem => mem.identifier.Val() == MUTEX_LOCK_IDENT })
        CJC_NULLPTR_CHECK(InteropLibBridge.mutexLock)
        return InteropLibBridge.mutexLock
    }

    public func GetMutexUnlock(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.mutexUnlock) { return result }
        let decl = Ty.GetDeclOfTy(GetForwarderMutexTy())
        CJC_NULLPTR_CHECK(decl)
        InteropLibBridge.mutexUnlock = GetMemberOfDecl<FuncDecl>(decl.getOrThrow(), { mem => mem.identifier.Val() == MUTEX_UNLOCK_IDENT })
        CJC_NULLPTR_CHECK(InteropLibBridge.mutexUnlock)
        return InteropLibBridge.mutexUnlock
    }

    public func GetMutexConstructor(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.mutexConstructor) { return result }
        let decl = Ty.GetDeclOfTy(GetForwarderMutexTy())
        CJC_NULLPTR_CHECK(decl)
        InteropLibBridge.mutexConstructor = GetMemberOfDecl<FuncDecl>(decl.getOrThrow(), { mem => mem.TestAttr(Attribute.CONSTRUCTOR) })
        CJC_NULLPTR_CHECK(InteropLibBridge.mutexConstructor)
        return InteropLibBridge.mutexConstructor
    }

    public func GetNativeObjCIdDecl(): Option<TypeAliasDecl> {
        if (let Some(result) <- InteropLibBridge.nativeObjCIdDecl) { return result }
        let result = GetInteropLibDecl<TypeAliasDecl>(INTEROPLIB_NATIVE_OBJ_C_ID, ASTKind.TYPE_ALIAS_DECL)
        InteropLibBridge.nativeObjCIdDecl = Some(result)
        return result
    }
    public func GetObjCIdDecl(): Option<InterfaceDecl> {
        if (let Some(result) <- InteropLibBridge.objCIdDecl) { return result }
        let result = GetObjCLangDecl<InterfaceDecl>(INTEROPLIB_OBJ_C_ID, ASTKind.INTERFACE_DECL)
        InteropLibBridge.objCIdDecl = Some(result)
        return result
    }
    public func GetNativeObjCIdTy(): Option<Ty> { return GetNativeObjCIdDecl().flatMap({ value => value.typeNode.flatMap({ node => node.GetTy() }) }) }
    public func GetNativeObjCSelDecl(): Option<TypeAliasDecl> {
        if (let Some(result) <- InteropLibBridge.nativeObjCSelDecl) { return result }
        let result = GetInteropLibDecl<TypeAliasDecl>(INTEROPLIB_NATIVE_OBJ_C_SEL, ASTKind.TYPE_ALIAS_DECL)
        InteropLibBridge.nativeObjCSelDecl = Some(result)
        return result
    }
    public func GetNativeObjCClassDecl(): Option<TypeAliasDecl> {
        if (let Some(result) <- InteropLibBridge.nativeObjCClassDecl) { return result }
        let result = GetInteropLibDecl<TypeAliasDecl>(INTEROPLIB_NATIVE_OBJ_C_CLASS, ASTKind.TYPE_ALIAS_DECL)
        InteropLibBridge.nativeObjCClassDecl = Some(result)
        return result
    }
    public func GetNativeObjCClassTy(): Option<Ty> { return GetNativeObjCClassDecl().flatMap({ value => value.typeNode.flatMap({ node => node.GetTy() }) }) }
    public func GetNativeObjCSuperPtrDecl(): Option<TypeAliasDecl> {
        if (let Some(result) <- InteropLibBridge.nativeObjCSuperPtrDecl) { return result }
        let result = GetInteropLibDecl<TypeAliasDecl>(INTEROPLIB_NATIVE_OBJ_C_SUPER_PTR, ASTKind.TYPE_ALIAS_DECL)
        InteropLibBridge.nativeObjCSuperPtrDecl = Some(result)
        return result
    }
    public func GetNativeObjCSuperPtrTy(): Option<Ty> { return GetNativeObjCSuperPtrDecl().flatMap({ value => value.typeNode.flatMap({ node => node.GetTy() }) }) }
    public func GetRegistryIdDecl(): Option<TypeAliasDecl> {
        if (let Some(result) <- InteropLibBridge.registryIdDecl) { return result }
        let result = GetInteropLibDecl<TypeAliasDecl>(INTEROPLIB_REGISTRY_ID, ASTKind.TYPE_ALIAS_DECL)
        InteropLibBridge.registryIdDecl = Some(result)
        return result
    }
    public func GetRegistryIdTy(): Option<Ty> { return GetRegistryIdDecl().flatMap({ value => value.typeNode.flatMap({ node => node.GetTy() }) }) }
    public func GetObjCUnreachableCodeExceptionDecl(): Option<ClassDecl> {
        if (let Some(result) <- InteropLibBridge.objCUnreachableCodeExceptionDecl) { return result }
        let result = GetInteropLibDecl<ClassDecl>(INTEROPLIB_OBJ_C_UNREACHABLE_CODE_EXCEPTION, ASTKind.CLASS_DECL)
        InteropLibBridge.objCUnreachableCodeExceptionDecl = Some(result)
        return result
    }
    public func GetObjCOptionalMethodUnimplementedExceptionDecl(): Option<ClassDecl> {
        if (let Some(result) <- InteropLibBridge.objCOptionalMethodUnimplementedExceptionDecl) { return result }
        let result = GetObjCLangDecl<ClassDecl>(INTEROPLIB_OBJ_C_OPTIONAL_METHOD_UNIMPLEMENTED_EXCEPTION,
            ASTKind.CLASS_DECL)
        InteropLibBridge.objCOptionalMethodUnimplementedExceptionDecl = Some(result)
        return result
    }
    public func GetObjCStaticMethodCallOnIntefaceExceptionDecl(): Option<ClassDecl> {
        if (let Some(result) <- InteropLibBridge.objCStaticMethodCallOnIntefaceExceptionDecl) { return result }
        let result = GetInteropLibDecl<ClassDecl>(INTEROPLIB_OBJ_C_STATIC_METHOD_CALL_ON_INTERFACE_EXCEPTION,
            ASTKind.CLASS_DECL)
        InteropLibBridge.objCStaticMethodCallOnIntefaceExceptionDecl = Some(result)
        return result
    }
    public func GetGetFromRegistryByNativeHandleDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.getFromRegistryByNativeHandleDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_GET_FROM_REGISTRY_BY_NATIVE_HANDLE,
            ASTKind.FUNC_DECL)
        InteropLibBridge.getFromRegistryByNativeHandleDecl = Some(result)
        return result
    }
    public func GetGetFromRegistryByIdDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.getFromRegistryByIdDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_GET_FROM_REGISTRY_BY_ID, ASTKind.FUNC_DECL)
        InteropLibBridge.getFromRegistryByIdDecl = Some(result)
        return result
    }
    public func GetPutToRegistryDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.putToRegistryDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_PUT_TO_REGISTRY, ASTKind.FUNC_DECL)
        InteropLibBridge.putToRegistryDecl = Some(result)
        return result
    }
    public func GetRemoveFromRegistryDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.removeFromRegistryDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_REMOVE_FROM_REGISTRY, ASTKind.FUNC_DECL)
        InteropLibBridge.removeFromRegistryDecl = Some(result)
        return result
    }
    public func GetAllocDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.allocDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_ALLOC, ASTKind.FUNC_DECL)
        InteropLibBridge.allocDecl = Some(result)
        return result
    }
    public func GetWithAutoreleasePoolDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.withAutoreleasePoolDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_WITH_AUTORELEASE_POOL, ASTKind.FUNC_DECL)
        InteropLibBridge.withAutoreleasePoolDecl = Some(result)
        return result
    }
    public func GetWithAutoreleasePoolObjDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.withAutoreleasePoolObjDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_WITH_AUTORELEASE_POOL_OBJ, ASTKind.FUNC_DECL)
        InteropLibBridge.withAutoreleasePoolObjDecl = Some(result)
        return result
    }
    public func GetRegisterNameDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.registerNameDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_REGISTER_NAME, ASTKind.FUNC_DECL)
        InteropLibBridge.registerNameDecl = Some(result)
        return result
    }
    public func GetGetInstanceVariableObjDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.getInstanceVariableObjDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_GET_INSTANCE_VARIABLE_OBJ, ASTKind.FUNC_DECL)
        InteropLibBridge.getInstanceVariableObjDecl = Some(result)
        return result
    }
    public func GetSetInstanceVariableObjDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.setInstanceVariableObjDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_SET_INSTANCE_VARIABLE_OBJ, ASTKind.FUNC_DECL)
        InteropLibBridge.setInstanceVariableObjDecl = Some(result)
        return result
    }
    public func GetGetInstanceVariableDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.getInstanceVariableDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_GET_INSTANCE_VARIABLE, ASTKind.FUNC_DECL)
        InteropLibBridge.getInstanceVariableDecl = Some(result)
        return result
    }
    public func GetSetInstanceVariableDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.setInstanceVariableDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_SET_INSTANCE_VARIABLE, ASTKind.FUNC_DECL)
        InteropLibBridge.setInstanceVariableDecl = Some(result)
        return result
    }
    public func GetGetClassDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.getClassDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_GET_CLASS, ASTKind.FUNC_DECL)
        InteropLibBridge.getClassDecl = Some(result)
        return result
    }
    public func GetGetProtoDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.getProtoDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_GET_PROTOCOL, ASTKind.FUNC_DECL)
        InteropLibBridge.getProtoDecl = Some(result)
        return result
    }
    public func GetGetSuperClassDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.getSuperClassDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_GET_SUPER_CLASS, ASTKind.FUNC_DECL)
        InteropLibBridge.getSuperClassDecl = Some(result)
        return result
    }
    public func GetObjCMsgSendDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCMsgSendDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_MSG_SEND, ASTKind.FUNC_DECL)
        InteropLibBridge.objCMsgSendDecl = Some(result)
        return result
    }
    public func GetObjCMsgSendSuperDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCMsgSendSuperDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_MSG_SEND_SUPER, ASTKind.FUNC_DECL)
        InteropLibBridge.objCMsgSendSuperDecl = Some(result)
        return result
    }
    public func GetObjCReleaseDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCReleaseDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_RELEASE, ASTKind.FUNC_DECL)
        InteropLibBridge.objCReleaseDecl = Some(result)
        return result
    }
    public func GetObjCRespondsToSelectorDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCRespondsToSelectorDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_RESPONSE_TO_SELECTOR, ASTKind.FUNC_DECL)
        InteropLibBridge.objCRespondsToSelectorDecl = Some(result)
        return result
    }
    public func GetGetProtocolDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.getProtocolDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_GET_PROTOCOL, ASTKind.FUNC_DECL)
        InteropLibBridge.getProtocolDecl = Some(result)
        return result
    }
    public func GetObjCRetainDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCRetainDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_RETAIN, ASTKind.FUNC_DECL)
        InteropLibBridge.objCRetainDecl = Some(result)
        return result
    }
    public func GetObjCAutoReleaseDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCAutoReleaseDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_AUTO_RELEASE, ASTKind.FUNC_DECL)
        InteropLibBridge.objCAutoReleaseDecl = Some(result)
        return result
    }
    public func GetWithObjCSuperDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.withObjCSuperDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_WITH_OBJ_C_SUPER, ASTKind.FUNC_DECL)
        InteropLibBridge.withObjCSuperDecl = Some(result)
        return result
    }
    public func GetObjCIsKindOfClassDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCIsKindOfClassDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_IS_KIND_OF_CLASS, ASTKind.FUNC_DECL)
        InteropLibBridge.objCIsKindOfClassDecl = Some(result)
        return result
    }
    public func GetObjCConformsToProtocolDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCConformsToProtocolDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_CONFORMS_TO_PROTOCOL, ASTKind.FUNC_DECL)
        InteropLibBridge.objCConformsToProtocolDecl = Some(result)
        return result
    }
    public func GetConvertToNSStringDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.convertToNSStringDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_CONVERT_TO_NSSTRING, ASTKind.FUNC_DECL)
        InteropLibBridge.convertToNSStringDecl = Some(result)
        return result
    }
    public func GetDescriptionAsStringDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.descriptionAsStringDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_DESCRIPTION_AS_STRING, ASTKind.FUNC_DECL)
        InteropLibBridge.descriptionAsStringDecl = Some(result)
        return result
    }
    public func GetObjCRetainAutoreleasedReturnValue(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCRetainAutoreleasedReturnValue) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_RETAIN_AUTORELEASED_RETURN_VALUE,
            ASTKind.FUNC_DECL)
        InteropLibBridge.objCRetainAutoreleasedReturnValue = Some(result)
        return result
    }

    public func GetObjCPointerDecl(): Option<StructDecl> {
        if (let Some(result) <- InteropLibBridge.objCPointerDecl) { return result }
        let result = GetObjCLangDecl<StructDecl>(OBJ_C_POINTER_IDENT, ASTKind.STRUCT_DECL)
        InteropLibBridge.objCPointerDecl = Some(result)
        return result
    }
    public func GetObjCFuncDecl(): Option<StructDecl> {
        if (let Some(result) <- InteropLibBridge.objCFuncDecl) { return result }
        let result = GetObjCLangDecl<StructDecl>(OBJ_C_FUNC_IDENT, ASTKind.STRUCT_DECL)
        InteropLibBridge.objCFuncDecl = Some(result)
        return result
    }
    public func GetObjCBlockDecl(): Option<ClassDecl> {
        if (let Some(result) <- InteropLibBridge.objCBlockDecl) { return result }
        let result = GetObjCLangDecl<ClassDecl>(OBJ_C_BLOCK_IDENT, ASTKind.CLASS_DECL)
        InteropLibBridge.objCBlockDecl = Some(result)
        return result
    }

    public func GetObjCPointerConstructor(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCPointerConstructor) { return result }
        let outer = GetObjCPointerDecl()
        CJC_NULLPTR_CHECK(outer)
        for (member in outer.getOrThrow().body.getOrThrow().decls) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (funcDecl.TestAttr(Attribute.CONSTRUCTOR) && funcDecl.funcBody.isSome() &&
                    funcDecl.funcBody.getOrThrow().paramLists[0].params.size == 1) {
                    InteropLibBridge.objCPointerConstructor = Some(funcDecl)
                    break
                }
            }
        }
        return InteropLibBridge.objCPointerConstructor
    }
    public func GetObjCPointerPointerField(): Option<VarDecl> {
        if (let Some(result) <- InteropLibBridge.objCPointerPointerField) { return result }
        let outer = GetObjCPointerDecl()
        CJC_NULLPTR_CHECK(outer)
        for (member in outer.getOrThrow().body.getOrThrow().decls) {
            if (let Some(fieldDecl) <- (member as VarDecl)) {
                if (fieldDecl.GetTy().getOrThrow().IsPointer()) {
                    InteropLibBridge.objCPointerPointerField = Some(fieldDecl)
                    break
                }
            }
        }
        return InteropLibBridge.objCPointerPointerField
    }
    public func GetObjCFuncConstructor(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCFuncConstructor) { return result }
        let outer = GetObjCFuncDecl()
        CJC_NULLPTR_CHECK(outer)
        for (member in outer.getOrThrow().body.getOrThrow().decls) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (funcDecl.TestAttr(Attribute.CONSTRUCTOR) && funcDecl.funcBody.isSome() &&
                    funcDecl.funcBody.getOrThrow().paramLists[0].params.size == 1) {
                    InteropLibBridge.objCFuncConstructor = Some(funcDecl)
                    break
                }
            }
        }
        return InteropLibBridge.objCFuncConstructor
    }
    public func GetObjCFuncFPointerAccessor(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCFuncFPointerAccessor) { return result }
        let outer = GetObjCFuncDecl()
        CJC_NULLPTR_CHECK(outer)
        for (member in outer.getOrThrow().body.getOrThrow().decls) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (funcDecl.identifier.Val() == OBJ_C_FUNC_GET_FPOINTER) {
                    InteropLibBridge.objCFuncFPointerAccessor = Some(funcDecl)
                    break
                }
            }
        }
        return InteropLibBridge.objCFuncFPointerAccessor
    }
    public func GetObjCBlockConstructorFromObjC(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCBlockConstructorFromObjC) { return result }
        let result = GetObjCBlockConstructorByABIName(this, INTEROPLIB_NATIVE_BLOCK_ABI)
        CJC_NULLPTR_CHECK(result)
        InteropLibBridge.objCBlockConstructorFromObjC = result
        return result
    }
    public func GetObjCBlockConstructorFromCangjie(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCBlockConstructorFromCangjie) { return result }
        let result = GetObjCBlockConstructorByABIName(this, INTEROPLIB_CANGJIE_BLOCK_ABI)
        CJC_NULLPTR_CHECK(result)
        InteropLibBridge.objCBlockConstructorFromCangjie = result
        return result
    }
    public func GetObjCBlockFPointerAccessor(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCBlockFPointerAccessor) { return result }
        let outer = GetObjCBlockDecl()
        CJC_NULLPTR_CHECK(outer)
        for (member in outer.getOrThrow().body.getOrThrow().decls) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (funcDecl.identifier.Val() == OBJ_C_FUNC_GET_FPOINTER) {
                    InteropLibBridge.objCBlockFPointerAccessor = Some(funcDecl)
                    break
                }
            }
        }
        return InteropLibBridge.objCBlockFPointerAccessor
    }
    public func GetObjCBlockAbiPointerAccessor(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objCBlockAbiPointerAccessor) { return result }
        let outer = GetObjCBlockDecl()
        CJC_NULLPTR_CHECK(outer)
        for (member in outer.getOrThrow().body.getOrThrow().decls) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (funcDecl.identifier.Val() == OBJ_C_BLOCK_GET_ABI_POINTER) {
                    InteropLibBridge.objCBlockAbiPointerAccessor = Some(funcDecl)
                    break
                }
            }
        }
        return InteropLibBridge.objCBlockAbiPointerAccessor
    }
    public func GetNativeBlockABIDecl(): Option<StructDecl> { return GetInteropLibDecl<StructDecl>(INTEROPLIB_NATIVE_BLOCK_ABI, ASTKind.STRUCT_DECL) }
    public func GetCangjieBlockABIDecl(): Option<StructDecl> { return GetInteropLibDecl<StructDecl>(INTEROPLIB_CANGJIE_BLOCK_ABI, ASTKind.STRUCT_DECL) }
    public func GetObjCStoreLambdaAsBlockDecl(): Option<FuncDecl> { return GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJC_STORE_LAMBDA_AS_BLOCK, ASTKind.FUNC_DECL) }
    public func GetObjCGetLambdaFromBlockDecl(): Option<FuncDecl> { return GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJC_GET_LAMBDA_FROM_BLOCK, ASTKind.FUNC_DECL) }
    public func GetObjectGetClassDecl(): Option<FuncDecl> {
        if (let Some(result) <- InteropLibBridge.objectGetClassDecl) { return result }
        let result = GetInteropLibDecl<FuncDecl>(INTEROPLIB_OBJ_C_OBJECT_GET_CLASS, ASTKind.FUNC_DECL)
        InteropLibBridge.objectGetClassDecl = Some(result)
        return result
    }
    public func IsInteropLibAccessible(importManager: SemaImportManager): Bool { return importManager.GetPackageDecl(INTEROPLIB_PACKAGE_NAME).isSome() }
    public func IsInteropLibAccessible(): Bool { return IsInteropLibAccessible(importManager) }

}

private func GetObjCBlockConstructorByABIName(bridge: InteropLibBridge,
    abiTypeName: String): Option<FuncDecl> {
    let outer = bridge.GetObjCBlockDecl()
    CJC_NULLPTR_CHECK(outer)
    for (member in outer.getOrThrow().body.getOrThrow().decls) {
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            if (!funcDecl.TestAttr(Attribute.CONSTRUCTOR)) { continue }
            if (funcDecl.funcBody.isNone()) { continue }
            let body = funcDecl.funcBody.getOrThrow()
            if (body.paramLists.size != 1 || body.paramLists[0].params.size != 1) { continue }
            let paramTy = body.paramLists[0].params[0].GetTy().getOrThrow()
            if (!paramTy.IsPointer()) { continue }
            let decl = Ty.GetDeclOfTy(paramTy.typeArgs[0])
            CJC_NULLPTR_CHECK(decl)
            if (decl.getOrThrow().identifier.Val() == abiTypeName) { return funcDecl }
        }
    }
    CJC_ABORT()
    return None
}
