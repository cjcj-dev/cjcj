class Item {}

class Holder {
    var item: Item = Item()
}

@NoWriteBarrier
func barrier(holder: Holder, value: Item): Unit {
    holder.item = value
}

main() {
    barrier(Holder(), Item())
}
