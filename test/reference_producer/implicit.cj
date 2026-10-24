package std.core

public open class Object {
    public init() {}
}

public interface CType {}

public class Finalized {
    ~init() {}
}

public func makeFinalized(): Object { Finalized() }
