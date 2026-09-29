// G10 valid-program negative control: option.

main(): Int64 {
    let x: ?Int64 = Some(42)
    let v = x ?? 0
    if (v != 42) { return 1 }
    return 0
}
