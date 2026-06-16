package cangjie_compiler::chir

public class ValueUseAnalysis {
    public init() {}

    public func CountUses(value: Value): Int64 {
        return value.GetUsersRef().size
    }
}
