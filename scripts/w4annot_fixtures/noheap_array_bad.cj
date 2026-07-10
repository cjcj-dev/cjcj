@NoHeapAlloc
func allocateArray(): Array<Int64> {
    return [1, 2, 3]
}

main() {
    let _ = allocateArray()
}
