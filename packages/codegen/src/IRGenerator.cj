package cangjie_compiler::codegen

public interface IRGeneratorImpl {
    func EmitIR(): Unit
}

public class IRGenerator {
    private let impl: IRGeneratorImpl

    public init(impl: IRGeneratorImpl) {
        this.impl = impl
    }

    public func EmitIR(): Unit {
        impl.EmitIR()
    }
}
