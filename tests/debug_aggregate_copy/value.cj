package debug_value

struct Offset<T> {
    let o: UInt32
    init() { o = 0u32 }
    init(o: UInt32) { this.o = o }
    func Union(): Offset<Any> { return Offset<Any>(o) }
    func IsNull(): Bool { return o == 0u32 }
}

main(): Int64 {
    let a = Offset<Int64>(0x12345678u32)
    let b = a.Union()
    if (a.IsNull() || b.IsNull() || !Offset<Any>().IsNull() || b.o != 0x12345678u32) {
        println("ASSERT generic_struct_value=FAIL")
        return 1
    }
    println("ASSERT generic_struct_value=PASS value=${b.o}")
    return 0
}
