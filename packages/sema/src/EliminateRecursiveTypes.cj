package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::utils.CJC_ASSERT

private class RecursiveEdgeEntry {
    public var decl: Decl
    public let targets: ArrayList<Decl> = ArrayList<Decl>()

    public init(decl: Decl) {
        this.decl = decl
    }
}

private class RecursiveEnumInEdgeEntry {
    public var enumDecl: EnumDecl
    public let inEdges: ArrayList<Decl> = ArrayList<Decl>()

    public init(enumDecl: EnumDecl) {
        this.enumDecl = enumDecl
    }
}

private class TarjanState {
    public var decl: Decl
    public var index: Int64 = -1
    public var lowlink: Int64 = -1
    public var onStack: Bool = false

    public init(decl: Decl) {
        this.decl = decl
    }
}

private class TarjanContext {
    public var index: Int64 = 0
    public let stack: ArrayList<Decl> = ArrayList<Decl>()
    public let states: ArrayList<TarjanState> = ArrayList<TarjanState>()
    public let sccs: ArrayList<RecursiveTypeGraph> = ArrayList<RecursiveTypeGraph>()

    public init() {}

    public func GetState(decl: Decl): Option<TarjanState> {
        for (state in states) {
            if (SameDecl(state.decl, decl)) {
                return state
            }
        }
        return None
    }

    public func EnsureState(decl: Decl): TarjanState {
        if (let Some(state) <- GetState(decl)) {
            return state
        }
        let state = TarjanState(decl)
        states.add(state)
        return state
    }
}

private func containsDecl(values: ArrayList<Decl>, decl: Decl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func addDeclUnique(values: ArrayList<Decl>, decl: Decl): Bool {
    if (containsDecl(values, decl)) {
        return false
    }
    values.add(decl)
    return true
}

private func isNonGenericValueDecl(decl: Decl): Bool {
    if (!Ty.IsTyCorrect(decl.GetTy())) {
        return false
    }
    if (let Some(ty) <- decl.GetTy()) {
        return !ty.HasGeneric()
    }
    return false
}

private class RecursiveTypeGraph {
    private let vertices: ArrayList<Decl> = ArrayList<Decl>()
    private let outEdges: ArrayList<RecursiveEdgeEntry> = ArrayList<RecursiveEdgeEntry>()
    private let enumInEdges: ArrayList<RecursiveEnumInEdgeEntry> = ArrayList<RecursiveEnumInEdgeEntry>()

    public init() {}

    public init(pkgs: ArrayList<PackageDecl>) {
        for (pkgDecl in pkgs) {
            AddArcs(pkgDecl.srcPackage)
        }
    }

    public func InEdges(enumDecl: EnumDecl): ArrayList<Decl> {
        if (let Some(entry) <- FindEnumInEdgeEntry(enumDecl)) {
            return entry.inEdges
        }
        return ArrayList<Decl>()
    }

    public func StronglyConnectedComponents(): ArrayList<RecursiveTypeGraph> {
        let ctx = TarjanContext()
        for (vertex in vertices) {
            if (let None <- ctx.GetState(vertex)) {
                TarjanSCC(ctx, vertex)
            }
        }
        return ctx.sccs
    }

    public func PeekEnumToBox(): Option<EnumDecl> {
        var candidate: Option<EnumDecl> = None
        var maxInDegree: Int64 = 0
        for (entry in enumInEdges) {
            let inDegree = entry.inEdges.size
            if (inDegree > maxInDegree) {
                candidate = entry.enumDecl
                maxInDegree = inDegree
            }
        }
        return candidate
    }

    public func RemoveVertex(enumDecl: EnumDecl): Unit {
        removeDecl(vertices, enumDecl)
        for (inEdge in InEdges(enumDecl)) {
            if (let Some(edgeEntry) <- FindOutEdgeEntry(inEdge)) {
                removeDecl(edgeEntry.targets, enumDecl)
            }
        }
        removeOutEdgeEntry(enumDecl)
        removeEnumInEdgeEntry(enumDecl)
    }

    private func AddVertex(decl: Decl): Unit {
        if (!isNonGenericValueDecl(decl)) {
            return
        }
        let _ = addDeclUnique(vertices, decl)
        let _ = EnsureOutEdgeEntry(decl)
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            let _ = EnsureEnumInEdgeEntry(enumDecl)
        }
    }

    private func AddArc(u: Decl, v: Decl): Unit {
        if (!isNonGenericValueDecl(u) || !isNonGenericValueDecl(v)) {
            return
        }
        AddVertex(u)
        AddVertex(v)
        let edgeEntry = EnsureOutEdgeEntry(u)
        let _ = addDeclUnique(edgeEntry.targets, v)
        if (let Some(enumDecl) <- (v as EnumDecl)) {
            let enumEntry = EnsureEnumInEdgeEntry(enumDecl)
            let _ = addDeclUnique(enumEntry.inEdges, u)
        }
    }

    private func AddArcs(decl: Decl, fieldTy: Ty): Unit {
        if (!Ty.IsTyCorrect(fieldTy)) {
            return
        }
        if ((fieldTy.IsStruct() || fieldTy.IsEnum())) {
            if (let Some(targetDecl) <- Ty.GetDeclOfTy(fieldTy)) {
                AddArc(decl, targetDecl)
            }
        } else if (let Some(tupleTy) <- (fieldTy as TupleTy)) {
            for (typeArg in tupleTy.typeArgs) {
                AddArcs(decl, typeArg)
            }
        }
    }

    private func AddArcs(structDecl: StructDecl): Unit {
        if (let Some(body) <- structDecl.body) {
            for (decl in body.decls) {
                if (decl.astKind != ASTKind.VAR_DECL || decl.TestAttr(Attribute.STATIC) || !Ty.IsTyCorrect(decl.GetTy())) {
                    continue
                }
                if (let Some(ty) <- decl.GetTy()) {
                    AddArcs(structDecl, ty)
                }
            }
        }
    }

    private func AddArcs(enumDecl: EnumDecl): Unit {
        for (constructor in enumDecl.constructors) {
            if (let Some(funcDecl) <- (constructor as FuncDecl)) {
                if (let Some(body) <- funcDecl.funcBody) {
                    if (!body.paramLists.isEmpty()) {
                        for (param in body.paramLists[0].params) {
                            if (let Some(paramTy) <- param.GetTy()) {
                                AddArcs(enumDecl, paramTy)
                            }
                        }
                    }
                }
            }
        }
    }

    private func AddArcs(decl: Decl): Unit {
        if (let Some(structDecl) <- (decl as StructDecl)) {
            AddArcs(structDecl)
        } else if (let Some(enumDecl) <- (decl as EnumDecl)) {
            AddArcs(enumDecl)
        }
    }

    private func AddArcs(pkg: Package): Unit {
        IterateToplevelDecls(pkg, { decl: Decl => AddArcs(decl) })
        for (decl in pkg.genericInstantiatedDecls) {
            AddArcs(decl)
        }
    }

    private func SubGraph(subVertices: ArrayList<Decl>): RecursiveTypeGraph {
        let subGraph = RecursiveTypeGraph()
        for (u in vertices) {
            if (!containsDecl(subVertices, u)) {
                continue
            }
            subGraph.AddVertex(u)
            if (let Some(edgeEntry) <- FindOutEdgeEntry(u)) {
                for (v in edgeEntry.targets) {
                    if (containsDecl(subVertices, v)) {
                        subGraph.AddArc(u, v)
                    }
                }
            }
        }
        return subGraph
    }

    private func TarjanSCC(ctx: TarjanContext, u: Decl): Unit {
        let uState = ctx.EnsureState(u)
        uState.index = ctx.index
        uState.lowlink = ctx.index
        ctx.index++
        ctx.stack.add(u)
        uState.onStack = true

        if (let Some(edgeEntry) <- FindOutEdgeEntry(u)) {
            for (v in edgeEntry.targets) {
                if (let Some(vState) <- ctx.GetState(v)) {
                    if (vState.onStack && vState.index < uState.lowlink) {
                        uState.lowlink = vState.index
                    }
                } else {
                    TarjanSCC(ctx, v)
                    if (let Some(updatedVState) <- ctx.GetState(v)) {
                        if (updatedVState.lowlink < uState.lowlink) {
                            uState.lowlink = updatedVState.lowlink
                        }
                    }
                }
            }
        }

        if (uState.lowlink == uState.index) {
            let subVertices = ArrayList<Decl>()
            var done = false
            while (!done && !ctx.stack.isEmpty()) {
                let w = ctx.stack[ctx.stack.size - 1]
                ctx.stack.remove(at: ctx.stack.size - 1)
                if (let Some(wState) <- ctx.GetState(w)) {
                    wState.onStack = false
                }
                subVertices.add(w)
                done = SameDecl(w, u)
            }
            ctx.sccs.add(SubGraph(subVertices))
        }
    }

    private func EnsureOutEdgeEntry(decl: Decl): RecursiveEdgeEntry {
        if (let Some(entry) <- FindOutEdgeEntry(decl)) {
            return entry
        }
        let entry = RecursiveEdgeEntry(decl)
        outEdges.add(entry)
        return entry
    }

    private func FindOutEdgeEntry(decl: Decl): Option<RecursiveEdgeEntry> {
        for (entry in outEdges) {
            if (SameDecl(entry.decl, decl)) {
                return entry
            }
        }
        return None
    }

    private func EnsureEnumInEdgeEntry(enumDecl: EnumDecl): RecursiveEnumInEdgeEntry {
        if (let Some(entry) <- FindEnumInEdgeEntry(enumDecl)) {
            return entry
        }
        let entry = RecursiveEnumInEdgeEntry(enumDecl)
        enumInEdges.add(entry)
        return entry
    }

    private func FindEnumInEdgeEntry(enumDecl: EnumDecl): Option<RecursiveEnumInEdgeEntry> {
        for (entry in enumInEdges) {
            if (SameDecl(entry.enumDecl, enumDecl)) {
                return entry
            }
        }
        return None
    }

    private func removeOutEdgeEntry(decl: Decl): Unit {
        var idx: Int64 = 0
        while (idx < outEdges.size) {
            if (SameDecl(outEdges[idx].decl, decl)) {
                outEdges.remove(at: idx)
                return
            }
            idx++
        }
    }

    private func removeEnumInEdgeEntry(enumDecl: EnumDecl): Unit {
        var idx: Int64 = 0
        while (idx < enumInEdges.size) {
            if (SameDecl(enumInEdges[idx].enumDecl, enumDecl)) {
                enumInEdges.remove(at: idx)
                return
            }
            idx++
        }
    }

    private func removeDecl(values: ArrayList<Decl>, decl: Decl): Unit {
        var idx: Int64 = 0
        while (idx < values.size) {
            if (SameDecl(values[idx], decl)) {
                values.remove(at: idx)
                return
            }
            idx++
        }
    }
}

private func checkAndUpdateDeclTyWithNewTy(decl: Decl, specifiedTy: EnumTy, typeManager: TypeManager): Unit {
    if (let Some(declTy) <- decl.GetTy()) {
        if (let Some(tupleTy) <- (declTy as TupleTy)) {
            var hasSpecifiedTy = false
            for (typeArg in tupleTy.typeArgs) {
                if (SameTy(typeArg, specifiedTy)) {
                    hasSpecifiedTy = true
                    break
                }
            }
            if (!hasSpecifiedTy) {
                return
            }
            let vec = ArrayList<Ty>()
            for (elemTy in tupleTy.typeArgs) {
                if (SameTy(elemTy, specifiedTy)) {
                    if (let Some(enumDecl) <- specifiedTy.declPtr) {
                        let newTy = typeManager.GetRefEnumTy(enumDecl, CopyTypeArgs(specifiedTy.typeArgs))
                        specifiedTy.hasCorrespondRefEnumTy = true
                        newTy.decl = specifiedTy.decl
                        vec.add(newTy)
                    } else {
                        vec.add(elemTy)
                    }
                } else {
                    vec.add(elemTy)
                }
            }
            decl.SetTy(typeManager.GetTupleTy(vec.toArray()))
        } else if (SameTy(declTy, specifiedTy)) {
            if (let Some(enumDecl) <- specifiedTy.declPtr) {
                let newTy = typeManager.GetRefEnumTy(enumDecl, CopyTypeArgs(specifiedTy.typeArgs))
                specifiedTy.hasCorrespondRefEnumTy = true
                newTy.decl = specifiedTy.decl
                decl.SetTy(newTy)
            }
        }
    }
}

public func UpdateMemberVariableTy(decl: Decl, enumTy: EnumTy, typeManager: TypeManager): Unit {
    if (let Some(structDecl) <- (decl as StructDecl)) {
        if (let Some(body) <- structDecl.body) {
            for (member in body.decls) {
                if (member.astKind != ASTKind.VAR_DECL || member.TestAttr(Attribute.STATIC)) {
                    continue
                }
                checkAndUpdateDeclTyWithNewTy(member, enumTy, typeManager)
            }
        }
    } else if (let Some(enumDecl) <- (decl as EnumDecl)) {
        for (constructor in enumDecl.constructors) {
            if (let Some(funcDecl) <- (constructor as FuncDecl)) {
                if (let Some(body) <- funcDecl.funcBody) {
                    if (!body.paramLists.isEmpty()) {
                        for (param in body.paramLists[0].params) {
                            checkAndUpdateDeclTyWithNewTy(param, enumTy, typeManager)
                        }
                    }
                }
            }
        }
    } else {
        CJC_ASSERT(false)
    }
}

public func PerformRecursiveTypesElimination(importedPkgs: ArrayList<PackageDecl>, typeManager: TypeManager): Unit {
    let graph = RecursiveTypeGraph(importedPkgs)
    let sccs = graph.StronglyConnectedComponents()
    while (!sccs.isEmpty()) {
        let scc = sccs[sccs.size - 1]
        sccs.remove(at: sccs.size - 1)
        if (let Some(enumDecl) <- scc.PeekEnumToBox()) {
            if (let Some(declTy) <- enumDecl.GetTy()) {
                if (let Some(enumTy) <- (declTy as EnumTy)) {
                for (u in scc.InEdges(enumDecl)) {
                    UpdateMemberVariableTy(u, enumTy, typeManager)
                }
                scc.RemoveVertex(enumDecl)
                for (subScc in scc.StronglyConnectedComponents()) {
                    sccs.add(subScc)
                }
                }
            }
        }
    }
}

public func EliminateRecursiveTypes(importedPkgs: ArrayList<PackageDecl>, typeManager: TypeManager): Unit {
    PerformRecursiveTypesElimination(importedPkgs, typeManager)
}
