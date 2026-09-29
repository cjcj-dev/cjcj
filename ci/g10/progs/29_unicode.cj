// G10 valid-program negative control: unicode.

main(): Int64 {
    let x = "仓颉"
    if (x != "仓颉") { return 1 }
    return 0
}
