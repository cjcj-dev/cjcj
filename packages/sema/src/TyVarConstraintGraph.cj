package cjcj::sema

import std.collection.*
import cjcj::ast.*

private class TyVarIndegreeEntry {
    public var tyVar: GenericsTy
    public var degree: Int64

    public init(tyVar: GenericsTy, degree: Int64) {
        this.tyVar = tyVar
        this.degree = degree
    }
}

private class TyVarEdgeEntry {
    public var tyVar: GenericsTy
    public let outs: ArrayList<GenericsTy> = ArrayList<GenericsTy>()

    public init(tyVar: GenericsTy) {
        this.tyVar = tyVar
    }
}

private class TyVarVisitedEntry {
    public var tyVar: GenericsTy
    public var visited: Bool

    public init(tyVar: GenericsTy, visited: Bool) {
        this.tyVar = tyVar
        this.visited = visited
    }
}

private func ContainsTyVar(values: ArrayList<GenericsTy>, tyVar: GenericsTy): Bool {
    for (value in values) {
        if (SameTy(value, tyVar)) {
            return true
        }
    }
    return false
}

private func AddTyVar(values: ArrayList<GenericsTy>, tyVar: GenericsTy): Bool {
    if (ContainsTyVar(values, tyVar)) {
        return false
    }
    values.add(tyVar)
    return true
}

private func CloneTyBlameEntries(entries: ArrayList<TyBlameEntry>): ArrayList<TyBlameEntry> {
    let out = ArrayList<TyBlameEntry>()
    for (entry in entries) {
        out.add(TyBlameEntry(entry.ty, blames: entry.blames.Clone()))
    }
    return out
}

private func CloneTyVarBounds(bounds: TyVarBounds): TyVarBounds {
    let out = TyVarBounds()
    out.lbs = bounds.lbs.Clone()
    out.ubs = bounds.ubs.Clone()
    out.sum = bounds.sum.Clone()
    out.eq = bounds.eq.Clone()
    for (entry in CloneTyBlameEntries(bounds.lb2Blames)) {
        out.lb2Blames.add(entry)
    }
    for (entry in CloneTyBlameEntries(bounds.ub2Blames)) {
        out.ub2Blames.add(entry)
    }
    return out
}

private func FindConstraintEntry(m: Constraint, tyVar: GenericsTy): Option<ConstraintEntry> {
    for (entry in m.entries) {
        if (SameTy(entry.tyVar, tyVar)) {
            return entry
        }
    }
    return None
}

private func AddConstraintEntry(out: Constraint, entry: ConstraintEntry): Unit {
    if (let Some(_) <- FindConstraintEntry(out, entry.tyVar)) {
        return
    }
    out.entries.add(ConstraintEntry(entry.tyVar, bounds: CloneTyVarBounds(entry.bounds)))
}

private func CollectGenericTyArgs(ty: Ty, mayUsedTyVars: ArrayList<GenericsTy>, out: ArrayList<GenericsTy>): Unit {
    if (let Some(gen) <- (ty as GenericsTy)) {
        if (ContainsTyVar(mayUsedTyVars, gen)) {
            let _ = AddTyVar(out, gen)
        }
    }
    for (arg in ty.typeArgs) {
        CollectGenericTyArgs(arg, mayUsedTyVars, out)
    }
    if (let Some(unionTy) <- (ty as UnionTy)) {
        for (item in unionTy.tys) {
            CollectGenericTyArgs(item, mayUsedTyVars, out)
        }
    } else if (let Some(intersectionTy) <- (ty as IntersectionTy)) {
        for (item in intersectionTy.tys) {
            CollectGenericTyArgs(item, mayUsedTyVars, out)
        }
    }
}

private func SubstituteTyVar(typeManager: TypeManager, tyVar: GenericsTy, subst: TypeSubst): Option<GenericsTy> {
    let newTy = typeManager.GetInstantiatedTy(tyVar, subst)
    if (let Some(newTyVar) <- (newTy as GenericsTy)) {
        return newTyVar
    }
    return None
}

public class TyVarConstraintGraph {
    private let indegree: ArrayList<TyVarIndegreeEntry> = ArrayList<TyVarIndegreeEntry>()
    private let edges: ArrayList<TyVarEdgeEntry> = ArrayList<TyVarEdgeEntry>()
    private let isVisited: ArrayList<TyVarVisitedEntry> = ArrayList<TyVarVisitedEntry>()
    private let solvedTyVars: ArrayList<GenericsTy> = ArrayList<GenericsTy>()
    private let usedTyVars: ArrayList<GenericsTy> = ArrayList<GenericsTy>()
    private var hasNext: Bool = true
    private var typeManager: TypeManager

    public init(m: Constraint, mayUsedTyVars: ArrayList<GenericsTy>, typeManager: TypeManager) {
        this.typeManager = typeManager
        PreProcessConstraintGraph(m, mayUsedTyVars)
    }

    private func FindIndegreeIndex(tyVar: GenericsTy): Option<Int64> {
        var idx: Int64 = 0
        for (entry in indegree) {
            if (SameTy(entry.tyVar, tyVar)) {
                return idx
            }
            idx++
        }
        return None
    }

    private func EnsureIndegree(tyVar: GenericsTy): TyVarIndegreeEntry {
        if (let Some(idx) <- FindIndegreeIndex(tyVar)) {
            return indegree[idx]
        }
        let entry = TyVarIndegreeEntry(tyVar, 0)
        indegree.add(entry)
        return entry
    }

    private func FindEdgeEntry(tyVar: GenericsTy): Option<TyVarEdgeEntry> {
        for (entry in edges) {
            if (SameTy(entry.tyVar, tyVar)) {
                return entry
            }
        }
        return None
    }

    private func EnsureEdgeEntry(tyVar: GenericsTy): TyVarEdgeEntry {
        if (let Some(entry) <- FindEdgeEntry(tyVar)) {
            return entry
        }
        let entry = TyVarEdgeEntry(tyVar)
        edges.add(entry)
        return entry
    }

    private func AddEdge(from: GenericsTy, to: GenericsTy): Unit {
        let edgeEntry = EnsureEdgeEntry(from)
        if (!ContainsTyVar(edgeEntry.outs, to)) {
            edgeEntry.outs.add(to)
            EnsureIndegree(to).degree++
        }
        let _ = EnsureIndegree(from)
    }

    private func SetVisited(tyVar: GenericsTy, visited: Bool): Unit {
        for (entry in isVisited) {
            if (SameTy(entry.tyVar, tyVar)) {
                entry.visited = visited
                return
            }
        }
        isVisited.add(TyVarVisitedEntry(tyVar, visited))
    }

    private func IsVisited(tyVar: GenericsTy): Bool {
        for (entry in isVisited) {
            if (SameTy(entry.tyVar, tyVar)) {
                return entry.visited
            }
        }
        return false
    }

    private func OutEdges(tyVar: GenericsTy): ArrayList<GenericsTy> {
        if (let Some(edgeEntry) <- FindEdgeEntry(tyVar)) {
            return edgeEntry.outs
        }
        return ArrayList<GenericsTy>()
    }

    private func BuildEdgesFromBounds(owner: GenericsTy, bounds: TySet, mayUsedTyVars: ArrayList<GenericsTy>): Unit {
        for (bound in bounds.values) {
            let gens = ArrayList<GenericsTy>()
            CollectGenericTyArgs(bound, mayUsedTyVars, gens)
            for (gen in gens) {
                let _ = AddTyVar(usedTyVars, gen)
                AddEdge(gen, owner)
            }
        }
    }

    public func PreProcessConstraintGraph(m: Constraint, mayUsedTyVars: ArrayList<GenericsTy>): Unit {
        indegree.clear()
        edges.clear()
        isVisited.clear()
        solvedTyVars.clear()
        usedTyVars.clear()
        hasNext = true
        for (constraint in m.entries) {
            if (!ContainsTyVar(mayUsedTyVars, constraint.tyVar)) {
                continue
            }
            let _ = AddTyVar(usedTyVars, constraint.tyVar)
            BuildEdgesFromBounds(constraint.tyVar, constraint.bounds.lbs, mayUsedTyVars)
            BuildEdgesFromBounds(constraint.tyVar, constraint.bounds.ubs, mayUsedTyVars)
        }
        for (usedKey in usedTyVars) {
            let _ = EnsureIndegree(usedKey)
            SetVisited(usedKey, false)
            let _ = EnsureEdgeEntry(usedKey)
        }
    }

    public func TopoOnce(m: Constraint): Constraint {
        let solvedConstraints = Constraint()
        if (!hasNext) {
            return solvedConstraints
        }
        for (entry in indegree) {
            if (entry.degree == 0 && !ContainsTyVar(solvedTyVars, entry.tyVar)) {
                let _ = AddTyVar(solvedTyVars, entry.tyVar)
                if (let Some(found) <- FindConstraintEntry(m, entry.tyVar)) {
                    AddConstraintEntry(solvedConstraints, found)
                }
                SetVisited(entry.tyVar, true)
            }
        }
        if (solvedTyVars.size == usedTyVars.size) {
            hasNext = false
            return solvedConstraints
        }
        if (solvedConstraints.entries.isEmpty()) {
            for (entry in indegree) {
                if (entry.degree == 1) {
                    FindLoopConstraints(m, entry.tyVar, solvedConstraints)
                    if (!solvedConstraints.entries.isEmpty()) {
                        break
                    }
                }
            }
        }
        for (solved in solvedConstraints.entries) {
            for (out in OutEdges(solved.tyVar)) {
                EnsureIndegree(out).degree--
            }
        }
        return solvedConstraints
    }

    public func ApplyTypeSubst(subst: TypeSubst): Unit {
        let newIndegree = ArrayList<TyVarIndegreeEntry>()
        for (entry in indegree) {
            if (let Some(tyVar) <- SubstituteTyVar(typeManager, entry.tyVar, subst)) {
                var hasEntry = false
                for (newEntry in newIndegree) {
                    if (SameTy(newEntry.tyVar, tyVar)) {
                        hasEntry = true
                    }
                }
                if (!hasEntry) {
                    newIndegree.add(TyVarIndegreeEntry(tyVar, entry.degree))
                }
            }
        }
        indegree.clear()
        for (entry in newIndegree) {
            indegree.add(entry)
        }

        let newEdges = ArrayList<TyVarEdgeEntry>()
        for (entry in edges) {
            if (let Some(tyVar) <- SubstituteTyVar(typeManager, entry.tyVar, subst)) {
                var hasEntry = false
                for (existing in newEdges) {
                    if (SameTy(existing.tyVar, tyVar)) {
                        hasEntry = true
                    }
                }
                if (!hasEntry) {
                    let created = TyVarEdgeEntry(tyVar)
                    for (out in entry.outs) {
                        if (let Some(newOut) <- SubstituteTyVar(typeManager, out, subst)) {
                            let _ = AddTyVar(created.outs, newOut)
                        }
                    }
                    newEdges.add(created)
                }
            }
        }
        edges.clear()
        for (entry in newEdges) {
            edges.add(entry)
        }

        ApplyTypeSubstForTyVarList(usedTyVars, subst)
        ApplyTypeSubstForTyVarList(solvedTyVars, subst)
    }

    private func ApplyTypeSubstForTyVarList(values: ArrayList<GenericsTy>, subst: TypeSubst): Unit {
        let substituted = ArrayList<GenericsTy>()
        for (tyVar in values) {
            if (let Some(newTyVar) <- SubstituteTyVar(typeManager, tyVar, subst)) {
                let _ = AddTyVar(substituted, newTyVar)
            }
        }
        values.clear()
        for (tyVar in substituted) {
            values.add(tyVar)
        }
    }

    private func FindLoopConstraints(m: Constraint, start: GenericsTy, tyVarsInLoop: Constraint): Unit {
        let loopPath = ArrayList<GenericsTy>()
        if (HasLoop(start, loopPath)) {
            var idx = loopPath.size - 1
            while (idx >= 0) {
                let tyVar = loopPath[idx]
                let _ = AddTyVar(solvedTyVars, tyVar)
                if (let Some(found) <- FindConstraintEntry(m, tyVar)) {
                    AddConstraintEntry(tyVarsInLoop, found)
                }
                idx--
            }
        }
    }

    private func HasLoop(start: GenericsTy, loopPath: ArrayList<GenericsTy>): Bool {
        if (IsVisited(start)) {
            return true
        }
        loopPath.add(start)
        SetVisited(start, true)
        for (out in OutEdges(start)) {
            if (HasLoop(out, loopPath)) {
                return true
            }
        }
        SetVisited(start, false)
        loopPath.remove(at: loopPath.size - 1)
        return false
    }
}
