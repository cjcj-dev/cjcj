main(): Int64 {
    if (Int64(20.5) != 20 || UInt32(r'a') != 97) { return 1 }
    println("PRIMITIVE_CONTROL_OK")
    return 0
}
