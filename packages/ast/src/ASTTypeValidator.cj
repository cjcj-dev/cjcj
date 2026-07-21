package cjcj::ast

import cjcj::basic.{DiagnosticEngine, DiagKindRefactor}
import cjcj::basic.Range as BasicRange
import std.collection.*

private class ValidRangeFrame {
    public let kind: ASTKind
    public let begin: Position
    public let end: Position
    public let range: BasicRange

    public init(node: Node) {
        kind = node.astKind
        begin = node.begin
        end = node.end
        range = MakeRange(node.begin, node.end)
    }

    public func IsForNode(node: Node): Bool {
        return kind == node.astKind && begin == node.begin && end == node.end
    }
}

public class ASTTypeValidator {
    public var failed: Bool = false
    public var firstInvalid: Option<Node> = None
    public let messages: ArrayList<String> = ArrayList<String>()
    private var walkerID: UInt32 = 0u32
    private let validRanges: ArrayList<ValidRangeFrame> = ArrayList<ValidRangeFrame>()
    private let checkStatus: ArrayList<Bool> = ArrayList<Bool>()
    private var diagEngine: Option<DiagnosticEngine> = None

    public init() {}

    public func Validate(pkg: Package): Bool {
        diagEngine = None
        return validateImpl(pkg)
    }

    public func Validate(diag: DiagnosticEngine, pkg: Package): Bool {
        diagEngine = diag
        return validateImpl(pkg)
    }

    private func validateImpl(pkg: Package): Bool {
        failed = false
        firstInvalid = None
        messages.clear()
        validRanges.clear()
        checkStatus.clear()
        validRanges.add(ValidRangeFrameForDefault())
        walkerID = GetNextWalkerID()
        let walker = Walker(pkg, walkerID, visitPre: { node: Node => PreVisitor(node) },
            visitPost: { node: Node => PostVisitor(node) })
        walker.Walk()
        return !failed
    }

    public func PreVisitor(node: Node): VisitAction {
        let range = MakeRange(node.begin, node.end)
        if (!range.HasZero()) {
            validRanges.add(ValidRangeFrame(node))
        }
        var strategy = getNodeValidatingStrategy(node)
        var action = strategy[0]
        var needCheck = strategy[1]
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(desugar) <- expr.desugarExpr) {
                let desugarAction = Walker(desugar, walkerID, visitPre: { child: Node => PreVisitor(child) },
                    visitPost: { child: Node => PostVisitor(child) }).Walk()
                if (desugarAction.isStopNow()) {
                    return VisitAction.STOP_NOW
                }
                action = VisitAction.SKIP_CHILDREN
            }
        }
        if (action.isSkipChildren()) {
            needCheck = false
        }
        checkStatus.add(needCheck)
        return if (IsTypeNode(node)) { VisitAction.SKIP_CHILDREN } else { action }
    }

    public func PostVisitor(node: Node): VisitAction {
        var needCheck = false
        if (!checkStatus.isEmpty()) {
            needCheck = checkStatus[checkStatus.size - 1]
            checkStatus.remove(at: checkStatus.size - 1)
        }
        if (!needCheck) {
            return VisitAction.WALK_CHILDREN
        }
        let valid = validateNode(node)
        if (!valid) {
            markInvalid(node)
            emitInvalidNodeDiagnostic(node)
            return VisitAction.STOP_NOW
        }
        popValidRangeIfCurrent(node)
        return VisitAction.WALK_CHILDREN
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

    private func validateNode(node: Node): Bool {
        let curTarget = node.GetTarget()
        if (let Some(target) <- curTarget) {
            if (!isIgnoredTargetNode(node) && !isIgnoreKind(target.astKind) && !Ty.IsTyCorrect(target.GetTy())) {
                messages.add("invalid target type from ${ASTKindName(node.astKind)} to ${ASTKindName(target.astKind)}")
                return false
            }
        }
        if (!Ty.IsTyCorrect(node.GetTy()) || hasUnresolvedTypeVars(node.GetTy())) {
            messages.add("invalid sema type on ${ASTKindName(node.astKind)} at ${node.begin.ToString()}")
            return false
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
                if (!Ty.IsTyCorrect(parentDecl.GetTy())) {
                    messages.add("invalid owner type for function body at ${body.begin.ToString()}")
                    return false
                }
            }
        }
        return true
    }

    private func hasUnresolvedTypeVars(ty: Option<Ty>): Bool {
        if (let Some(value) <- ty) {
            return value.HasIdealTy() || value.HasQuestTy()
        }
        return true
    }

    private func currentValidRange(): BasicRange {
        if (!validRanges.isEmpty()) {
            return validRanges[validRanges.size - 1].range
        }
        return MakeRange(DEFAULT_POSITION, DEFAULT_POSITION)
    }

    private func popValidRangeIfCurrent(node: Node): Unit {
        if (validRanges.isEmpty()) {
            return
        }
        let last = validRanges[validRanges.size - 1]
        if (last.IsForNode(node)) {
            validRanges.remove(at: validRanges.size - 1)
        }
    }

    private func emitInvalidNodeDiagnostic(node: Node): Unit {
        if (let Some(diag) <- diagEngine) {
            let builder = DiagnoseRefactor(
                diag, DiagKindRefactor.sema_invalid_node_after_check, node, currentValidRange())
            builder.AddNote("please report this to Cangjie team and include the project")
            builder.Emit()
        }
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

public func ValidateUsedNodes(diagEngine: DiagnosticEngine, pkg: Package): Unit {
    ASTTypeValidator().Validate(diagEngine, pkg)
}

private func ValidRangeFrameForDefault(): ValidRangeFrame {
    let node = Node()
    node.begin = DEFAULT_POSITION
    node.end = DEFAULT_POSITION
    return ValidRangeFrame(node)
}
