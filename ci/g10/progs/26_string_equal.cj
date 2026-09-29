// G10 valid-program negative control: string_equal.

main(): Int64 {
    let x = "hello"
    if (x != "hello") { return 1 }
    return 0
}
