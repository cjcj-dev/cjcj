package cjcj::chir

import cjcj::utils.CJC_ASSERT
import std.collection.*

func IsInstanceOfValue<VD, Pool>(): Bool where VD <: AbstractDomain<VD> & ValueDomainAccess<VD>,
    Pool <: ValueStatePool<VD, Pool> {
    return Pool.IsInstanceOfValue()
}

public func GetRefName(index: Int64): String {
    return "Ref" + index.toString()
}

public func GetObjName(index: Int64): String {
    return "Obj" + index.toString()
}

public func GetObjChildName(parentName: String, fieldIdx: Int64): String {
    return parentName + "." + fieldIdx.toString()
}

public interface ValueStatePool<VD, Pool> where VD <: AbstractDomain<VD> & ValueDomainAccess<VD> {
    static func IsInstanceOfValue(): Bool
    static func Create(): Pool
    func Clone(): Pool
    func CopyFrom(rhs: Pool): Unit
    func Size(): Int64
    func Clear(): Unit
    func Find(value: Value): Option<VD>
    func Contains(value: Value): Bool
    func At(value: Value): VD
    func GetAt(index: Int64): (Value, VD)
    func Insert(value: Value, domain: VD): Unit
    func SetRef(value: Value, refValue: Ref): Unit
    func SetBound(value: Value, isTop: Bool): Unit
    func Join(rhs: Pool): Bool
}

public class FullStatePool<VD> <: ValueStatePool<VD, FullStatePool<VD>>
    where VD <: AbstractDomain<VD> & ValueDomainAccess<VD> {
    // C++ ActiveStatePool.h:41-42,71-83,129-130: the pool is backed by
    // unordered_map<Value*, ValueDomain>. keys only preserves the existing
    // selfhost GetAt(index) iteration adapter.
    private let data: HashMap<Value, VD> = HashMap<Value, VD>()
    private let keys: ArrayList<Value> = ArrayList<Value>()

    public init() {}

    public init(other: FullStatePool<VD>) {
        var idx: Int64 = 0
        while (idx < other.keys.size) {
            let key = other.keys[idx]
            keys.add(key)
            data[key] = other.data[key].Clone()
            idx++
        }
    }

    public static func IsInstanceOfValue(): Bool { return false }

    public static func Create(): FullStatePool<VD> {
        return FullStatePool<VD>()
    }

    public func Clone(): FullStatePool<VD> {
        return FullStatePool<VD>(this)
    }

    public func CopyFrom(rhs: FullStatePool<VD>): Unit {
        // Rebuild the observable insertion order in keys, while retaining the
        // pass-local backing storage and matching domain objects.
        for (key in keys) {
            if (!rhs.data.contains(key)) {
                data.remove(key)
            }
        }
        keys.clear()
        for (key in rhs.keys) {
            if (let Some(domain) <- data.get(key)) {
                domain.CopyFrom(rhs.data[key])
            } else {
                data[key] = rhs.data[key].Clone()
            }
            keys.add(key)
        }
    }

    public func Size(): Int64 {
        return data.size
    }

    public func Clear(): Unit {
        data.clear()
        keys.clear()
    }

    public func Find(value: Value): Option<VD> {
        // C++ ActiveStatePool.h:71-83: data.find(value).
        return data.get(value)
    }

    public func Contains(value: Value): Bool {
        return data.contains(value)
    }

    public func At(value: Value): VD {
        // C++ ActiveStatePool.h:100-107: data.at(value).
        if (let Some(domain) <- data.get(value)) {
            return domain
        }
        throw IllegalStateException("ValueAnalysis state missing value: " + value.GetIdentifier())
    }

    public func GetAt(index: Int64): (Value, VD) {
        let key = keys[index]
        return (key, data[key])
    }

    public func Insert(value: Value, domain: VD): Unit {
        if (let Some(current) <- data.get(value)) {
            // The map owns the mutable domain. Updating it in place avoids a
            // short-lived domain allocation and a HashMap reference write.
            current.CopyFrom(domain)
            return
        }
        // C++ ActiveStatePool.h:91-94: data.emplace(value, domain).
        data[value] = domain.Clone()
        keys.add(value)
    }

    public func SetRef(value: Value, refValue: Ref): Unit {
        Insert(value, VD.Create(refValue))
    }

    public func SetBound(value: Value, isTop: Bool): Unit {
        if (let Some(domain) <- data.get(value)) {
            domain.SetSelfToBound(isTop)
            return
        }
        data[value] = VD.Create(isTop)
        keys.add(value)
    }

    public func Join(rhs: FullStatePool<VD>): Bool {
        var changed = false
        var idx: Int64 = 0
        while (idx < rhs.keys.size) {
            let rhsKey = rhs.keys[idx]
            let rhsValue = rhs.data[rhsKey]
            // C++ Utils.h:33-40, ActiveStatePool.h:115-118: MapJoin on data.
            if (let Some(lhsValue) <- data.get(rhsKey)) {
                changed = lhsValue.Join(rhsValue) || changed
            } else {
                data[rhsKey] = rhsValue.Clone()
                keys.add(rhsKey)
                changed = true
            }
            idx++
        }
        return changed
    }
}

public class ActiveStateNode {
    public var prev: Option<ActiveStateNode> = None
    public var next: Option<ActiveStateNode> = None
    public let value: Value

    public init(value: Value) {
        this.value = value
    }
}

public class ActiveStatePool<VD> <: ValueStatePool<VD, ActiveStatePool<VD>>
    where VD <: AbstractDomain<VD> & ValueDomainAccess<VD> {
    private static let MAX_STATE_POOL_SIZE: Int64 = 120
    private static let BASE_STATE_POOL_SIZE: Int64 = 80

    private let data: HashMap<Value, VD> = HashMap<Value, VD>()
    private let keys: ArrayList<Value> = ArrayList<Value>()
    private let obj2StateNode: HashMap<Value, ActiveStateNode> = HashMap<Value, ActiveStateNode>()
    private var first: Option<ActiveStateNode> = None
    private var tails: Option<ActiveStateNode> = None
    private let topState: VD = VD.Create(true)
    private let topRefState: VD = VD.Create(Ref.GetTopRefInstance())

    public init() {}

    public init(other: ActiveStatePool<VD>) {
        if (other.first.isNone()) {
            return
        }
        for (key in other.keys) {
            data[key] = other.data[key].Clone()
            keys.add(key)
            obj2StateNode[key] = ActiveStateNode(key)
        }
        for (key in other.keys) {
            let newNode = obj2StateNode[key]
            let node = other.obj2StateNode[key]
            if (let Some(prevNode) <- node.prev) {
                newNode.prev = Some(obj2StateNode[prevNode.value])
            }
            if (let Some(nextNode) <- node.next) {
                newNode.next = Some(obj2StateNode[nextNode.value])
            }
        }
        if (let Some(firstNode) <- other.first) {
            first = Some(obj2StateNode[firstNode.value])
        }
        if (let Some(tailNode) <- other.tails) {
            tails = Some(obj2StateNode[tailNode.value])
        }
    }

    public static func IsInstanceOfValue(): Bool { return true }

    public static func Create(): ActiveStatePool<VD> {
        return ActiveStatePool<VD>()
    }

    public func Clone(): ActiveStatePool<VD> {
        return ActiveStatePool<VD>(this)
    }

    public func CopyFrom(rhs: ActiveStatePool<VD>): Unit {
        Clear()
        if (rhs.first.isNone()) {
            return
        }
        for (key in rhs.keys) {
            data[key] = rhs.data[key].Clone()
            keys.add(key)
            obj2StateNode[key] = ActiveStateNode(key)
        }
        for (key in rhs.keys) {
            let newNode = obj2StateNode[key]
            let node = rhs.obj2StateNode[key]
            if (let Some(prevNode) <- node.prev) {
                newNode.prev = Some(obj2StateNode[prevNode.value])
            }
            if (let Some(nextNode) <- node.next) {
                newNode.next = Some(obj2StateNode[nextNode.value])
            }
        }
        if (let Some(firstNode) <- rhs.first) {
            first = Some(obj2StateNode[firstNode.value])
        }
        if (let Some(tailNode) <- rhs.tails) {
            tails = Some(obj2StateNode[tailNode.value])
        }
    }

    public func Size(): Int64 {
        return data.size
    }

    public func Clear(): Unit {
        first = None
        tails = None
        data.clear()
        keys.clear()
        obj2StateNode.clear()
    }

    public func Find(value: Value): Option<VD> {
        return data.get(value)
    }

    public func Contains(value: Value): Bool {
        return data.contains(value)
    }

    public func At(value: Value): VD {
        if (let Some(domain) <- data.get(value)) {
            return domain
        }
        return GetTopState(value)
    }

    public func GetAt(index: Int64): (Value, VD) {
        let key = keys[index]
        return (key, data[key])
    }

    public func Insert(value: Value, domain: VD): Unit {
        if (data.contains(value)) {
            return
        }
        data[value] = domain.Clone()
        keys.add(value)
        let stateNode = ActiveStateNode(value)
        obj2StateNode[value] = stateNode
        stateNode.next = None
        stateNode.prev = tails
        if (tails.isNone()) {
            CJC_ASSERT(first.isNone())
            tails = Some(stateNode)
            first = Some(stateNode)
        } else {
            tails.getOrThrow().next = Some(stateNode)
            tails = Some(stateNode)
        }
        CheckPoolOverflow()
    }

    public func SetRef(value: Value, refValue: Ref): Unit {
        if (let Some(domain) <- data.get(value)) {
            domain.SetRef(refValue)
        } else {
            Insert(value, VD.Create(refValue))
        }
    }

    public func SetBound(value: Value, isTop: Bool): Unit {
        if (let Some(domain) <- data.get(value)) {
            domain.SetSelfToBound(isTop)
        } else {
            Insert(value, VD.Create(isTop))
        }
    }

    public func Join(other: ActiveStatePool<VD>): Bool {
        var changed = false
        for ((_, value) in data) {
            if (value.IsRef()) {
                value.SetRef(Ref.GetTopRefInstance())
            }
        }
        for ((key, value) in other.data) {
            if (let Some(current) <- data.get(key)) {
                changed = current.Join(value) || changed
            } else if (!value.IsRef()) {
                Insert(key, value)
            }
        }
        return changed
    }

    private func CheckPoolOverflow(): Unit {
        if (data.size < MAX_STATE_POOL_SIZE) {
            return
        }
        while (data.size > BASE_STATE_POOL_SIZE) {
            let stateFirst = first.getOrThrow()
            let stateNext = stateFirst.next.getOrThrow()
            stateNext.prev = None
            first = Some(stateNext)
            let value = stateFirst.value
            obj2StateNode.remove(value)
            data.remove(value)
            var keyIndex: Int64 = 0
            while (keyIndex < keys.size) {
                if (keys[keyIndex] == value) {
                    keys.remove(at: keyIndex)
                    break
                }
                keyIndex++
            }
        }
    }

    private func GetTopState(value: Value): VD {
        if (let Some(typeValue) <- value.GetType()) {
            if (typeValue.IsRef()) {
                return topRefState
            }
        }
        return topState
    }
}

public enum RefMapValue {
    | RefTarget(Ref)
    | ObjectTarget(AbstractObject)
}

public class RefMap {
    private let keys: ArrayList<Ref> = ArrayList<Ref>()
    private let values: ArrayList<RefMapValue> = ArrayList<RefMapValue>()

    public init() {}

    public init(other: RefMap) {
        var idx: Int64 = 0
        while (idx < other.keys.size) {
            keys.add(other.keys[idx])
            values.add(other.values[idx])
            idx++
        }
    }

    public func Clone(): RefMap {
        return RefMap(this)
    }

    public func CopyFrom(rhs: RefMap): Unit {
        // RefMap is insertion ordered; overwrite the two parallel buffers in
        // place so CopyFrom is byte-equivalent to Clone without new buffers.
        var idx: Int64 = 0
        while (idx < rhs.keys.size) {
            if (idx < keys.size) {
                keys[idx] = rhs.keys[idx]
                values[idx] = rhs.values[idx]
            } else {
                keys.add(rhs.keys[idx])
                values.add(rhs.values[idx])
            }
            idx++
        }
        while (keys.size > rhs.keys.size) {
            keys.remove(at: keys.size - 1)
            values.remove(at: values.size - 1)
        }
    }

    public func Size(): Int64 {
        return keys.size
    }

    public func Clear(): Unit {
        keys.clear()
        values.clear()
    }

    public func Find(key: Ref): Option<Int64> {
        var idx: Int64 = 0
        while (idx < keys.size) {
            if (refEq(keys[idx], key)) {
                return idx
            }
            idx++
        }
        return None
    }

    public func Get(key: Ref): Option<RefMapValue> {
        if (let Some(idx) <- Find(key)) {
            return values[idx]
        }
        return None
    }

    public func GetAt(index: Int64): (Ref, RefMapValue) {
        return (keys[index], values[index])
    }

    public func Set(key: Ref, value: RefMapValue): Unit {
        if (let Some(idx) <- Find(key)) {
            values[idx] = value
            return
        }
        keys.add(key)
        values.add(value)
    }

    public func SetAt(index: Int64, value: RefMapValue): Unit {
        values[index] = value
    }
}

public class ChildrenMap {
    private let keys: ArrayList<Value> = ArrayList<Value>()
    private let values: ArrayList<ArrayList<AbstractObject>> = ArrayList<ArrayList<AbstractObject>>()

    public init() {}

    public func Clear(): Unit {
        keys.clear()
        values.clear()
    }

    public func Size(): Int64 {
        return keys.size
    }

    public func Find(key: Value): Option<Int64> {
        var idx: Int64 = 0
        while (idx < keys.size) {
            if (refEq(keys[idx], key)) {
                return idx
            }
            idx++
        }
        return None
    }

    public func Get(key: Value): Option<ArrayList<AbstractObject>> {
        if (let Some(idx) <- Find(key)) {
            return values[idx]
        }
        return None
    }

    public func Set(key: Value, value: ArrayList<AbstractObject>): Unit {
        if (let Some(idx) <- Find(key)) {
            values[idx] = value
            return
        }
        keys.add(key)
        values.add(value)
    }
}

public class AllocatedRefMap {
    private let keys: ArrayList<Expression> = ArrayList<Expression>()
    private let values: ArrayList<Ref> = ArrayList<Ref>()

    public init() {}

    public func Clear(): Unit {
        keys.clear()
        values.clear()
    }

    public func Find(key: Expression): Option<Ref> {
        var idx: Int64 = 0
        while (idx < keys.size) {
            if (refEq(keys[idx], key)) {
                return values[idx]
            }
            idx++
        }
        return None
    }

    public func Set(key: Expression, value: Ref): Unit {
        var idx: Int64 = 0
        while (idx < keys.size) {
            if (refEq(keys[idx], key)) {
                values[idx] = value
                return
            }
            idx++
        }
        keys.add(key)
        values.add(value)
    }
}

public class AllocatedObjMap {
    private let keys: ArrayList<Expression> = ArrayList<Expression>()
    private let values: ArrayList<AbstractObject> = ArrayList<AbstractObject>()

    public init() {}

    public func Clear(): Unit {
        keys.clear()
        values.clear()
    }

    public func Size(): Int64 {
        return keys.size
    }

    public func Find(key: Expression): Option<AbstractObject> {
        var idx: Int64 = 0
        while (idx < keys.size) {
            if (refEq(keys[idx], key)) {
                return values[idx]
            }
            idx++
        }
        return None
    }

    public func Set(key: Expression, value: AbstractObject): Unit {
        var idx: Int64 = 0
        while (idx < keys.size) {
            if (refEq(keys[idx], key)) {
                values[idx] = value
                return
            }
            idx++
        }
        keys.add(key)
        values.add(value)
    }
}

public class State<VD, Pool> <: AbstractDomain<State<VD, Pool>> where VD <: AbstractDomain<VD> & ValueDomainAccess<VD>,
    Pool <: ValueStatePool<VD, Pool> {
    public var programState: Pool = Pool.Create()
    public var refMap: RefMap = RefMap()
    public let childrenMap: ChildrenMap
    public let allocatedRefMap: AllocatedRefMap
    public let allocatedTwoLevelRefMap: Option<AllocatedRefMap>
    public let allocatedObjMap: AllocatedObjMap
    public let refPool: ArrayList<Ref>
    public let absObjPool: ArrayList<AbstractObject>
    private let isGlobalState: Bool

    public init(childrenMap: ChildrenMap, allocatedRefMap: AllocatedRefMap,
        allocatedTwoLevelRefMap: Option<AllocatedRefMap>, allocatedObjMap: AllocatedObjMap,
        refPool: ArrayList<Ref>, absObjPool: ArrayList<AbstractObject>, isGlobalState!: Bool = false) {
        super()
        this.childrenMap = childrenMap
        this.allocatedRefMap = allocatedRefMap
        this.allocatedTwoLevelRefMap = allocatedTwoLevelRefMap
        this.allocatedObjMap = allocatedObjMap
        this.refPool = refPool
        this.absObjPool = absObjPool
        this.isGlobalState = isGlobalState
    }

    public init(other: State<VD, Pool>) {
        super()
        kind = other.kind
        programState = other.programState.Clone()
        refMap = other.refMap.Clone()
        childrenMap = other.childrenMap
        allocatedRefMap = other.allocatedRefMap
        allocatedTwoLevelRefMap = other.allocatedTwoLevelRefMap
        allocatedObjMap = other.allocatedObjMap
        refPool = other.refPool
        absObjPool = other.absObjPool
        isGlobalState = other.isGlobalState
    }

    public override func Clone(): State<VD, Pool> {
        return State<VD, Pool>(this)
    }

    public func SetReachable(value: Bool): Unit {
        kind = if (value) { ReachableKind.REACHABLE } else { ReachableKind.UNREACHABLE }
    }

    public override func CopyFrom(rhs: State<VD, Pool>): Unit {
        kind = rhs.kind
        if (IsInstanceOfValue<VD, Pool>()) {
            // ActiveStatePool.Join iterates its HashMap directly. Keep the old
            // fresh-clone path so retained bucket capacity cannot change eviction.
            programState = rhs.programState.Clone()
        } else {
            programState.CopyFrom(rhs.programState)
        }
        refMap.CopyFrom(rhs.refMap)
    }

    public override func Join(rhs: State<VD, Pool>): Bool {
        if (rhs.IsBottom()) {
            return false
        }
        if (IsBottom()) {
            CopyFrom(rhs)
            return true
        }
        let changed = programState.Join(rhs.programState)
        return RefMapJoin(rhs) || changed
    }

    public override func ToString(): String {
        if (IsBottom()) {
            return "Unreachable"
        }
        var out = "programState: { "
        var idx: Int64 = 0
        while (idx < programState.Size()) {
            let entry = programState.GetAt(idx)
            out += entry[0].GetIdentifier() + " -> " + entry[1].ToString() + ", "
            idx++
        }
        out += "}\nrefMap: { "
        var refIdx: Int64 = 0
        while (refIdx < refMap.Size()) {
            let entry = refMap.GetAt(refIdx)
            out += entry[0].GetUniqueID() + " -> "
            match (entry[1]) {
                case RefMapValue.RefTarget(refValue) => out += refValue.GetUniqueID()
                case RefMapValue.ObjectTarget(obj) => out += obj.GetIdentifier()
            }
            out += ", "
            refIdx++
        }
        return out + "}"
    }

    public func Update(dest: Value, refValue: Ref): Unit {
        programState.SetRef(dest, refValue)
    }

    public func Update(dest: Value, domain: VD): Unit {
        programState.Insert(dest, domain)
    }

    public func SetToBound(dest: Value, isTop: Bool): Unit {
        programState.SetBound(dest, isTop)
    }

    public func TrySetToTopOrTopRef(dest: Value, isRef: Bool): Unit {
        if (programState.Contains(dest)) {
            return
        }
        InitToTopOrTopRef(dest, isRef)
    }

    public func SetToTopOrTopRef(dest: Value, isRef: Bool): Unit {
        if (isRef) {
            programState.SetRef(dest, Ref.GetTopRefInstance())
        } else {
            programState.SetBound(dest, true)
        }
    }

    public func GetAbstractDomain(obj: Value): Option<VD> {
        var absObj: Option<Value> = obj
        if (let Some(ty) <- obj.GetType()) {
            if (ty.IsRef()) {
                absObj = match (CheckAbstractObjectRefBy(obj)) {
                    case Some(realObj) => Some(realObj)
                    case None => None
                }
            }
        }
        if (let Some(value) <- absObj) {
            return CheckAbstractValueWithTopBottom(value)
        }
        return None
    }

    public func CheckAbstractValueWithTopBottom(obj: Value): Option<VD> {
        return programState.Find(obj)
    }

    public func Propagate(src: Value, dest: Value, state!: Option<State<VD, Pool>> = None): Unit {
        let targetState = state ?? this
        targetState.PropagateWithoutChildren(src, dest, targetProgramState: Some(targetState.programState))

        let destChildrenOpt = targetState.childrenMap.Get(dest)
        let srcChildrenOpt = childrenMap.Get(src)
        if (let Some(destChildren) <- destChildrenOpt) {
            if (let Some(srcChildren) <- srcChildrenOpt) {
                CJC_ASSERT(srcChildren.size >= destChildren.size)
                var idx: Int64 = 0
                while (idx < destChildren.size) {
                    targetState.PropagateWithoutChildren(srcChildren[idx], destChildren[idx],
                        targetProgramState: Some(targetState.programState))
                    idx++
                }
            } else {
                targetState.SetNonTopChildrenStateToTop(destChildren)
            }
        } else if (let Some(srcChildren) <- srcChildrenOpt) {
            let setChildState = { child: AbstractObject, index: Int64 =>
                targetState.programState.Insert(child, programState.At(srcChildren[index]))
            }
            targetState.CreateChildren(dest, srcChildren.size, setChildState)
        }
    }

    public func CheckAbstractObjectRefBy(refVal: Value): Option<AbstractObject> {
        if (let Some(domain) <- CheckAbstractValueWithTopBottom(refVal)) {
            CJC_ASSERT(domain.GetKind() == ValueDomainKind.REF)
            if (let Some(refValue) <- domain.GetRef()) {
                if (let Some(target) <- refMap.Get(refValue)) {
                    match (target) {
                        case RefMapValue.ObjectTarget(obj) => return obj
                        case RefMapValue.RefTarget(innerRef) =>
                            if (let Some(innerTarget) <- refMap.Get(innerRef)) {
                                match (innerTarget) {
                                    case RefMapValue.ObjectTarget(obj) => return obj
                                    case RefMapValue.RefTarget(_) => return None
                                }
                            }
                    }
                }
            }
        }
        return None
    }

    public func GetChildren(obj: Value): ArrayList<AbstractObject> {
        if (let Some(children) <- childrenMap.Get(obj)) {
            return children
        }
        if (let Some(domain) <- CheckAbstractValueWithTopBottom(obj)) {
            if (domain.GetKind() == ValueDomainKind.REF) {
                if (let Some(refValue) <- domain.GetRef()) {
                    if (let Some(target) <- refMap.Get(refValue)) {
                        match (target) {
                            case RefMapValue.ObjectTarget(innerObj) => return GetChildren(innerObj)
                            case RefMapValue.RefTarget(_) => return ArrayList<AbstractObject>()
                        }
                    }
                }
            }
        }
        return ArrayList<AbstractObject>()
    }

    public func GetChild(obj: Value, index: Int64): Option<AbstractObject> {
        let children = GetChildren(obj)
        if (index < children.size) {
            return children[index]
        }
        return None
    }

    public func GetReferencedObjAndSetToTop(dest: Value, expr!: Option<Expression> = None): AbstractObject {
        if (let Some(ty) <- dest.GetType()) {
            CJC_ASSERT(ty.IsRef() || ty.IsGeneric())
        }
        let refValue = CreateNewRef(expr: expr)
        Update(dest, refValue)
        let obj = CreateNewObject(GetObjName(absObjPool.size), expr: expr)
        SetToBound(obj, true)
        refMap.Set(refValue, RefMapValue.ObjectTarget(obj))
        return obj
    }

    public func GetTwoLevelRefAndSetToTop(dest: Value, expr: Expression): AbstractObject {
        if (let Some(ty) <- dest.GetType()) {
            CJC_ASSERT(ty.IsRef())
        }
        let refOuter = CreateNewRef(expr: Some(expr))
        Update(dest, refOuter)
        let refInner = CreateNewRef(expr: Some(expr), createTwoLevelRef: true)
        refMap.Set(refOuter, RefMapValue.RefTarget(refInner))
        let obj = CreateNewObject(GetObjName(absObjPool.size), expr: Some(expr))
        refMap.Set(refInner, RefMapValue.ObjectTarget(obj))
        SetToBound(obj, true)
        return obj
    }

    public func CheckValueIsBottom(value: Value): Bool {
        if (let Some(domain) <- CheckAbstractValueWithTopBottom(value)) {
            return domain.GetKind() == ValueDomainKind.BOTTOM
        }
        return false
    }

    public func CheckValueIsTop(value: Value): Bool {
        if (let Some(domain) <- CheckAbstractValueWithTopBottom(value)) {
            return domain.GetKind() == ValueDomainKind.TOP
        }
        return false
    }

    public func CheckValueIsObject(value: Value): Bool {
        if (let Some(domain) <- CheckAbstractValueWithTopBottom(value)) {
            return domain.GetKind() == ValueDomainKind.VAL
        }
        return false
    }

    public func CheckValueIsRef(value: Value): Bool {
        if (let Some(domain) <- CheckAbstractValueWithTopBottom(value)) {
            return domain.GetKind() == ValueDomainKind.REF
        }
        return false
    }

    public func ClearState(): Unit {
        var idx: Int64 = 0
        while (idx < programState.Size()) {
            let entry = programState.GetAt(idx)
            if (entry[1].GetKind() == ValueDomainKind.VAL) {
                programState.SetBound(entry[0], true)
            }
            idx++
        }
    }

    public func CreateNewRef(expr!: Option<Expression> = None, createTwoLevelRef!: Bool = false): Ref {
        let allocateMap = if (createTwoLevelRef) { allocatedTwoLevelRefMap.getOrThrow() } else { allocatedRefMap }
        if (let Some(expression) <- expr) {
            if (let Some(existing) <- allocateMap.Find(expression)) {
                return existing
            }
            let refValue = Ref(GetRefName(refPool.size), isGlobalState)
            refPool.add(refValue)
            allocateMap.Set(expression, refValue)
            return refValue
        }
        let refValue = Ref(GetRefName(refPool.size), isGlobalState)
        refPool.add(refValue)
        return refValue
    }

    public func CreateNewObject(objectName: String, expr!: Option<Expression> = None): AbstractObject {
        let realName = if (isGlobalState) { "s" + objectName } else { objectName }
        if (let Some(expression) <- expr) {
            if (let Some(existing) <- allocatedObjMap.Find(expression)) {
                return existing
            }
            let obj = AbstractObject(realName)
            absObjPool.add(obj)
            allocatedObjMap.Set(expression, obj)
            return obj
        }
        let obj = AbstractObject(realName)
        absObjPool.add(obj)
        return obj
    }

    public func InitToTopOrTopRef(dest: Value, isRef: Bool): Unit {
        CJC_ASSERT(!programState.Contains(dest))
        if (isRef) {
            programState.SetRef(dest, Ref.GetTopRefInstance())
        } else {
            programState.SetBound(dest, true)
        }
    }

    public func PropagateWithoutChildren(src: Value, dest: Value,
        targetProgramState!: Option<Pool> = None): Unit {
        let state = targetProgramState ?? programState
        if (!src.IsParameter() && !src.IsLocalVar()) {
            CJC_ASSERT(src.IsFunc())
            if (!state.Contains(dest)) {
                state.SetBound(dest, true)
            }
            return
        }
        if (IsInstanceOfValue<VD, Pool>() && !state.Contains(src)) {
            return
        }
        if (state.Contains(dest)) {
            state.Insert(dest, programState.At(src))
        } else {
            state.Insert(dest, programState.At(src))
        }
    }

    public func CreateChildren(obj: Value, childrenNum: Int64,
        setChildState: (AbstractObject, Int64) -> Unit): Unit {
        let objName = obj.GetIdentifier()
        let children = ArrayList<AbstractObject>()
        var idx: Int64 = 0
        while (idx < childrenNum) {
            let child = CreateNewObject(GetObjChildName(objName, idx))
            setChildState(child, idx)
            children.add(child)
            idx++
        }
        if (!children.isEmpty()) {
            childrenMap.Set(obj, children)
        }
    }

    public func SetSelfAndChildrenStateToTop(value: Value): Unit {
        let obj: Option<Value> = if (value.GetType().getOrThrow().IsRef()) {
            match (CheckAbstractObjectRefBy(value)) {
                case Some(realObj) => Some(realObj)
                case None => None
            }
        } else {
            value
        }
        if (let Some(realObj) <- obj) {
            SetToBound(realObj, true)
            SetNonTopChildrenStateToTop(GetChildren(realObj))
        }
    }

    public func SetNonTopChildrenStateToTop(children: ArrayList<AbstractObject>): Unit {
        for (child in children) {
            let domain = match (CheckAbstractValueWithTopBottom(child)) {
                case Some(value) => value
                case None =>
                    if (IsInstanceOfValue<VD, Pool>()) {
                        continue
                    }
                    throw IllegalStateException("ValueAnalysis child state missing")
            }
            if (domain.GetKind() == ValueDomainKind.VAL) {
                programState.SetBound(child, true)
            }
        }
    }

    public func StoreGVChildrenState(src: Value, dest: AbstractObject, globalState: State<VD, Pool>): Unit {
        let srcChildren = childrenMap.Get(src) ?? return
        let destChildren = globalState.GetChildren(dest)
        CJC_ASSERT(srcChildren.size == destChildren.size)
        var idx: Int64 = 0
        while (idx < srcChildren.size) {
            let objState = programState.At(srcChildren[idx])
            if (objState.GetKind() == ValueDomainKind.VAL) {
                globalState.Update(destChildren[idx], objState)
            } else if (objState.GetKind() == ValueDomainKind.REF) {
                if (let Some(srcObj) <- CheckAbstractObjectRefBy(srcChildren[idx])) {
                    let targetObj = globalState.GetReferencedObjAndSetToTop(destChildren[idx])
                    PropagateWithoutChildren(srcObj, targetObj, targetProgramState: Some(globalState.programState))
                }
            }
            idx++
        }
    }

    public func LoadGVChildrenState(src: AbstractObject, dest: LocalVar, globalState: State<VD, Pool>): Unit {
        let objChildren = globalState.childrenMap.Get(src) ?? return
        let setChildState = { child: AbstractObject, index: Int64 =>
            let srcState = globalState.programState.At(objChildren[index])
            programState.Insert(child, srcState)
            if (srcState.GetKind() == ValueDomainKind.REF) {
                if (let Some(refValue) <- srcState.GetRef()) {
                    if (!refValue.IsTopRefInstance() && refMap.Get(refValue).isNone()) {
                        if (let Some(target) <- globalState.refMap.Get(refValue)) {
                            refMap.Set(refValue, target)
                            match (target) {
                                case RefMapValue.ObjectTarget(obj) =>
                                    programState.Insert(obj, globalState.programState.At(obj))
                                case RefMapValue.RefTarget(_) => ()
                            }
                        }
                    }
                }
            }
        }
        if (let Some(destChildren) <- childrenMap.Get(dest)) {
            CJC_ASSERT(objChildren.size == destChildren.size)
            var idx: Int64 = 0
            while (idx < destChildren.size) {
                setChildState(destChildren[idx], idx)
                idx++
            }
        } else {
            CreateChildren(dest, objChildren.size, setChildState)
        }
    }

    private func RefMapJoin(rhs: State<VD, Pool>): Bool {
        var changed = false
        var idx: Int64 = 0
        while (idx < rhs.refMap.Size()) {
            let rhsEntry = rhs.refMap.GetAt(idx)
            if (let Some(lhsIdx) <- refMap.Find(rhsEntry[0])) {
                changed = JoinRefMapValue(lhsIdx, rhsEntry[1], rhs) || changed
            } else {
                refMap.Set(rhsEntry[0], rhsEntry[1])
                changed = true
            }
            idx++
        }
        return changed
    }

    private func JoinRefMapValue(lhsIdx: Int64, rhsValue: RefMapValue, rhs: State<VD, Pool>): Bool {
        let lhsEntry = refMap.GetAt(lhsIdx)
        match (lhsEntry[1]) {
            case RefMapValue.RefTarget(ref1) =>
                if (ref1.IsTopRefInstance()) {
                    return false
                }
                let ref2 = match (rhsValue) {
                    case RefMapValue.RefTarget(value) => value
                    case RefMapValue.ObjectTarget(_) =>
                        throw IllegalStateException("ValueAnalysis ref-map kind mismatch")
                }
                if (ref2.IsTopRefInstance()) {
                    refMap.SetAt(lhsIdx, RefMapValue.RefTarget(Ref.GetTopRefInstance()))
                    return true
                }
                if (!refEq(ref1, ref2)) {
                    if (ref1.IsEquivalent(ref2)) {
                        return false
                    } else if (ref2.CanRepresent(ref1)) {
                        refMap.SetAt(lhsIdx, RefMapValue.RefTarget(ref2))
                        return true
                    } else if (ref1.CanRepresent(ref2)) {
                        return false
                    } else {
                        refMap.SetAt(lhsIdx, RefMapValue.RefTarget(MergeRef(ref1, ref2, rhs.programState, rhs.refMap)))
                        return true
                    }
                }
            case RefMapValue.ObjectTarget(obj1) =>
                let obj2 = match (rhsValue) {
                    case RefMapValue.ObjectTarget(value) => value
                    case RefMapValue.RefTarget(_) =>
                        throw IllegalStateException("ValueAnalysis ref-map kind mismatch")
                }
                if (!IsInstanceOfValue<VD, Pool>()) {
                    CJC_ASSERT(refEq(obj1, obj2))
                }
        }
        return false
    }

    private func MergeRef(lhs: Ref, rhs: Ref, rhsProgramState: Pool, rhsRefMap: RefMap): Ref {
        let lhsObj = GetAbsObject(refMap, lhs)
        let rhsObj = GetAbsObject(rhsRefMap, rhs)
        CJC_ASSERT(lhsObj.isSome() && rhsObj.isSome())
        let newRef = CreateNewRef()
        newRef.AddRoots(lhs, rhs)
        let newObj = CreateNewObject(GetObjName(absObjPool.size))
        let newAbsVal = programState.At(lhsObj.getOrThrow()).Clone()
        newAbsVal.Join(rhsProgramState.At(rhsObj.getOrThrow()))
        programState.Insert(newObj, newAbsVal)
        refMap.Set(newRef, RefMapValue.ObjectTarget(newObj))
        return newRef
    }

    private static func GetAbsObject(refMap: RefMap, refValue: Ref): Option<AbstractObject> {
        if (let Some(target) <- refMap.Get(refValue)) {
            match (target) {
                case RefMapValue.ObjectTarget(obj) => return obj
                case RefMapValue.RefTarget(_) => return None
            }
        }
        return None
    }
}

// C++ State::Update and State::CheckAbstractValue at ValueAnalysis.h:166-179,
// :226-232 preserve the concrete AbstractValue type carried by ValueDomain.
extend<AV, Pool> State<ValueDomain<AV>, Pool> where AV <: HasEqual<AV>,
    Pool <: ValueStatePool<ValueDomain<AV>, Pool> {
    public func Update(dest: Value, absVal: AV): Unit {
        programState.Insert(dest, ValueDomain<AV>(absVal))
    }

    public func CheckAbstractValue(obj: Value): Option<AV> {
        if (let Some(domain) <- programState.Find(obj)) {
            return domain.CheckAbsVal()
        }
        return None
    }
}
