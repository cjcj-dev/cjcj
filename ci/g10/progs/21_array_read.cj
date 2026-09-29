// G10 valid-program negative control: array_read.

main(): Int64 {
    let x = [10, 42, 3]
    if (x[1] != 42) { return 1 }
    return 0
}
