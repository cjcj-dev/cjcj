func classify(x: Int64): String {
    return match (x) {
        case n where n < 0 => "neg"
        case n where n >= 0 && n < 10 => "small"
        case _ => "big"
    }
}

// returns Some for non-negative input, None otherwise
func lookup(x: Int64): Option<Int64> {
    if (x >= 0) {
        return Some(x * 2)
    }
    return None
}

main() {
    println(classify(-3))
    println(classify(5))
    println(classify(99))

    let a = lookup(7)
    let b = lookup(-1)
    println(a?.toString() ?? "nil")
    println(b?.toString() ?? "nil")
}
