package objc.internal

// Linux front-end fixture only; these declarations do not implement an ObjC runtime.
public type NativeObjCId = CPointer<Unit>
public type NativeObjCClass = CPointer<Unit>
public type NativeObjCSel = CPointer<Unit>
public type NativeObjCSuperPtr = CPointer<Unit>
public type RegistryId = Int64
public struct NativeBlockABI {}
public struct NativeObjCIdMarker {}
public let __NATIVE_OBJC_ID_MARKER = NativeObjCIdMarker()
public func getClass(name: String): NativeObjCClass { CPointer<Unit>() }
public func getProtocol(name: String): NativeObjCId { CPointer<Unit>() }
public func registerName(name: String): NativeObjCSel { CPointer<Unit>() }
public func objCRelease(obj: NativeObjCId): Unit {}
public func objCRetain(obj: NativeObjCId): NativeObjCId { obj }
public func objCRetainAutoreleasedReturnValue(obj: NativeObjCId): NativeObjCId { obj }
public func objCAutorelease(obj: NativeObjCId): NativeObjCId { obj }
public func alloc(name: String): NativeObjCId { CPointer<Unit>() }
public func withAutoreleasePool<T>(action: () -> T): T { action() }
public func withAutoreleasePoolObj(action: () -> NativeObjCId): NativeObjCId { action() }
public func withObjCSuper<T>(obj: NativeObjCId, name: String, action: (NativeObjCId, NativeObjCSuperPtr) -> T): T { action(obj, obj) }
public func objCMsgSend(): CPointer<Unit> { CPointer<Unit>() }
public func objCMsgSendSuper(): CPointer<Unit> { CPointer<Unit>() }
public func getFromRegistryByNativeHandle<T>(obj: NativeObjCId): T { throw Exception("fixture") }
public func getFromRegistryById<T>(id: RegistryId): T { throw Exception("fixture") }
public func putToRegistry<T>(obj: T): RegistryId { 0 }
public func removeFromRegistry(id: RegistryId): Unit {}
public class ObjCUnreachableCodeException <: Exception {}
public class ObjCOptionalMethodUnimplementedException <: Exception {}
public class ObjCStaticMethodCallOnInterfaceException <: Exception {}
public func convertToNSString(value: String): NativeObjCId { CPointer<Unit>() }
public func descriptionAsString(value: NativeObjCId): String { "fixture" }
