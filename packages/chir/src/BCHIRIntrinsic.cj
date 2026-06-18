package cangjie_compiler::chir

public class BCHIRIntrinsic {
    public static func ToByteCodeKind(kind: IntrinsicKind): Int64 {
        return match (kind) {
            case IntrinsicKind.ARRAY_GET_UNCHECKED => 10
            case IntrinsicKind.OBJECT_REFEQ => 40
            case IntrinsicKind.RAW_ARRAY_REFEQ => 41
            case IntrinsicKind.FUNC_REFEQ => 42
            case IntrinsicKind.VARRAY_GET => 60
            case IntrinsicKind.BEGIN_CATCH => 347
            case IntrinsicKind.CJ_CORE_CAN_USE_SIMD => 106
            case _ => -1
        }
    }

    public static func IsReferenceEquality(kind: IntrinsicKind): Bool {
        return kind == IntrinsicKind.OBJECT_REFEQ || kind == IntrinsicKind.RAW_ARRAY_REFEQ ||
            kind == IntrinsicKind.FUNC_REFEQ
    }

    public static func IsReferenceEquality(kind: Int64): Bool {
        return kind == 40 || kind == 41 || kind == 42
    }

    public static func IsArrayGetUnchecked(kind: IntrinsicKind): Bool {
        return kind == IntrinsicKind.ARRAY_GET_UNCHECKED
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
