package cangjie_compiler::chir

public class ClosureConversion {
    public init() {}

    public func RunOnPackage(pkg: Package): Unit {
        // TODO(selfhost:CHIR): port closure environment class generation after AST2CHIR and class layout are complete.
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (fn.IsLambda()) {
                fn.EnableAttr(Attribute.THIN)
            }
        }
    }
}
