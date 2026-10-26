package canonical_match_guard

enum Choice {
    Left(Int64) | Right(Int64) | Empty
}

func select(value: Choice, accept: Bool): Int64 {
    match (value) {
        case Left(_) | Right(_) where accept =>
            match (value) {
                case Left(n) => n
                case Right(n) => n
                case Empty => throw Exception("guarded payload branch received Empty")
            }
        case Left(n) => n + 10
        case Right(n) => n + 20
        case Empty => -1
    }
}

main(): Int64 {
    if (select(Choice.Left(3), true) != 3) { return 1 }
    if (select(Choice.Right(4), true) != 4) { return 2 }
    if (select(Choice.Left(3), false) != 13) { return 3 }
    if (select(Choice.Right(4), false) != 24) { return 4 }
    if (select(Choice.Empty, true) != -1) { return 5 }
    println("ASSERT match_guard=PASS")
    return 0
}
