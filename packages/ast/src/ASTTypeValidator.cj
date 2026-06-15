package cangjie_compiler::ast

import std.collection.*

public class ASTTypeValidator {
    public var failed: Bool = false
    public var firstInvalid: Option<Node> = None
    public let messages: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func Validate(pkg: Package): Bool {
        failed = false
        firstInvalid = None
        messages.clear()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!validateNode(node)) {
                failed = true
                firstInvalid = node
                return VisitAction.STOP_NOW
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
        return !failed
    }

    private func validateNode(node: Node): Bool {
        if (!isIgnored(node) && !Ty.IsTyCorrect(node.GetTy())) {
            messages.add("invalid sema type on ${ASTKindName(node.astKind)} at ${node.begin.ToString()}")
            return false
        }
        if (let Some(target) <- node.GetTarget()) {
            if (!isIgnoredTargetNode(node) && !isIgnored(target) && !Ty.IsTyCorrect(target.GetTy())) {
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
                if (!Ty.IsTyCorrect(parentDecl.GetTy())) {
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

    private func isIgnored(node: Node): Bool {
        if (node.TestAttr(Attribute.GENERIC) || node.TestAttr(Attribute.INCRE_COMPILE) ||
            node.TestAttr(Attribute.FROM_COMMON_PART) ||
            (node.TestAttr(Attribute.COMMON) && node.TestAttr(Attribute.IMPORTED))) {
            return true
        }
        return node.astKind == ASTKind.PACKAGE || node.astKind == ASTKind.FILE ||
            node.astKind == ASTKind.MODIFIER || node.astKind == ASTKind.ANNOTATION ||
            node.astKind == ASTKind.PACKAGE_SPEC || node.astKind == ASTKind.IMPORT_SPEC ||
            node.astKind == ASTKind.GENERIC_PARAM_DECL || node.astKind == ASTKind.GENERIC_CONSTRAINT ||
            node.astKind == ASTKind.PRIMARY_CTOR_DECL || node.astKind == ASTKind.TYPE_ALIAS_DECL ||
            node.astKind == ASTKind.BUILTIN_DECL || node.astKind == ASTKind.GENERIC ||
            node.astKind == ASTKind.RETURN_EXPR || node.astKind == ASTKind.LET_PATTERN_DESTRUCTOR ||
            node.astKind == ASTKind.FUNC_PARAM_LIST || node.astKind == ASTKind.CLASS_BODY ||
            node.astKind == ASTKind.INTERFACE_BODY || node.astKind == ASTKind.STRUCT_BODY ||
            node.astKind == ASTKind.DUMMY_BODY
    }
}

public func ValidateUsedNodes(pkg: Package): Bool {
    return ASTTypeValidator().Validate(pkg)
}
