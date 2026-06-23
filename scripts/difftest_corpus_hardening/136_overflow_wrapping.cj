@OverflowWrapping
func wrapAdd(a: Int8, b: Int8): Int8 {
    return a + b
}

@OverflowSaturating
func satAdd(a: Int8, b: Int8): Int8 {
    return a + b
}

main() {
    // Int8 max is 127; 127 + 1 wraps to -128
    println(wrapAdd(127, 1))
    // saturating clamps to 127
    println(satAdd(127, 1))
}
