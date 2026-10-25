package signed_min_control
main(): Int64 {
    let x: Int64 = -127
    let y: Int64 = -1
    if (x % y != 0 || x / y != 127) { return 1 }
    if (-17 % 5 != -2 || -17 / 5 != -3) { return 2 }
    println("ASSERT ordinary_arithmetic=PASS")
    return 0
}
