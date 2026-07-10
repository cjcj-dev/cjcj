package cjcj::chir

import cjcj::utils.CJC_ABORT
import std.collection.*

public class IValUtils {
    @When[arch == "x86_64" || arch == "aarch64"]
    public static func PrimitiveUIntNat(value: Int64): InterpreterValue {
        return InterpreterValue.MakeUInt(InterpreterValueKind.IUINTNAT, value)
    }

    @When[arch != "x86_64" && arch != "aarch64"]
    public static func PrimitiveUIntNat(value: Int64): InterpreterValue {
        return InterpreterValue.MakeUInt(InterpreterValueKind.IUINTNAT, value & 0xffffffff)
    }

    @When[arch == "x86_64" || arch == "aarch64"]
    public static func PrimitiveIntNat(value: Int64): InterpreterValue {
        return InterpreterValue.MakeInt(InterpreterValueKind.IINTNAT, value)
    }

    @When[arch != "x86_64" && arch != "aarch64"]
    @OverflowWrapping
    public static func PrimitiveIntNat(value: Int64): InterpreterValue {
        return InterpreterValue.MakeInt(InterpreterValueKind.IINTNAT, Int64(Int32(value)))
    }

    public static func FromLiteral(literal: LiteralValue): InterpreterValue {
        if (let Some(value) <- (literal as IntLiteral)) {
            return InterpreterValue.MakeInt(InterpreterValueKind.IINT64, value.value)
        }
        if (let Some(value) <- (literal as FloatLiteral)) {
            return InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT64, value.value)
        }
        if (let Some(value) <- (literal as BoolLiteral)) {
            return InterpreterValue.MakeBool(value.value)
        }
        if (let Some(value) <- (literal as RuneLiteral)) {
            return InterpreterValue.MakeRune(value.value)
        }
        if (let Some(value) <- (literal as StringLiteral)) {
            return InterpreterValue.MakeString(value.value)
        }
        if (literal.IsNullLit()) {
            return InterpreterValue.MakeNull()
        }
        if (literal.IsUnitLit()) {
            return InterpreterValue.MakeUnit()
        }
        return InterpreterValue.MakeInvalid()
    }

    public static func ToLiteral(value: InterpreterValue): Option<LiteralValue> {
        if (let Some(literal) <- value.GetLiteral()) {
            return literal
        }
        if (value.IsIntLike()) {
            return IntLiteral(value.GetInt())
        }
        if (value.IsFloatLike()) {
            return FloatLiteral(value.GetFloat())
        }
        if (value.kind == InterpreterValueKind.IRUNE) {
            return RuneLiteral(Rune(value.GetInt()))
        }
        if (value.kind == InterpreterValueKind.IBOOL) {
            return BoolLiteral(value.GetBool())
        }
        if (value.kind == InterpreterValueKind.ISTRING) {
            return StringLiteral(value.GetText())
        }
        if (value.kind == InterpreterValueKind.IUNIT) {
            return UnitLiteral()
        }
        if (value.kind == InterpreterValueKind.INULLPTR) {
            return NullLiteral()
        }
        return None
    }

    public static func PrimitiveOfType(ty: Type, raw: Int64): InterpreterValue {
        match (ty.GetTypeKind()) {
            case TypeKind.TYPE_UINT8 => return InterpreterValue.MakeUInt(InterpreterValueKind.IUINT8, raw)
            case TypeKind.TYPE_UINT16 => return InterpreterValue.MakeUInt(InterpreterValueKind.IUINT16, raw)
            case TypeKind.TYPE_UINT32 => return InterpreterValue.MakeUInt(InterpreterValueKind.IUINT32, raw)
            case TypeKind.TYPE_ENUM | TypeKind.TYPE_UINT64 =>
                return InterpreterValue.MakeUInt(InterpreterValueKind.IUINT64, raw)
            case TypeKind.TYPE_UINT_NATIVE => return PrimitiveUIntNat(raw)
            case TypeKind.TYPE_INT8 => return InterpreterValue.MakeInt(InterpreterValueKind.IINT8, raw)
            case TypeKind.TYPE_INT16 => return InterpreterValue.MakeInt(InterpreterValueKind.IINT16, raw)
            case TypeKind.TYPE_INT32 => return InterpreterValue.MakeInt(InterpreterValueKind.IINT32, raw)
            case TypeKind.TYPE_INT64 => return InterpreterValue.MakeInt(InterpreterValueKind.IINT64, raw)
            case TypeKind.TYPE_INT_NATIVE => return PrimitiveIntNat(raw)
            case TypeKind.TYPE_FLOAT16 => return InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT16, Float64(raw))
            case TypeKind.TYPE_FLOAT32 => return InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT32, Float64(raw))
            case TypeKind.TYPE_FLOAT64 => return InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT64, Float64(raw))
            case _ => CJC_ABORT()
        }
        return InterpreterValue.MakeNull()
    }

    public static func ToString(value: InterpreterValue): String {
        if (let Some(literal) <- ToLiteral(value)) {
            return literal.ToString()
        }
        return match (value.kind) {
            case InterpreterValueKind.IINVALID => "<invalid>"
            case InterpreterValueKind.IPOINTER => PointerToString(value)
            case InterpreterValueKind.IFUNC => "func@${value.GetFunctionIndex()}"
            case InterpreterValueKind.ITUPLE => "(" + JoinValueStrings(value.GetElementsRef(), ", ") + ")"
            case InterpreterValueKind.IARRAY => "[" + JoinValueStrings(value.GetElementsRef(), ", ") + "]"
            case InterpreterValueKind.IOBJECT => "object#${value.GetClassId()}{" +
                JoinValueStrings(value.GetElementsRef(), ", ") + "}"
            case _ => "${value.GetInt()}"
        }
    }

    public static func Equals(left: InterpreterValue, right: InterpreterValue): Bool {
        if (left.kind != right.kind) {
            if (left.IsIntLike() && right.IsIntLike()) {
                return left.GetInt() == right.GetInt()
            }
            return false
        }
        if (left.IsIntLike()) {
            return left.GetInt() == right.GetInt()
        }
        if (left.IsFloatLike()) {
            return left.GetFloat() == right.GetFloat()
        }
        if (left.kind == InterpreterValueKind.IBOOL) {
            return left.GetBool() == right.GetBool()
        }
        if (left.kind == InterpreterValueKind.IRUNE) {
            return left.GetInt() == right.GetInt()
        }
        if (left.kind == InterpreterValueKind.ISTRING) {
            return left.GetText() == right.GetText()
        }
        if (left.kind == InterpreterValueKind.IUNIT || left.kind == InterpreterValueKind.INULLPTR) {
            return true
        }
        if (left.kind == InterpreterValueKind.IPOINTER) {
            if (left.GetPointerRootKind() != right.GetPointerRootKind() ||
                left.GetPointerIndex() != right.GetPointerIndex()) {
                return false
            }
            let leftPath = left.GetPointerPathRef()
            let rightPath = right.GetPointerPathRef()
            if (leftPath.size != rightPath.size) {
                return false
            }
            var pathIdx: Int64 = 0
            while (pathIdx < leftPath.size) {
                if (leftPath[pathIdx] != rightPath[pathIdx]) {
                    return false
                }
                pathIdx++
            }
            return true
        }
        if (left.kind == InterpreterValueKind.IFUNC) {
            return left.GetFunctionIndex() == right.GetFunctionIndex()
        }
        if (left.kind == InterpreterValueKind.ITUPLE || left.kind == InterpreterValueKind.IARRAY ||
            left.kind == InterpreterValueKind.IOBJECT) {
            let leftItems = left.GetElementsRef()
            let rightItems = right.GetElementsRef()
            if (leftItems.size != rightItems.size) {
                return false
            }
            var idx: Int64 = 0
            while (idx < leftItems.size) {
                if (!Equals(leftItems[idx], rightItems[idx])) {
                    return false
                }
                idx++
            }
            return left.GetClassId() == right.GetClassId()
        }
        return false
    }

    public static func IsTruthy(value: InterpreterValue): Bool {
        if (value.kind == InterpreterValueKind.IBOOL) {
            return value.GetBool()
        }
        if (value.IsIntLike()) {
            return value.GetInt() != 0
        }
        if (value.kind == InterpreterValueKind.INULLPTR || value.kind == InterpreterValueKind.IINVALID) {
            return false
        }
        return true
    }

    public static func StringToArray(text: String): InterpreterValue {
        let items = ArrayList<InterpreterValue>()
        items.add(InterpreterValue.MakeInt(InterpreterValueKind.IINT64, text.size))
        var idx: Int64 = 0
        while (idx < text.size) {
            items.add(InterpreterValue.MakeUInt(InterpreterValueKind.IUINT8, Int64(text[idx])))
            idx++
        }
        return InterpreterValue.MakeArray(items)
    }

    public static func CreateCPointer(address: Int64): InterpreterValue {
        let items = ArrayList<InterpreterValue>()
        items.add(InterpreterValue.MakeUInt(InterpreterValueKind.IUINTNAT, address))
        return InterpreterValue.MakeTuple(items)
    }
}

private func PointerToString(value: InterpreterValue): String {
    let root = match (value.GetPointerRootKind()) {
        case InterpreterPointerRootKind.PARENA => "arena"
        case InterpreterPointerRootKind.PGLOBAL => "global"
        case InterpreterPointerRootKind.PINVALID => "invalid"
    }
    let path = value.GetPointerPathRef()
    if (path.isEmpty()) {
        return "&${root}:${value.GetPointerIndex()}"
    }
    var out = "&${root}:${value.GetPointerIndex()}"
    for (part in path) {
        out += ".${part}"
    }
    return out
}

private func JoinValueStrings(values: ArrayList<InterpreterValue>, sep: String): String {
    var out = ""
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            out += sep
        }
        out += IValUtils.ToString(values[idx])
        idx++
    }
    return out
}
