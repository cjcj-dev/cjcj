package wasm_cfg_roots

class BranchCanary {
    let serial: Int64
    init(serial: Int64) { this.serial = serial }
}

private func serialOf(value: BranchCanary): Int64 {
    return value.serial
}

private func allocateNoise(seed: Int64): Int64 {
    var sum = seed
    for (i in 0..8) {
        sum += serialOf(BranchCanary(i))
    }
    return sum
}

private func keepAcrossBlocks(value: BranchCanary, flag: Bool): Int64 {
    let before = allocateNoise(1)
    var chosen = 0i64
    if (flag) {
        chosen = allocateNoise(10) + serialOf(value)
    } else {
        chosen = allocateNoise(20) + serialOf(value)
    }
    return before + chosen + serialOf(value)
}

private func deadOnOneEdge(value: BranchCanary, flag: Bool): Int64 {
    if (flag) {
        return allocateNoise(30) + serialOf(value)
    }
    return allocateNoise(40)
}

main(): Int64 {
    let value = BranchCanary(17)
    if (keepAcrossBlocks(value, true) != 101 || keepAcrossBlocks(value, false) != 111 ||
        deadOnOneEdge(value, true) != 75 || deadOnOneEdge(value, false) != 68) {
        return 83
    }
    println("wasm CFG roots canaries reached")
    return 0
}
