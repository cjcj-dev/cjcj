enum E { A | B | C }

func stringEnumLet(s: String): E {
    let mapped = match (s) {
        case "a" => E.A
        case "b" => E.B
        case _ => E.C
    }
    return mapped
}

func stringEnumReturn(s: String): E {
    return match (s) {
        case "a" => E.A
        case "b" => E.B
        case _ => E.C
    }
}

func intEnumLet(x: Int64): E {
    let mapped = match (x) { case 0 => E.A; case 1 => E.B; case _ => E.C }
    return mapped
}

func stringIntLet(s: String): Int64 {
    let mapped = match (s) { case "a" => 1; case "b" => 2; case _ => 3 }
    return mapped
}

func show(e: E): Unit {
    match (e) {
        case A => println("A")
        case B => println("B")
        case C => println("C")
    }
}

main() {
    show(stringEnumLet("a"))
    show(stringEnumLet("b"))
    show(stringEnumLet("z"))
    show(stringEnumReturn("a"))
    show(intEnumLet(1))
    println(stringIntLet("z"))
}
