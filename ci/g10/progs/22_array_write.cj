// G10 valid-program negative control: array_write.

main(): Int64 {
    let x = [0, 0]
    x[1] = 42
    if (x[1] != 42) { return 1 }
    return 0
}
