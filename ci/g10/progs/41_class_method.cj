// G10 valid-program negative control: class_method.
class Box { let value: Int64; init(v: Int64) { value = v }; func twice(): Int64 { value * 2 } }
main(): Int64 {
    let b = Box(21)
    if (b.twice() != 42) { return 1 }
    return 0
}
