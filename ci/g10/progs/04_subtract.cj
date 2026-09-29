// G10 valid-program negative control: subtract.

main(): Int64 {
    let x = 50 - 8
    if (x != 42) { return 1 }
    return 0
}
