package cangjie_compiler::modules

import std.collection.*

public class IncrementalLoader {
    public init() {}

    public func LoadRemovedMangles(): HashSet<String> {
        // TODO(selfhost:Modules): read incremental removed-mangle records from serialized AST cache data.
        return HashSet<String>()
    }
}
