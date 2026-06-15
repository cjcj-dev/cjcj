package cangjie_compiler::ast

public enum VisitAction {
    | WALK_CHILDREN
    | SKIP_CHILDREN
    | STOP_NOW
    | KEEP_DECISION
}

private func VisitActionIndex(action: VisitAction): Int64 {
    return match (action) {
        case VisitAction.WALK_CHILDREN => 0
        case VisitAction.SKIP_CHILDREN => 1
        case VisitAction.STOP_NOW => 2
        case VisitAction.KEEP_DECISION => 3
    }
}

extend VisitAction <: Equatable<VisitAction> {
    public operator func ==(right: VisitAction): Bool {
        return VisitActionIndex(this) == VisitActionIndex(right)
    }

    public operator func !=(right: VisitAction): Bool {
        return !(this == right)
    }
}

private var nextWalkerID: UInt32 = 1u32

public func GetNextWalkerID(): UInt32 {
    let out = nextWalkerID
    nextWalkerID++
    if (nextWalkerID == 0u32) {
        nextWalkerID = 1u32
    }
    return out
}

public class Walker {
    private var root: Option<Node> = None
    private var id: UInt32 = 0u32
    private var visitPre: Option<(Node) -> VisitAction> = None
    private var visitPost: Option<(Node) -> VisitAction> = None

    public init(node: Node, visitPre!: Option<(Node) -> VisitAction> = None,
        visitPost!: Option<(Node) -> VisitAction> = None) {
        root = node
        id = GetNextWalkerID()
        this.visitPre = visitPre
        this.visitPost = visitPost
    }

    public init(node: Node, walkerID: UInt32, visitPre!: Option<(Node) -> VisitAction> = None,
        visitPost!: Option<(Node) -> VisitAction> = None) {
        root = node
        id = walkerID
        this.visitPre = visitPre
        this.visitPost = visitPost
    }

    public func Walk(): VisitAction {
        if (let Some(node) <- root) {
            return WalkNode(node)
        }
        return VisitAction.WALK_CHILDREN
    }

    public func WalkNode(curNode: Node): VisitAction {
        if (curNode.astKind != ASTKind.MODIFIER && curNode.visitedByWalkerID == id) {
            return VisitAction.WALK_CHILDREN
        }
        curNode.visitedByWalkerID = id

        var action = VisitAction.WALK_CHILDREN
        if (let Some(pre) <- visitPre) {
            action = pre(curNode)
        }
        if (action == VisitAction.STOP_NOW) {
            return action
        }
        if (action == VisitAction.WALK_CHILDREN) {
            let childAction = WalkChildren(curNode)
            if (childAction == VisitAction.STOP_NOW) {
                return childAction
            }
        }
        if (let Some(post) <- visitPost) {
            let postAction = post(curNode)
            if (postAction == VisitAction.STOP_NOW) {
                return postAction
            }
        }
        return action
    }

    private func walkExprOption(node: Option<Expr>): VisitAction {
        if (let Some(value) <- node) {
            return WalkNode(value)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func walkTypeOption(node: Option<Type>): VisitAction {
        if (let Some(value) <- node) {
            return WalkNode(value)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func stopIf(action: VisitAction): Bool {
        return action == VisitAction.STOP_NOW
    }

    public func WalkChildren(curNode: Node): VisitAction {
        // TODO(selfhost:AST): complete the exhaustive C++ Walker.cpp child table after all AST node fields are ported.
        if (let Some(expr) <- (curNode as Expr)) {
            if (stopIf(walkExprOption(expr.desugarExpr))) { return VisitAction.STOP_NOW }
        }
        if (let Some(decl) <- (curNode as Decl)) {
            for (annotation in decl.annotations) {
                if (stopIf(WalkNode(annotation))) { return VisitAction.STOP_NOW }
            }
            if (let Some(array) <- decl.annotationsArray) {
                if (stopIf(WalkNode(array))) { return VisitAction.STOP_NOW }
            }
            if (let Some(generic) <- decl.GetGeneric()) {
                if (stopIf(WalkNode(generic))) { return VisitAction.STOP_NOW }
            }
        }
        if (let Some(pkg) <- (curNode as Package)) {
            for (file in pkg.files) {
                if (stopIf(WalkNode(file))) { return VisitAction.STOP_NOW }
            }
            for (decl in pkg.genericInstantiatedDecls) {
                if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW }
            }
            for (decl in pkg.srcImportedNonGenericDecls) {
                if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(file) <- (curNode as File)) {
            if (let Some(feature) <- file.feature) {
                if (stopIf(WalkNode(feature))) { return VisitAction.STOP_NOW }
            }
            if (let Some(pkgSpec) <- file.packageSpec) {
                if (stopIf(WalkNode(pkgSpec))) { return VisitAction.STOP_NOW }
            }
            for (importSpec in file.imports) {
                if (stopIf(WalkNode(importSpec))) { return VisitAction.STOP_NOW }
            }
            for (decl in file.exportedInternalDecls) {
                if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW }
            }
            for (decl in file.decls) {
                if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(funcBody) <- (curNode as FuncBody)) {
            if (let Some(generic) <- funcBody.generic) {
                if (stopIf(WalkNode(generic))) { return VisitAction.STOP_NOW }
            }
            for (params in funcBody.paramLists) {
                if (stopIf(WalkNode(params))) { return VisitAction.STOP_NOW }
            }
            if (stopIf(walkTypeOption(funcBody.retType))) { return VisitAction.STOP_NOW }
            if (let Some(body) <- funcBody.body) {
                if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(paramList) <- (curNode as FuncParamList)) {
            for (param in paramList.params) {
                if (stopIf(WalkNode(param))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(block) <- (curNode as Block)) {
            for (node in block.body) {
                if (stopIf(WalkNode(node))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(call) <- (curNode as CallExpr)) {
            if (stopIf(walkExprOption(call.baseFunc))) { return VisitAction.STOP_NOW }
            for (arg in call.args) {
                if (stopIf(WalkNode(arg))) { return VisitAction.STOP_NOW }
            }
            for (arg in call.defaultArgs) {
                if (stopIf(WalkNode(arg))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(arg) <- (curNode as FuncArg)) {
            if (stopIf(walkExprOption(arg.expr))) { return VisitAction.STOP_NOW }
        } else if (let Some(refType) <- (curNode as RefType)) {
            for (ty in refType.typeArguments) {
                if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(qualified) <- (curNode as QualifiedType)) {
            if (stopIf(walkTypeOption(qualified.baseType))) { return VisitAction.STOP_NOW }
            for (ty in qualified.typeArguments) {
                if (stopIf(WalkNode(ty))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(member) <- (curNode as MemberAccess)) {
            if (stopIf(walkExprOption(member.baseExpr))) { return VisitAction.STOP_NOW }
        } else if (let Some(generic) <- (curNode as Generic)) {
            for (param in generic.typeParameters) {
                if (stopIf(WalkNode(param))) { return VisitAction.STOP_NOW }
            }
            for (constraint in generic.genericConstraints) {
                if (stopIf(WalkNode(constraint))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(constraint) <- (curNode as GenericConstraint)) {
            if (let Some(refType) <- constraint.refType) {
                if (stopIf(WalkNode(refType))) { return VisitAction.STOP_NOW }
            }
            for (ub in constraint.upperBounds) {
                if (stopIf(WalkNode(ub))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(varDecl) <- (curNode as VarDeclAbstract)) {
            if (stopIf(walkTypeOption(varDecl.typeNode))) { return VisitAction.STOP_NOW }
            if (stopIf(walkExprOption(varDecl.initializer))) { return VisitAction.STOP_NOW }
        } else if (let Some(funcDecl) <- (curNode as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(classDecl) <- (curNode as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(structDecl) <- (curNode as StructDecl)) {
            if (let Some(body) <- structDecl.body) {
                if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(interfaceDecl) <- (curNode as InterfaceDecl)) {
            if (let Some(body) <- interfaceDecl.body) {
                if (stopIf(WalkNode(body))) { return VisitAction.STOP_NOW }
            }
        } else if (let Some(body) <- (curNode as ClassBody)) {
            for (decl in body.decls) { if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW } }
        } else if (let Some(body) <- (curNode as StructBody)) {
            for (decl in body.decls) { if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW } }
        } else if (let Some(body) <- (curNode as InterfaceBody)) {
            for (decl in body.decls) { if (stopIf(WalkNode(decl))) { return VisitAction.STOP_NOW } }
        }
        return VisitAction.WALK_CHILDREN
    }
}
