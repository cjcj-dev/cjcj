package java.internal

public let INTEROPLIB_VERSION: Int64 = 12

public type JNIEnv_ptr = CPointer<Unit>
public type jobject = CPointer<Unit>

public struct Java_CFFI_JavaEntity {
    public init() {}
    public func asJObject(): jobject {
        CPointer<Unit>()
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
    CPointer<Unit>()
}

public func Java_CFFI_newJavaArray(env: JNIEnv_ptr, jniType: String, length: Int32): Java_CFFI_JavaEntity {
    Java_CFFI_JavaEntity()
}

public func Java_CFFI_swapLocalWithGlobalRef(env: JNIEnv_ptr, localRef: jobject): jobject {
    localRef
}

public func Java_CFFI_JavaEntityJobject(obj: jobject): Java_CFFI_JavaEntity {
    Java_CFFI_JavaEntity()
}

public func Java_CFFI_ensure_not_null(entity: Java_CFFI_JavaEntity): Java_CFFI_JavaEntity {
    entity
}

public func Java_CFFI_isInstanceOf(env: JNIEnv_ptr, entity: Java_CFFI_JavaEntity, name: String): Bool {
    false
}
