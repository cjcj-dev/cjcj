// G10 valid-program negative control: break.

main(): Int64 {
    var x = 0
    while (true) { x++; if (x == 42) { break } }
    if (x != 42) { return 1 }
    return 0
}
