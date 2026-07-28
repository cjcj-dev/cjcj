package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.Range as BasicRange

// INT32_MAX: CodeGen array-copy chunk ABI limit (IRBuilder.cj:5721-5723).
private let ARRAY_ELEMENT_SIZE_LIMIT: Int64 = 2147483647

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

    // L240 / arrchunk: CodeGen only had InternalError for elementSize > INT32_MAX
    // (packages/codegen/src/IRBuilder.cj:5721-5723). Official C++ has no CodeGen/Sema
    // diagnostic channel for this limit either. Raise a formal sema diagnostic when a
    // static lower-bound layout of an array element type exceeds INT32_MAX (2GiB-1).
    // Only diagnose when the lower bound is proven; never reject smaller legal types.
    private func LayoutVisitedContains(visited: ArrayList<Ty>, ty: Ty): Bool {
        for (seen in visited) {
            if (SameTy(seen, ty)) {
                return true
            }
        }
        return false
    }

    private func PrimitiveLayoutSize(kind: TypeKind): Option<Int64> {
        match (kind) {
            case TypeKind.TYPE_UNIT | TypeKind.TYPE_NOTHING => Some(0)
            case TypeKind.TYPE_BOOLEAN => Some(1)
            case TypeKind.TYPE_INT8 | TypeKind.TYPE_UINT8 => Some(1)
            case TypeKind.TYPE_INT16 | TypeKind.TYPE_UINT16 => Some(2)
            case TypeKind.TYPE_INT32 | TypeKind.TYPE_UINT32 | TypeKind.TYPE_RUNE => Some(4)
            case TypeKind.TYPE_INT64 | TypeKind.TYPE_UINT64 => Some(8)
            case TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT_NATIVE => Some(8)
            case TypeKind.TYPE_FLOAT16 => Some(2)
            case TypeKind.TYPE_FLOAT32 => Some(4)
            case TypeKind.TYPE_FLOAT64 => Some(8)
            case _ => None
        }
    }

    private func SaturatingMul(a: Int64, b: Int64): Int64 {
        if (a <= 0 || b <= 0) {
            return 0
        }
        if (a > ARRAY_ELEMENT_SIZE_LIMIT || b > ARRAY_ELEMENT_SIZE_LIMIT) {
            return ARRAY_ELEMENT_SIZE_LIMIT + 1
        }
        if (a > (ARRAY_ELEMENT_SIZE_LIMIT + 1) / b) {
            return ARRAY_ELEMENT_SIZE_LIMIT + 1
        }
        return a * b
    }

    private func SaturatingAdd(a: Int64, b: Int64): Int64 {
        if (a > ARRAY_ELEMENT_SIZE_LIMIT || b > ARRAY_ELEMENT_SIZE_LIMIT) {
            return ARRAY_ELEMENT_SIZE_LIMIT + 1
        }
        if (a > (ARRAY_ELEMENT_SIZE_LIMIT + 1) - b) {
            return ARRAY_ELEMENT_SIZE_LIMIT + 1
        }
        return a + b
    }

    // Lower-bound layout size in bytes. None = cannot prove a bound (generic/unknown).
    // Proven sizes use conservative lower bounds for reference-like types (pointer width).
    private func EstimateLayoutLowerBound(ty: Ty, visited: ArrayList<Ty>): Option<Int64> {
        if (!Ty.IsTyCorrect(ty) || ty.IsGeneric() || ty.HasGeneric()) {
            return None
        }
        if (let Some(size) <- PrimitiveLayoutSize(ty.kind)) {
            return Some(size)
        }
        if (ty.IsClassLike() || ty.IsFunc() || ty.IsPointer() || ty.IsCString() || ty.IsArray() ||
            ty.IsStructArray()) {
            // Reference / heap header / fat-pointer lower bound; never alone exceeds 2GiB.
            return Some(8)
        }
        if (let Some(varrayTy) <- (ty as VArrayTy)) {
            if (varrayTy.typeArgs.isEmpty()) {
                return None
            }
            if (varrayTy.size < 0) {
                return None
            }
            let elemBound = EstimateLayoutLowerBound(varrayTy.typeArgs[0], visited) ?? return None
            return Some(SaturatingMul(varrayTy.size, elemBound))
        }
        if (let Some(tupleTy) <- (ty as TupleTy)) {
            var total: Int64 = 0
            for (elem in tupleTy.typeArgs) {
                let elemBound = EstimateLayoutLowerBound(elem, visited) ?? return None
                total = SaturatingAdd(total, elemBound)
            }
            return Some(total)
        }
        if (LayoutVisitedContains(visited, ty)) {
            // Recursive value types are diagnosed elsewhere; do not invent a size.
            return None
        }
        if (let Some(structTy) <- (ty as StructTy)) {
            if (let None <- structTy.declPtr) {
                return None
            }
            let decl = structTy.declPtr.getOrThrow()
            if (structTy.IsString() || structTy.IsRange()) {
                return Some(8)
            }
            visited.add(ty)
            var total: Int64 = 0
            var ok = true
            for (member in decl.GetMemberDecls()) {
                if (!ok) {
                    continue
                }
                if (member.astKind != ASTKind.VAR_DECL || member.TestAttr(Attribute.STATIC)) {
                    continue
                }
                if (let Some(memberTy) <- member.GetTy()) {
                    if (let Some(fieldBound) <- EstimateLayoutLowerBound(memberTy, visited)) {
                        total = SaturatingAdd(total, fieldBound)
                    } else {
                        ok = false
                    }
                } else {
                    ok = false
                }
            }
            visited.remove(at: visited.size - 1)
            if (!ok) {
                return None
            }
            return Some(total)
        }
        if (ty.IsEnum()) {
            // Conservative: only prove oversize when a constructor payload lower-bound
            // alone exceeds the limit (full enum ABI may add a tag).
            if (let Some(decl) <- Ty.GetDeclOfTy(Some(ty))) {
                if (let Some(enumDecl) <- (decl as EnumDecl)) {
                    visited.add(ty)
                    var maxPayload: Int64 = 0
                    var provedOversize = false
                    for (constructor in enumDecl.constructors) {
                        if (constructor.astKind != ASTKind.FUNC_DECL) {
                            continue
                        }
                        let funcDecl = (constructor as FuncDecl).getOrThrow()
                        if (let Some(funcBody) <- funcDecl.funcBody) {
                            if (funcBody.paramLists.isEmpty()) {
                                continue
                            }
                            var payload: Int64 = 0
                            var payloadOk = true
                            for (param in funcBody.paramLists[0].params) {
                                if (!payloadOk) {
                                    continue
                                }
                                if (let Some(paramTy) <- param.GetTy()) {
                                    if (let Some(paramBound) <- EstimateLayoutLowerBound(paramTy, visited)) {
                                        payload = SaturatingAdd(payload, paramBound)
                                    } else {
                                        payloadOk = false
                                    }
                                } else {
                                    payloadOk = false
                                }
                            }
                            if (payloadOk && payload > maxPayload) {
                                maxPayload = payload
                                if (maxPayload > ARRAY_ELEMENT_SIZE_LIMIT) {
                                    provedOversize = true
                                }
                            }
                        }
                    }
                    visited.remove(at: visited.size - 1)
                    if (provedOversize) {
                        return Some(maxPayload)
                    }
                }
            }
            return None
        }
        return None
    }

    private func ArrayElementTypeOf(ty: Ty): Option<Ty> {
        if (let Some(arrayTy) <- (ty as ArrayTy)) {
            if (arrayTy.typeArgs.isEmpty()) {
                return None
            }
            return Some(arrayTy.typeArgs[0])
        }
        if (ty.IsStructArray()) {
            if (ty.typeArgs.isEmpty()) {
                return None
            }
            return Some(ty.typeArgs[0])
        }
        return None
    }

    private func EmitArrayElementSizeLimitDiag(node: Node, elementTy: Ty, lowerBound: Int64): Unit {
        if (let Some(diagValue) <- diag) {
            let typeName = elementTy.String()
            let sizeText = "${lowerBound}"
            let message = "array element type '" + typeName + "' has size at least " + sizeText +
                " bytes, which exceeds the current 2 GiB (" + "${ARRAY_ELEMENT_SIZE_LIMIT}" +
                " bytes) array-element implementation limit"
            let builder = Diagnose(diagValue, node, BasicDiagKind.sema_diag_report_error_message,
                args: [BasicDiagArgument(message)])
            builder.AddNote(
                "this limit matches the CodeGen array-copy chunk ABI (element size must fit in Int32); " +
                "previously reported only as an internal compiler error")
            builder.Emit()
        }
    }

    private func ReportIfElementExceedsLimit(node: Node, elementTy: Ty, reported: ArrayList<Ty>): Unit {
        for (seen in reported) {
            if (SameTy(seen, elementTy)) {
                return
            }
        }
        if (let Some(lowerBound) <- EstimateLayoutLowerBound(elementTy, ArrayList<Ty>())) {
            if (lowerBound <= ARRAY_ELEMENT_SIZE_LIMIT) {
                return
            }
            reported.add(elementTy)
            EmitArrayElementSizeLimitDiag(node, elementTy, lowerBound)
        }
    }

    private func CheckStructDeclElementSizeLimit(decl: StructDecl, reported: ArrayList<Ty>): Unit {
        if (let Some(ty) <- decl.GetTy()) {
            if (!Ty.IsTyCorrect(ty) || ty.HasGeneric()) {
                return
            }
            // Prefer pointing at the field that alone exceeds the limit.
            for (member in decl.GetMemberDecls()) {
                if (member.astKind != ASTKind.VAR_DECL || member.TestAttr(Attribute.STATIC)) {
                    continue
                }
                if (let Some(memberTy) <- member.GetTy()) {
                    if (let Some(fieldBound) <- EstimateLayoutLowerBound(memberTy, ArrayList<Ty>())) {
                        if (fieldBound > ARRAY_ELEMENT_SIZE_LIMIT) {
                            ReportIfElementExceedsLimit(member, memberTy, reported)
                            return
                        }
                    }
                }
            }
            if (let Some(total) <- EstimateLayoutLowerBound(ty, ArrayList<Ty>())) {
                if (total > ARRAY_ELEMENT_SIZE_LIMIT) {
                    ReportIfElementExceedsLimit(decl, ty, reported)
                }
            }
        }
    }

    public func CheckArrayElementSizeLimit(pkg: Package): Unit {
        let reported = ArrayList<Ty>()
        IterateToplevelDecls(pkg, { decl: Decl =>
            if (let Some(structDecl) <- (decl as StructDecl)) {
                CheckStructDeclElementSizeLimit(structDecl, reported)
            }
        })
        for (instantiatedDecl in pkg.genericInstantiatedDecls) {
            if (let Some(structDecl) <- (instantiatedDecl as StructDecl)) {
                CheckStructDeclElementSizeLimit(structDecl, reported)
            }
        }
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(ty) <- node.GetTy()) {
                if (let Some(elemTy) <- ArrayElementTypeOf(ty)) {
                    ReportIfElementExceedsLimit(node, elemTy, reported)
                }
            }
            if (let Some(typeNode) <- (node as Type)) {
                if (let Some(ty) <- typeNode.GetTy()) {
                    if (let Some(elemTy) <- ArrayElementTypeOf(ty)) {
                        ReportIfElementExceedsLimit(typeNode, elemTy, reported)
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
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
