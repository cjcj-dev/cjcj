@C[align: 16]
struct Aligned {
    var x: UInt8 = 7u8
}
@C[align: 64, packed]
struct PackedAligned {
    var tag: UInt8 = 3u8
    var value: UInt32 = 1000u32
}
@C
struct Outer {
    var prefix: UInt8 = 1u8
    var inner: Aligned = Aligned()
}
@C
struct PackedOuter {
    var prefix: UInt8 = 2u8
    var inner: PackedAligned = PackedAligned()
}
@C[packed]
struct DenseOuter {
    var prefix: UInt8 = 2u8
    var inner: Aligned = Aligned()
}
foreign {
    func c_layout(a: Outer, b: PackedOuter, c: DenseOuter): Int32
    func c_outer(): Outer
}
main(): Int64 {
    if (sizeOf<Outer>() != 32 || alignOf<Outer>() != 16) { return 1 }
    if (sizeOf<PackedOuter>() != 128 || alignOf<PackedOuter>() != 64) { return 2 }
    if (sizeOf<DenseOuter>() != 17 || alignOf<DenseOuter>() != 1) { return 3 }
    unsafe {
        if (c_layout(Outer(), PackedOuter(), DenseOuter()) != 1i32) { return 4 }
        let outer = c_outer()
        if (outer.prefix != 5u8 || outer.inner.x != 9u8) { return 5 }
    }
    println("PASS nested overalign packed layout TI values return")
    return 0
}
