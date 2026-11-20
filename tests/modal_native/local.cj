package local_consumer

import std.runtime.getAllocatedLocalObjectSize

class Cell {
    let payload: Int64
    public exclave init(this @local!, n: Int64) { this.payload = n }
    public func read(this @local?): Int64 { return payload }
}

var activeBytes: Int64 = -1

func exercise(n: Int64): Int64 {
    let c = Cell(n) @local!
    activeBytes = getAllocatedLocalObjectSize()
    return c.read()
}

main(): Int64 {
    let before = getAllocatedLocalObjectSize()
    let answer = exercise(73)
    let after = getAllocatedLocalObjectSize()
    println("local before=${before} active=${activeBytes} after=${after} payload=${answer}")
    if (answer != 73) { return 21 }
    if (activeBytes <= before) { return 22 }
    if (after != before) { return 23 }
    return 0
}
