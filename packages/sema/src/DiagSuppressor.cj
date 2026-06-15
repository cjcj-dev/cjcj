package cangjie_compiler::sema

public class DiagSuppressor {
    private var suppressed: Bool = false

    public init() {}

    public func Suppress(): Unit {
        suppressed = true
    }

    public func Restore(): Unit {
        suppressed = false
    }

    public func IsSuppressed(): Bool {
        return suppressed
    }
}
