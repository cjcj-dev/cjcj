package enumzero

public struct Empty {}
public enum NoArgs { Only }
public enum OneEmpty { Only(Empty) }
public enum TwoEmpty { Only(Empty, Empty) }
public enum Nonzero { Only(Int64) }
public enum Generic<T> { Only(T) }

public func noArgs(): NoArgs { NoArgs.Only }
public func oneEmpty(): OneEmpty { OneEmpty.Only(Empty()) }
public func twoEmpty(): TwoEmpty { TwoEmpty.Only(Empty(), Empty()) }
public func nonzero(): Nonzero { Nonzero.Only(42) }
public func generic(): Generic<Empty> { Generic<Empty>.Only(Empty()) }

main(): Int64 {
    let _ = noArgs()
    let _ = oneEmpty()
    let _ = twoEmpty()
    let _ = nonzero()
    let _ = generic()
    return 0
}
