package cangjie_compiler::chir

public class CHIRSerializer {
    public init() {}

    public func SerializePackage(pkg: Package): String {
        return CHIRSerializerImpl().SerializePackage(pkg)
    }

    public func SerializePackage(pkg: Package, context: CHIRContext): String {
        return CHIRSerializerImpl().SerializePackage(pkg, context)
    }
}
