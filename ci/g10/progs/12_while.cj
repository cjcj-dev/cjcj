// G10 valid-program negative control: while.

main(): Int64 {
    var x = 0
    while (x < 42) { x++ }
    if (x != 42) { return 1 }
    return 0
}
