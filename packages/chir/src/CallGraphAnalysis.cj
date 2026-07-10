package cjcj::chir

import std.collection.*
import std.sort.*

public enum CallGraphEdgeKind {
    | VIRTUAL | DIRECT
}

private func CallGraphEdgeKindIndex(kind: CallGraphEdgeKind): Int64 {
    return match (kind) {
        case CallGraphEdgeKind.VIRTUAL => 0
        case CallGraphEdgeKind.DIRECT => 1
    }
}

extend CallGraphEdgeKind <: Equatable<CallGraphEdgeKind> {
    public operator func ==(right: CallGraphEdgeKind): Bool {
        return CallGraphEdgeKindIndex(this) == CallGraphEdgeKindIndex(right)
    }

    public operator func !=(right: CallGraphEdgeKind): Bool {
        return !(this == right)
    }
}

public class CallGraphEdge {
    private let node: CallGraphNode
    private let kind: CallGraphEdgeKind

    public init(node: CallGraphNode, kind: CallGraphEdgeKind) {
        this.node = node
        this.kind = kind
    }

    public func GetNode(): CallGraphNode {
        return node
    }

    public func GetKind(): CallGraphEdgeKind {
        return kind
    }

    public func IsSame(other: CallGraphEdge): Bool {
        return node.id == other.node.id
    }
}

public class CallGraphNode {
    public let id: Int64
    public let functionValue: Option<Function>
    public let callees: ArrayList<Function> = ArrayList<Function>()
    private let calledEdges: ArrayList<CallGraphEdge> = ArrayList<CallGraphEdge>()

    public init(id: Int64, functionValue: Option<Function>) {
        this.id = id
        this.functionValue = functionValue
    }

    public func GetFunction(): Option<Function> {
        return functionValue
    }

    public func AddCalledEdge(edge: CallGraphEdge): Unit {
        calledEdges.add(edge)
        if (let Some(calleeFunc) <- edge.GetNode().GetFunction()) {
            if (!ContainsFunction(callees, calleeFunc)) {
                callees.add(calleeFunc)
            }
        }
    }

    public func DeleteCalledEdge(edge: CallGraphEdge): Unit {
        var idx: Int64 = 0
        while (idx < calledEdges.size) {
            if (calledEdges[idx].IsSame(edge)) {
                calledEdges.remove(at: idx)
                RebuildCallees()
                return
            }
            idx++
        }
    }

    public func GetCalledEdges(): ArrayList<CallGraphEdge> {
        let out = ArrayList<CallGraphEdge>()
        for (edge in calledEdges) {
            out.add(edge)
        }
        return out
    }

    public func Empty(): Bool {
        return calledEdges.isEmpty()
    }

    private func RebuildCallees(): Unit {
        callees.clear()
        for (edge in calledEdges) {
            if (let Some(calleeFunc) <- edge.GetNode().GetFunction()) {
                if (!ContainsFunction(callees, calleeFunc)) {
                    callees.add(calleeFunc)
                }
            }
        }
    }
}

private class VirtualCallInfo {
    public let object: Value
    public let methodName: String
    public let paramTypes: ArrayList<Type> = ArrayList<Type>()

    public init(object: Value, methodName: String, paramTypes: ArrayList<Type>) {
        this.object = object
        this.methodName = methodName
        for (paramTy in paramTypes) {
            this.paramTypes.add(paramTy)
        }
    }
}

public class CallGraph {
    private let functionMap: HashMap<Int64, CallGraphNode> = HashMap<Int64, CallGraphNode>()
    private let functionNodes: ArrayList<CallGraphNode> = ArrayList<CallGraphNode>()
    private let entryNode: CallGraphNode = CallGraphNode(0, None)
    private let exitNode: CallGraphNode = CallGraphNode(1, None)
    private var devirtFuncInfo: Option<DevirtualizationInfo> = None
    private var nextNodeId: Int64 = 2

    public init(chirPackage: Package) {
        Build(chirPackage)
    }

    public init(chirPackage: Package, devirtFuncInfo: DevirtualizationInfo) {
        this.devirtFuncInfo = devirtFuncInfo
        Build(chirPackage)
    }

    public func GetEntryNode(): CallGraphNode {
        return entryNode
    }

    public func GetExitNode(): CallGraphNode {
        return exitNode
    }

    public func GetFunctionNodes(): ArrayList<CallGraphNode> {
        let out = ArrayList<CallGraphNode>()
        for (node in functionNodes) {
            out.add(node)
        }
        return out
    }

    public func GetOrCreateNode(functionValue: Function): CallGraphNode {
        if (let Some(node) <- functionMap.get(functionValue.nodeId)) {
            return node
        }
        let node = CallGraphNode(nextNodeId, functionValue)
        nextNodeId++
        functionMap[functionValue.nodeId] = node
        functionNodes.add(node)
        return node
    }

    public func PopulateCallGraphNode(node: CallGraphNode, funcBlockGroup: BlockGroup): Unit {
        VisitBlockGroup(node, funcBlockGroup)
    }

    public func AddToCallGraph(functionValue: Function, isCalledByEntryNode: Bool): Unit {
        let node = GetOrCreateNode(functionValue)
        if (isCalledByEntryNode) {
            entryNode.AddCalledEdge(CallGraphEdge(node, CallGraphEdgeKind.VIRTUAL))
        }
        if (let Some(body) <- node.GetFunction()) {
            if (let Some(group) <- body.GetBody()) {
                PopulateCallGraphNode(node, group)
            }
        }
    }

    public func GetAllPossibleCalleeOfInvoke(methodName: String, paramTypes: ArrayList<Type>): ArrayList<Function> {
        let _ = methodName
        let _ = paramTypes
        return ArrayList<Function>()
    }

    private func Build(chirPackage: Package): Unit {
        for (functionValue in chirPackage.GetGlobalFuncsWithBody()) {
            AddToCallGraph(functionValue, functionValue.GetUsers().isEmpty())
        }
    }

    private func VisitBlockGroup(node: CallGraphNode, group: BlockGroup): Unit {
        for (block in group.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                VisitExpression(node, expr)
            }
        }
    }

    private func VisitExpression(node: CallGraphNode, expr: Expression): Unit {
        let kind = expr.GetExprKind()
        if (kind == ExprKind.INVOKE || kind == ExprKind.INVOKE_WITH_EXCEPTION) {
            AddVirtualEdgeToNode(node, expr)
        } else if (kind == ExprKind.APPLY || kind == ExprKind.APPLY_WITH_EXCEPTION) {
            AddDirectEdgeToNode(node, expr)
        }
        for (group in expr.GetBlockGroups()) {
            VisitBlockGroup(node, group)
        }
    }

    private func AddVirtualEdgeToNode(node: CallGraphNode, expr: Expression): Unit {
        let callInfo = ExtractVirtualCallInfo(expr)
        if (callInfo.isNone()) {
            return
        }
        if (let Some(info) <- callInfo) {
            let receiverTy = if (let Some(objectTy) <- info.object.GetType()) {
                objectTy.StripAllRefs()
            } else {
                return
            }
            if (!receiverTy.IsClass()) {
                return
            }
            let possibleCallees = GetAllPossibleCalleeOfInvoke(info.methodName, info.paramTypes)
            sort(possibleCallees, by: { left: Function, right: Function =>
                if (left.GetIdentifier() < right.GetIdentifier()) {
                    Ordering.LT
                } else if (left.GetIdentifier() > right.GetIdentifier()) {
                    Ordering.GT
                } else {
                    Ordering.EQ
                }
            }, stable: true)
            AddVirtualCalleesToNode(node, possibleCallees)
        }
    }

    private func AddVirtualCalleesToNode(node: CallGraphNode, possibleCallees: ArrayList<Function>): Unit {
        for (possibleCallee in possibleCallees) {
            if (possibleCallee.IsFuncWithBody()) {
                let edge = CallGraphEdge(GetOrCreateNode(possibleCallee), CallGraphEdgeKind.VIRTUAL)
                entryNode.DeleteCalledEdge(edge)
                node.AddCalledEdge(edge)
            } else {
                let exitEdge = CallGraphEdge(exitNode, CallGraphEdgeKind.VIRTUAL)
                entryNode.DeleteCalledEdge(exitEdge)
                node.AddCalledEdge(exitEdge)
            }
        }
    }

    private func AddDirectEdgeToNode(node: CallGraphNode, expr: Expression): Unit {
        let calledFunc = ResolveDirectCallee(expr)
        if (let Some(functionValue) <- calledFunc) {
            node.AddCalledEdge(CallGraphEdge(GetOrCreateNode(functionValue), CallGraphEdgeKind.DIRECT))
        } else {
            node.AddCalledEdge(CallGraphEdge(exitNode, CallGraphEdgeKind.DIRECT))
        }
    }
}

private func ExtractVirtualCallInfo(expr: Expression): Option<VirtualCallInfo> {
    if (let Some(invoke) <- (expr as Invoke)) {
        return VirtualCallInfo(invoke.GetObject(), invoke.GetMethodName(),
            VirtualCallParamTypes(invoke.GetMethodType()))
    }
    if (let Some(invokeWithException) <- (expr as InvokeWithException)) {
        return VirtualCallInfo(invokeWithException.GetObject(), invokeWithException.GetMethodName(),
            VirtualCallParamTypes(invokeWithException.GetMethodType()))
    }
    return None
}

private func VirtualCallParamTypes(methodType: FuncType): ArrayList<Type> {
    let allParamTypes = methodType.GetParamTypes()
    let out = ArrayList<Type>()
    var idx: Int64 = 1
    while (idx < allParamTypes.size) {
        out.add(allParamTypes[idx])
        idx++
    }
    return out
}

private func ResolveDirectCallee(expr: Expression): Option<Function> {
    var calleeValue: Option<Value> = None
    if (let Some(apply) <- (expr as Apply)) {
        calleeValue = apply.GetCallee()
    } else if (let Some(applyWithException) <- (expr as ApplyWithException)) {
        calleeValue = applyWithException.GetCallee()
    }
    if (let Some(value) <- calleeValue) {
        if (let Some(callee) <- value.AsFunction()) {
            if (callee.IsFuncWithBody()) {
                return callee
            }
        }
    }
    return None
}

public class CallGraphAnalysis {
    private var chirPackage: Option<Package> = None
    private var visitNum: Int64 = 0
    private let nodeVisitNumbers: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let lowLinks: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let onStack: HashMap<Int64, Bool> = HashMap<Int64, Bool>()
    private let sccNodeStack: ArrayList<CallGraphNode> = ArrayList<CallGraphNode>()
    private let currentSCC: ArrayList<CallGraphNode> = ArrayList<CallGraphNode>()
    public let postOrderSCCFunctionlist: ArrayList<Option<Function>> = ArrayList<Option<Function>>()

    public init() {}

    public init(chirPackage: Package, devirtFuncInfo: DevirtualizationInfo) {
        let _ = devirtFuncInfo
        this.chirPackage = chirPackage
    }

    public func Run(chirPackage: Package): ArrayList<CallGraphNode> {
        let callGraph = CallGraph(chirPackage)
        BuildSCC(callGraph)
        return callGraph.GetFunctionNodes()
    }

    public func DoCallGraphAnalysis(isDebug: Bool): Unit {
        if (let Some(packageValue) <- chirPackage) {
            let callGraph = CallGraph(packageValue)
            BuildSCC(callGraph)
            if (isDebug) {
                PrintCallGraph(callGraph)
            }
        }
    }

    public func BuildSCC(callGraph: CallGraph): Unit {
        ClearSCCState()
        DFSVisitOne(callGraph.GetEntryNode())
    }

    public func PrintCallGraph(callGraph: CallGraph): Unit {
        let nodeStack = ArrayList<CallGraphNode>()
        let seen = HashMap<Int64, Bool>()
        for (edge in callGraph.GetEntryNode().GetCalledEdges()) {
            let node = edge.GetNode()
            nodeStack.add(node)
            seen[node.id] = true
        }
        while (!nodeStack.isEmpty()) {
            let node = nodeStack[nodeStack.size - 1]
            nodeStack.remove(at: nodeStack.size - 1)
            if (node.Empty()) {
                if (let Some(fn) <- node.GetFunction()) {
                    println("[CallGraphAnalysis] Call Graph found " + fn.GetIdentifierWithoutPrefix())
                }
                continue
            }
            var message = "[CallGraphAnalysis] Call Graph found "
            if (let Some(fn) <- node.GetFunction()) {
                message += fn.GetIdentifierWithoutPrefix()
            } else {
                message += "Unknown Function"
            }
            for (edge in node.GetCalledEdges()) {
                message += if (edge.GetKind() == CallGraphEdgeKind.DIRECT) { ", DIRECT CALL:" } else {
                    ", VIRTUAL CALL:"
                }
                if (let Some(callee) <- edge.GetNode().GetFunction()) {
                    message += callee.GetIdentifierWithoutPrefix()
                } else {
                    message += "Unknown Function"
                }
                if (!seen.contains(edge.GetNode().id)) {
                    nodeStack.add(edge.GetNode())
                    seen[edge.GetNode().id] = true
                }
            }
            println(message)
        }
    }

    private func ClearSCCState(): Unit {
        visitNum = 0
        nodeVisitNumbers.clear()
        lowLinks.clear()
        onStack.clear()
        sccNodeStack.clear()
        currentSCC.clear()
        postOrderSCCFunctionlist.clear()
    }

    private func DFSVisitOne(node: CallGraphNode): Unit {
        visitNum++
        nodeVisitNumbers[node.id] = visitNum
        lowLinks[node.id] = visitNum
        sccNodeStack.add(node)
        onStack[node.id] = true
        for (edge in node.GetCalledEdges()) {
            let child = edge.GetNode()
            if (!nodeVisitNumbers.contains(child.id)) {
                DFSVisitOne(child)
                UpdateLowLinkFromChild(node, child)
            } else if (onStack.get(child.id) ?? false) {
                UpdateLowLinkWithVisitedChild(node, child)
            }
        }
        if ((lowLinks.get(node.id) ?? Int64.Max) == (nodeVisitNumbers.get(node.id) ?? Int64.Min)) {
            PopCurrentSCC(node)
        }
    }

    private func UpdateLowLinkFromChild(node: CallGraphNode, child: CallGraphNode): Unit {
        let nodeLow = lowLinks.get(node.id) ?? Int64.Max
        let childLow = lowLinks.get(child.id) ?? Int64.Max
        if (childLow < nodeLow) {
            lowLinks[node.id] = childLow
        }
    }

    private func UpdateLowLinkWithVisitedChild(node: CallGraphNode, child: CallGraphNode): Unit {
        let nodeLow = lowLinks.get(node.id) ?? Int64.Max
        let childVisit = nodeVisitNumbers.get(child.id) ?? Int64.Max
        if (childVisit < nodeLow) {
            lowLinks[node.id] = childVisit
        }
    }

    private func PopCurrentSCC(root: CallGraphNode): Unit {
        currentSCC.clear()
        var keepPopping = true
        while (keepPopping && !sccNodeStack.isEmpty()) {
            let top = sccNodeStack[sccNodeStack.size - 1]
            sccNodeStack.remove(at: sccNodeStack.size - 1)
            onStack[top.id] = false
            currentSCC.add(top)
            if (top.id == root.id) {
                keepPopping = false
            }
        }
        for (node in currentSCC) {
            postOrderSCCFunctionlist.add(node.GetFunction())
        }
    }
}

private func ContainsFunction(functions: ArrayList<Function>, target: Function): Bool {
    for (fn in functions) {
        if (fn.nodeId == target.nodeId) {
            return true
        }
    }
    return false
}
