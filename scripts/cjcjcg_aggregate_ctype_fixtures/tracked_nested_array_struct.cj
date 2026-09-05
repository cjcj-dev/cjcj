struct NestedArrayLeaf {
    var x: UInt32
    var y: UInt32
    init(x: UInt32, y: UInt32) { this.x = x; this.y = y }
}

class NestedArrayStructHolder {
    var payload: VArray<VArray<NestedArrayLeaf, $2>, $2> =
        VArray<VArray<NestedArrayLeaf, $2>, $2>({ outer: Int64 =>
            VArray<NestedArrayLeaf, $2>({ inner: Int64 =>
                let seed = UInt32(outer * 2 + inner)
                NestedArrayLeaf(seed + 11u32, seed + 19u32)
            })
        })

    func read(): VArray<VArray<NestedArrayLeaf, $2>, $2> { return payload }
}

main() {
    let copied = NestedArrayStructHolder().read()
    if (copied[0][0].x != 11u32 || copied[1][1].y != 22u32) {
        throw Exception("tracked AS1 nested array-of-struct mismatch")
    }
}
