// G10 valid-program negative control: if_else.

main(): Int64 {
    var x = 0
    if (true) { x = 42 } else { x = 7 }
    if (x != 42) { return 1 }
    return 0
}
