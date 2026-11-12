// Upstream cangjie_compiler !2344: a getOrThrow on a value that was already unwrapped on every path
// reuses the earlier result, including calls lowered as TryApply inside try blocks.
func pick(o: Option<Int64>, k: Int64): Int64 {
    var acc = 0
    try {
        acc += o.getOrThrow()
        if (k > 0) {
            acc += o.getOrThrow() * k
        }
        acc += o.getOrThrow()
    } catch (e: NoneValueException) {
        acc = -1
    }
    return acc
}

main(): Int64 {
    let a = pick(Some(3), 2)
    let b = pick(None, 2)
    if (a == 12 && b == -1) {
        println("GET_OR_THROW_OK")
        return 0
    }
    println("GET_OR_THROW_BAD ${a} ${b}")
    return 1
}
