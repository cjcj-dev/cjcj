package flatbuffer_borrowing_plugin

// CHIR.cpp:1225-1251 keeps ExecutePlugin's detached input alive through
// DeserializePluginResult and FreeCachedData. A plugin may return that span.
@C
public struct PluginResult {
    public let data: CPointer<UInt8>
    public let size: Int64
    public let success: Bool

    public init(data: CPointer<UInt8>, size: Int64, success: Bool) {
        this.data = data
        this.size = size
        this.success = success
    }
}

var borrowed: CPointer<UInt8> = CPointer<UInt8>()
var snapshot: Array<UInt8> = []

@C
public func executeCHIRPlugins(data: CPointer<UInt8>, size: Int64): PluginResult {
    borrowed = data
    snapshot = Array<UInt8>(size, { i => unsafe { data.read(i) } })
    println("ASSERT plugin received serialized input: ${size > 4}")
    return PluginResult(data, size, size > 4)
}

@C
public func freeSerializedMemory(): Unit {
    var same = true
    for (i in 0..snapshot.size) {
        if (unsafe { borrowed.read(i) } != snapshot[i]) { same = false }
    }
    println("ASSERT plugin borrowed input survived deserialization: ${same}")
    // The input belongs to the compiler, so this plugin has no allocation to free.
    snapshot = []
    borrowed = CPointer<UInt8>()
}
