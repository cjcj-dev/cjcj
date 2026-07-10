package cangjie_compiler::chir

import std.collection.*
import cangjie_compiler::basic.DiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine

public class NoHeapAllocChecker {
    private let diag: BasicDiagnosticEngine

    public init(diag: BasicDiagnosticEngine) {
        this.diag = diag
    }

    public func RunOnPackage(pkg: Package): Unit {
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            if (fn.TestAttr(Attribute.NO_HEAP_ALLOC)) {
                CheckFunction(fn)
            }
        }
    }

    private func CheckFunction(fn: Function): Unit {
        if (let Some(body) <- fn.GetBody()) {
            VisitBlockGroup(fn, body)
        }
    }

    private func VisitBlockGroup(fn: Function, group: BlockGroup): Unit {
        for (block in group.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                VisitExpression(fn, expr)
            }
        }
    }

    private func VisitExpression(fn: Function, expr: Expression): Unit {
        if (IsHeapAllocation(expr)) {
            let exprPos = GetDebugPos(expr)
            let fnPos = GetDebugPos(fn)
            let reportRange = if (exprPos[0]) { exprPos[1] } else { fnPos[1] }
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_annotation_not_applicable,
                reportRange,
                arguments: ["NoHeapAlloc", "function containing heap allocation '" +
                    ExprKindName(expr.GetExprKind()) + "'"])
            builder.AddNote(if (fnPos[0]) { fnPos[1] } else { reportRange },
                "function '" + FunctionName(fn) + "' is marked @NoHeapAlloc")
            builder.Emit()
        }
        for (group in expr.GetBlockGroups()) {
            VisitBlockGroup(fn, group)
        }
    }

    private func IsHeapAllocation(expr: Expression): Bool {
        match (expr.GetExprKind()) {
            case ExprKind.ALLOCATE =>
                return (expr as Allocate).getOrThrow().GetType().StripAllRefs().IsClass()
            case ExprKind.ALLOCATE_WITH_EXCEPTION =>
                return (expr as AllocateWithException).getOrThrow().GetType().StripAllRefs().IsClass()
            case ExprKind.RAW_ARRAY_ALLOCATE | ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION => return true
            case _ => return false
        }
    }
}

public class NoWriteBarrierRecChecker {
    private let diag: BasicDiagnosticEngine
    private let reachable: ArrayList<CallGraphNode> = ArrayList<CallGraphNode>()
    private let visited: HashSet<Int64> = HashSet<Int64>()
    private let active: HashSet<Int64> = HashSet<Int64>()
    private let paths: HashMap<Int64, String> = HashMap<Int64, String>()
    private let cycles: ArrayList<String> = ArrayList<String>()

    public init(diag: BasicDiagnosticEngine) {
        this.diag = diag
    }

    public func RunOnPackage(pkg: Package): Unit {
        let callGraph = CallGraph(pkg)
        for (root in callGraph.GetFunctionNodes()) {
            if (let Some(fn) <- root.GetFunction()) {
                if (fn.TestAttr(Attribute.NO_WRITE_BARRIER_REC)) {
                    CheckStaticCallClosure(root)
                }
            }
        }
    }

    private func CheckStaticCallClosure(root: CallGraphNode): Unit {
        reachable.clear()
        visited.clear()
        active.clear()
        paths.clear()
        cycles.clear()
        let rootFn = root.GetFunction().getOrThrow()
        VisitCallGraphNode(root, FunctionName(rootFn))
        for (node in reachable) {
            if (let Some(fn) <- node.GetFunction()) {
                if (let Some(body) <- fn.GetBody()) {
                    VisitBlockGroup(rootFn, fn, body, paths.get(node.id) ?? FunctionName(fn))
                }
            }
        }
    }

    private func VisitCallGraphNode(node: CallGraphNode, path: String): Unit {
        if (visited.contains(node.id)) {
            return
        }
        visited.add(node.id)
        active.add(node.id)
        reachable.add(node)
        paths[node.id] = path
        for (edge in node.GetCalledEdges()) {
            if (edge.GetKind() != CallGraphEdgeKind.DIRECT) {
                continue
            }
            let child = edge.GetNode()
            if (let Some(childFn) <- child.GetFunction()) {
                let childPath = path + " -> " + FunctionName(childFn)
                if (active.contains(child.id)) {
                    if (!cycles.contains(childPath)) {
                        cycles.add(childPath)
                    }
                } else {
                    VisitCallGraphNode(child, childPath)
                }
            }
        }
        active.remove(node.id)
    }

    private func VisitBlockGroup(root: Function, fn: Function, group: BlockGroup, path: String): Unit {
        for (block in group.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                VisitExpression(root, fn, expr, path)
            }
        }
    }

    private func VisitExpression(root: Function, fn: Function, expr: Expression, path: String): Unit {
        if (IsWriteBarrierExpression(expr)) {
            let exprPos = GetDebugPos(expr)
            let fnPos = GetDebugPos(fn)
            let rootPos = GetDebugPos(root)
            let reportRange = if (exprPos[0]) { exprPos[1] } else { fnPos[1] }
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_annotation_not_applicable,
                reportRange,
                arguments: ["NoWriteBarrierRec", "static call closure containing write-barrier operation '" +
                    ExprKindName(expr.GetExprKind()) + "'"])
            builder.AddNote(if (rootPos[0]) { rootPos[1] } else { reportRange },
                "@NoWriteBarrierRec root is '" + FunctionName(root) + "'")
            builder.AddNote(if (fnPos[0]) { fnPos[1] } else { reportRange }, "static call path: " + path)
            for (cycle in cycles) {
                builder.AddNote("recursive static-call cycle: " + cycle)
            }
            builder.Emit()
        }
        for (group in expr.GetBlockGroups()) {
            VisitBlockGroup(root, fn, group, path)
        }
    }

    private func IsWriteBarrierExpression(expr: Expression): Bool {
        match (expr.GetExprKind()) {
            case ExprKind.STORE =>
                let store = (expr as Store).getOrThrow()
                return IsManagedStoreLocation(store.GetLocation()) && ValueNeedsWriteBarrier(store.GetValue())
            case ExprKind.STORE_ELEMENT_REF =>
                let store = (expr as StoreElementRef).getOrThrow()
                return IsManagedBase(store.GetLocation()) && ValueNeedsWriteBarrier(store.GetValue())
            case ExprKind.STORE_ELEMENT_BY_NAME =>
                let store = (expr as StoreElementByName).getOrThrow()
                return IsManagedBase(store.GetLocation()) && ValueNeedsWriteBarrier(store.GetValue())
            case ExprKind.RAW_ARRAY_LITERAL_INIT =>
                for (value in (expr as RawArrayLiteralInit).getOrThrow().GetElements()) {
                    if (ValueNeedsWriteBarrier(value)) { return true }
                }
                return false
            case ExprKind.RAW_ARRAY_INIT_BY_VALUE =>
                return ValueNeedsWriteBarrier((expr as RawArrayInitByValue).getOrThrow().GetInitValue())
            case ExprKind.INTRINSIC =>
                let intrinsic = (expr as Intrinsic).getOrThrow()
                let args = intrinsic.GetArgs()
                return IsArrayWriteIntrinsic(intrinsic.GetIntrinsicKind()) &&
                    !args.isEmpty() && ValueNeedsWriteBarrier(args[args.size - 1])
            case ExprKind.INTRINSIC_WITH_EXCEPTION =>
                let intrinsic = (expr as IntrinsicWithException).getOrThrow()
                let args = intrinsic.GetArgs()
                return IsArrayWriteIntrinsic(intrinsic.GetIntrinsicKind()) &&
                    !args.isEmpty() && ValueNeedsWriteBarrier(args[args.size - 1])
            case _ => return false
        }
    }

    private func IsManagedStoreLocation(location: Value): Bool {
        if (location.AsGlobalVar().isSome()) {
            return true
        }
        if (let Some(local) <- location.AsLocalVar()) {
            if (let Some(expr) <- local.GetExpr()) {
                if (let Some(element) <- (expr as GetElementRef)) {
                    return IsManagedBase(element.GetLocation())
                }
                if (let Some(element) <- (expr as GetElementByName)) {
                    return IsManagedBase(element.GetLocation())
                }
            }
        }
        return false
    }

    private func IsManagedBase(value: Value): Bool {
        if (let Some(ty) <- value.GetType()) {
            return ty.StripAllRefs().IsReferenceType()
        }
        return false
    }

    private func ValueNeedsWriteBarrier(value: Value): Bool {
        if (let Some(ty) <- value.GetType()) {
            let stripped = ty.StripAllRefs()
            return stripped.IsReferenceType() || stripped.IsGeneric()
        }
        return false
    }

    private func IsArrayWriteIntrinsic(kind: IntrinsicKind): Bool {
        return kind == IntrinsicKind.ARRAY_SET || kind == IntrinsicKind.ARRAY_SET_UNCHECKED ||
            kind == IntrinsicKind.ARRAY_SLICE_SET_ELEMENT ||
            kind == IntrinsicKind.ARRAY_SLICE_SET_ELEMENT_UNCHECKED
    }
}

private func FunctionName(fn: Function): String {
    return if (fn.GetSrcCodeIdentifier().isEmpty()) { fn.GetIdentifier() } else { fn.GetSrcCodeIdentifier() }
}
