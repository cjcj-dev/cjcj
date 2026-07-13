class Item {}

@NoHeapAlloc
func makeClosure(): () -> Item {
    return { => Item() }
}

main() {
    let _ = makeClosure()
}
