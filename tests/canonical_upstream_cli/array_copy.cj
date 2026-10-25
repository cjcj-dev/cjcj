package canonical_array_copy

class Cell {
    public let value: Int64
    public init(value: Int64) { this.value = value }
}

func copy<T>(source: Array<T>, target: Array<T>, count: Int64): Unit {
    source.copyTo(target, 1, 2, count)
}

main(args: Array<String>): Int64 {
    if (args.size != 1) { return 1 }
    let count = Int64.parse(args[0])
    if (count < 2) { return 2 }
    let source = Array<Int64>(count + 3, {i => i * 7})
    let target = Array<Int64>(count + 4, {_ => -1})
    copy(source, target, count)
    for (i in 0..count) {
        if (target[i + 2] != source[i + 1]) { return 3 }
    }
    if (target[0] != -1 || target[1] != -1 || target[count + 2] != -1) { return 4 }
    let refs = Array<Cell>(count + 3, {i => Cell(i * 11)})
    let refsTarget = Array<Cell>(count + 4, {_ => Cell(-1)})
    copy(refs, refsTarget, count)
    for (i in 0..count) {
        if (refsTarget[i + 2].value != refs[i + 1].value) { return 5 }
    }
    if (refsTarget[1].value != -1 || refsTarget[count + 2].value != -1) { return 6 }
    // The public API permits overlapping ranges: retain memmove semantics.
    source.copyTo(source, 0, 1, count)
    for (i in 1..count + 1) {
        if (source[i] != (i - 1) * 7) { return 7 }
    }
    source.copyTo(source, 0, 0, 0)
    println("ASSERT array_copy=PASS")
    return 0
}
