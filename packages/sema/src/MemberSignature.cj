package cjcj::sema

import std.collection.*
import cjcj::ast.*

public class MemberSignature {
    public var decl: Option<Decl> = None
    public var ty: Option<Ty> = None
    public var structTy: Option<Ty> = None
    public var extendDecl: Option<ExtendDecl> = None
    public let upperBounds: ArrayList<TySet> = ArrayList<TySet>()
    public let inconsistentTypes: TySet = TySet()
    public var shouldBeImplemented: Bool = false
    public var replaceOther: Bool = false
    public var isInheritedInterface: Bool = false

    public init() {}

    public init(decl!: Option<Decl> = None, ty!: Option<Ty> = None, structTy!: Option<Ty> = None,
        extendDecl!: Option<ExtendDecl> = None) {
        this.decl = decl
        this.ty = ty
        this.structTy = structTy
        this.extendDecl = extendDecl
    }

    public func Clone(): MemberSignature {
        let out = MemberSignature(decl: decl, ty: ty, structTy: structTy, extendDecl: extendDecl)
        for (bounds in upperBounds) {
            out.upperBounds.add(bounds.Clone())
        }
        out.inconsistentTypes.AddAll(inconsistentTypes)
        out.shouldBeImplemented = shouldBeImplemented
        out.replaceOther = replaceOther
        out.isInheritedInterface = isInheritedInterface
        return out
    }

    public func HasDecl(): Bool {
        if (let Some(_) <- decl) {
            return true
        }
        return false
    }

    public func IsFunc(): Bool {
        if (let Some(realDecl) <- decl) {
            return realDecl.IsFunc()
        }
        return false
    }

    public func IsProp(): Bool {
        if (let Some(realDecl) <- decl) {
            return realDecl.astKind == ASTKind.PROP_DECL
        }
        return false
    }

    public func Name(): String {
        if (let Some(realDecl) <- decl) {
            return realDecl.identifier.Val()
        }
        return ""
    }
}

public class MemberMapEntry {
    public var name: String
    public var signature: MemberSignature

    public init(name: String, signature: MemberSignature) {
        this.name = name
        this.signature = signature
    }
}

public class MemberMap {
    public let entries: ArrayList<MemberMapEntry>

    public init() {
        entries = ArrayList<MemberMapEntry>()
    }

    private init(capacity: Int64) {
        entries = ArrayList<MemberMapEntry>(capacity)
    }

    public func Add(name: String, signature: MemberSignature): Unit {
        entries.add(MemberMapEntry(name, signature), at: NameBound(name, afterEqual: true))
    }

    public func Add(signature: MemberSignature): Unit {
        Add(signature.Name(), signature)
    }

    private func NameBound(name: String, afterEqual!: Bool = false): Int64 {
        var lo: Int64 = 0
        var hi = entries.size
        while (lo < hi) {
            let mid = lo + (hi - lo) / 2
            let current = entries[mid].name
            if (current < name || (afterEqual && current == name)) {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    public func Get(name: String): ArrayList<MemberSignature> {
        let out = ArrayList<MemberSignature>()
        var idx = NameBound(name)
        while (idx < entries.size && entries[idx].name == name) {
            out.add(entries[idx].signature)
            idx++
        }
        return out
    }

    public func Clear(): Unit {
        entries.clear()
    }

    public func Remove(index: Int64): Unit {
        entries.remove(at: index)
    }

    public func Clone(): MemberMap {
        let out = MemberMap(entries.size)
        for (entry in entries) {
            out.entries.add(MemberMapEntry(entry.name, entry.signature.Clone()))
        }
        return out
    }

    public func Size(): Int64 {
        return entries.size
    }

    public func IsEmpty(): Bool {
        return entries.isEmpty()
    }

    public func Names(): ArrayList<String> {
        let out = ArrayList<String>()
        for (entry in entries) {
            if (out.isEmpty() || out[out.size - 1] != entry.name) {
                out.add(entry.name)
            }
        }
        return out
    }
}
