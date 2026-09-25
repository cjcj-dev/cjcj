// Stage1 fixture for d935a736 unreachable diagnostics.
// Markers are the source lines the checker binds to compiler warnings.

enum Payload {
    | Left(Int64)
    | Right(Int64)
}

func reachable(x: Int64): Int64 {
    if (x == 1) {
        return 1
    } else {
        return 2
    }
}

func elseIfArms(): Int64 {
    if (true) {
        return 1
    } else if (false) {
        return 2
    } else {
        return 3
    }
}

func matchOnce(value: Payload): Int64 {
    match (value) {
        case Left(_) | Right(_) if true => 1
        case Left(0) | Right(0) => 2
        case _ => 0
    }
}

func afterReturn(x: Int64): Int64 {
    return match (x) {
        case 1 => return 1
        case _ => return 0
    }
    return 9
}

func die(): Nothing {
    while (true) {
    }
}

func keepLater(first: Int64, later: Int64): Int64 {
    return first + later
}

func nothingLater(): Int64 {
    keepLater(die(), 7)
    return 0
}

main() {
    println(reachable(1))
}
