package objc.internal
public type NativeObjCId = CPointer<Unit>
public type NativeObjCClass = CPointer<Unit>
public type NativeObjCSel = CPointer<Unit>
public struct NativeBlockABI {}
public func objCRelease(p: NativeObjCId): Unit {}
public func objCRetain(p: NativeObjCId): NativeObjCId { p }
public func getClass(name: String): NativeObjCClass { CPointer<Unit>() }
public class ObjCStaticMethodCallOnInterfaceException <: Exception {
    public init() { super() }
}
public class ObjCUnreachableCodeException <: Exception {
    public init() { super() }
}
public func getProtocol(name: String): NativeObjCClass { CPointer<Unit>() }
