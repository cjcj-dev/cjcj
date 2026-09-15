package literal_control
import std.runtime.gc
foreign {
    func recordLibraryInit(tag: Int32): Int64
    func recordLibraryBytes(ptr: CPointer<UInt8>, size: Int64, tag: Int32): Int32
    func recordLibraryGC(): Unit
}
let initialized = unsafe { recordLibraryInit(1) }
let message = "control-世界"
@C
public func controlRead(arg: CPointer<Unit>): CPointer<Unit> {
    unsafe {
        let handle = acquireArrayRawData(message.rawData())
        let _ = recordLibraryBytes(handle.pointer, message.size, 1)
        releaseArrayRawData(handle)
    }
    return arg
}
@C
public func libraryGC(arg: CPointer<Unit>): CPointer<Unit> {
    gc(heavy: true)
    unsafe { recordLibraryGC() }
    return arg
}
