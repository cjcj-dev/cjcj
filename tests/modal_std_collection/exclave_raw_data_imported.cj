// Both std.core acquireArrayRawData<Byte> overloads, the plain one (array_common.cj:582) and the exclave
// `@local?` one (array_common.cj:588), instantiated in one importing package, as std.fs file.cj:770 does.
func readPlain(buf: Array<Byte>): Int64 {
    unsafe {
        let p: CPointerHandle<Byte> = acquireArrayRawData(buf)
        let v = p.pointer.read(1)
        releaseArrayRawData(p)
        return Int64(v)
    }
}

func readLocal(buf: Array<Byte> @local?): Int64 {
    unsafe {
        let p: CPointerHandle<Byte> @local? = acquireArrayRawData(buf)
        let v = p.pointer.read(2)
        releaseArrayRawData(p)
        return Int64(v)
    }
}

main(): Int64 {
    let data: Array<Byte> = [3u8, 5u8, 7u8]
    let sum = readPlain(data) + readLocal(data)
    println("raw data sum ${sum}")
    return if (sum == 12) { 0 } else { 1 }
}
