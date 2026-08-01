// Young-collection corpus for CI.
// Official cjc stack-escapes tiny class instances, so short-lived Cell churn
// only ever heap-allocates ~1 region (~1 young under 1MiB). Force heap via
// large Array<UInt8> buffers. Pair with MRT_STICKY_MINOR_YOUNG_BYTES=1MiB.

main(): Int64 {
    var i: Int64 = 0
    var acc: Int64 = 0
    // 200k * 4KiB ≈ 800MiB short-lived heap churn.
    // kkk2 prior (sticky FORCE_SLOW_PATH, 1MiB young): young=43, wall≈12s.
    while (i < 200000) {
        let buf = Array<UInt8>(4096, repeat: UInt8(0))
        buf[0] = UInt8(i % 256)
        buf[4095] = UInt8((i / 256) % 256)
        acc = acc + Int64(buf[0]) + Int64(buf[4095])
        i = i + 1
    }
    println("young_alloc_done ${acc}")
    return 0
}
