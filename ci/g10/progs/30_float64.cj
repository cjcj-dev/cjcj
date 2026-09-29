// G10 valid-program negative control: float64.

main(): Int64 {
    let x: Float64 = 1.5 * 2.0
    if (x != 3.0) { return 1 }
    return 0
}
