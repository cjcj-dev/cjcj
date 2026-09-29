// G10 valid-program negative control: remainder.

main(): Int64 {
    let x = 44 % 43
    if (x != 1) { return 1 }
    return 0
}
