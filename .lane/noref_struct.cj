public struct NoRefLeaf {
    var x: Int64
    var y: Int64

    public init(x: Int64, y: Int64) {
        this.x = x
        this.y = y
    }
}

func noRefStructCopy(): Int64 {
    let src = [NoRefLeaf(1, 2), NoRefLeaf(3, 4)]
    let dst = [NoRefLeaf(0, 0), NoRefLeaf(0, 0)]
    src.copyTo(dst, 0, 0, src.size)
    return dst[0].x + dst[0].y + dst[1].x + dst[1].y
}

main() {
    println("NOREF_STRUCT_OK ${noRefStructCopy()}")
}
