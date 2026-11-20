package local_consumer

import std.runtime.getAllocatedLocalObjectSize

class Cell {
    demode let payload: Int64
    public exclave init(this @local!, n: Int64) { this.payload = n }
    public prop value: Int64 { get() { 0 } }
    public prop value: Int64 @local! { get() { payload } }
    public func read(this @local?): Int64 { return payload }
    public exclave func wireRead(this @local!): Int64 { return payload }
}

var activeBytes: Int64 = -1

func copyValue<T>(x: T @local?): T where T <: Copyable { return x }

func exercise(n: Int64): Int64 {
    let c = Cell(n) @local!
    activeBytes = getAllocatedLocalObjectSize()
    let v = copyValue<Int64>(c.value)
    if (v != c.read() || v != c.wireRead()) { return -1 }
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

var innerBytes: Int64 = -1

func raiseWithCell(n: Int64): Unit {
    let inner = Cell(n) @local!
    if (inner.read() == n) {
        innerBytes = getAllocatedLocalObjectSize()
        throw Exception("inner region")
    }
}

func catchWithCell(n: Int64): Bool {
    let outer = Cell(n) @local!
    let held = getAllocatedLocalObjectSize()
    try {
        raiseWithCell(n + 1)
    } catch (e: Exception) {
        let remaining = getAllocatedLocalObjectSize()
        println("unwind held=${held} inner=${innerBytes} remaining=${remaining}")
        return e.message == "inner region" && innerBytes > held && remaining == held && outer.read() == n
    }
    return false
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
    if (!catchWithCell(51) || getAllocatedLocalObjectSize() != after) { return 25 }
    return 0
}
