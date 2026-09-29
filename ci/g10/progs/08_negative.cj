// G10 valid-program negative control: negative.

main(): Int64 {
    let x: Int64 = -42
    if (-x != 42) { return 1 }
    return 0
}
