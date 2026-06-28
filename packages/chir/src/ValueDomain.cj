package cangjie_compiler::chir

import cangjie_compiler::utils.{CJC_ABORT, CJC_ASSERT}
import std.collection.*
import std.sync.*

public class AbstractObject <: Value {
    private static let ins = AbstractObject("TopObj")

    public init(identifier: String) {
        super(None, identifier, ValueKind.KIND_LOCALVAR)
    }

    public static func GetTopObjInstance(): AbstractObject {
        return ins
    }

    public func IsTopObjInstance(): Bool {
        return refEq(this, GetTopObjInstance())
    }

    public func CloneObject(): AbstractObject {
        if (IsTopObjInstance()) {
            return GetTopObjInstance()
        }
        return AbstractObject(GetIdentifier())
    }

    public override func ToString(indent: Int64): String {
        let _ = indent
        return GetIdentifier()
    }
}

public class Ref {
    private static let ins = Ref("TopRef", false)

    private let isStaticRef: Bool
    private let uniqueID: String
    private let roots: ArrayList<Ref> = ArrayList<Ref>()
    private let cacheKeys: ArrayList<Ref> = ArrayList<Ref>()
    private let cacheValues: ArrayList<Bool> = ArrayList<Bool>()
    private let cacheMtx: Mutex = Mutex()

    public init(uniqueID: String, isStatic: Bool) {
        this.uniqueID = uniqueID
        isStaticRef = isStatic
    }

    public func GetUniqueID(): String {
        return if (isStaticRef) { "s" + uniqueID } else { uniqueID }
    }

    public func AddRoots(left: Ref, right: Ref): Unit {
        AddRootSet(left)
        AddRootSet(right)
    }

    public func IsEquivalent(ref: Ref): Bool {
        if (roots.isEmpty() || roots.size != ref.roots.size) {
            return false
        }
        for (root in roots) {
            if (!ContainsRoot(ref.roots, root)) {
                return false
            }
        }
        return true
    }

    public func CanRepresent(ref: Ref): Bool {
        if (let Some(cached) <- CheckCache(ref)) {
            return cached
        }
        let result = if (roots.isEmpty()) {
            false
        } else if (ref.roots.isEmpty()) {
            ContainsRoot(roots, ref)
        } else {
            RootsContainAll(roots, ref.roots)
        }
        WriteCache(ref, result)
        return result
    }

    public func CheckCache(ref: Ref): Option<Bool> {
        if (isStaticRef) {
            synchronized(cacheMtx) {
                var idx: Int64 = 0
                while (idx < cacheKeys.size) {
                    if (refEq(cacheKeys[idx], ref)) {
                        return cacheValues[idx]
                    }
                    idx++
                }
            }
            return None
        }
        var idx: Int64 = 0
        while (idx < cacheKeys.size) {
            if (refEq(cacheKeys[idx], ref)) {
                return cacheValues[idx]
            }
            idx++
        }
        return None
    }

    public func WriteCache(ref: Ref, result: Bool): Unit {
        if (isStaticRef) {
            synchronized(cacheMtx) {
                var idx: Int64 = 0
                while (idx < cacheKeys.size) {
                    if (refEq(cacheKeys[idx], ref)) {
                        return
                    }
                    idx++
                }
                cacheKeys.add(ref)
                cacheValues.add(result)
            }
            return
        }
        var idx: Int64 = 0
        while (idx < cacheKeys.size) {
            if (refEq(cacheKeys[idx], ref)) {
                return
            }
            idx++
        }
        cacheKeys.add(ref)
        cacheValues.add(result)
    }

    public static func GetTopRefInstance(): Ref {
        return ins
    }

    public func IsTopRefInstance(): Bool {
        return refEq(this, GetTopRefInstance())
    }

    private func AddRootSet(ref: Ref): Unit {
        if (ref.roots.isEmpty()) {
            AddRoot(ref)
            return
        }
        for (root in ref.roots) {
            AddRoot(root)
        }
    }

    private func AddRoot(ref: Ref): Unit {
        if (!ContainsRoot(roots, ref)) {
            roots.add(ref)
        }
    }
}

public enum ValueDomainKind {
    | BOTTOM | REF | VAL | TOP
}

public func ValueDomainKindIndex(kind: ValueDomainKind): Int64 {
    return match (kind) {
        case ValueDomainKind.BOTTOM => 0
        case ValueDomainKind.REF => 1
        case ValueDomainKind.VAL => 2
        case ValueDomainKind.TOP => 3
    }
}

extend ValueDomainKind <: Equatable<ValueDomainKind> {
    public operator func ==(right: ValueDomainKind): Bool {
        return ValueDomainKindIndex(this) == ValueDomainKindIndex(right)
    }

    public operator func !=(right: ValueDomainKind): Bool {
        return !(this == right)
    }
}

public class ValueDomain {
    private var kind: ValueDomainKind
    private var ref: Option<Ref> = None
    private var absVal: Option<AbstractObject> = None

    public init(isTop: Bool) {
        kind = if (isTop) { ValueDomainKind.TOP } else { ValueDomainKind.BOTTOM }
    }

    public init(ref: Ref) {
        kind = ValueDomainKind.REF
        this.ref = ref
    }

    public init(value: AbstractObject) {
        kind = ValueDomainKind.VAL
        absVal = value
    }

    public func Clone(): ValueDomain {
        if (kind == ValueDomainKind.REF) {
            if (let Some(refValue) <- ref) {
                return ValueDomain(refValue)
            }
        }
        if (kind == ValueDomainKind.VAL) {
            if (let Some(obj) <- absVal) {
                return ValueDomain(obj.CloneObject())
            }
        }
        return ValueDomain(kind == ValueDomainKind.TOP)
    }

    public func GetKind(): ValueDomainKind { return kind }
    public func IsTop(): Bool { return kind == ValueDomainKind.TOP }
    public func IsBottom(): Bool { return kind == ValueDomainKind.BOTTOM }
    public func IsRef(): Bool { return kind == ValueDomainKind.REF }
    public func IsVal(): Bool { return kind == ValueDomainKind.VAL }
    public func GetRef(): Option<Ref> { return ref }
    public func GetAbstractValue(): Option<AbstractObject> { return absVal }

    public func Join(rhs: ValueDomain): Bool {
        if (IsTop() || rhs.IsBottom()) {
            return false
        }
        if (rhs.IsTop()) {
            SetSelfToBound(true)
            return true
        }
        if (IsBottom()) {
            CopyFrom(rhs)
            return true
        }
        if (IsRef() && rhs.IsRef()) {
            return JoinRef(rhs)
        }
        if (IsVal() && rhs.IsVal()) {
            return JoinValue(rhs)
        }
        CJC_ABORT()
        return false
    }

    public func SetSelfToBound(isTop: Bool): Unit {
        kind = if (isTop) { ValueDomainKind.TOP } else { ValueDomainKind.BOTTOM }
        ref = None
        absVal = None
    }

    public func SetSelfToTopRef(): Unit {
        CJC_ASSERT(kind == ValueDomainKind.REF)
        ref = Ref.GetTopRefInstance()
    }

    public func SetSelfToTopObj(): Unit {
        kind = ValueDomainKind.VAL
        ref = None
        absVal = AbstractObject.GetTopObjInstance()
    }

    public func ToString(): String {
        return match (kind) {
            case ValueDomainKind.BOTTOM => "Bottom"
            case ValueDomainKind.TOP => "TOP"
            case ValueDomainKind.REF => if (let Some(refValue) <- ref) {
                refValue.GetUniqueID()
            } else {
                CJC_ABORT()
                ""
            }
            case ValueDomainKind.VAL => if (let Some(obj) <- absVal) {
                obj.ToString(0)
            } else {
                CJC_ABORT()
                ""
            }
        }
    }

    private func CopyFrom(rhs: ValueDomain): Unit {
        kind = rhs.kind
        ref = rhs.ref
        if (let Some(obj) <- rhs.absVal) {
            absVal = obj.CloneObject()
        } else {
            absVal = None
        }
    }

    private func JoinRef(rhs: ValueDomain): Bool {
        if (let Some(leftRef) <- ref) {
            if (leftRef.IsTopRefInstance()) {
                return false
            }
            if (let Some(rightRef) <- rhs.ref) {
                if (rightRef.IsTopRefInstance()) {
                    SetSelfToTopRef()
                    return true
                }
                if (refEq(leftRef, rightRef)) {
                    return false
                }
                SetSelfToTopRef()
                return true
            }
            CJC_ASSERT(false)
            return false
        }
        CJC_ASSERT(false)
        return false
    }

    private func JoinValue(rhs: ValueDomain): Bool {
        if (let Some(leftObj) <- absVal) {
            if (leftObj.IsTopObjInstance()) {
                return false
            }
            if (let Some(rightObj) <- rhs.absVal) {
                if (rightObj.IsTopObjInstance()) {
                    SetSelfToTopObj()
                    return true
                }
                if (leftObj.GetIdentifier() == rightObj.GetIdentifier()) {
                    return false
                }
                SetSelfToTopObj()
                return true
            }
        }
        SetSelfToTopObj()
        return true
    }
}

private func ContainsRoot(roots: ArrayList<Ref>, ref: Ref): Bool {
    for (root in roots) {
        if (refEq(root, ref)) {
            return true
        }
    }
    return false
}

private func RootsContainAll(roots: ArrayList<Ref>, subset: ArrayList<Ref>): Bool {
    if (subset.size > roots.size) {
        return false
    }
    for (root in subset) {
        if (!ContainsRoot(roots, root)) {
            return false
        }
    }
    return true
}
