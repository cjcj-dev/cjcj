func nestedReturn(x: Int64): Int64 {
    return match (x) {
        case 1 => return 1
        case _ => return 0
    }
    return 9
}
main() { println(nestedReturn(1)) }
