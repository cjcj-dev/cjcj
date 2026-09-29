// G10 valid-program negative control: array_size.

main(): Int64 {
    let x = [1, 2, 3]
    if (x.size != 3) { return 1 }
    return 0
}
