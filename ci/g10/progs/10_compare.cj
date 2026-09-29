// G10 valid-program negative control: compare.

main(): Int64 {
    if (!(2 < 3 && 3 >= 3 && 4 != 5)) { return 1 }
    return 0
}
