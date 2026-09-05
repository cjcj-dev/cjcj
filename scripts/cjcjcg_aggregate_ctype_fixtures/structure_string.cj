// Exact std.core StructureString ABI shape, isolated from the known full-core
// static-aggregate bootstrap wall.
@C
struct StructureString {
    let buffer: CPointer<UInt8>
    let length: UIntNative

    init(buffer: CPointer<UInt8>, length: UIntNative) {
        this.buffer = buffer
        this.length = length
    }
}

func structureStringRead(ptr: CPointer<StructureString>): StructureString {
    unsafe { ptr.read() }
}

func structureStringWrite(ptr: CPointer<StructureString>, value: StructureString): Unit {
    unsafe { ptr.write(value) }
}

main() {
    let byte = unsafe { LibC.malloc<UInt8>() }
    let slot = unsafe { LibC.malloc<StructureString>() }
    structureStringWrite(slot, StructureString(byte, UIntNative(23)))
    let copied = structureStringRead(slot)
    if (copied.buffer.toUIntNative() != byte.toUIntNative() || copied.length != UIntNative(23)) {
        throw Exception("StructureString aggregate mismatch")
    }
    unsafe {
        LibC.free(slot)
        LibC.free(byte)
    }
}
