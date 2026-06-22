func classify(x: Int64): Unit {
    match (x) {
        case 0 => return
        case _ => println("nonzero")
    }
}

func sign(x: Int64): Unit {
    match (x) {
        case 0 => return
        case 1 => println("one")
        case _ => return
    }
}

main() {
    classify(0)
    classify(7)
    sign(0)
    sign(1)
    sign(2)
}
