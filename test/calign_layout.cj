@C[align: 64]
struct CacheLineAligned {
    var tag: UInt8 = 0u8
    var value: UInt32 = 0u32
}

@C[packed]
struct PackedOne {
    var tag: UInt8 = 0u8
    var value: UInt32 = 0u32
}

@C[packed: 8]
struct PackedEight {
    var tag: UInt8 = 0u8
    var value: UInt32 = 0u32
}

@C[align: 64, packed]
struct PackedCacheLine {
    var tag: UInt8 = 0u8
    var value: UInt32 = 0u32
}

let globalAligned = CacheLineAligned()

main(): Int64 {
    if (alignOf<CacheLineAligned>() != 64 || sizeOf<CacheLineAligned>() != 64) { return 1 }
    if (alignOf<PackedOne>() != 1 || sizeOf<PackedOne>() != 5) { return 2 }
    if (alignOf<PackedEight>() != 8 || sizeOf<PackedEight>() != 8) { return 3 }
    if (alignOf<PackedCacheLine>() != 64 || sizeOf<PackedCacheLine>() != 64) { return 4 }
    let localAligned = CacheLineAligned()
    if (localAligned.tag != globalAligned.tag) { return 5 }
    println("calign layout ok")
    return 0
}
