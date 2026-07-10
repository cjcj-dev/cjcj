package cjcj::chir

public class AttributeInfo {
    private var attributesInfo: VArray<UInt64, $2>

    public init() {
        attributesInfo = VArray<UInt64, $2>({ _: Int64 => 0u64 })
    }

    public init(other: AttributeInfo) {
        attributesInfo = VArray<UInt64, $2>({ _: Int64 => 0u64 })
        for (idx in 0..2) {
            attributesInfo[idx] = other.attributesInfo[idx]
        }
    }

    public func Enable(attr: Attribute): Unit {
        let index = AttributeIndex(attr)
        let word = Int64(UInt64(index) / 64u64)
        let mask = 1u64 << (UInt64(index) % 64u64)
        attributesInfo[word] = attributesInfo[word] | mask
    }

    public func Disable(attr: Attribute): Unit {
        let index = AttributeIndex(attr)
        let word = Int64(UInt64(index) / 64u64)
        let mask = 1u64 << (UInt64(index) % 64u64)
        attributesInfo[word] = attributesInfo[word] & (UInt64.Max ^ mask)
    }

    public func Test(attr: Attribute): Bool {
        let index = AttributeIndex(attr)
        let word = Int64(UInt64(index) / 64u64)
        let mask = 1u64 << (UInt64(index) % 64u64)
        return (attributesInfo[word] & mask) != 0u64
    }

    public func Append(info: AttributeInfo): Unit {
        for (idx in 0..2) {
            attributesInfo[idx] = attributesInfo[idx] | info.attributesInfo[idx]
        }
    }

    public func Clear(): Unit {
        for (idx in 0..2) {
            attributesInfo[idx] = 0u64
        }
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
            Attribute.UNSAFE, Attribute.JAVA_MIRROR, Attribute.JAVA_IMPL,
            Attribute.OBJ_C_MIRROR, Attribute.HAS_INITED_FIELD, Attribute.JAVA_HAS_DEFAULT,
            Attribute.PREVIOUSLY_DESERIALIZED, Attribute.NO_HEAP_ALLOC,
            Attribute.NO_WRITE_BARRIER_REC, Attribute.NO_STACK_GROW
        ]
        for (attr in attrsInOrder) {
            if (Test(attr)) {
                out += "[" + AttributeName(attr) + "] "
            }
        }
        return out
    }
}
