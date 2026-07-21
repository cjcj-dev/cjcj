package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.Range as BasicRange

// C++ src/Sema/CJMP/CheckCJMP.cpp:1342-1357.
public func GetInheritedTypesWithSpecificImpl(
    inheritedTypes: ArrayList<Type>, hasSpecificImpl: Bool, compilePlatform: Bool
): Unit {
    if (!compilePlatform || hasSpecificImpl) {
        return
    }
    for (inheritedType in inheritedTypes) {
        if (let Some(decl) <- Ty.GetDeclOfTy(inheritedType.GetTy())) {
            if (let Some(specificDecl) <- decl.specificImplementation) {
                if (let Some(specificTy) <- specificDecl.GetTy()) {
                    inheritedType.SetTy(specificTy)
                }
            }
        }
    }
}

private func GetCycleOnPath(root: Decl, path: ArrayList<Decl>): ArrayList<Decl> {
    let cycle = ArrayList<Decl>()
    var foundCycleStart = false
    for (decl in path) {
        if (decl == root) {
            foundCycleStart = true
        }
        if (foundCycleStart) {
            cycle.add(decl)
        }
    }
    return cycle
}

private func IsInitRef(node: Node): Bool {
    if (let Some(target) <- node.GetTarget()) {
        return IsInstanceConstructor(target)
    }
    return false
}

private func CollectInitRefsInVar(decls: ArrayList<Decl>): ArrayList<Node> {
    let initRefsInVar = ArrayList<Node>()
    for (decl in decls) {
        if ((decl as VarDeclAbstract).isSome() && !decl.TestAttr(Attribute.STATIC)) {
            if (let Some(initializer) <- (decl as VarDeclAbstract).getOrThrow().initializer) {
                let _ = Walker(initializer, visitPre: { node: Node =>
                    if (IsInitRef(node)) {
                        initRefsInVar.add(node)
                    }
                    VisitAction.WALK_CHILDREN
                }).Walk()
            }
        }
    }
    return initRefsInVar
}

private func CollectInitRefsInVar(typeDecl: Decl): ArrayList<Node> {
    if (let Some(structDecl) <- (typeDecl as StructDecl)) {
        return CollectInitRefsInVar(structDecl.body.getOrThrow().decls)
    } else if (let Some(classDecl) <- (typeDecl as ClassDecl)) {
        return CollectInitRefsInVar(classDecl.body.getOrThrow().decls)
    }
    return ArrayList<Node>()
}

private class RecursiveCtorCtx {
    let finished = HashSet<Node>()
    let visited = HashSet<Node>()
    let ignored = HashSet<Node>()
    let typeDeclToInitRefsInVar = HashMap<Decl, ArrayList<Node>>()
    let path = ArrayList<Node>()
    var foundCycle = false

    func GetDependencies(initDecl: Decl): ArrayList<Node> {
        let typeDecl = initDecl.outerDecl.getOrThrow()
        if (!typeDeclToInitRefsInVar.contains(typeDecl)) {
            typeDeclToInitRefsInVar[typeDecl] = CollectInitRefsInVar(typeDecl)
        }
        return typeDeclToInitRefsInVar[typeDecl]
    }
}

private func VisitRecursiveCtorCtx(ctx: RecursiveCtorCtx, node: Node): VisitAction {
    ctx.path.add(node)
    if (ctx.finished.contains(node)) {
        return VisitAction.SKIP_CHILDREN
    }
    if (ctx.visited.contains(node)) {
        ctx.foundCycle = true
        return VisitAction.STOP_NOW
    }
    ctx.visited.add(node)
    return VisitAction.WALK_CHILDREN
}

private func CheckRecursiveCtorFoundCycle(ctx: RecursiveCtorCtx, decl: Node): Bool {
    let postVisit = { node: Node =>
        if (IsInstanceConstructor(node) || IsInitRef(node)) {
            ctx.path.remove(at: ctx.path.size - 1)
            ctx.finished.add(node)
        }
        VisitAction.SKIP_CHILDREN
    }
    let preVisit = { node: Node =>
        if (ctx.ignored.contains(node)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(nodeDecl) <- (node as Decl)) {
            if (let Some(annotationsArray) <- nodeDecl.annotationsArray) {
                ctx.ignored.add(annotationsArray)
                for (annotation in nodeDecl.annotations) {
                    ctx.ignored.add(annotation)
                }
            }
        }
        if (IsInstanceConstructor(node)) {
            let initDecl = (node as Decl).getOrThrow()
            if (initDecl.outerDecl.isNone()) {
                return VisitAction.STOP_NOW
            }
            let action = VisitRecursiveCtorCtx(ctx, initDecl)
            if (!action.isWalkChildren()) {
                return action
            }
            for (refNode in ctx.GetDependencies(initDecl)) {
                if (CheckRecursiveCtorFoundCycle(ctx, refNode)) {
                    return VisitAction.STOP_NOW
                }
            }
        } else if (IsInitRef(node)) {
            let action = VisitRecursiveCtorCtx(ctx, node)
            if (!action.isWalkChildren()) {
                return action
            }
            let target = node.GetTarget().getOrThrow()
            if (CheckRecursiveCtorFoundCycle(ctx, target)) {
                return VisitAction.STOP_NOW
            }
        }
        return VisitAction.WALK_CHILDREN
    }
    let _ = Walker(decl, visitPre: preVisit, visitPost: postVisit).Walk()
    return ctx.foundCycle
}

private func MakeRangeForRecursiveConstructorCall(node: Node): BasicRange {
    if (let Some(funcDecl) <- (node as FuncDecl)) {
        return MakeRangeForDeclIdentifier(funcDecl)
    }
    return MakeRange(node.begin, node.end)
}

private func DiagRecursiveConstructorCall(diag: BasicDiagnosticEngine, path: ArrayList<Node>): Unit {
    let head = path[path.size - 1]
    let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_recursive_constructor_call,
        head, MakeRangeForRecursiveConstructorCall(head))
    var cycleBegin: Int64 = 0
    while (cycleBegin < path.size && path[cycleBegin] != head) {
        cycleBegin++
    }
    var idx = cycleBegin + 1
    while (idx < path.size) {
        let node = path[idx]
        if (let Some(refExpr) <- (node as RefExpr)) {
            if (node.TestAttr(Attribute.COMPILER_ADD) && refExpr.isSuper) {
                let initDecl = (path[idx - 1] as FuncDecl).getOrThrow()
                let funcBody = initDecl.funcBody.getOrThrow()
                if (funcBody.begin == node.begin) {
                    idx++
                    continue
                }
            }
        }
        AddNote(builder, node, MakeRangeForRecursiveConstructorCall(node), "depends on")
        idx++
    }
    builder.Emit()
}

private func HasOnlyStructTypeInCycle(cycle: ArrayList<Decl>): Bool {
    var result = true
    for (decl in cycle) {
        if (decl.astKind != ASTKind.STRUCT_DECL) {
            result = false
            break
        }
    }
    return result
}

extend TypeCheckerImpl {
    public func CheckValueTypeRecursiveDFS(root: Option<Decl>, path!: ArrayList<Decl> = ArrayList<Decl>()): Unit {
        if (let None <- root) {
            return
        }
        let rootDecl = root.getOrThrow()
        match (rootDecl.checkFlag) {
            case InheritanceVisitStatus.VISITED => return
            case InheritanceVisitStatus.VISITING =>
                let cycle = GetCycleOnPath(rootDecl, path)
                if (HasOnlyStructTypeInCycle(cycle)) {
                    var message = ""
                    for (node in cycle) {
                        message += node.identifier.Val() + "->"
                    }
                    message += rootDecl.identifier.Val()
                    if (let Some(diagValue) <- diag) {
                        Diagnose(diagValue, rootDecl, BasicDiagKind.sema_value_type_recursive,
                            args: [BasicDiagArgument(message)]).Emit()
                    }
                }
                return
            case InheritanceVisitStatus.UNVISITED => ()
        }

        rootDecl.checkFlag = InheritanceVisitStatus.VISITING
        path.add(rootDecl)
        CheckValueTypeRecursiveDFSSwitch(rootDecl, path)
        path.remove(at: path.size - 1)
        rootDecl.checkFlag = InheritanceVisitStatus.VISITED
    }

    public func CheckValueTypeRecursiveDFSSwitch(root: Decl, path: ArrayList<Decl>): Unit {
        if (root.astKind != ASTKind.STRUCT_DECL && root.astKind != ASTKind.ENUM_DECL) {
            return
        }
        if ((let Some(rootTy) <- root.GetTy()) && rootTy.IsEnum() && (rootTy as RefEnumTy).isSome()) {
            return
        }
        let checkField = { decl: Decl =>
            let fieldTy = decl.GetTy().getOrThrow()
            if (fieldTy.IsEnum() && (fieldTy as RefEnumTy).isSome()) {
                return
            }
            let needCheckElemTy = (fieldTy as TupleTy).isSome() || (fieldTy as VArrayTy).isSome()
            if (!needCheckElemTy) {
                CheckValueTypeRecursiveDFS(Ty.GetDeclOfTy(Some(fieldTy)), path: path)
                return
            }
            for (elementTy in fieldTy.typeArgs) {
                CheckValueTypeRecursiveDFS(Ty.GetDeclOfTy(Some(elementTy)), path: path)
            }
        }
        if (let Some(structDecl) <- (root as StructDecl)) {
            for (decl in structDecl.body.getOrThrow().decls) {
                if (decl.astKind != ASTKind.VAR_DECL || decl.TestAttr(Attribute.STATIC)) {
                    continue
                }
                checkField(decl)
            }
        } else {
            let enumDecl = (root as EnumDecl).getOrThrow()
            for (constructor in enumDecl.constructors) {
                if (constructor.astKind != ASTKind.FUNC_DECL) {
                    continue
                }
                let funcDecl = (constructor as FuncDecl).getOrThrow()
                let funcBody = funcDecl.funcBody.getOrThrow()
                if (funcBody.paramLists.isEmpty()) {
                    continue
                }
                for (value in funcBody.paramLists[0].params) {
                    checkField(value)
                }
            }
        }
    }

    public func CheckValueTypeRecursive(pkg: Package): Unit {
        IterateToplevelDecls(pkg, { decl: Decl =>
            if (decl.astKind == ASTKind.ENUM_DECL || decl.astKind == ASTKind.STRUCT_DECL) {
                CheckValueTypeRecursiveDFS(Some(decl))
            }
        })
        for (instantiatedDecl in pkg.genericInstantiatedDecls) {
            if (instantiatedDecl.astKind == ASTKind.ENUM_DECL ||
                instantiatedDecl.astKind == ASTKind.STRUCT_DECL) {
                CheckValueTypeRecursiveDFS(Some(instantiatedDecl))
            }
        }
    }

    public func CheckRecursiveConstructorCall(decls: ArrayList<Decl>): Unit {
        if (decls.isEmpty()) {
            return
        }
        let _ = decls[0].outerDecl.getOrThrow()
        let ctx = RecursiveCtorCtx()
        for (decl in decls) {
            if ((decl.astKind == ASTKind.VAR_DECL && !decl.TestAttr(Attribute.STATIC)) ||
                IsInstanceConstructor(decl)) {
                if (CheckRecursiveCtorFoundCycle(ctx, decl)) {
                    if (let Some(diagValue) <- diag) {
                        DiagRecursiveConstructorCall(diagValue, ctx.path)
                    }
                    return
                }
            }
        }
    }
}
