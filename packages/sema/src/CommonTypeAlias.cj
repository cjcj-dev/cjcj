package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::utils.{CJC_ASSERT, PData, VersionID}

public enum BlameStyle {
    | ARGUMENT
    | RETURN
    | CONSTRAINT
}

private func BlameStyleIndex(style: BlameStyle): Int64 {
    return match (style) {
        case BlameStyle.ARGUMENT => 0
        case BlameStyle.RETURN => 1
        case BlameStyle.CONSTRAINT => 2
    }
}

extend BlameStyle <: Equatable<BlameStyle> {
    public operator func ==(right: BlameStyle): Bool {
        return BlameStyleIndex(this) == BlameStyleIndex(right)
    }

    public operator func !=(right: BlameStyle): Bool {
        return !(this == right)
    }
}

public class Blame {
    public var src: Option<Node> = None
    public var lb: Option<Ty> = None
    public var ub: Option<Ty> = None
    public var style: BlameStyle = BlameStyle.ARGUMENT

    public init() {}

    public init(src!: Option<Node> = None, lb!: Option<Ty> = None, ub!: Option<Ty> = None,
        style!: BlameStyle = BlameStyle.ARGUMENT) {
        this.src = src
        this.lb = lb
        this.ub = ub
        this.style = style
    }

    public func Less(rhs: Blame): Bool {
        if (let Some(rightNode) <- rhs.src) {
            if (let Some(leftNode) <- src) {
                return leftNode.begin < rightNode.begin ||
                    (leftNode.begin == rightNode.begin && leftNode.end < rightNode.end)
            }
            return true
        }
        return false
    }

    public func ToString(): String {
        let lower = Ty.ToString(lb)
        let upper = Ty.ToString(ub)
        return "${BlameStyleToString(style)}:${lower}<:${upper}"
    }
}

public func BlameStyleToString(style: BlameStyle): String {
    return match (style) {
        case BlameStyle.ARGUMENT => "argument"
        case BlameStyle.RETURN => "return"
        case BlameStyle.CONSTRAINT => "constraint"
    }
}

public type TyVars = ArrayList<GenericsTy>

public class TySet {
    public let values: ArrayList<Ty> = ArrayList<Ty>()
    private let log: ArrayList<ArrayList<(Bool, Ty)>> = ArrayList<ArrayList<(Bool, Ty)>>()
    private let stashes: ArrayList<ArrayList<ArrayList<(Bool, Ty)>>> =
        ArrayList<ArrayList<ArrayList<(Bool, Ty)>>>()

    public init() {
        commit()
    }

    public init(values: Array<Ty>) {
        for (ty in values) {
            if (!Contains(ty)) {
                this.values.add(ty)
            }
        }
        commit()
    }

    public init(other: TySet) {
        for (ty in other.values) {
            values.add(ty)
        }
        for (entries in other.log) {
            let cloned = ArrayList<(Bool, Ty)>()
            for (entry in entries) {
                cloned.add(entry)
            }
            log.add(cloned)
        }
        for (stashGroup in other.stashes) {
            let clonedGroup = ArrayList<ArrayList<(Bool, Ty)>>()
            for (stash in stashGroup) {
                let cloned = ArrayList<(Bool, Ty)>()
                for (entry in stash) {
                    cloned.add(entry)
                }
                clonedGroup.add(cloned)
            }
            stashes.add(clonedGroup)
        }
    }

    public func Add(ty: Ty): Bool {
        checkIn(ty)
        return insert(ty)
    }

    public func AddAll(other: TySet): Unit {
        for (ty in other.values) {
            Add(ty)
        }
    }

    public func Contains(ty: Ty): Bool {
        for (value in values) {
            if (SameTy(value, ty)) {
                return true
            }
        }
        return false
    }

    public func Remove(ty: Ty): Bool {
        checkOut(ty)
        return erase(ty)
    }

    public func IsEmpty(): Bool {
        return values.isEmpty()
    }

    public func Size(): Int64 {
        return values.size
    }

    public func Clear(): Unit {
        values.clear()
        log.clear()
        stashes.clear()
        commit()
    }

    public func Clone(): TySet {
        return TySet(this)
    }

    public func ToString(): String {
        let parts = ArrayList<String>()
        for (ty in values) {
            parts.add(ty.String())
        }
        return "{" + JoinStrings(parts, ", ") + "}"
    }

    public func softClear(): Unit {
        let oldValues = ArrayList<Ty>()
        for (value in values) {
            oldValues.add(value)
        }
        for (value in oldValues) {
            Remove(value)
        }
    }

    public func commit(): Unit {
        log.add(ArrayList<(Bool, Ty)>())
        stashes.add(ArrayList<ArrayList<(Bool, Ty)>>())
    }

    public func reset(): Unit {
        CJC_ASSERT(!log.isEmpty())
        let last = log[log.size - 1]
        var idx = last.size - 1
        while (idx >= 0) {
            resetOne(last[idx])
            idx--
        }
        last.clear()
    }

    public func stash(): VersionID {
        CJC_ASSERT(!stashes.isEmpty())
        let lastLog = log[log.size - 1]
        let currentStashes = stashes[stashes.size - 1]
        let cloned = ArrayList<(Bool, Ty)>()
        for (entry in lastLog) {
            cloned.add(entry)
        }
        currentStashes.add(cloned)
        reset()
        return currentStashes.size
    }

    public func apply(version: VersionID): Unit {
        if (version == 0) {
            return
        }
        let versionRaw = version - 1
        let currentStashes = stashes[stashes.size - 1]
        CJC_ASSERT(currentStashes.size > versionRaw)
        for (entry in currentStashes[versionRaw]) {
            applyOne(entry)
        }
    }

    public func resetSoft(): Unit {
        if (log.size > 1) {
            stashes.remove(at: stashes.size - 1)
            let newLast = log[log.size - 2]
            for (entry in log[log.size - 1]) {
                newLast.add(entry)
            }
            log.remove(at: log.size - 1)
        } else {
            stashes[stashes.size - 1].clear()
        }
    }

    public func diff(): Bool {
        return log[log.size - 1].isEmpty()
    }

    private func insert(value: Ty): Bool {
        if (Contains(value)) {
            return false
        }
        values.add(value)
        return true
    }

    private func erase(value: Ty): Bool {
        var idx: Int64 = 0
        while (idx < values.size) {
            if (SameTy(values[idx], value)) {
                values.remove(at: idx)
                return true
            }
            idx++
        }
        return false
    }

    private func resetOne(entry: (Bool, Ty)): Unit {
        if (entry[0]) {
            erase(entry[1])
        } else {
            insert(entry[1])
        }
    }

    private func applyOne(entry: (Bool, Ty)): Unit {
        if (entry[0]) {
            insert(entry[1])
        } else {
            erase(entry[1])
        }
    }

    private func checkIn(value: Ty): Unit {
        if (!Contains(value)) {
            log[log.size - 1].add((true, value))
        }
    }

    private func checkOut(value: Ty): Unit {
        if (Contains(value)) {
            log[log.size - 1].add((false, value))
        }
    }
}

public type LowerBounds = TySet
public type UpperBounds = TySet

private func AddTyVarUnique(values: TyVars, tyVar: GenericsTy): Bool {
    for (value in values) {
        if (SameTy(value, tyVar)) {
            return false
        }
    }
    values.add(tyVar)
    return true
}

public func StaticToTyVars<T>(tys: ArrayList<T>): TyVars where T <: Ty {
    let ret = TyVars()
    for (ty in tys) {
        let _ = AddTyVarUnique(ret, (ty as GenericsTy).getOrThrow())
    }
    return ret
}

public func StaticToTyVars(tys: TySet): TyVars {
    let ret = TyVars()
    for (ty in tys.values) {
        let _ = AddTyVarUnique(ret, (ty as GenericsTy).getOrThrow())
    }
    return ret
}

public class BlameSet {
    public let values: ArrayList<Blame> = ArrayList<Blame>()

    public init() {}

    public func Add(blame: Blame): Unit {
        var idx: Int64 = 0
        while (idx < values.size) {
            if (values[idx].Less(blame)) {
                idx++
                continue
            }
            if (!blame.Less(values[idx])) {
                return
            }
            values.add(blame, at: idx)
            return
        }
        values.add(blame)
    }

    public func Clone(): BlameSet {
        let out = BlameSet()
        for (blame in values) {
            out.Add(blame)
        }
        return out
    }
}

public class TyBlameEntry {
    public var ty: Ty
    public var blames: BlameSet

    public init(ty: Ty, blames!: BlameSet = BlameSet()) {
        this.ty = ty
        this.blames = blames
    }
}

public class TyVarBounds {
    public var lbs: TySet = TySet()
    public var ubs: TySet = TySet()
    public var sum: TySet = TySet()
    public var eq: TySet = TySet()
    public let lb2Blames: ArrayList<TyBlameEntry> = ArrayList<TyBlameEntry>()
    public let ub2Blames: ArrayList<TyBlameEntry> = ArrayList<TyBlameEntry>()

    public init() {}

    public func ToString(): String {
        return "lbs=${lbs.ToString()}, ubs=${ubs.ToString()}, sum=${sum.ToString()}, eq=${eq.ToString()}"
    }
}

public class TypeSubstEntry {
    public var tyVar: GenericsTy
    public var ty: Ty

    public init(tyVar: GenericsTy, ty: Ty) {
        this.tyVar = tyVar
        this.ty = ty
    }
}

public class TypeSubst {
    public let entries: ArrayList<TypeSubstEntry> = ArrayList<TypeSubstEntry>()

    public init() {}

    public init(entries: Array<TypeSubstEntry>) {
        for (entry in entries) {
            Put(entry.tyVar, entry.ty)
        }
    }

    public func Put(tyVar: GenericsTy, ty: Ty): Unit {
        for (entry in entries) {
            if (SameTy(entry.tyVar, tyVar)) {
                entry.ty = ty
                return
            }
        }
        entries.add(TypeSubstEntry(tyVar, ty))
    }

    public func Get(tyVar: GenericsTy): Option<Ty> {
        for (entry in entries) {
            if (SameTy(entry.tyVar, tyVar)) {
                return entry.ty
            }
        }
        return None
    }

    public func Contains(tyVar: GenericsTy): Bool {
        if (let Some(_) <- Get(tyVar)) {
            return true
        }
        return false
    }

    public func IsEmpty(): Bool {
        return entries.isEmpty()
    }

    public func Clone(): TypeSubst {
        let out = TypeSubst()
        for (entry in entries) {
            out.Put(entry.tyVar, entry.ty)
        }
        return out
    }
}

public class MultiTypeSubstEntry {
    public var tyVar: GenericsTy
    public var tys: TySet

    public init(tyVar: GenericsTy, tys!: TySet = TySet()) {
        this.tyVar = tyVar
        this.tys = tys
    }
}

public class MultiTypeSubst {
    public let entries: ArrayList<MultiTypeSubstEntry> = ArrayList<MultiTypeSubstEntry>()

    public init() {}

    public func Put(tyVar: GenericsTy, ty: Ty): Unit {
        for (entry in entries) {
            if (SameTy(entry.tyVar, tyVar)) {
                entry.tys.Add(ty)
                return
            }
        }
        let set = TySet()
        set.Add(ty)
        entries.add(MultiTypeSubstEntry(tyVar, tys: set))
    }

    public func PutAll(tyVar: GenericsTy, tys: TySet): Unit {
        for (ty in tys.values) {
            Put(tyVar, ty)
        }
    }

    public func Get(tyVar: GenericsTy): Option<TySet> {
        for (entry in entries) {
            if (SameTy(entry.tyVar, tyVar)) {
                return entry.tys
            }
        }
        return None
    }

    public func Clone(): MultiTypeSubst {
        let out = MultiTypeSubst()
        for (entry in entries) {
            out.PutAll(entry.tyVar, entry.tys)
        }
        return out
    }
}

public class SubstPack {
    public var u2i: TypeSubst = TypeSubst()
    public var inst: MultiTypeSubst = MultiTypeSubst()

    public init() {}

    public init(u2i: TypeSubst, inst: MultiTypeSubst) {
        this.u2i = u2i
        this.inst = inst
    }

    public func Clone(): SubstPack {
        return SubstPack(u2i.Clone(), inst.Clone())
    }

    public func Merge(other: SubstPack): Unit {
        for (entry in other.u2i.entries) {
            u2i.Put(entry.tyVar, entry.ty)
        }
        for (entry in other.inst.entries) {
            inst.PutAll(entry.tyVar, entry.tys)
        }
    }
}

public func StableTyCmp(ty1: Option<Ty>, ty2: Option<Ty>): Bool {
    return CompTyByNames(ty1, ty2)
}

public func StableTyCmp(ty1: Ty, ty2: Ty): Bool {
    return StableTyCmp(Some(ty1), Some(ty2))
}

public class StableTys {
    public let values: ArrayList<Ty> = ArrayList<Ty>()

    public init() {}

    public init(tys: TySet) {
        for (ty in tys.values) {
            Add(ty)
        }
    }

    public func Add(ty: Ty): Bool {
        var idx: Int64 = 0
        while (idx < values.size) {
            if (StableTyCmp(values[idx], ty)) {
                idx++
                continue
            }
            if (!StableTyCmp(ty, values[idx])) {
                return false
            }
            values.add(ty, at: idx)
            return true
        }
        values.add(ty)
        return true
    }
}

public class StableTyVars {
    public let values: ArrayList<GenericsTy> = ArrayList<GenericsTy>()

    public init() {}

    public init(tys: TyVars) {
        for (ty in tys) {
            Add(ty)
        }
    }

    public func Add(ty: GenericsTy): Bool {
        var idx: Int64 = 0
        while (idx < values.size) {
            if (StableTyCmp(values[idx], ty)) {
                idx++
                continue
            }
            if (!StableTyCmp(ty, values[idx])) {
                return false
            }
            values.add(ty, at: idx)
            return true
        }
        values.add(ty)
        return true
    }
}

public class ConstraintEntry {
    public var tyVar: GenericsTy
    public var bounds: TyVarBounds

    public init(tyVar: GenericsTy, bounds!: TyVarBounds = TyVarBounds()) {
        this.tyVar = tyVar
        this.bounds = bounds
    }
}

public class Constraint {
    public let entries: ArrayList<ConstraintEntry> = ArrayList<ConstraintEntry>()

    public init() {}

    public func GetOrCreate(tyVar: GenericsTy): TyVarBounds {
        for (entry in entries) {
            if (SameTy(entry.tyVar, tyVar)) {
                return entry.bounds
            }
        }
        let created = ConstraintEntry(tyVar)
        entries.add(created)
        return created.bounds
    }

    public func Clear(): Unit {
        entries.clear()
    }

    public func CommitScope(): ConstraintPDataCommitScope {
        return PData.CommitScope(this)
    }

    public func Reset(): Unit {
        PData.Reset(this)
    }
}

public class Constraints {
    public let values: ArrayList<Constraint> = ArrayList<Constraint>()
    public init() {}
}

public enum SolvingErrStyle {
    | DEFAULT
    | NO_CONSTRAINT
    | CONFLICTING_CONSTRAINTS
    | ARG_MISMATCH
    | RET_MISMATCH
}

public class SolvingErrInfo {
    public var style: SolvingErrStyle = SolvingErrStyle.DEFAULT
    public var tyVar: Option<GenericsTy> = None
    public let lbs: ArrayList<Ty> = ArrayList<Ty>()
    public let ubs: ArrayList<Ty> = ArrayList<Ty>()
    public let blames: ArrayList<BlameSet> = ArrayList<BlameSet>()

    public init() {}
}

public class ErrOrSubst {
    public var error: Option<SolvingErrInfo> = None
    public var subst: Option<TypeSubst> = None

    public init(error: SolvingErrInfo) {
        this.error = error
    }

    public init(subst: TypeSubst) {
        this.subst = subst
    }

    public func IsError(): Bool {
        if (let Some(_) <- error) {
            return true
        }
        return false
    }
}

public type CstVersionID = ArrayList<(GenericsTy, (VersionID, VersionID, VersionID, VersionID))>

extend PData {
    public static func CommitScope(data: Constraint): ConstraintPDataCommitScope {
        return ConstraintPDataCommitScope(data)
    }

    public static func Commit(data: Constraint): Unit {
        for (entry in data.entries) {
            entry.bounds.lbs.commit()
            entry.bounds.ubs.commit()
            entry.bounds.sum.commit()
            entry.bounds.eq.commit()
        }
    }

    public static func Reset(data: Constraint): Unit {
        for (entry in data.entries) {
            entry.bounds.lbs.reset()
            entry.bounds.ubs.reset()
            entry.bounds.sum.reset()
            entry.bounds.eq.reset()
        }
    }

    public static func Stash(data: Constraint): CstVersionID {
        let ver = CstVersionID()
        for (entry in data.entries) {
            let id1 = entry.bounds.lbs.stash()
            let id2 = entry.bounds.ubs.stash()
            let id3 = entry.bounds.sum.stash()
            let id4 = entry.bounds.eq.stash()
            ver.add((entry.tyVar, (id1, id2, id3, id4)))
        }
        return ver
    }

    public static func Apply(data: Constraint, version: CstVersionID): Unit {
        for (entry in version) {
            let bounds = data.GetOrCreate(entry[0])
            let ids = entry[1]
            bounds.lbs.apply(ids[0])
            bounds.ubs.apply(ids[1])
            bounds.sum.apply(ids[2])
            bounds.eq.apply(ids[3])
        }
    }

    public static func ResetSoft(data: Constraint): Unit {
        for (entry in data.entries) {
            entry.bounds.lbs.resetSoft()
            entry.bounds.ubs.resetSoft()
            entry.bounds.sum.resetSoft()
            entry.bounds.eq.resetSoft()
        }
    }
}

public class ConstraintPDataCommitScope <: Resource {
    private let data: Constraint
    private var closed: Bool = false

    public init(data: Constraint) {
        this.data = data
        PData.Commit(data)
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        PData.ResetSoft(data)
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

public func ToStringC(c: Constraint): String {
    let parts = ArrayList<String>()
    for (entry in c.entries) {
        parts.add("${entry.tyVar.String()} -> ${entry.bounds.ToString()}")
    }
    return "[" + JoinStrings(parts, "; ") + "]"
}

public func ToStringS(m: TypeSubst): String {
    let parts = ArrayList<String>()
    for (entry in m.entries) {
        parts.add("${entry.tyVar.String()} |-> ${entry.ty.String()}")
    }
    return "[" + JoinStrings(parts, ", ") + "]"
}

public func ToStringMS(m: MultiTypeSubst): String {
    let parts = ArrayList<String>()
    for (entry in m.entries) {
        parts.add("${entry.tyVar.String()} |-> ${entry.tys.ToString()}")
    }
    return "[" + JoinStrings(parts, ", ") + "]"
}

public func ToStringP(m: SubstPack): String {
    return "u2i=${ToStringS(m.u2i)}, inst=${ToStringMS(m.inst)}"
}
