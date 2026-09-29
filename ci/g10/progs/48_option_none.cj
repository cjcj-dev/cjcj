// G10 valid-program negative control: option_none.

main(): Int64 {
    let x: ?Int64 = None
    if ((x ?? 42) != 42) { return 1 }
    return 0
}
