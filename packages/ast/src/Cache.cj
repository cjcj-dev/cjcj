package cjcj::ast

import cjcj::basic.DiagnosticCache
import std.collection.*

public class TargetCache {
    public var first: Option<Decl> = None
    public var second: Option<Decl> = None

    public init() {}

    public init(first: Option<Decl>, second: Option<Decl>) {
        this.first = first
        this.second = second
    }
}

public class CacheEntry {
    public var successful: Bool
    public var result: Option<Ty>
    public var diags: DiagnosticCache
    public var targets: TargetCache

    public init(successful: Bool, result: Option<Ty>, diags: DiagnosticCache, targets: TargetCache) {
        this.successful = successful
        this.result = result
        this.diags = diags
        this.targets = targets
    }
}

public class CacheKey <: Hashable & Equatable<CacheKey> {
    public var target: Option<Ty> = None
    public var isDesugared: Bool = false
    public var diagKey: Int64 = 0

    public init() {}

    public init(target: Option<Ty>, isDesugared: Bool, diagKey: Int64) {
        this.target = target
        this.isDesugared = isDesugared
        this.diagKey = diagKey
    }

    public operator func ==(right: CacheKey): Bool {
        return sameTy(target, right.target) && isDesugared == right.isDesugared && diagKey == right.diagKey
    }

    public operator func !=(right: CacheKey): Bool {
        return !(this == right)
    }

    public func hashCode(): Int64 {
        var out = diagKey
        if (isDesugared) {
            out = out ^ 0x9e3779b9
        }
        if (let Some(value) <- target) {
            out = out ^ value.objectId.hashCode()
        }
        return out
    }

    private func sameTy(left: Option<Ty>, right: Option<Ty>): Bool {
        if (let Some(l) <- left) {
            if (let Some(r) <- right) {
                return Ptr<Ty>(l) == Ptr<Ty>(r)
            }
            return false
        }
        if (let Some(_) <- right) {
            return false
        }
        return true
    }
}

public class TypeCheckCache {
    public let synCache: HashMap<CacheKey, CacheEntry> = HashMap<CacheKey, CacheEntry>(0)
    public let chkCache: HashMap<CacheKey, CacheEntry> = HashMap<CacheKey, CacheEntry>(0)
    public var lastKey: Option<CacheKey> = None
    public init() {}
}

public class MemSig <: Hashable & Equatable<MemSig> {
    public var id: String = ""
    public var isVarOrProp: Bool = false
    public var arity: UInt64 = 0
    public var genArity: UInt64 = 0

    public init() {}

    public init(id: String, isVarOrProp: Bool, arity: UInt64, genArity: UInt64) {
        this.id = id
        this.isVarOrProp = isVarOrProp
        this.arity = arity
        this.genArity = genArity
    }

    public operator func ==(right: MemSig): Bool {
        return id == right.id && isVarOrProp == right.isVarOrProp &&
            arity == right.arity && genArity == right.genArity
    }

    public operator func !=(right: MemSig): Bool {
        return !(this == right)
    }

    @OverflowWrapping
    public func hashCode(): Int64 {
        var out = id.hashCode()
        out = (out * 131) + Int64(arity)
        out = (out * 131) + Int64(genArity)
        return if (isVarOrProp) { out ^ 1 } else { out }
    }
}

public func CollectTargets(node: Node): TargetCache {
    if (let Some(arg) <- (node as FuncArg)) {
        if (let Some(expr) <- arg.expr) {
            return CollectTargets(expr)
        }
    }
    let first = node.GetTarget()
    if (let None <- first) {
        return TargetCache(None, None)
    }
    var second: Option<Decl> = None
    if (let Some(member) <- (node as MemberAccess)) {
        if (let Some(base) <- member.baseExpr) {
            if (base.IsReferenceExpr()) {
                second = base.GetTarget()
            }
        }
    }
    return TargetCache(first, second)
}

public func RestoreTargets(node: Node, targets: TargetCache): Unit {
    if (let Some(arg) <- (node as FuncArg)) {
        if (let Some(expr) <- arg.expr) {
            RestoreTargets(expr, targets)
            return
        }
    }
    node.SetTarget(targets.first)
    if (let Some(member) <- (node as MemberAccess)) {
        if (let Some(base) <- member.baseExpr) {
            if (base.IsReferenceExpr()) {
                base.SetTarget(targets.second)
            }
        }
    }
}
