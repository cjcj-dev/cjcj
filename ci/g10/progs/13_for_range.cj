// G10 valid-program negative control: for_range.

main(): Int64 {
    var x = 0
    for (i in 0..7) { x += i }
    if (x != 21) { return 1 }
    return 0
}
