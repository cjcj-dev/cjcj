// G10 valid-program negative control: string_concat.

main(): Int64 {
    let x = "hello" + " world"
    if (x != "hello world") { return 1 }
    return 0
}
