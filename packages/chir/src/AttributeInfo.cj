package cangjie_compiler::chir

import std.collection.*

public class AttributeInfo {
    private let attrs: HashSet<Attribute> = HashSet<Attribute>()

    public init() {}

    public func Enable(attr: Attribute): Unit {
        attrs.add(attr)
    }

    public func Disable(attr: Attribute): Unit {
        attrs.remove(attr)
    }

    public func Test(attr: Attribute): Bool {
        return attrs.contains(attr)
    }

    public func Append(info: AttributeInfo): Unit {
        for (attr in info.attrs) {
            attrs.add(attr)
        }
    }

    public func Clear(): Unit {
        attrs.clear()
    }

    public func CopyFrom(info: AttributeInfo): Unit {
        attrs.clear()
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
            Attribute.PREVIOUSLY_DESERIALIZED
        ]
        for (attr in attrsInOrder) {
            if (attrs.contains(attr)) {
                out += "[" + AttributeName(attr) + "] "
            }
        }
        return out
    }
}
