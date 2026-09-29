// G10 valid-program negative control: continue.

main(): Int64 {
    var x = 0
    for (i in 0..5) { if (i == 2) { continue }; x += i }
    if (x != 8) { return 1 }
    return 0
}
