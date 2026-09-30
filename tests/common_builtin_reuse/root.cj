package std.core

public open class Object {
    public const init() {}
}

public interface CType {}

public open class Middle <: Object {
    public init() { super() }
}

public class Finalized <: Middle {
    public init() { super() }
    ~init() {}
}

public class Plain <: Object {
    public init() { super() }
}

public func makeFinalized(): Object { Finalized() }
public func makePlain(): Object { Plain() }
