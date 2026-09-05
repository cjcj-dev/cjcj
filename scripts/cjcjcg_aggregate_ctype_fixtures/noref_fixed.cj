struct FixedLeaf {
    var x: UInt32
    var y: UInt32

    init(x: UInt32, y: UInt32) {
        this.x = x
        this.y = y
    }
}

struct FixedNest {
    var leaves: VArray<FixedLeaf, $2>
    var tag: UInt32

    init(seed: UInt32) {
        leaves = VArray<FixedLeaf, $2>({ index: Int64 =>
            FixedLeaf(seed + UInt32(index), seed + UInt32(index) + 1u32)
        })
        tag = seed
    }
}

func fixedArrayControl(value: FixedNest): UInt32 {
    let copied = value
    return copied.tag
}

main() {
    if (fixedArrayControl(FixedNest(7u32)) != 7u32) {
        throw Exception("fixed array mismatch")
    }
}
