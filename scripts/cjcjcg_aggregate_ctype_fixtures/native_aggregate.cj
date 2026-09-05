@C
struct NativePair {
    var buf: CPointer<UInt8>
    var len: UIntNative

    init(buf: CPointer<UInt8>, len: UIntNative) {
        this.buf = buf
        this.len = len
    }
}

func nativeRead(ptr: CPointer<NativePair>): NativePair {
    unsafe { ptr.read() }
}

func nativeWrite(ptr: CPointer<NativePair>, value: NativePair): Unit {
    unsafe { ptr.write(value) }
}

func nativeArrayRead(ptr: CPointer<VArray<UInt32, $2>>): VArray<UInt32, $2> {
    unsafe { ptr.read() }
}

func nativeArrayWrite(ptr: CPointer<VArray<UInt32, $2>>, value: VArray<UInt32, $2>): Unit {
    unsafe { ptr.write(value) }
}

main() {
    let byte = unsafe { LibC.malloc<UInt8>() }
    let pair = unsafe { LibC.malloc<NativePair>() }
    nativeWrite(pair, NativePair(byte, UIntNative(11)))
    let copied = nativeRead(pair)
    if (copied.buf.toUIntNative() != byte.toUIntNative() || copied.len != UIntNative(11)) {
        throw Exception("native aggregate mismatch")
    }
    let array = unsafe { LibC.malloc<VArray<UInt32, $2>>() }
    nativeArrayWrite(array, VArray<UInt32, $2>({ index: Int64 => if (index == 0) { 7u32 } else { 9u32 } }))
    let copiedArray = nativeArrayRead(array)
    if (copiedArray[0] != 7u32 || copiedArray[1] != 9u32) {
        throw Exception("native fixed-array mismatch")
    }
    unsafe {
        LibC.free(array)
        LibC.free(pair)
        LibC.free(byte)
    }
}
