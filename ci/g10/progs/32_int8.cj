// G10 valid-program negative control: int8.

main(): Int64 {
    let x: Int8 = 42
    if (Int64(x) != 42) { return 1 }
    return 0
}
