package objc.internal

// Front-end fixture only. These definitions model the interop declaration surface;
// their bodies must never be used to claim Objective-C runtime behaviour.
public type NativeObjCId = CPointer<Unit>
public type NativeObjCClass = CPointer<Unit>
public type NativeObjCSel = CPointer<Unit>
public type NativeObjCSuperPtr = CPointer<Unit>
public type RegistryId = Int64
public struct NativeObjCIdMarker {}
public let __NATIVE_OBJC_ID_MARKER = NativeObjCIdMarker()
public struct NativeBlockABI {}
public struct CangjieBlockABI {}
public func getFromRegistryById<T>(id: RegistryId): T {
    throw Exception("front-end fixture: registry access is not executable")
}
public func putToRegistry<T>(value: T): RegistryId { 1 }
public func removeFromRegistry(id: RegistryId): Unit {}
public func getRegistryId(handle: NativeObjCId): RegistryId { 1 }
public func setRegistryId(handle: NativeObjCId, id: RegistryId): Unit {}
public func alloc(name: String): NativeObjCId { CPointer<Unit>() }
public func objCRelease(handle: NativeObjCId): Unit {}
public func objCRetain(handle: NativeObjCId): NativeObjCId { handle }
public func objCAutorelease(handle: NativeObjCId): NativeObjCId { handle }
public func objCRetainAutoreleasedReturnValue(handle: NativeObjCId): NativeObjCId { handle }
