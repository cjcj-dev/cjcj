// !2344 target path: the TryAllocate result is only stored into a local slot.
// The success edge must be reconnected after the allocation and its Store are
// removed; the value is never returned or passed to a call.
class Cell {
    var value: Int64 = 0
}

func work(n: Int64): Int64 {
    var slot = Cell()
    try {
        slot = Cell()
        slot.value = n
        return n + 1
    } catch (e: Exception) {
        return -1
    }
}

main(): Int64 {
    println("TRY_ALLOC_ONLY_WRITTEN_OK ${work(41)}")
    return 0
}
