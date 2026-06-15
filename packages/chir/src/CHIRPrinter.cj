package cangjie_compiler::chir

public class CHIRPrinter {
    public init() {}

    public func PrintPackage(pkg: Package): String {
        return pkg.ToString()
    }

    public func PrintFunction(fn: Function): String {
        return fn.ToString(0)
    }

    public func PrintBlockGroup(group: BlockGroup): String {
        return group.ToString(0)
    }
}
