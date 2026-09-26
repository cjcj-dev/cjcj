package devirt_unchecked_cast

public func pickUnchecked(x: Int32): Int64 {
    match (x) {
        case 1 => 10
        case 2 => 20
        case _ => 0
    }
}

main(): Int64 {
    return pickUnchecked(1)
}
