package cangjie_compiler::chir

import std.collection.*

public enum AnalysisKind {
    | MUST | MAYBE
}

public func AnalysisKindIndex(kind: AnalysisKind): Int64 {
    return match (kind) {
        case AnalysisKind.MUST => 0
        case AnalysisKind.MAYBE => 1
    }
}

extend AnalysisKind <: Equatable<AnalysisKind> {
    public operator func ==(right: AnalysisKind): Bool {
        return AnalysisKindIndex(this) == AnalysisKindIndex(right)
    }

    public operator func !=(right: AnalysisKind): Bool {
        return !(this == right)
    }
}

public abstract class GenKillDomain<Domain> <: AbstractDomain<Domain> {
    private var reachable: Bool = false
    private let states: ArrayList<Bool> = ArrayList<Bool>()

    public init(domainSize: Int64) {
        super()
        var idx: Int64 = 0
        while (idx < domainSize) {
            states.add(false)
            idx++
        }
    }

    public func IsReachable(): Bool {
        return reachable
    }

    public func SetReachable(value: Bool): Unit {
        reachable = value
        kind = if (value) { ReachableKind.REACHABLE } else { ReachableKind.UNREACHABLE }
    }

    public override func IsBottom(): Bool {
        return !reachable
    }

    public func Size(): Int64 {
        return states.size
    }

    public func JoinStates(rhs: GenKillDomain<Domain>, kind: AnalysisKind): Bool {
        if (!rhs.reachable) {
            return false
        }
        if (!reachable) {
            CopyBaseFrom(rhs)
            return true
        }
        var changed = false
        var idx: Int64 = 0
        while (idx < states.size && idx < rhs.states.size) {
            let oldState = states[idx]
            states[idx] = if (kind == AnalysisKind.MUST) { oldState && rhs.states[idx] } else { oldState || rhs.states[idx] }
            changed = changed || oldState != states[idx]
            idx++
        }
        return changed
    }

    public func CopyBaseFrom(rhs: GenKillDomain<Domain>): Unit {
        reachable = rhs.reachable
        kind = rhs.kind
        states.clear()
        for (state in rhs.states) {
            states.add(state)
        }
    }

    public func Gen(index: Int64): Unit {
        if (index >= 0 && index < states.size) {
            states[index] = true
        }
    }

    public func Kill(index: Int64): Unit {
        if (index >= 0 && index < states.size) {
            states[index] = false
        }
    }

    public func GenAll(): Unit {
        var idx: Int64 = 0
        while (idx < states.size) {
            states[idx] = true
            idx++
        }
    }

    public func KillAll(): Unit {
        var idx: Int64 = 0
        while (idx < states.size) {
            states[idx] = false
            idx++
        }
    }

    public func PropagateFrom(from: Int64, to: Int64): Unit {
        if (from >= 0 && from < states.size && to >= 0 && to < states.size) {
            states[to] = states[from]
        }
    }

    public func IsTrueAt(index: Int64): Bool {
        if (index >= 0 && index < states.size) {
            return states[index]
        }
        return false
    }

    public override func ToString(): String {
        if (!reachable) {
            return "Unreachable"
        }
        let parts = ArrayList<String>()
        for (state in states) {
            parts.add(if (state) { "1" } else { "0" })
        }
        return "Reachable(" + JoinStrings(parts, " ") + ")"
    }
}
