// G10 valid-program negative control: struct.
struct Pair { let a: Int64; let b: Int64; init(x: Int64, y: Int64) { a = x; b = y }; func sum(): Int64 { a + b } }
main(): Int64 {
    let b = Pair(20, 22)
    if (b.sum() != 42) { return 1 }
    return 0
}
