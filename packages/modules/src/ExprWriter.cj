package cangjie_compiler::modules

import std.collection.*

public class SerializedExpr {
    public var kind: String = ""
    public var value: String = ""
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public let operands: ArrayList<SerializedExpr> = ArrayList<SerializedExpr>()
    public let attributes: HashMap<String, String> = HashMap<String, String>()

    public init() {}

    public init(kind: String) {
        this.kind = kind
    }

    public init(kind: String, value: String) {
        this.kind = kind
        this.value = value
    }
}
