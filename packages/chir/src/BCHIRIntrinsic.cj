package cangjie_compiler::chir

public class BCHIRIntrinsic {
    public static func IsReferenceEquality(kind: Int64): Bool {
        return kind == 40 || kind == 41 || kind == 42
    }

    public static func IsArrayGetUnchecked(kind: Int64): Bool {
        return kind == 10
    }

    public static func ReferenceEquals(left: InterpreterValue, right: InterpreterValue): Bool {
        if (left.kind == InterpreterValueKind.INULLPTR) {
            return right.kind == InterpreterValueKind.INULLPTR
        }
        if (right.kind == InterpreterValueKind.INULLPTR) {
            return false
        }
        if (left.kind == InterpreterValueKind.IPOINTER && right.kind == InterpreterValueKind.IPOINTER) {
            return IValUtils.Equals(left, right)
        }
        if (left.kind == InterpreterValueKind.IFUNC && right.kind == InterpreterValueKind.IFUNC) {
            return left.GetFunctionIndex() == right.GetFunctionIndex()
        }
        return false
    }
}
