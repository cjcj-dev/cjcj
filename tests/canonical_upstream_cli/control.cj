package canonical_control

main(): Int64 {
    let values = [3, 5, 8]
    if (values[0] + values[1] != values[2]) { return 1 }
    println("ASSERT control=PASS")
    return 0
}
