func boxInteger(value: Int64): Any {
    return value
}

@NoHeapAlloc
func noHeapBox(value: Int64): Any {
    return boxInteger(value)
}

main() {
    let _ = noHeapBox(1)
}
