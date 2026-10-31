package parallel_lowering

let shared: Int64 = 7
func identity<T>(value: T): T { value }
func pick<T>(first: T, second: T, choose: Bool): T {
    let retained = first
    let fallback = second
    if (choose) { return retained }
    return fallback
}
func genericCapture<T>(value: T): T {
    let retained = value
    let f = { => retained }
    return f()
}
func addShared(value: Int64): Int64 { value + shared }
func branch(value: Int64): Int64 { if (value > 0) { addShared(value) } else { shared } }
func loop(value: Int64): Int64 {
    var result: Int64 = 0
    for (i in 0..value) { result += branch(i) }
    return result
}
func closure(value: Int64): Int64 {
    let f = { x: Int64 => addShared(x) + value }
    return f(identity<Int64>(3))
}
func nested(value: Int64): Int64 {
    func local(x: Int64): Int64 { x * 2 }
    return local(value)
}
func checked(value: Int64): Int64 {
    try {
        if (value == 0) { throw Exception("zero") }
        return identity<Int64>(value)
    } catch (e: Exception) {
        return if (e.message == "zero") { shared } else { -1 }
    }
}
open class Base {
    public init() {}
    public open func read(): Int64 { shared }
}
class Derived <: Base {
    let value: Int64
    public init(value: Int64) { super(); this.value = value }
    public override func read(): Int64 { addShared(value) }
}
func virtualCall(value: Base): Int64 { value.read() }
func arrays(value: Int64): Int64 {
    let values = [value, addShared(value), branch(value)]
    return values[0] + values[1] + values[2]
}
main(): Int64 {
    if (loop(4) != 34) { return 1 }
    if (closure(5) != 15 || nested(6) != 12) { return 2 }
    if (checked(0) != 7 || checked(11) != 11) { return 3 }
    if (virtualCall(Derived(9)) != 16 || arrays(2) != 20) { return 4 }
    if (pick<Int64>(2, 3, true) != 2 || pick<Int64>(2, 3, false) != 3) { return 5 }
    if (genericCapture<Int64>(13) != 13) { return 6 }
    println("PARALLEL_LOWERING_OK")
    return 0
}
