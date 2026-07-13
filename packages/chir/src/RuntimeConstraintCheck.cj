package cjcj::chir

import std.collection.*
import cjcj::basic.DiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine

public class NoHeapAllocChecker {
    private let diag: BasicDiagnosticEngine
    private let constrainedRoots: HashMap<Int64, Function> = HashMap<Int64, Function>()
    private let paths: HashMap<Int64, String> = HashMap<Int64, String>()
    private let visited: HashSet<Int64> = HashSet<Int64>()
    private let reportedExpressions: HashSet<Int64> = HashSet<Int64>()
    private let reportedFunctions: HashSet<Int64> = HashSet<Int64>()

    public init(diag: BasicDiagnosticEngine) {
        this.diag = diag
    }

    public func RunOnPackage(pkg: Package): Unit {
        constrainedRoots.clear()
        paths.clear()
        reportedExpressions.clear()
        reportedFunctions.clear()
        var hasNoHeapAlloc = false
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            if (fn.TestAttr(Attribute.NO_HEAP_ALLOC)) {
                hasNoHeapAlloc = true
                break
            }
        }
        if (!hasNoHeapAlloc) {
            return
        }
        let callGraph = CallGraph(pkg)
        for (root in callGraph.GetFunctionNodes()) {
            if (let Some(fn) <- root.GetFunction()) {
                if (fn.TestAttr(Attribute.NO_HEAP_ALLOC)) {
                    CheckStaticCallClosure(root)
                }
            }
        }
    }

    private func CheckStaticCallClosure(root: CallGraphNode): Unit {
        visited.clear()
        let rootFn = root.GetFunction().getOrThrow()
        VisitCallGraphNode(rootFn, root, FunctionName(rootFn))
    }

    private func VisitCallGraphNode(root: Function, node: CallGraphNode, path: String): Unit {
        if (visited.contains(node.id)) {
            return
        }
        visited.add(node.id)
        if (let Some(nodeFn) <- node.GetFunction()) {
            if (!constrainedRoots.contains(nodeFn.nodeId)) {
                constrainedRoots[nodeFn.nodeId] = root
                paths[nodeFn.nodeId] = path
            }
        }
        for (edge in node.GetCalledEdges()) {
            if (edge.GetKind() != CallGraphEdgeKind.DIRECT) {
                continue
            }
            let child = edge.GetNode()
            if (let Some(childFn) <- child.GetFunction()) {
                VisitCallGraphNode(root, child, path + " -> " + FunctionName(childFn))
            }
        }
    }

    public func CheckFunction(fn: Function, expr: Option<Expression>, operation: String): Unit {
        let root = constrainedRoots.get(fn.nodeId) ?? return
        var reportPos = GetDebugPos(fn)
        if (let Some(currentExpr) <- expr) {
            if (reportedExpressions.contains(currentExpr.nodeId)) {
                return
            }
            reportedExpressions.add(currentExpr.nodeId)
            let exprPos = GetDebugPos(currentExpr)
            if (exprPos[0]) {
                reportPos = exprPos
            }
        } else {
            if (reportedFunctions.contains(fn.nodeId)) {
                return
            }
            reportedFunctions.add(fn.nodeId)
        }
        let fnPos = GetDebugPos(fn)
        let rootPos = GetDebugPos(root)
        let reportRange = if (reportPos[0]) { reportPos[1] } else { fnPos[1] }
        let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_annotation_not_applicable,
            reportRange,
            arguments: ["NoHeapAlloc", "static call closure emitted heap allocation '" + operation + "'"])
        builder.AddNote(if (rootPos[0]) { rootPos[1] } else { reportRange },
            "@NoHeapAlloc root is '" + FunctionName(root) + "'")
        builder.AddNote(if (fnPos[0]) { fnPos[1] } else { reportRange },
            "static call path: " + (paths.get(fn.nodeId) ?? FunctionName(fn)))
        builder.Emit()
    }
}

public class NoWriteBarrierRecChecker {
    private let diag: BasicDiagnosticEngine
    private let constrainedRoots: HashMap<Int64, Function> = HashMap<Int64, Function>()
    private let paths: HashMap<Int64, String> = HashMap<Int64, String>()
    private let visited: HashSet<Int64> = HashSet<Int64>()
    private let active: HashSet<Int64> = HashSet<Int64>()
    private let cycles: ArrayList<String> = ArrayList<String>()
    private let reportedExpressions: HashSet<Int64> = HashSet<Int64>()
    private let reportedFunctions: HashSet<Int64> = HashSet<Int64>()

    public init(diag: BasicDiagnosticEngine) {
        this.diag = diag
    }

    public func RunOnPackage(pkg: Package): Unit {
        constrainedRoots.clear()
        paths.clear()
        cycles.clear()
        reportedExpressions.clear()
        reportedFunctions.clear()
        var hasNoWriteBarrier = false
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            if (fn.TestAttr(Attribute.NO_WRITE_BARRIER) || fn.TestAttr(Attribute.NO_WRITE_BARRIER_REC)) {
                hasNoWriteBarrier = true
                break
            }
        }
        if (!hasNoWriteBarrier) {
            return
        }
        let callGraph = CallGraph(pkg)
        for (root in callGraph.GetFunctionNodes()) {
            if (let Some(fn) <- root.GetFunction()) {
                if (fn.TestAttr(Attribute.NO_WRITE_BARRIER_REC)) {
                    CheckStaticCallClosure(root)
                } else if (fn.TestAttr(Attribute.NO_WRITE_BARRIER)) {
                    constrainedRoots[fn.nodeId] = fn
                    paths[fn.nodeId] = FunctionName(fn)
                }
            }
        }
    }

    private func CheckStaticCallClosure(root: CallGraphNode): Unit {
        visited.clear()
        active.clear()
        let rootFn = root.GetFunction().getOrThrow()
        VisitCallGraphNode(rootFn, root, FunctionName(rootFn))
    }

    private func VisitCallGraphNode(root: Function, node: CallGraphNode, path: String): Unit {
        if (visited.contains(node.id)) {
            return
        }
        visited.add(node.id)
        active.add(node.id)
        if (let Some(nodeFn) <- node.GetFunction()) {
            if (!constrainedRoots.contains(nodeFn.nodeId)) {
                constrainedRoots[nodeFn.nodeId] = root
                paths[nodeFn.nodeId] = path
            }
        }
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
                    VisitCallGraphNode(root, child, childPath)
                }
            }
        }
        active.remove(node.id)
    }

    public func CheckFunction(fn: Function, expr: Option<Expression>): Unit {
        let root = constrainedRoots.get(fn.nodeId) ?? return
        var operation = "codegen-generated"
        var reportPos = GetDebugPos(fn)
        if (let Some(currentExpr) <- expr) {
            if (reportedExpressions.contains(currentExpr.nodeId)) {
                return
            }
            reportedExpressions.add(currentExpr.nodeId)
            operation = ExprKindName(currentExpr.GetExprKind())
            let exprPos = GetDebugPos(currentExpr)
            if (exprPos[0]) {
                reportPos = exprPos
            }
        } else {
            if (reportedFunctions.contains(fn.nodeId)) {
                return
            }
            reportedFunctions.add(fn.nodeId)
        }
        let fnPos = GetDebugPos(fn)
        let rootPos = GetDebugPos(root)
        let annotationName = if (root.TestAttr(Attribute.NO_WRITE_BARRIER_REC)) {
            "NoWriteBarrierRec"
        } else {
            "NoWriteBarrier"
        }
        let reportRange = if (reportPos[0]) { reportPos[1] } else { fnPos[1] }
        let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_annotation_not_applicable,
            reportRange,
            arguments: [annotationName, "static call closure emitted write barrier while lowering '" +
                operation + "'"])
        builder.AddNote(if (rootPos[0]) { rootPos[1] } else { reportRange },
            "@" + annotationName + " root is '" + FunctionName(root) + "'")
        builder.AddNote(if (fnPos[0]) { fnPos[1] } else { reportRange },
            "static call path: " + (paths.get(fn.nodeId) ?? FunctionName(fn)))
        for (cycle in cycles) {
            builder.AddNote("recursive static-call cycle: " + cycle)
        }
        builder.Emit()
    }
}

private func FunctionName(fn: Function): String {
    return if (fn.GetSrcCodeIdentifier().isEmpty()) { fn.GetIdentifier() } else { fn.GetSrcCodeIdentifier() }
}
