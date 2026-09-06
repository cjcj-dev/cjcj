func primitiveCopy(): UInt64 {
    let src = [10u8, 20u8, 30u8, 40u8]
    let dst = [0u8, 0u8, 0u8, 0u8]
    src.copyTo(dst, 0, 0, src.size)
    return UInt64(dst[0]) + UInt64(dst[1]) + UInt64(dst[2]) + UInt64(dst[3])
}

main() {
    println("PRIMITIVE_OK ${primitiveCopy()}")
}
