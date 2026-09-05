struct ArrayEnvelope {
    var items: VArray<UInt32, $3>
    var tag: UInt32

    init(items: VArray<UInt32, $3>, tag: UInt32) {
        this.items = items
        this.tag = tag
    }
}

class StructArrayHolder {
    var payload: ArrayEnvelope = ArrayEnvelope(
        VArray<UInt32, $3>({ index: Int64 => UInt32(index) + 31u32 }), 47u32)

    func readItems(): VArray<UInt32, $3> { return payload.items }
}

main() {
    let copied = StructArrayHolder().readItems()
    if (copied[0] != 31u32 || copied[2] != 33u32) {
        throw Exception("tracked AS1 struct-of-array mismatch")
    }
}
