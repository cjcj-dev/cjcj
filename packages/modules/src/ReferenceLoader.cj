package cangjie_compiler::modules

public class ReferenceLoader {
    public init() {}

    public func LoadReference(reference: String): String {
        // TODO(selfhost:Modules): resolve serialized cross-package references to AST declarations and types.
        return reference
    }
}
