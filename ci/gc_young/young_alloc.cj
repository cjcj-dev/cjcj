// Minimal young-collection corpus for CI.
// Churn short-lived managed objects so sticky minor can fire many times.
// Pair with MRT_STICKY_MINOR_YOUNG_BYTES=1MiB (see run_gc_young.mjs).

class Cell {
    let a: Int64
    let b: Int64
    let c: Int64
    let d: Int64
    init(x: Int64) {
        a = x
        b = x + 1
        c = x + 2
        d = x + 3
    }
}

main(): Int64 {
    var i: Int64 = 0
    var acc: Int64 = 0
    // ~800k cells * ~48B ≈ 38MiB of short-lived churn.
    while (i < 800000) {
        let cell = Cell(i)
        acc = acc + cell.a + cell.b
        i = i + 1
    }
    println("young_alloc_done ${acc}")
    return 0
}
