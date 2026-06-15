package cangjie_compiler::modules

import std.collection.*

public class SerializationMapping {
    private let declToIndex: HashMap<String, FormattedIndex> = HashMap<String, FormattedIndex>()
    private let indexToDecl: HashMap<FormattedIndex, String> = HashMap<FormattedIndex, String>()

    public init() {}

    public func PutDecl(name: String, index: FormattedIndex): Unit {
        declToIndex[name] = index
        indexToDecl[index] = name
    }

    public func GetDeclIndex(name: String): Option<FormattedIndex> {
        return declToIndex.get(name)
    }

    public func GetDeclName(index: FormattedIndex): Option<String> {
        return indexToDecl.get(index)
    }
}
