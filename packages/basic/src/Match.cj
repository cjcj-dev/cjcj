package cangjie_compiler::basic

public class Matcher<T> {
    private let node: T

    public init(node: T) {
        this.node = node
    }

    public func value(): T {
        return node
    }
}

public func matchNode<T>(node: T): Matcher<T> {
    return Matcher<T>(node)
}
