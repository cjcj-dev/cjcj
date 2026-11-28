package cjcj::chir

// Base embeds the words; AttributeInfo is the mutable snapshot passed through
// the public interfaces and serializers.
struct AttributeInfoBits {
    private var lo: UInt64
    private var hi: UInt64 = 0u64

    init(lo: UInt64) {
        this.lo = lo
    }

    mut func Enable(attr: Attribute): Unit {
        let index = AttributeIndex(attr)
        let mask = 1u64 << UInt64(index % 64)
        if (index < 64) { lo = lo | mask } else { hi = hi | mask }
    }

    mut func Disable(attr: Attribute): Unit {
        let index = AttributeIndex(attr)
        let mask = UInt64.Max ^ (1u64 << UInt64(index % 64))
        if (index < 64) { lo = lo & mask } else { hi = hi & mask }
    }

    func Test(attr: Attribute): Bool {
        let index = AttributeIndex(attr)
        let word = if (index < 64) { lo } else { hi }
        return (word & (1u64 << UInt64(index % 64))) != 0u64
    }

    func GetRawAttrs(): UInt64 {
        return lo
    }

    mut func Append(other: AttributeInfoBits): Unit {
        lo = lo | other.lo
        hi = hi | other.hi
    }
}

public class AttributeInfo {
    private var bits: AttributeInfoBits

    public init() {
        bits = AttributeInfoBits(0u64)
    }

    public init(attrs: UInt64) {
        bits = AttributeInfoBits(attrs)
    }

    public init(other: AttributeInfo) {
        bits = other.bits
    }

    init(bits: AttributeInfoBits) {
        this.bits = bits
    }

    func GetBits(): AttributeInfoBits {
        return bits
    }

    public func Enable(attr: Attribute): Unit {
        bits.Enable(attr)
    }

    public func Disable(attr: Attribute): Unit {
        bits.Disable(attr)
    }

    public func Test(attr: Attribute): Bool {
        return bits.Test(attr)
    }

    public func GetRawAttrs(): UInt64 {
        return bits.GetRawAttrs()
    }

    public func Append(info: AttributeInfo): Unit {
        bits.Append(info.bits)
    }

    public func Clear(): Unit {
        bits = AttributeInfoBits(0u64)
    }

    public func CopyFrom(info: AttributeInfo): Unit {
        Clear()
        Append(info)
    }

    public func ToString(): String {
        var out = ""
        let attrsInOrder = [
            Attribute.STATIC, Attribute.PUBLIC, Attribute.PRIVATE, Attribute.PROTECTED,
            Attribute.ABSTRACT, Attribute.VIRTUAL, Attribute.OVERRIDE, Attribute.REDEF,
            Attribute.SEALED, Attribute.FOREIGN, Attribute.MUT, Attribute.FINAL,
            Attribute.OPERATOR, Attribute.READONLY, Attribute.CONST, Attribute.IMPORTED,
            Attribute.GENERIC_INSTANTIATED, Attribute.NO_DEBUG_INFO, Attribute.GENERIC,
            Attribute.INTERNAL, Attribute.COMPILER_ADD, Attribute.NO_REFLECT_INFO,
            Attribute.NO_INLINE, Attribute.NON_RECOMPILE, Attribute.UNREACHABLE,
            Attribute.NO_SIDE_EFFECT, Attribute.COMMON, Attribute.SPECIFIC,
            Attribute.SKIP_ANALYSIS, Attribute.DESERIALIZED, Attribute.INITIALIZER,
            Attribute.UNSAFE, Attribute.JAVA_FOREIGN, Attribute.JAVA_EXPORT,
            Attribute.OBJ_C_FOREIGN, Attribute.HAS_INITED_FIELD, Attribute.JAVA_HAS_DEFAULT,
            Attribute.PREVIOUSLY_DESERIALIZED, Attribute.DOES_NOT_THROW, Attribute.OBJ_C_EXPORT, Attribute.MATCH_PATTERN, Attribute.PLUGIN_ADDED,
            Attribute.DEMODE, Attribute.EXCLAVE, Attribute.FAST_NATIVE, Attribute.NO_HEAP_ALLOC,
            Attribute.NO_WRITE_BARRIER, Attribute.NO_WRITE_BARRIER_REC, Attribute.NO_STACK_GROW,
            Attribute.SYSTEM_STACK
        ]
        for (attr in attrsInOrder) {
            if (Test(attr)) {
                out += "[" + AttributeName(attr) + "] "
            }
        }
        return out
    }
}
