package cangjie_compiler::chir

public enum BCHIRResultKind {
    | OK | TRAP | UNSUPPORTED
}

public class BCHIRResult {
    public let kind: BCHIRResultKind
    public let message: String

    public init(kind: BCHIRResultKind, message!: String = "") {
        this.kind = kind
        this.message = message
    }
}

public class ConstEval {
    public init() {}

    public func Evaluate(expr: Expression): BCHIRResult {
        if (expr.IsConstant()) {
            return BCHIRResult(BCHIRResultKind.OK)
        }
        // TODO(selfhost:CHIR): port BCHIR bytecode interpreter and intrinsic execution semantics.
        return BCHIRResult(BCHIRResultKind.UNSUPPORTED, message: "non-constant CHIR expression evaluation is not ported")
    }
}
