class HeapObject {}

@NoHeapAlloc
func allocateObject(): HeapObject {
    return HeapObject()
}

main() {
    let _ = allocateObject()
}
