package literal_probe
foreign {
    func recordLibraryInit(tag: Int32): Int64
    func recordLibraryBytes(ptr: CPointer<UInt8>, size: Int64, tag: Int32): Int32
}
let initialized = unsafe { recordLibraryInit(0) }
let message = "plugin-世界"
@C
public func libraryRead(arg: CPointer<Unit>): CPointer<Unit> {
    unsafe {
        let handle = acquireArrayRawData(message.rawData())
        let _ = recordLibraryBytes(handle.pointer, message.size, 0)
        releaseArrayRawData(handle)
    }
    return arg
}
