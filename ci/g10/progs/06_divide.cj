// G10 valid-program negative control: divide.

main(): Int64 {
    let x = 84 / 2
    if (x != 42) { return 1 }
    return 0
}
