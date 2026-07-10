@NoHeapAlloc
func boxInteger(value: Int64): Any {
    return value
}

main() {
    let _ = boxInteger(1)
}
