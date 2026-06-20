package pkgB2

import pkgA2.*

func score(choice: Choice): Int64 {
    return match (choice) {
        case Empty => 1
        case Num(n) => n
        case Pair(a, b) => a + b
    }
}

main() {
    let meter = Meter(21)
    let describer: Describer = meter
    let store = IntStore(5)
    let cargo = Cargo<Int64>(7)
    let labelBonus = if (describer.describe() == "meter") { 0 } else { 1000 }
    println(meter.doubled() + store.get() + score(Pair(3, 4)) + cargo.get() + labelBonus)
}
