package canonical_struct_store

struct Inner {
    public var value: Int64
    public init(value: Int64) { this.value = value }
    public mut func set(value: Int64): Unit { this.value = value }
}

struct Outer {
    public var inner: Inner
    public let fixed: Int64
    public init(value: Int64) { inner = Inner(value); fixed = 17 }
    public mut func set(value: Int64): Unit { inner.set(value) }
}

func read(value: Outer): Int64 { value.inner.value }

main(args: Array<String>): Int64 {
    if (args.size != 1) { return 1 }
    let input = Int64.parse(args[0])
    var value = Outer(3)
    let original = value
    if (read(value) != 3) { return 2 }
    value.inner.value = input
    if (read(value) != input || read(original) != 3) { return 3 }
    value.inner.set(input + 1)
    if (read(value) != input + 1) { return 4 }
    value.set(input + 2)
    if (read(value) != input + 2 || value.fixed != 17) { return 5 }
    println("ASSERT struct_store=PASS")
    return 0
}
