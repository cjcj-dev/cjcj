package generic_substitution_cli

enum EnumTest<T> {
    Item(T)
}

extend<Y> EnumTest<Y> {
    public func transform<X>(value: X): EnumTest<X> {
        EnumTest<X>.Item(value)
    }
}

func identity<T>(value: T): T { value }
func first<X, Y>(x: X, _: Y): X { x }

main(): Int64 {
    let y = EnumTest<Int64>.Item(17)
    let nested = identity(first(y, y)).transform(y)
    match (nested) {
        case EnumTest<EnumTest<Int64>>.Item(inner) =>
            match (inner) {
                case EnumTest<Int64>.Item(value) =>
                    if (value != 17) { return 1 }
            }
    }
    if (identity<Int64>(31) != 31) { return 2 }
    println("ASSERT generic_substitution=PASS")
    return 0
}
