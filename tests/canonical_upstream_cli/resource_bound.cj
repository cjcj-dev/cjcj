package canonical_resource_bound

interface Tagged {
    func tag(): Int64
}

class Handle <: Resource & Tagged {
    public var closes: Int64 = 0
    public func isClosed(): Bool { closes != 0 }
    public func close(): Unit { closes++ }
    public func tag(): Int64 { 19 }
}

func consume<T>(value: T, fail: Bool): Int64 where T <: Tagged & Resource {
    try (r = value) {
        if (fail) { throw Exception("resource body") }
        return r.tag()
    }
}

main(): Int64 {
    let normal = Handle()
    if (consume(normal, false) != 19 || normal.closes != 1) { return 1 }
    let failing = Handle()
    var caught = false
    try {
        consume(failing, true)
    } catch (e: Exception) {
        caught = e.message == "resource body"
    }
    if (!caught || failing.closes != 1) { return 2 }
    println("ASSERT resource_bound=PASS")
    return 0
}
