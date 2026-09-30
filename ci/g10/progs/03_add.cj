// G10 valid-program negative control: add.

main(): Int64 {
    let x = 20 + 22
    if (x != 42) { return 1 }
    return 0
}
