// G10 valid-program negative control: uint64.

main(): Int64 {
    let x: UInt64 = 42
    if (x != 42) { return 1 }
    return 0
}
