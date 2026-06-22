private const TYPED_LIMIT: Int64 = 40
public const INFERRED_LIMIT = 2

func value(): Int64 {
    return TYPED_LIMIT + INFERRED_LIMIT
}

main() {
    println(value())
}
