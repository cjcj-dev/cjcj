package cjcj::chir

import cjcj::utils.{CJC_ABORT, CJC_ASSERT}
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

public class ValueDomain<AV> <: AbstractDomain<ValueDomain<AV>> where AV <: ConstValue {
    private var valueKind: ValueDomainKind
    private var ref: Option<Ref> = None
    private var absVal: Option<AV> = None

    public init(isTop: Bool) {
        super()
        valueKind = if (isTop) { ValueDomainKind.TOP } else { ValueDomainKind.BOTTOM }
    }

    public init(ref: Ref) {
        super()
        valueKind = ValueDomainKind.REF
        this.ref = ref
    }

    public init(value: AV) {
        super()
        valueKind = ValueDomainKind.VAL
        absVal = value
    }

    public override func Clone(): ValueDomain<AV> {
        if (valueKind == ValueDomainKind.REF) {
            if (let Some(refValue) <- ref) {
                return ValueDomain<AV>(refValue)
            }
        }
        if (valueKind == ValueDomainKind.VAL) {
            if (let Some(value) <- absVal) {
                return ValueDomain<AV>(CloneAbsVal(value))
            }
        }
        return ValueDomain<AV>(valueKind == ValueDomainKind.TOP)
    }

    public func GetKind(): ValueDomainKind { return valueKind }
    public func IsTop(): Bool { return valueKind == ValueDomainKind.TOP }
    public override func IsBottom(): Bool { return valueKind == ValueDomainKind.BOTTOM }
    public func IsRef(): Bool { return valueKind == ValueDomainKind.REF }
    public func IsVal(): Bool { return valueKind == ValueDomainKind.VAL }
    public func GetRef(): Option<Ref> { return ref }
    public func CheckAbsVal(): Option<AV> { return absVal }

    public override func Join(rhs: ValueDomain<AV>): Bool {
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

    public func SetRef(ref: Ref): Unit {
        CJC_ASSERT(valueKind != ValueDomainKind.VAL)
        if (valueKind != ValueDomainKind.REF) {
            valueKind = ValueDomainKind.REF
        }
        this.ref = ref
    }

    public func SetSelfToBound(isTop: Bool): Unit {
        valueKind = if (isTop) { ValueDomainKind.TOP } else { ValueDomainKind.BOTTOM }
        ref = None
        absVal = None
    }

    public func SetSelfToTopRef(): Unit {
        CJC_ASSERT(valueKind == ValueDomainKind.REF)
        ref = Ref.GetTopRefInstance()
    }

    public override func ToString(): String {
        return match (valueKind) {
            case ValueDomainKind.BOTTOM => "Bottom"
            case ValueDomainKind.TOP => "TOP"
            case ValueDomainKind.REF => if (let Some(refValue) <- ref) {
                refValue.GetUniqueID()
            } else {
                CJC_ABORT()
                ""
            }
            case ValueDomainKind.VAL => if (let Some(value) <- absVal) {
                value.ToString()
            } else {
                CJC_ABORT()
                ""
            }
        }
    }

    private func CopyFrom(rhs: ValueDomain<AV>): Unit {
        valueKind = rhs.valueKind
        ref = rhs.ref
        if (let Some(value) <- rhs.absVal) {
            absVal = CloneAbsVal(value)
        } else {
            absVal = None
        }
    }

    private func JoinRef(rhs: ValueDomain<AV>): Bool {
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

    private func JoinValue(rhs: ValueDomain<AV>): Bool {
        if (let Some(leftVal) <- absVal) {
            if (let Some(rightVal) <- rhs.absVal) {
                let res = leftVal.Join(rightVal)
                if (let Some(newVal) <- res) {
                    if (let Some(value) <- newVal) {
                        absVal = CastAbsVal(value)
                    } else {
                        SetSelfToBound(true)
                    }
                    return true
                }
                return false
            }
        }
        SetSelfToBound(true)
        return true
    }

    private func CloneAbsVal(value: AV): AV {
        return CastAbsVal(value.Clone())
    }

    private func CastAbsVal(value: ConstValue): AV {
        return (value as AV).getOrThrow()
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
