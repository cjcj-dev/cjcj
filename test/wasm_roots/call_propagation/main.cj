package wasm_call_roots

class CallCanary {
    let serial: Int64
    init(serial: Int64) { this.serial = serial }
}

private func serialOf(value: CallCanary): Int64 {
    return value.serial
}

private func newCanary(serial: Int64): CallCanary {
    return CallCanary(serial)
}

private func allocateNoise(): Int64 {
    var sum = 0i64
    for (i in 0..32) {
        sum += serialOf(CallCanary(i))
    }
    return sum
}

private func keepArgument(value: CallCanary): Int64 {
    let sum = allocateNoise()
    return sum + serialOf(value)
}

private func keepResult(): Int64 {
    let kept = newCanary(31)
    let sum = allocateNoise()
    return sum + serialOf(kept)
}

main(): Int64 {
    if (keepArgument(newCanary(47)) != 543 || keepResult() != 527) { return 83 }
    println("wasm call roots canaries reached")
    return 0
}
