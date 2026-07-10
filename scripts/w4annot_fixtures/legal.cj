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

main() {
    println(stackOnly(40) + countdown(2))
}
