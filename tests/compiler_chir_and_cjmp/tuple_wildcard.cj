// Upstream cangjie_compiler !2359: rows whose head is a tuple of wildcards must survive wildcard
// specialization, otherwise this exhaustive match is reported as non-exhaustive.
func classify(x: (Int64, Int64), b: Bool): Int64 {
    match ((x, b)) {
        case ((_, _), true) => 1
        case ((_, _), false) => 2
    }
}

func nested(v: ((Int64, (Bool, Int64)), Bool)): Int64 {
    match (v) {
        case ((_, (_, _)), true) => 10
        case ((0, _), false) => 20
        case ((_, (_, _)), false) => 30
    }
}

main(): Int64 {
    let r = classify((1, 2), true) + classify((3, 4), false) + nested(((0, (true, 1)), false)) + nested(((5, (false, 2)), false))
    if (r == 53) {
        println("TUPLE_WILDCARD_OK")
        return 0
    }
    println("TUPLE_WILDCARD_BAD ${r}")
    return 1
}
