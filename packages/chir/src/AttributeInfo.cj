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

    private func AppendIfPresent(parts: ArrayList<String>, attr: Attribute): Unit {
        if (attrs.contains(attr)) {
            parts.add(AttributeName(attr))
        }
    }

    public func ToString(): String {
        if (attrs.isEmpty()) {
            return ""
        }
        let parts = ArrayList<String>()
        AppendIfPresent(parts, Attribute.PUBLIC)
        AppendIfPresent(parts, Attribute.PROTECTED)
        AppendIfPresent(parts, Attribute.PRIVATE)
        AppendIfPresent(parts, Attribute.STATIC)
        AppendIfPresent(parts, Attribute.MUT)
        AppendIfPresent(parts, Attribute.CONST)
        AppendIfPresent(parts, Attribute.ABSTRACT)
        AppendIfPresent(parts, Attribute.VIRTUAL)
        AppendIfPresent(parts, Attribute.IMPORTED)
        AppendIfPresent(parts, Attribute.SRC_CODE_IMPORTED)
        AppendIfPresent(parts, Attribute.FOREIGN)
        AppendIfPresent(parts, Attribute.C)
        AppendIfPresent(parts, Attribute.FAST_NATIVE)
        AppendIfPresent(parts, Attribute.NO_SIDE_EFFECT)
        AppendIfPresent(parts, Attribute.READONLY)
        AppendIfPresent(parts, Attribute.BUILTIN)
        AppendIfPresent(parts, Attribute.THIN)
        if (parts.isEmpty()) {
            for (attr in attrs) {
                parts.add(AttributeName(attr))
            }
        }
        return "[" + JoinStrings(parts, " ") + "] "
    }
}
