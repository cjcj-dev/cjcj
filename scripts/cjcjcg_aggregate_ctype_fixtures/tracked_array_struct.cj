struct ArrayLeaf {
    var x: UInt32
    var y: UInt32
    init(x: UInt32, y: UInt32) { this.x = x; this.y = y }
}

class ArrayStructHolder {
    var payload: VArray<ArrayLeaf, $2> = VArray<ArrayLeaf, $2>({ index: Int64 =>
        ArrayLeaf(UInt32(index) + 3u32, UInt32(index) + 7u32)
    })
    func read(): VArray<ArrayLeaf, $2> { return payload }
}

main() {
    let copied = ArrayStructHolder().read()
    if (copied[0].x != 3u32 || copied[1].y != 8u32) {
        throw Exception("tracked AS1 array-of-aggregate mismatch")
    }
}
