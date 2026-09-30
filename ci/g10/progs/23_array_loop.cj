// G10 valid-program negative control: array_loop.

main(): Int64 {
    var x = 0
    for (v in [10, 12, 20]) { x += v }
    if (x != 42) { return 1 }
    return 0
}
