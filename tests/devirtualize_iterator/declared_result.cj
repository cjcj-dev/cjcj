package declared_result

interface Value { func value(): Int64 }
class Closed <: Value { public func value(): Int64 { return 17 } }
func makeClosed(): Closed { return Closed() }
func makeThrowing(fail: Bool): Closed {
    if (fail) { throw Exception() }
    return Closed()
}
public func closedCall(): Int64 {
    let item: Value = makeClosed()
    return item.value()
}
public func throwingCall(fail: Bool): Int64 {
    try {
        let item: Value = makeThrowing(fail)
        return item.value()
    } catch (e: Exception) { return -1 }
}

public open class Open {
    public open func value(): Int64 { return 23 }
}
class Derived <: Open {
    public override func value(): Int64 { return 29 }
}
public func openCall(item: Open): Int64 { return item.value() }
main(): Int64 {
    if (closedCall() != 17 || throwingCall(false) != 17 || throwingCall(true) != -1 ||
        openCall(Open()) != 23 || openCall(Derived()) != 29) { return 1 }
    return 0
}
