@NoHeapAlloc
func stackOnly(value: Int64): Int64 {
    var local = value
    local++
    return local
}

@NoWriteBarrierRec
func countdown(value: Int64): Int64 {
    if (value <= 0) {
        return 0
    }
    return countdown(value - 1) + 1
}

@NoWriteBarrier
func noBarrier(value: Int64): Int64 {
    return value
}

class Item {}

class Holder {
    var item: Item = Item()
}

func writeThroughHelper(holder: Holder, value: Item): Unit {
    holder.item = value
}

@NoWriteBarrier
func nonRecursiveBarrierScope(holder: Holder, value: Item): Unit {
    writeThroughHelper(holder, value)
}

@NoStackGrow
func noGrow(value: Int64): Int64 {
    return value
}

@SystemStack
func markedSystemStack(value: Int64): Int64 {
    return value
}

main() {
    nonRecursiveBarrierScope(Holder(), Item())
    println(stackOnly(40) + countdown(2) + noBarrier(0) + noGrow(0) + markedSystemStack(0))
}
