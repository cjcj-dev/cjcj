// G10 valid-program negative control: float32.

main(): Int64 {
    let x: Float32 = 1.5
    if (x + x != 3.0) { return 1 }
    return 0
}
