// G10 valid-program negative control: interpolation.

main(): Int64 {
    let x = 42
    if ("value=${x}" != "value=42") { return 1 }
    return 0
}
