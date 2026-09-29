// G10 valid-program negative control: closure.

main(): Int64 {
    let f = { x: Int64 => x * 2 }
    if (f(21) != 42) { return 1 }
    return 0
}
