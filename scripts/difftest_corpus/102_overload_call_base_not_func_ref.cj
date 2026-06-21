struct Position {}
struct Range {}

func getPos(): Position {
    return Position()
}

func currentChar(): String {
    return "x"
}

func diagnose(pos: Position, arg: String): Int64 {
    return 7
}

func diagnose(range: Range, arg: String): Int64 {
    return 11
}

main(): Int64 {
    println(diagnose(getPos(), currentChar()))
    return 0
}
