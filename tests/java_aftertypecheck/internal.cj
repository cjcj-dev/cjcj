package java.internal

public let INTEROPLIB_VERSION: Int64 = 12

public type jobject = CPointer<Unit>

@C
public struct JNINativeInterface_ {
    public var CallLongMethod: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int64> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int64>(CPointer<Unit>()) }
    public var CallStaticIntMethod: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int32> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int32>(CPointer<Unit>()) }
    public var GetLongField: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int64> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int64>(CPointer<Unit>()) }
    public var GetStaticIntField: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int32> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int32>(CPointer<Unit>()) }
    public var SetLongField: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, Int64) -> Unit> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, Int64) -> Unit>(CPointer<Unit>()) }
    public var SetStaticIntField: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, Int32) -> Unit> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, Int32) -> Unit>(CPointer<Unit>()) }
    public var CallIntMethod: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int32> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int32>(CPointer<Unit>()) }
    public var NewObject: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> jobject> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> jobject>(CPointer<Unit>()) }
    public var NewObjectA: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, CPointer<UInt64>) -> jobject> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, CPointer<UInt64>) -> jobject>(CPointer<Unit>()) }
    public var GetBooleanField: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> UInt8> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> UInt8>(CPointer<Unit>()) }
    public var GetIntField: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int32> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> Int32>(CPointer<Unit>()) }
    public var GetObjectField: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> jobject> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject) -> jobject>(CPointer<Unit>()) }
    public var SetBooleanField: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, UInt8) -> Unit> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, UInt8) -> Unit>(CPointer<Unit>()) }
    public var SetIntField: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, Int32) -> Unit> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, Int32) -> Unit>(CPointer<Unit>()) }
    public var SetObjectField: CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, jobject) -> Unit> =
        unsafe { CFunc<(CPointer<CPointer<JNINativeInterface_>>, jobject, jobject, jobject) -> Unit>(CPointer<Unit>()) }
}

public type JNIEnv_ptr = CPointer<CPointer<JNINativeInterface_>>

public struct Java_CFFI_JavaEntity {
    public init() {}
    public init(v: Bool) {}
    public init(v: Int8) {}
    public init(v: Int16) {}
    public init(v: UInt16) {}
    public init(v: Int32) {}
    public init(v: Int64) {}
    public init(v: Float32) {}
    public init(v: Float64) {}
    public func asJObject(): jobject {
        CPointer<Unit>()
    }
    public func asJValue(): Java_CFFI_JavaEntity {
        this
    }
}

public enum Java_CFFI_JavaEntityKind {
    | JOBJECT
    | JBYTE
    | JSHORT
    | JCHAR
    | JINT
    | JLONG
    | JFLOAT
    | JDOUBLE
    | JBOOLEAN
}

public func Java_CFFI_get_env(): JNIEnv_ptr {
    CPointer<CPointer<JNINativeInterface_>>()
}

public func Java_CFFI_getClass(env: JNIEnv_ptr, name: String): jobject {
    CPointer<Unit>()
}

public func Java_CFFI_getMethodID(env: JNIEnv_ptr, clazz: jobject, name: String, signature: String): jobject {
    CPointer<Unit>()
}

public func Java_CFFI_getStaticMethodID(env: JNIEnv_ptr, clazz: jobject, name: String, signature: String): jobject {
    CPointer<Unit>()
}

public func Java_CFFI_getInstanceFieldId(env: JNIEnv_ptr, clazz: jobject, name: String, signature: String): jobject {
    CPointer<Unit>()
}

public func Java_CFFI_getStaticFieldId(env: JNIEnv_ptr, clazz: jobject, name: String, signature: String): jobject {
    CPointer<Unit>()
}

public func Java_CFFI_newJavaArray(env: JNIEnv_ptr, jniType: String, length: Int32): Java_CFFI_JavaEntity {
    Java_CFFI_JavaEntity()
}

public func Java_CFFI_CangjieStringToJava(env: JNIEnv_ptr, s: String): Java_CFFI_JavaEntity {
    Java_CFFI_JavaEntity()
}

public func Java_CFFI_swapLocalWithGlobalRef(env: JNIEnv_ptr, localRef: jobject): jobject {
    localRef
}

public func Java_CFFI_newGlobalReference(env: JNIEnv_ptr, obj: jobject, isWeak: Bool): jobject {
    obj
}

public func Java_CFFI_deleteGlobalReference(env: JNIEnv_ptr, obj: jobject): Unit {}

public func Java_CFFI_JavaEntityJobject(obj: jobject): Java_CFFI_JavaEntity {
    Java_CFFI_JavaEntity()
}

public func Java_CFFI_ensure_not_null(entity: Java_CFFI_JavaEntity): Java_CFFI_JavaEntity {
    entity
}

public func Java_CFFI_isInstanceOf(env: JNIEnv_ptr, entity: Java_CFFI_JavaEntity, name: String): Bool {
    false
}

public struct Java_CFFI_JClass {}

public struct Java_CFFI_FieldID {}

public func Java_CFFI_ClassInit(env: JNIEnv_ptr, name: String): Java_CFFI_JClass {
    Java_CFFI_JClass()
}

public func Java_CFFI_parseComponentSignature(signature: String): String {
    signature
}

public func Java_CFFI_FieldIDConstr(env: JNIEnv_ptr, clazz: Java_CFFI_JClass, name: String, signature: String): Java_CFFI_FieldID {
    Java_CFFI_FieldID()
}

public func Java_CFFI_setField<T>(env: JNIEnv_ptr, obj: jobject, field: Java_CFFI_FieldID, value: T): Unit {}

public func Java_CFFI_setStaticField<T>(env: JNIEnv_ptr, clazz: Java_CFFI_JClass, field: Java_CFFI_FieldID, value: T): Unit {}

public func handlePendingException(env: JNIEnv_ptr): Unit {}

public func withExceptionHandling<T>(env: JNIEnv_ptr, action: () -> T): T {
    action()
}

public func Java_CFFI_getFromRegistry<T>(env: JNIEnv_ptr, id: Int64): T {
    Java_CFFI_getFromRegistry<T>(env, id)
}

public func Java_CFFI_getFromRegistryOption<T>(id: Int64): Option<T> {
    None<T>
}

public func Java_CFFI_putToRegistry(env: JNIEnv_ptr, entity: Java_CFFI_JavaEntity, obj: Java_CFFI_JavaEntity): Unit {}

public func Java_CFFI_put_to_registry_1(obj: Java_CFFI_JavaEntity): Int64 {
    0
}

public func Java_CFFI_removeFromRegistry(id: Int64): Unit {}

public func Java_CFFI_JavaEntityJobjectNull(): Java_CFFI_JavaEntity {
    Java_CFFI_JavaEntity()
}

public struct Java_CFFI_MethodID {}

public func Java_CFFI_parseMethodSignature(signature: String): String {
    signature
}

public func Java_CFFI_JavaCallNestInit(count: Int64): Int64 {
    count
}

public func Java_CFFI_MethodIDConstr(env: JNIEnv_ptr, clazz: Java_CFFI_JClass, name: String,
    signature: String): Java_CFFI_MethodID {
    Java_CFFI_MethodID()
}

public func Java_CFFI_MethodIDConstrStatic(env: JNIEnv_ptr, clazz: Java_CFFI_JClass, name: String,
    signature: String): Java_CFFI_MethodID {
    Java_CFFI_MethodID()
}

public func Java_CFFI_newJavaObject(env: JNIEnv_ptr, clazz: Java_CFFI_JClass, method: Java_CFFI_MethodID,
    args: Array<Java_CFFI_JavaEntity>, nest: Int64): Java_CFFI_JavaEntity {
    Java_CFFI_JavaEntity()
}

public func Java_CFFI_callMethod(env: JNIEnv_ptr, obj: jobject, method: Java_CFFI_MethodID,
    args: Array<Java_CFFI_JavaEntity>, nest: Int64): Java_CFFI_JavaEntity {
    Java_CFFI_JavaEntity()
}

public func Java_CFFI_callVirtualMethod(env: JNIEnv_ptr, obj: jobject, method: Java_CFFI_MethodID,
    args: Array<Java_CFFI_JavaEntity>, nest: Int64): Java_CFFI_JavaEntity {
    Java_CFFI_JavaEntity()
}

public func Java_CFFI_callStaticMethod(env: JNIEnv_ptr, clazz: Java_CFFI_JClass, method: Java_CFFI_MethodID,
    args: Array<Java_CFFI_JavaEntity>, nest: Int64): Java_CFFI_JavaEntity {
    Java_CFFI_JavaEntity()
}

public func Java_CFFI_unwrapJavaEntityAsValue<T>(entity: Java_CFFI_JavaEntity): T {
    Java_CFFI_unwrapJavaEntityAsValue<T>(entity)
}
