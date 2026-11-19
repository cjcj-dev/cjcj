package wasm_roots

class RootCanary {
    let serial: Int64
    init(serial: Int64) { this.serial = serial }
}

let staticCanary = RootCanary(29)
let staticPair = (17i64, RootCanary(47))

func readCanary(value: RootCanary): Int64 {
    return value.serial
}

func allocateNoise(): Int64 {
    var sum = 0i64
    for (i in 0..32) {
        sum += readCanary(RootCanary(i))
    }
    return sum
}

main(): Int64 {
    let kept = RootCanary(31)
    let sum = allocateNoise()
    let localSerial = readCanary(kept)
    if (sum != 496 || localSerial != 31) { return 81 }
    if (readCanary(staticCanary) != 29 || readCanary(staticPair[1]) != 47) { return 82 }
    println("wasm roots canaries reached")
    return 0
}
