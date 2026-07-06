package cangjie_compiler::sema.InheritanceChecker

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

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
    public let entries: ArrayList<MemberMapEntry> = ArrayList<MemberMapEntry>()

    public init() {}

    public func Add(name: String, signature: MemberSignature): Unit {
        entries.add(MemberMapEntry(name, signature))
    }

    public func Add(signature: MemberSignature): Unit {
        Add(signature.Name(), signature)
    }

    public func Get(name: String): ArrayList<MemberSignature> {
        let out = ArrayList<MemberSignature>()
        for (entry in entries) {
            if (entry.name == name) {
                out.add(entry.signature)
            }
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
        let out = MemberMap()
        for (entry in entries) {
            out.Add(entry.name, entry.signature.Clone())
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
            var found = false
            for (name in out) {
                if (name == entry.name) {
                    found = true
                    break
                }
            }
            if (!found) {
                out.add(entry.name)
            }
        }
        return out
    }
}
