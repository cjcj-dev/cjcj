public enum MatchKind {
    | Zero
    | One
    | Two
}

public func indexOf(kind: MatchKind): Int64 {
    return match (kind) {
        case MatchKind.Zero => 0
        case MatchKind.One => 1
        case MatchKind.Two => 2
    }
}

main() {
    println(indexOf(MatchKind.Two) * 20 + indexOf(MatchKind.One) + 1)
}
