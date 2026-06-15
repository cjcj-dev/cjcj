package cangjie_compiler::chir

public class AST2CHIRResult {
    public let pkg: Package

    public init(pkg: Package) {
        this.pkg = pkg
    }
}

public class AST2CHIR {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func CreateEmptyPackage(name: String): AST2CHIRResult {
        // TODO(selfhost:CHIR): replace with typed AST package lowering once chir can depend on real ast/sema packages.
        return AST2CHIRResult(builder.CreatePackage(name))
    }
}

public func ToCHIR(packageName: String, builder: CHIRBuilder): Package {
    // TODO(selfhost:CHIR): mirror C++ ToCHIR(AST::Package, GlobalOptions, ...) public entrypoint.
    return AST2CHIR(builder).CreateEmptyPackage(packageName).pkg
}
