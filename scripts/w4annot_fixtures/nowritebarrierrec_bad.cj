class Item {}

class Holder {
    var item: Item

    init(value: Item) {
        item = value
    }
}

func makeHolder(value: Item): Holder {
    return Holder(value)
}

@NoWriteBarrierRec
func barrierRoot(value: Item): Holder {
    return makeHolder(value)
}

main() {
    let _ = barrierRoot(Item())
}
