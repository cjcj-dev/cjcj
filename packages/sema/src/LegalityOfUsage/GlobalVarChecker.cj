package cjcj::sema.LegalityOfUsage

import std.collection.*
import cjcj::ast.*
import cjcj::sema.*

public enum GlobalVarInitIssueKind {
    | USED_BEFORE_INITIALIZATION
    | INITIALIZATION_CYCLE
    | COMMON_STATIC_LET_INITIALIZED_IN_STATIC_INIT
}

private func GlobalVarInitIssueKindIndex(kind: GlobalVarInitIssueKind): Int64 {
    return match (kind) {
        case GlobalVarInitIssueKind.USED_BEFORE_INITIALIZATION => 0
        case GlobalVarInitIssueKind.INITIALIZATION_CYCLE => 1
        case GlobalVarInitIssueKind.COMMON_STATIC_LET_INITIALIZED_IN_STATIC_INIT => 2
    }
}

extend GlobalVarInitIssueKind <: Equatable<GlobalVarInitIssueKind> {
    public operator func ==(right: GlobalVarInitIssueKind): Bool {
        return GlobalVarInitIssueKindIndex(this) == GlobalVarInitIssueKindIndex(right)
    }

    public operator func !=(right: GlobalVarInitIssueKind): Bool {
        return !(this == right)
    }
}

public class GlobalVarInitializationIssue {
    public var kind: GlobalVarInitIssueKind
    public var refNode: Node
    public var refPos: Position
    public var refName: String
    public var user: Decl
    public var used: Decl
    public var message: String

    public init(kind: GlobalVarInitIssueKind, refNode: Node, refPos: Position, refName: String, user: Decl, used: Decl,
        message!: String = "") {
        this.kind = kind
        this.refNode = refNode
        this.refPos = refPos
        this.refName = refName
        this.user = user
        this.used = used
        this.message = message
    }
}

private enum DefColor {
    | WHITE
    | BLACK
    | GRAY
}

private func DefColorIndex(color: DefColor): Int64 {
    return match (color) {
        case DefColor.WHITE => 0
        case DefColor.BLACK => 1
        case DefColor.GRAY => 2
    }
}

extend DefColor <: Equatable<DefColor> {
    public operator func ==(right: DefColor): Bool {
        return DefColorIndex(this) == DefColorIndex(right)
    }

    public operator func !=(right: DefColor): Bool {
        return !(this == right)
    }
}

private class DefNode {
    public var variable: Decl
    public let usage: ArrayList<UseEdge> = ArrayList<UseEdge>()
    public var visitOrder: Int64 = -1
    public var color: DefColor = DefColor.WHITE

    public init(variable: Decl) {
        this.variable = variable
    }
}

private class UseEdge {
    public var refNode: Node
    public var refPos: Position
    public var refName: String
    public var node: DefNode

    public init(node: DefNode) {
        this.refNode = node.variable
        this.refPos = Position()
        this.refName = node.variable.identifier.Val()
        this.node = node
    }

    public init(refNode: Node, refPos: Position, refName: String, node: DefNode) {
        this.refNode = refNode
        this.refPos = refPos
        this.refName = refName
        this.node = node
    }
}

private func SameNode(left: Node, right: Node): Bool {
    return left.astKind == right.astKind && left.begin == right.begin && left.end == right.end
}

private func ContainsDecl(values: ArrayList<Decl>, decl: Decl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func ContainsNode(values: ArrayList<Node>, node: Node): Bool {
    for (value in values) {
        if (SameNode(value, node)) {
            return true
        }
    }
    return false
}

private func DeclLessBySource(left: Decl, right: Decl): Bool {
    if (left.begin.fileID < right.begin.fileID) {
        return true
    }
    if (left.begin.fileID > right.begin.fileID) {
        return false
    }
    if (left.begin < right.begin) {
        return true
    }
    if (right.begin < left.begin) {
        return false
    }
    let leftKind = ASTKindIndex(left.astKind)
    let rightKind = ASTKindIndex(right.astKind)
    if (leftKind < rightKind) {
        return true
    }
    if (rightKind < leftKind) {
        return false
    }
    return left.end < right.end
}

private func IsGlobalOrStaticOrConstVar(decl: Decl): Bool {
    if (decl.astKind != ASTKind.VAR_DECL && decl.astKind != ASTKind.VAR_WITH_PATTERN_DECL) {
        return false
    }
    return decl.TestAnyAttr(Attribute.GLOBAL, Attribute.STATIC) || decl.IsConst()
}

private func IsInSameFile(left: Node, right: Node): Bool {
    if (left.astKind == ASTKind.FILE || right.astKind == ASTKind.FILE) {
        return false
    }
    if (let Some(leftFile) <- left.curFile) {
        if (let Some(rightFile) <- right.curFile) {
            return leftFile.fileHash == rightFile.fileHash
        }
    }
    return false
}

private func CanIgnoreTarget(decl: Decl): Bool {
    return decl.TestAnyAttr(Attribute.UNSAFE, Attribute.IMPORTED, Attribute.FOREIGN)
}

private func GetTargetIfShouldCollect(expr: Expr): Option<Decl> {
    if (let Some(rawTarget) <- expr.GetTarget()) {
        let usedTarget = GetUsedMemberDecl(rawTarget, !expr.TestAttr(Attribute.LEFT_VALUE))
        if (usedTarget.astKind == ASTKind.FUNC_DECL) {
            return usedTarget
        }
    }
    return None
}

private class VarWithPatternDeclMap {
    private let cachedVPDs: ArrayList<VarWithPatternDecl> = ArrayList<VarWithPatternDecl>()
    private let outerVPDMap: ArrayList<(VarDecl, VarWithPatternDecl)> = ArrayList<(VarDecl, VarWithPatternDecl)>()

    private func ContainsVPD(vpd: VarWithPatternDecl): Bool {
        for (cached in cachedVPDs) {
            if (SameDecl(cached, vpd)) {
                return true
            }
        }
        return false
    }

    public func Add(vpd: VarWithPatternDecl): Unit {
        if (ContainsVPD(vpd)) {
            return
        }
        let walker = Walker(vpd, visitPre: { node: Node =>
            if (let Some(varDecl) <- (node as VarDecl)) {
                outerVPDMap.add((varDecl, vpd))
                return VisitAction.SKIP_CHILDREN
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
        cachedVPDs.add(vpd)
    }

    public func GetOuterVPD(vd: VarDecl): Option<VarWithPatternDecl> {
        for (entry in outerVPDMap) {
            if (SameDecl(entry[0], vd)) {
                return entry[1]
            }
        }
        return None
    }
}

private class DefUseGraph {
    public let nodes: ArrayList<DefNode> = ArrayList<DefNode>()
    private let vpdMap: VarWithPatternDeclMap = VarWithPatternDeclMap()

    public func GetOrBuildNode(decl: Decl): DefNode {
        var owner = decl
        if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
            vpdMap.Add(vpd)
        } else if (let Some(varDecl) <- (decl as VarDecl)) {
            if (let Some(outer) <- vpdMap.GetOuterVPD(varDecl)) {
                owner = outer
            }
        }
        for (node in nodes) {
            if (SameDecl(node.variable, owner)) {
                return node
            }
        }
        let newNode = DefNode(owner)
        var idx: Int64 = 0
        while (idx < nodes.size) {
            if (DeclLessBySource(owner, nodes[idx].variable)) {
                nodes.add(newNode, at: idx)
                return newNode
            }
            idx++
        }
        nodes.add(newNode)
        return newNode
    }

    public func AddEdge(user: Decl, used: VarDeclAbstract, refExpr: Expr): Unit {
        let userNode = GetOrBuildNode(user)
        let usedNode = GetOrBuildNode(used)
        var refPos = refExpr.begin
        var refName = used.identifier.Val()
        if (let Some(refNode) <- (refExpr as RefExpr)) {
            refPos = refNode.begin
            refName = refNode.ref.identifier.Val()
        } else if (let Some(member) <- (refExpr as MemberAccess)) {
            refPos = member.field.Begin()
            refName = member.field.Val()
        }
        userNode.usage.add(UseEdge(refExpr, refPos, refName, usedNode))
    }

    public func AddOrderEdge(user: Decl, used: VarDeclAbstract): Unit {
        let userNode = GetOrBuildNode(user)
        let usedNode = GetOrBuildNode(used)
        userNode.usage.add(UseEdge(usedNode))
    }
}

public class GlobalVarInitializationChecker {
    private let graph: DefUseGraph = DefUseGraph()
    private let issues: ArrayList<GlobalVarInitializationIssue> = ArrayList<GlobalVarInitializationIssue>()
    private var currentNode: Option<DefNode> = None
    private var visitOrder: Int64 = 0

    public init() {}

    public func Analyze(pkg: Package): ArrayList<GlobalVarInitializationIssue> {
        DoCollect(pkg)
        DoCheck(pkg)
        return issues
    }

    private func DoCollect(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (IsGlobalOrStaticOrConstVar(decl)) {
                    CollectForVar(decl)
                } else if (let Some(classDecl) <- (decl as ClassDecl)) {
                    CollectForStaticVar(classDecl.GetMemberDeclPtrs())
                } else if (let Some(structDecl) <- (decl as StructDecl)) {
                    CollectForStaticVar(structDecl.GetMemberDeclPtrs())
                }
            }
        }
    }

    private func CollectForStaticVar(members: ArrayList<Decl>): Unit {
        let uninitStaticVars = ArrayList<Decl>()
        var staticInit: Option<FuncDecl> = None
        for (member in members) {
            if (IsGlobalOrStaticOrConstVar(member)) {
                CollectForVar(member)
                if (let Some(varDecl) <- (member as VarDecl)) {
                    if (let None <- varDecl.initializer) {
                        uninitStaticVars.add(varDecl)
                    }
                }
            } else if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (IsStaticInitializer(funcDecl)) {
                    staticInit = funcDecl
                }
            }
        }
        if (let Some(initFunc) <- staticInit) {
            CollectForStaticInit(initFunc, uninitStaticVars)
        }
    }

    private func CollectForVar(decl: Decl): Unit {
        if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
            let builtNode = graph.GetOrBuildNode(varDecl)
            currentNode = builtNode
            builtNode.visitOrder = visitOrder
            visitOrder++
            CollectVarUsageBFS(varDecl)
        }
    }

    private func CollectForStaticInit(staticInit: FuncDecl, staticVars: ArrayList<Decl>): Unit {
        let visited = ArrayList<Decl>()
        if (let Some(body) <- staticInit.funcBody) {
            let walker = Walker(body, visitPre: { node: Node =>
                if (let Some(expr) <- (node as Expr)) {
                    if (let Some(desugar) <- expr.desugarExpr) {
                        CollectVarUsageBFS(desugar)
                        return VisitAction.SKIP_CHILDREN
                    }
                }
                if (let Some(assign) <- (node as AssignExpr)) {
                    if (let Some(left) <- assign.leftValue) {
                        if (let Some(target) <- left.GetTarget()) {
                            if (let Some(varTarget) <- (target as VarDecl)) {
                                if (ContainsDecl(staticVars, varTarget) && !ContainsDecl(visited, varTarget)) {
                                    varTarget.EnableAttr(Attribute.INITIALIZED)
                                    if (!varTarget.isVar && varTarget.TestAttr(Attribute.COMMON) &&
                                        varTarget.TestAttr(Attribute.STATIC)) {
                                        issues.add(GlobalVarInitializationIssue(
                                            GlobalVarInitIssueKind.COMMON_STATIC_LET_INITIALIZED_IN_STATIC_INIT,
                                            assign,
                                            assign.begin,
                                            varTarget.identifier.Val(),
                                            staticInit,
                                            varTarget,
                                            message: "common static let cannot be initialized in static init"
                                        ))
                                    }
                                    let staticNode = graph.GetOrBuildNode(varTarget)
                                    currentNode = staticNode
                                    staticNode.visitOrder = visitOrder
                                    visitOrder++
                                    if (let Some(right) <- assign.rightExpr) {
                                        CollectVarUsageBFS(right)
                                    }
                                    visited.add(varTarget)
                                    return VisitAction.SKIP_CHILDREN
                                }
                            }
                        }
                    }
                }
                VisitAction.WALK_CHILDREN
            })
            walker.Walk()
        }
        let initNode = graph.GetOrBuildNode(staticInit)
        currentNode = initNode
        initNode.visitOrder = visitOrder
        visitOrder++
        CollectVarUsageBFS(staticInit)
    }

    private func CollectVarUsageBFS(root: Node): Unit {
        let worklist = ArrayList<Node>()
        let visited = ArrayList<Node>()
        worklist.add(root)
        var cursor: Int64 = 0
        while (cursor < worklist.size) {
            let current = worklist[cursor]
            cursor++
            if (ContainsNode(visited, current)) {
                continue
            }
            visited.add(current)
            CollectVarUsageBFSImpl(current, worklist)
        }
    }

    private func CollectVarUsageBFSImpl(root: Node, worklist: ArrayList<Node>): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            if (let Some(expr) <- (node as Expr)) {
                if (let Some(desugar) <- expr.desugarExpr) {
                    worklist.add(desugar)
                    return VisitAction.SKIP_CHILDREN
                }
            }
            if (let Some(funcDecl) <- (node as FuncDecl)) {
                if (CanIgnoreTarget(funcDecl)) {
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(outer) <- funcDecl.outerDecl) {
                    if (IsInstanceConstructor(funcDecl)) {
                        for (member in GetDefaultInitVariables(outer)) {
                            worklist.add(member)
                        }
                    }
                }
                return VisitAction.WALK_CHILDREN
            }
            if (let Some(varDecl) <- (node as VarDecl)) {
                if (let Some(initExpr) <- varDecl.initializer) {
                    if (initExpr.astKind != ASTKind.LAMBDA_EXPR) {
                        worklist.add(initExpr)
                    }
                }
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(vpd) <- (node as VarWithPatternDecl)) {
                if (let Some(initExpr) <- vpd.initializer) {
                    worklist.add(initExpr)
                }
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(assign) <- (node as AssignExpr)) {
                if (let Some(right) <- assign.rightExpr) {
                    if (right.astKind != ASTKind.LAMBDA_EXPR) {
                        worklist.add(right)
                    }
                }
                if (let Some(left) <- assign.leftValue) {
                    if (let Some(target) <- GetTargetIfShouldCollect(left)) {
                        worklist.add(target)
                    }
                }
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(member) <- (node as MemberAccess)) {
                if (let Some(target) <- GetTargetIfShouldCollect(member)) {
                    worklist.add(target)
                }
                CollectInMemberAccess(member)
                return VisitAction.WALK_CHILDREN
            }
            if (let Some(refExpr) <- (node as RefExpr)) {
                CollectInRefExpr(refExpr)
                if (let Some(target) <- GetTargetIfShouldCollect(refExpr)) {
                    worklist.add(target)
                }
                return VisitAction.SKIP_CHILDREN
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    private func GetDefaultInitVariables(outer: Decl): ArrayList<VarDecl> {
        let result = ArrayList<VarDecl>()
        for (member in outer.GetMemberDeclPtrs()) {
            if (let Some(varDecl) <- (member as VarDecl)) {
                if (!varDecl.TestAttr(Attribute.STATIC)) {
                    result.add(varDecl)
                }
            }
        }
        return result
    }

    private func CurrentVariable(): Option<Decl> {
        if (let Some(node) <- currentNode) {
            return node.variable
        }
        return None
    }

    private func CollectInRefExpr(refExpr: RefExpr): Unit {
        if (refExpr.isThis) {
            return
        }
        if (let Some(target) <- refExpr.ref.target) {
            if (target.astKind == ASTKind.GENERIC_PARAM_DECL ||
                target.TestAnyAttr(Attribute.IMPORTED, Attribute.FOREIGN, Attribute.ENUM_CONSTRUCTOR)) {
                return
            }
            if (IsGlobalOrStaticOrConstVar(target)) {
                if (let Some(varTarget) <- (target as VarDeclAbstract)) {
                    if (let Some(user) <- CurrentVariable()) {
                        graph.AddEdge(user, varTarget, refExpr)
                    }
                }
            }
        }
    }

    private func CollectInMemberAccess(member: MemberAccess): Unit {
        if (let Some(target) <- member.target) {
            if (IsGlobalOrStaticOrConstVar(target)) {
                if (let Some(varTarget) <- (target as VarDeclAbstract)) {
                    if (let Some(user) <- CurrentVariable()) {
                        graph.AddEdge(user, varTarget, member)
                    }
                }
            }
        }
    }

    private func DoCheck(pkg: Package): Unit {
        if (!CheckInSameFile()) {
            return
        }
        CheckCrossFile(pkg)
    }

    private func CheckInSameFile(): Bool {
        var result = true
        for (node in graph.nodes) {
            if (!CheckVarUsageForDefNode(node)) {
                result = false
            }
        }
        return result
    }

    private func CheckVarUsageForDefNode(node: DefNode): Bool {
        for (usage in node.usage) {
            let usedNode = usage.node
            if (!IsInSameFile(node.variable, usedNode.variable)) {
                continue
            }
            if (usedNode.visitOrder >= node.visitOrder) {
                issues.add(GlobalVarInitializationIssue(
                    GlobalVarInitIssueKind.USED_BEFORE_INITIALIZATION,
                    usage.refNode,
                    usage.refPos,
                    usage.refName,
                    node.variable,
                    usedNode.variable
                ))
                return false
            }
        }
        return true
    }

    private func CheckCrossFile(pkg: Package): Unit {
        for (file in pkg.files) {
            AddInitializationOrderEdge(file)
        }
        CheckByToposort()
    }

    private func AddInitializationOrderEdge(file: File): Unit {
        var previous: Option<VarDecl> = None
        for (decl in file.decls) {
            if (let Some(varDecl) <- (decl as VarDecl)) {
                if (let Some(prevDecl) <- previous) {
                    graph.AddOrderEdge(varDecl, prevDecl)
                }
                previous = varDecl
            }
        }
    }

    private func CheckByToposort(): Unit {
        for (node in graph.nodes) {
            if (node.color == DefColor.WHITE) {
                if (!ToposortDFS(node)) {
                    return
                }
            }
        }
    }

    private func ToposortDFS(node: DefNode): Bool {
        if (node.color == DefColor.BLACK) {
            return true
        }
        if (node.color == DefColor.GRAY) {
            return false
        }
        node.color = DefColor.GRAY
        for (usage in node.usage) {
            if (!ToposortDFS(usage.node)) {
                if (usage.node.color == DefColor.GRAY) {
                    issues.add(GlobalVarInitializationIssue(
                        GlobalVarInitIssueKind.INITIALIZATION_CYCLE,
                        usage.refNode,
                        usage.refPos,
                        usage.refName,
                        node.variable,
                        usage.node.variable
                    ))
                }
                node.color = DefColor.BLACK
                return false
            }
        }
        node.color = DefColor.BLACK
        return true
    }
}

public func CheckGlobalVarInitialization(pkg: Package): ArrayList<GlobalVarInitializationIssue> {
    return GlobalVarInitializationChecker().Analyze(pkg)
}

public func SelfhostPortStatus_LegalityOfUsage_GlobalVarChecker(): Bool {
    return true
}
