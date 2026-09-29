// G10 valid-program negative control: multiply.

main(): Int64 {
    let x = 6 * 7
    if (x != 42) { return 1 }
    return 0
}
