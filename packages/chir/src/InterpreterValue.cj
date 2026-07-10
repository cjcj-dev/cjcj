package cjcj::chir

import std.collection.*

public enum InterpreterValueKind {
    | IINVALID
    | IUINT8 | IUINT16 | IUINT32 | IUINT64 | IUINTNAT
    | IINT8 | IINT16 | IINT32 | IINT64 | IINTNAT
    | IFLOAT16 | IFLOAT32 | IFLOAT64
    | IRUNE | IBOOL | IUNIT | INULLPTR | ISTRING
    | IPOINTER | ITUPLE | IARRAY | IOBJECT | IFUNC
}

public enum InterpreterPointerRootKind {
    | PINVALID | PARENA | PGLOBAL
}

public func InterpreterPointerRootKindIndex(kind: InterpreterPointerRootKind): Int64 {
    return match (kind) {
        case InterpreterPointerRootKind.PINVALID => 0
        case InterpreterPointerRootKind.PARENA => 1
        case InterpreterPointerRootKind.PGLOBAL => 2
    }
}

extend InterpreterPointerRootKind <: Equatable<InterpreterPointerRootKind> {
    public operator func ==(right: InterpreterPointerRootKind): Bool {
        return InterpreterPointerRootKindIndex(this) == InterpreterPointerRootKindIndex(right)
    }

    public operator func !=(right: InterpreterPointerRootKind): Bool {
        return !(this == right)
    }
}

public func InterpreterValueKindIndex(kind: InterpreterValueKind): Int64 {
    return match (kind) {
        case InterpreterValueKind.IINVALID => 0
        case InterpreterValueKind.IUINT8 => 1
        case InterpreterValueKind.IUINT16 => 2
        case InterpreterValueKind.IUINT32 => 3
        case InterpreterValueKind.IUINT64 => 4
        case InterpreterValueKind.IUINTNAT => 5
        case InterpreterValueKind.IINT8 => 6
        case InterpreterValueKind.IINT16 => 7
        case InterpreterValueKind.IINT32 => 8
        case InterpreterValueKind.IINT64 => 9
        case InterpreterValueKind.IINTNAT => 10
        case InterpreterValueKind.IFLOAT16 => 11
        case InterpreterValueKind.IFLOAT32 => 12
        case InterpreterValueKind.IFLOAT64 => 13
        case InterpreterValueKind.IRUNE => 14
        case InterpreterValueKind.IBOOL => 15
        case InterpreterValueKind.IUNIT => 16
        case InterpreterValueKind.INULLPTR => 17
        case InterpreterValueKind.ISTRING => 18
        case InterpreterValueKind.IPOINTER => 19
        case InterpreterValueKind.ITUPLE => 20
        case InterpreterValueKind.IARRAY => 21
        case InterpreterValueKind.IOBJECT => 22
        case InterpreterValueKind.IFUNC => 23
    }
}

extend InterpreterValueKind <: Equatable<InterpreterValueKind> {
    public operator func ==(right: InterpreterValueKind): Bool {
        return InterpreterValueKindIndex(this) == InterpreterValueKindIndex(right)
    }

    public operator func !=(right: InterpreterValueKind): Bool {
        return !(this == right)
    }
}

public class InterpreterValue {
    public let kind: InterpreterValueKind
    private let intContent: Int64
    private let floatContent: Float64
    private let boolContent: Bool
    private let textContent: String
    private let literalContent: Option<LiteralValue>
    private let classId: Int64
    private let pointerRootKind: InterpreterPointerRootKind
    private let pointerIndex: Int64
    private let pointerPath: ArrayList<Int64> = ArrayList<Int64>()
    private let functionIndex: Int64
    private let elements: ArrayList<InterpreterValue> = ArrayList<InterpreterValue>()

    public init(kind: InterpreterValueKind, intContent!: Int64 = 0, floatContent!: Float64 = 0.0,
        boolContent!: Bool = false, textContent!: String = "", literalContent!: Option<LiteralValue> = None,
        classId!: Int64 = 0, pointerRootKind!: InterpreterPointerRootKind = InterpreterPointerRootKind.PINVALID,
        pointerIndex!: Int64 = -1, pointerPath!: Option<ArrayList<Int64>> = None, functionIndex!: Int64 = 0,
        elements!: Option<ArrayList<InterpreterValue>> = None) {
        this.kind = kind
        this.intContent = intContent
        this.floatContent = floatContent
        this.boolContent = boolContent
        this.textContent = textContent
        this.literalContent = literalContent
        this.classId = classId
        this.pointerRootKind = pointerRootKind
        this.pointerIndex = pointerIndex
        this.functionIndex = functionIndex
        if (let Some(path) <- pointerPath) {
            for (part in path) {
                this.pointerPath.add(part)
            }
        }
        if (let Some(items) <- elements) {
            for (item in items) {
                this.elements.add(item.Clone())
            }
        }
    }

    public static func MakeInvalid(): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.IINVALID)
    }

    public static func MakeInt(kind: InterpreterValueKind, value: Int64): InterpreterValue {
        let normalized = NormalizeIntegerForKind(kind, value)
        return InterpreterValue(kind, intContent: normalized, literalContent: IntLiteral(normalized))
    }

    public static func MakeUInt(kind: InterpreterValueKind, value: Int64): InterpreterValue {
        let normalized = NormalizeIntegerForKind(kind, value)
        return InterpreterValue(kind, intContent: normalized, literalContent: IntLiteral(normalized))
    }

    public static func MakeFloat(kind: InterpreterValueKind, value: Float64): InterpreterValue {
        return InterpreterValue(kind, floatContent: value, literalContent: FloatLiteral(value))
    }

    public static func MakeBool(value: Bool): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.IBOOL, boolContent: value, literalContent: BoolLiteral(value))
    }

    public static func MakeRune(value: Rune): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.IRUNE, intContent: Int64(UInt32(value)),
            literalContent: RuneLiteral(value))
    }

    public static func MakeString(value: String): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.ISTRING, textContent: value, literalContent: StringLiteral(value))
    }

    public static func MakeUnit(): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.IUNIT, literalContent: UnitLiteral())
    }

    public static func MakeNull(): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.INULLPTR, literalContent: NullLiteral())
    }

    public static func MakePointer(index: Int64): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.IPOINTER, pointerRootKind: InterpreterPointerRootKind.PARENA,
            pointerIndex: index)
    }

    public static func MakeGlobalPointer(index: Int64): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.IPOINTER, pointerRootKind: InterpreterPointerRootKind.PGLOBAL,
            pointerIndex: index)
    }

    public static func MakePointerWithPath(rootKind: InterpreterPointerRootKind, index: Int64,
        path: ArrayList<Int64>): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.IPOINTER, pointerRootKind: rootKind, pointerIndex: index,
            pointerPath: path)
    }

    public static func MakeFunction(index: Int64): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.IFUNC, functionIndex: index)
    }

    public static func MakeTuple(items: ArrayList<InterpreterValue>): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.ITUPLE, elements: items)
    }

    public static func MakeArray(items: ArrayList<InterpreterValue>): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.IARRAY, elements: items)
    }

    public static func MakeObject(id: Int64, fields: ArrayList<InterpreterValue>): InterpreterValue {
        return InterpreterValue(InterpreterValueKind.IOBJECT, classId: id, elements: fields)
    }

    public func GetInt(): Int64 { return intContent }
    public func GetFloat(): Float64 { return floatContent }
    public func GetBool(): Bool { return boolContent }
    public func GetText(): String { return textContent }
    public func GetLiteral(): Option<LiteralValue> { return literalContent }
    public func GetClassId(): Int64 { return classId }
    public func GetPointerRootKind(): InterpreterPointerRootKind { return pointerRootKind }
    public func GetPointerIndex(): Int64 { return pointerIndex }
    public func GetPointerPath(): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        for (part in pointerPath) {
            out.add(part)
        }
        return out
    }
    public func GetPointerPathRef(): ArrayList<Int64> { return pointerPath }
    public func GetFunctionIndex(): Int64 { return functionIndex }

    public func GetElements(): ArrayList<InterpreterValue> {
        let out = ArrayList<InterpreterValue>()
        for (item in elements) {
            out.add(item.Clone())
        }
        return out
    }

    public func GetElementsRef(): ArrayList<InterpreterValue> {
        return elements
    }

    public func IsInvalid(): Bool { return kind == InterpreterValueKind.IINVALID }
    public func IsIntLike(): Bool {
        return kind == InterpreterValueKind.IUINT8 || kind == InterpreterValueKind.IUINT16 ||
            kind == InterpreterValueKind.IUINT32 || kind == InterpreterValueKind.IUINT64 ||
            kind == InterpreterValueKind.IUINTNAT || kind == InterpreterValueKind.IINT8 ||
            kind == InterpreterValueKind.IINT16 || kind == InterpreterValueKind.IINT32 ||
            kind == InterpreterValueKind.IINT64 || kind == InterpreterValueKind.IINTNAT
    }
    public func IsFloatLike(): Bool {
        return kind == InterpreterValueKind.IFLOAT16 || kind == InterpreterValueKind.IFLOAT32 ||
            kind == InterpreterValueKind.IFLOAT64
    }

    public func Clone(): InterpreterValue {
        return InterpreterValue(kind, intContent: intContent, floatContent: floatContent, boolContent: boolContent,
            textContent: textContent, literalContent: literalContent, classId: classId,
            pointerRootKind: pointerRootKind, pointerIndex: pointerIndex, pointerPath: pointerPath,
            functionIndex: functionIndex, elements: elements)
    }
}

private func NormalizeIntegerForKind(kind: InterpreterValueKind, value: Int64): Int64 {
    return match (kind) {
        case InterpreterValueKind.IINT8 => NormalizeSignedInteger(value, 8)
        case InterpreterValueKind.IINT16 => NormalizeSignedInteger(value, 16)
        case InterpreterValueKind.IINT32 => NormalizeSignedInteger(value, 32)
        case InterpreterValueKind.IUINT8 => NormalizeUnsignedInteger(value, 8)
        case InterpreterValueKind.IUINT16 => NormalizeUnsignedInteger(value, 16)
        case InterpreterValueKind.IUINT32 => NormalizeUnsignedInteger(value, 32)
        case _ => value
    }
}

private func NormalizeSignedInteger(value: Int64, width: Int64): Int64 {
    let range = 1 << width
    let signBit = 1 << (width - 1)
    let truncated = value & (range - 1)
    return if (truncated >= signBit) { truncated - range } else { truncated }
}

private func NormalizeUnsignedInteger(value: Int64, width: Int64): Int64 {
    return value & ((1 << width) - 1)
}
