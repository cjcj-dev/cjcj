package std.core

public open class Object {
    public init() {}
}

public interface CType {}

public class Finalized <: Object {
    public init() { super() }
    public init(value: Bool) { this() }
    ~init() {}
}

public func makeFinalized(value: Bool): Object { Finalized(value) }
