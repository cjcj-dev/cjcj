package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

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

public class TySet {
    public let values: ArrayList<Ty> = ArrayList<Ty>()

    public init() {}

    public init(values: Array<Ty>) {
        for (ty in values) {
            Add(ty)
        }
    }

    public func Add(ty: Ty): Bool {
        if (Contains(ty)) {
            return false
        }
        values.add(ty)
        return true
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
        var idx: Int64 = 0
        while (idx < values.size) {
            if (SameTy(values[idx], ty)) {
                values.remove(at: idx)
                return true
            }
            idx++
        }
        return false
    }

    public func IsEmpty(): Bool {
        return values.isEmpty()
    }

    public func Size(): Int64 {
        return values.size
    }

    public func Clear(): Unit {
        values.clear()
    }

    public func Clone(): TySet {
        let out = TySet()
        for (ty in values) {
            out.Add(ty)
        }
        return out
    }

    public func ToString(): String {
        let parts = ArrayList<String>()
        for (ty in values) {
            parts.add(ty.String())
        }
        return "{" + JoinStrings(parts, ", ") + "}"
    }
}

public class BlameSet {
    public let values: ArrayList<Blame> = ArrayList<Blame>()

    public init() {}

    public func Add(blame: Blame): Unit {
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
