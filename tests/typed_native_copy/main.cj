import typed_copy_values.*

main(): Int64 {
    let first = choosePair(true, 11u64)
    let second = choosePair(false, 13u64)
    if (first.first != 11u64 || first.second != 29u64 || second.first != 17u64 || second.second != 13u64) {
        return 1
    }
    if (chooseByte(true, 37u8).getOrThrow() != 37u8 || !chooseByte(false, 41u8).isNone()) {
        return 2
    }
    println("TYPED_NATIVE_COPY_EXECUTED pair=true option=true")
    let refValue = referenceControl("reference control")
    if (refValue.text != "reference control" || refValue.value != 31u64) {
        return 3
    }
    println("TYPED_REFERENCE_CONTROL_EXECUTED ok=true")
    return 0
}
