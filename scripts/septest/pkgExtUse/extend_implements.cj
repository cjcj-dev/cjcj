import pkgExtIface.*

public struct Token {
    public let id: Int64

    public init(id: Int64) {
        this.id = id
    }
}

extend Token <: Same<Token> {
    public func same(right: Token): Bool {
        return id == right.id
    }
}

main() {
    let left = Token(1)
    let right = Token(1)
    if (left.same(right)) {
        println(1)
    } else {
        println(0)
    }
}
