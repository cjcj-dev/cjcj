package cangjie_compiler::ast

import std.collection.*

public class ASTTypeValidator {
    public var failed: Bool = false
    public var firstInvalid: Option<Node> = None
    public let messages: ArrayList<String> = ArrayList<String>()
    private var walkerID: UInt32 = 0u32

    public init() {}

    public func Validate(pkg: Package): Bool {
        failed = false
        firstInvalid = None
        messages.clear()
        walkerID = GetNextWalkerID()
        let walker = Walker(pkg, walkerID, visitPre: { node: Node => preVisitor(node) })
        walker.Walk()
        return !failed
    }

    private func preVisitor(node: Node): VisitAction {
        var strategy = getNodeValidatingStrategy(node)
        var action = strategy[0]
        var needCheck = strategy[1]
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(desugar) <- expr.desugarExpr) {
                let desugarAction = Walker(desugar, walkerID, visitPre: { child: Node => preVisitor(child) }).Walk()
                if (desugarAction == VisitAction.STOP_NOW) {
                    return VisitAction.STOP_NOW
                }
                action = VisitAction.SKIP_CHILDREN
            }
        }
        if (action == VisitAction.SKIP_CHILDREN) {
            needCheck = false
        }
        if (needCheck && !validateNode(node)) {
            markInvalid(node)
            return VisitAction.STOP_NOW
        }
        return if (IsTypeNode(node)) { VisitAction.SKIP_CHILDREN } else { action }
    }

    private func markInvalid(node: Node): Unit {
        failed = true
        if (let None <- firstInvalid) {
            firstInvalid = node
        }
    }

    private func getNodeValidatingStrategy(node: Node): (VisitAction, Bool) {
        var action = VisitAction.WALK_CHILDREN
        var needCheck = true
        if (node.TestAttr(Attribute.GENERIC) || isIgnoreKind(node.astKind) ||
            (node.astKind != ASTKind.PACKAGE && node.TestAttr(Attribute.INCRE_COMPILE)) ||
            node.TestAttr(Attribute.FROM_COMMON_PART) ||
            (node.TestAttr(Attribute.COMMON) && node.TestAttr(Attribute.IMPORTED)) ||
            (node.astKind == ASTKind.FUNC_ARG && node.TestAttr(Attribute.HAS_INITIAL))) {
            action = VisitAction.SKIP_CHILDREN
        } else if (isNoneTyKind(node.astKind)) {
            needCheck = false
        } else if (IsTypeNode(node)) {
            if (let Some(ty) <- node.GetTy()) {
                if (ty.IsGeneric()) {
                    action = VisitAction.SKIP_CHILDREN
                }
            }
        } else if (let Some(target) <- node.GetTarget()) {
            if (target.astKind == ASTKind.PACKAGE_DECL) {
                action = VisitAction.SKIP_CHILDREN
            }
        }
        return (action, needCheck)
    }

    private func isResolvedTy(ty: Option<Ty>): Bool {
        if (let Some(value) <- ty) {
            return !value.HasInvalidTy() && !value.HasIdealTy() && !value.HasQuestTy()
        }
        return false
    }

    private func validateNode(node: Node): Bool {
        if (!isResolvedTy(node.GetTy())) {
            messages.add("invalid sema type on ${ASTKindName(node.astKind)} at ${node.begin.ToString()}")
            return false
        }
        if (let Some(target) <- node.GetTarget()) {
            if (!isIgnoredTargetNode(node) && !isIgnoreKind(target.astKind) && !isResolvedTy(target.GetTy())) {
                messages.add("invalid target type from ${ASTKindName(node.astKind)} to ${ASTKindName(target.astKind)}")
                return false
            }
        }
        if (let Some(body) <- (node as FuncBody)) {
            var parent: Option<Decl> = None
            if (let Some(classLike) <- body.parentClassLike) {
                parent = classLike
            } else if (let Some(structDecl) <- body.parentStruct) {
                parent = structDecl
            } else if (let Some(enumDecl) <- body.parentEnum) {
                parent = enumDecl
            }
            if (let Some(parentDecl) <- parent) {
                if (!isResolvedTy(parentDecl.GetTy())) {
                    messages.add("invalid owner type for function body at ${body.begin.ToString()}")
                    return false
                }
            }
        }
        return true
    }

    private func isIgnoredTargetNode(node: Node): Bool {
        return IsTypeNode(node) || node.astKind == ASTKind.MACRO_EXPAND_DECL ||
            node.astKind == ASTKind.MACRO_EXPAND_EXPR || node.astKind == ASTKind.MACRO_EXPAND_PARAM
    }

    private func isIgnoreKind(kind: ASTKind): Bool {
        return kind == ASTKind.GENERIC_PARAM_DECL || kind == ASTKind.GENERIC_CONSTRAINT ||
            kind == ASTKind.PRIMARY_CTOR_DECL || kind == ASTKind.TYPE_ALIAS_DECL ||
            kind == ASTKind.BUILTIN_DECL || kind == ASTKind.MODIFIER || kind == ASTKind.ANNOTATION ||
            kind == ASTKind.PACKAGE_SPEC || kind == ASTKind.IMPORT_SPEC ||
            kind == ASTKind.WILDCARD_PATTERN || kind == ASTKind.GENERIC ||
            kind == ASTKind.MACRO_EXPAND_DECL || kind == ASTKind.MACRO_EXPAND_EXPR ||
            kind == ASTKind.MACRO_EXPAND_PARAM
    }

    private func isNoneTyKind(kind: ASTKind): Bool {
        return kind == ASTKind.PACKAGE || kind == ASTKind.FILE || kind == ASTKind.PRIMARY_CTOR_DECL ||
            kind == ASTKind.MACRO_DECL || kind == ASTKind.MAIN_DECL ||
            kind == ASTKind.CLASS_BODY || kind == ASTKind.INTERFACE_BODY ||
            kind == ASTKind.STRUCT_BODY || kind == ASTKind.DUMMY_BODY ||
            kind == ASTKind.RETURN_EXPR || kind == ASTKind.LET_PATTERN_DESTRUCTOR ||
            kind == ASTKind.FUNC_PARAM_LIST
    }
}

public func ValidateUsedNodes(pkg: Package): Bool {
    return ASTTypeValidator().Validate(pkg)
}
