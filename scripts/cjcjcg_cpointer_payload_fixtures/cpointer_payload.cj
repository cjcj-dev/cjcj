// Product fixture for the generic CPointer read/write lowering.
public func readGeneric<T>(pointer: CPointer<T>, index: Int64): T where T <: CType {
    unsafe { pointer.read(index) }
}

public func writeGeneric<T>(pointer: CPointer<T>, index: Int64, value: T): Unit where T <: CType {
    unsafe { pointer.write(index, value) }
}

main() {
    let integers = unsafe { LibC.malloc<Int64>(count: 2) }
    let pointers = unsafe { LibC.malloc<CPointer<Unit>>() }
    writeGeneric<Int64>(integers, 1, 42)
    writeGeneric<CPointer<Unit>>(pointers, 0, CPointer<Unit>())
    let integer = readGeneric<Int64>(integers, 1)
    let pointer = readGeneric<CPointer<Unit>>(pointers, 0)
    if (integer != 42 || !pointer.isNull()) {
        throw IllegalStateException("generic CPointer payload identity failed")
    }
    println("CPOINTER_PAYLOAD_OK")
    unsafe {
        LibC.free(integers)
        LibC.free(pointers)
    }
}
