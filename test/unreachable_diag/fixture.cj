// Stage1 fixture for d935a736 unreachable diagnostics.
// Markers are the source lines the checker binds to compiler warnings.

enum Payload {
    | Left(Int64)
    | Right(Int64)
    | Third(Int64)
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
    } else { // else-if false arm
        return 3
    }
}

func matchSplit(): Int64 {
    let value = Left(9)
    match (value) {
        case Left(1) | Left(2) => 1
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
    return die()
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

func matchConstructors(): Int64 {
    let value = Third(9)
    match (value) {
        case Left(1) | Right(2) => 1
        case _ => 0
    }
}
