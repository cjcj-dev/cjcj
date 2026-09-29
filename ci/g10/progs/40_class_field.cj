// G10 valid-program negative control: class_field.
class Box { public let value: Int64; init(v: Int64) { value = v } }
main(): Int64 {
    let b = Box(42)
    if (b.value != 42) { return 1 }
    return 0
}
