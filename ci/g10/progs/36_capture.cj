// G10 valid-program negative control: capture.

main(): Int64 {
    let n = 20
    let f = { x: Int64 => x + n }
    if (f(22) != 42) { return 1 }
    return 0
}
