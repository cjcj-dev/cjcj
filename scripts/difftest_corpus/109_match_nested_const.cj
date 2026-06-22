enum Mark {
    | X
    | Y
}

func enumNested(o: Option<String>): Int64 {
    return match (o) {
        case Some("a") => 1
        case Some(_) => 2
        case None => 3
    }
}

func tupleNested(t: (String, Int64)): Mark {
    return match (t) {
        case ("a", 1) => Mark.X
        case _ => Mark.Y
    }
}

main() {
    println(enumNested(Some("a")))
    println(enumNested(Some("z")))
    println(enumNested(None))
    println(match (tupleNested(("a", 1))) { case Mark.X => "X"; case Mark.Y => "Y" })
    println(match (tupleNested(("b", 1))) { case Mark.X => "X"; case Mark.Y => "Y" })
}
