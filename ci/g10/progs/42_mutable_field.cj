// G10 valid-program negative control: mutable_field.
class Box { public var value: Int64 = 0 }
main(): Int64 {
    let b = Box()
    b.value = 42
    if (b.value != 42) { return 1 }
    return 0
}
