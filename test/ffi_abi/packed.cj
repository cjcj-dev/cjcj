@C[packed]
struct Packed { var tag: UInt8 = 3u8; var value: UInt32 = 1000u32 }
foreign {
    func c_storage(): CPointer<Packed>
    func c_check(): Int32
    func c_packed_roundtrip(p: Packed): Packed
    func c_packed_callbacks(): Int32
    func c_get_packed(): CFunc<(Packed) -> Packed>
}
@C
func cj_packed_write(p: CPointer<Packed>): UInt32 {
    unsafe {
        var v = p.read()
        let old = v.value
        v.tag = 5u8
        v.value = old + 11u32
        p.write(v)
        return old
    }
}
@C
func cj_packed_return(p: Packed): Packed { var v = p; v.value = p.value + 13u32; return v }
main(): Int64 {
    unsafe {
        let p = c_storage()
        if (cj_packed_write(p) != 1000u32 || c_check() != 1i32) { println("FAIL packed unaligned read write copy"); return 1 }
        let v = c_packed_roundtrip(Packed())
        if (v.tag != 3u8 || v.value != 1013u32) { println("FAIL packed roundtrip"); return 2 }
        if (c_packed_callbacks() != 1i32) { println("FAIL packed callbacks"); return 3 }
        let indirect = c_get_packed()(Packed())
        if (indirect.tag != 3u8 || indirect.value != 1013u32) { println("FAIL packed indirect sret"); return 4 }
    }
    println("PASS packed unaligned read write copy args return")
    return 0
}
