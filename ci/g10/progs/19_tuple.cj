// G10 valid-program negative control: tuple.

main(): Int64 {
    let x = (42, true)
    if (x[0] != 42 || !x[1]) { return 1 }
    return 0
}
