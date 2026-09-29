// G10 valid-program negative control: nested_loop.

main(): Int64 {
    var x = 0
    for (i in 0..6) { for (j in 0..7) { x++ } }
    if (x != 42) { return 1 }
    return 0
}
