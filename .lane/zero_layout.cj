public struct ZeroLayout {
    public init() {}
}

func zeroLayoutCopy(): Int64 {
    let src = [ZeroLayout(), ZeroLayout()]
    let dst = [ZeroLayout(), ZeroLayout()]
    src.copyTo(dst, 0, 0, src.size)
    return dst.size
}

main() {
    println("ZERO_LAYOUT_OK ${zeroLayoutCopy()}")
}
