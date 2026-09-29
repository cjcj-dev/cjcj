// G10 valid-program negative control: boolean.

main(): Int64 {
    let x = true && !false
    if (!x) { return 1 }
    return 0
}
