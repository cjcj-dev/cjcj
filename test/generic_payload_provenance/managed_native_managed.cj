// Product-lowering shape: blackBox lowers a managed aggregate reference
// through an AS1 -> AS0 -> AS1 round-trip. The ABI then materializes the value,
// so the direct guard rejection is covered by GenericPayloadProvenanceTest.
import std.runtime.blackBox

public struct Pair<T> {
    let left: T
    let right: T

    public init(left: T, right: T) {
        this.left = left
        this.right = right
    }
}

class Holder {
    let pair = Pair<Int64>(7, 8)
}

public func callGeneric<T>(payload: Pair<T>): Unit {
    let _ = payload.left
}

main() {
    let holder = Holder()
    callGeneric<Int64>(blackBox(holder.pair))
}
