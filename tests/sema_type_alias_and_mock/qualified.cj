import aliases
main(): Int64 {
    if (aliases.Chained(257) != UInt16(257)) { return 1 }
    println("QUALIFIED_ALIAS_OK")
    return 0
}
