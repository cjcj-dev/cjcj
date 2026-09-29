// G10 valid-program negative control: nested_array.

main(): Int64 {
    let x = [[1, 2], [42, 3]]
    if (x[1][0] != 42) { return 1 }
    return 0
}
