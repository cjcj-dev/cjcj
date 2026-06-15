package cangjie_compiler::modules

public class ASTLoaderCJMP {
    public init() {}

    public func PreloadCommonPart(loader: ASTLoader, pkg: Package): Bool {
        return loader.PreloadCommonPartOfPackage(pkg)
    }
}
