package cjcj::ast

import std.collection.*
import std.sync.AtomicUInt32
import cjcj::utils.Identifiable

public struct HashID <: Hashable & Equatable<HashID> {
    public var hash64: UInt64 = 0
    public var fieldID: UInt32 = 0u32

    public init() {}

    public init(hash64: UInt64, fieldID: UInt32) {
        this.hash64 = hash64
        this.fieldID = fieldID
    }

    public operator func ==(right: HashID): Bool {
        return hash64 == right.hash64 && fieldID == right.fieldID
    }

    public operator func !=(right: HashID): Bool {
        return !(this == right)
    }

    public operator func <(right: HashID): Bool {
        return hash64 < right.hash64 || (hash64 == right.hash64 && fieldID < right.fieldID)
    }

    public func hashCode(): Int64 {
        return Int64(hash64 ^ UInt64(fieldID))
    }
}

public class Symbol <: Identifiable {
    public var name: String = ""
    public var id: Option<Symbol> = None
    public var node: Option<Node> = None
    public var scopeName: String = ""
    public var hashID: HashID = HashID()
    public var scopeLevel: UInt32 = 0u32
    public var astKind: ASTKind = ASTKind.NODE
    public var target: Option<Decl> = None
    public var invertedIndexBeenDeleted: Bool = false
    public var isNeedExposedToInterop: Bool = false
    public let children: ArrayList<Symbol> = ArrayList<Symbol>()
    public prop objectId: Int64 {
        get() { Int64(hashID.fieldID) }
    }

    public init() {}

    public init(name: String, node!: Option<Node> = None) {
        this.name = name
        this.node = node
        if (let Some(value) <- node) {
            scopeName = value.scopeName
            scopeLevel = value.scopeLevel
            astKind = value.astKind
            if (let Some(file) <- value.curFile) {
                hashID = SymbolApi.NextHashID(file.fileHash)
            } else {
                hashID = SymbolApi.NextHashID(0)
            }
        }
    }

    public init(fileHash: UInt64, name: String, node: Node, scopeLevel: UInt32, scopeName: String) {
        this.name = name
        id = this
        this.node = node
        this.scopeLevel = scopeLevel
        this.scopeName = scopeName
        astKind = node.astKind
        hashID = SymbolApi.NextHashID(fileHash)
    }

    public func UnbindTarget(): Unit {
        target = None
    }
}

public class SymbolApi {
    private static let ids = AtomicUInt32(UInt32.Max)

    public init() {}

    @OverflowWrapping
    public static func NextHashID(fileHash: UInt64): HashID {
        let fieldID = ids.fetchAdd(1u32) + 1u32
        return HashID(fileHash, fieldID)
    }

    public static func ResetID(): Unit {
        ids.store(UInt32.Max)
    }

    public static func GetName(symbol: Option<Symbol>): String {
        if (let Some(value) <- symbol) {
            return value.name
        }
        return ""
    }
}
