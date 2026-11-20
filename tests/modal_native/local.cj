package local_consumer

import std.runtime.getAllocatedLocalObjectSize

class Cell {
    let payload: Int64
    public exclave init(this @local!, n: Int64) { this.payload = n }
    public prop value: Int64 { get() { 0 } }
    public prop value: Int64 @local! { get() { payload } }
    public func read(this @local?): Int64 { return payload }
}

var activeBytes: Int64 = -1

func copyValue<T>(x: T @local?): T where T <: Copyable { return x }

func exercise(n: Int64): Int64 {
    let c = Cell(n) @local!
    activeBytes = getAllocatedLocalObjectSize()
    let v = copyValue<Int64>(c.value)
    if (v != c.read()) { return -1 }
    return v
}

func invokeCaptured(f: (() -> Int64) @local?): Int64 { return f() }

func captureParameter(c: Cell @local?): Int64 {
    return invokeCaptured({ => c.read() })
}

func capturedValue(n: Int64): Int64 {
    let c = Cell(n) @local!
    return captureParameter(c)
}

main(): Int64 {
    let before = getAllocatedLocalObjectSize()
    let answer = exercise(73)
    let after = getAllocatedLocalObjectSize()
    println("local before=${before} active=${activeBytes} after=${after} payload=${answer}")
    if (answer != 73) { return 21 }
    if (activeBytes <= before) { return 22 }
    if (after != before) { return 23 }
    if (capturedValue(37) != 37 || getAllocatedLocalObjectSize() != after) { return 24 }
    return 0
}
