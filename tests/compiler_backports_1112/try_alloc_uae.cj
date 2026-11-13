// upstream !2344 (UselessAllocateElimination): an allocation inside try whose object is only written.
class Cell {
    var v: Int64 = 0
}

func work(n: Int64): Int64 {
    var r = 0
    try {
        let c = Cell()
        c.v = n
        r = n + 1
    } catch (e: Exception) {
        r = -1
    }
    return r
}

main(): Int64 {
    println("TRY_ALLOC_OK ${work(41)}")
    return 0
}
