class Item {
    let value: Int64
    init(value: Int64) { this.value = value }
}

func exercise<K>(key: K, item: Item): Int64 {
    let source = Array<(Int64, K, Item)>(4, {i => (17 + i, key, item)})
    let cloned = source.clone()
    if (cloned.size != 4 || cloned[3][0] != 20 || cloned[3][2].value != 29) { return 1 }
    println("TUPLE_CLONE_ASSERTION_EXECUTED")
    let ranged = source.clone(1..3)
    if (ranged.size != 2 || ranged[0][0] != 18 || ranged[1][0] != 19) { return 2 }
    println("TUPLE_RANGE_ASSERTION_EXECUTED")
    let dest = Array<(Int64, K, Item)>(5, repeat: (0, key, Item(0)))
    source.copyTo(dest, 1, 2, 2)
    if (dest[1][0] != 0 || dest[2][0] != 18 || dest[3][0] != 19 || dest[4][0] != 0 || dest[3][2].value != 29) { return 3 }
    println("TUPLE_OFFSET_ASSERTION_EXECUTED")
    source.copyTo(dest)
    if (dest[3][0] != 20 || dest[4][0] != 0) { return 4 }
    println("TUPLE_FULL_COPY_ASSERTION_EXECUTED")
    return 0
}

main(args: Array<String>): Int64 {
    if (args.size > 0 && args[0] == "control") {
        let empty = Array<Int64>().clone()
        let ints = Array<Int64>(3, {i => i + 1}).clone()
        let refs = Array<Item>(2, repeat: Item(29)).clone()
        let dest = Array<Int64>(3, repeat: 0)
        ints.copyTo(dest, 1, 1, 1)
        ints.copyTo(dest, 0, 0, 0)
        if (empty.size != 0 || ints[2] != 3 || refs[1].value != 29 || dest[1] != 2 || dest[0] != 0) { return 5 }
        println("ARRAY_COPY_CONTROL_ASSERTION_EXECUTED")
        return 0
    }
    let result = exercise<Int64>(23, Item(29))
    if (result == 0) { println("ARRAY_COPY_SIZE_OK") }
    return result
}
