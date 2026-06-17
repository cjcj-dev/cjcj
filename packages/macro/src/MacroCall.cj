package cangjie_compiler::macro_pkg

import std.collection.*

public enum MacroKind {
    | EXPR_KIND
    | DECL_KIND
    | PARAM_KIND
    | UNINITIALIZED
}

private func MacroKindIndex(kind: MacroKind): Int64 {
    return match (kind) {
        case MacroKind.EXPR_KIND => 0
        case MacroKind.DECL_KIND => 1
        case MacroKind.PARAM_KIND => 2
        case MacroKind.UNINITIALIZED => 3
    }
}

extend MacroKind <: Equatable<MacroKind> {
    public operator func ==(right: MacroKind): Bool {
        return MacroKindIndex(this) == MacroKindIndex(right)
    }

    public operator func !=(right: MacroKind): Bool {
        return !(this == right)
    }
}

public enum MacroEvalStatus {
    | INIT
    | READY
    | EVAL
    | SUCCESS
    | FAIL
    | REEVAL
    | FINISH
    | ANNOTATION
    | REEVALFAILED
}

public func MacroEvalStatusIndex(status: MacroEvalStatus): Int64 {
    return match (status) {
        case MacroEvalStatus.INIT => 0
        case MacroEvalStatus.READY => 1
        case MacroEvalStatus.EVAL => 2
        case MacroEvalStatus.SUCCESS => 3
        case MacroEvalStatus.FAIL => 4
        case MacroEvalStatus.REEVAL => 5
        case MacroEvalStatus.FINISH => 6
        case MacroEvalStatus.ANNOTATION => 7
        case MacroEvalStatus.REEVALFAILED => 8
    }
}

extend MacroEvalStatus <: Equatable<MacroEvalStatus> {
    public operator func ==(right: MacroEvalStatus): Bool {
        return MacroEvalStatusIndex(this) == MacroEvalStatusIndex(right)
    }

    public operator func !=(right: MacroEvalStatus): Bool {
        return !(this == right)
    }
}

public enum ItemKind {
    | STRING
    | INT
    | BOOL
    | TKS
}

public func ItemKindIndex(kind: ItemKind): Int64 {
    return match (kind) {
        case ItemKind.STRING => 1
        case ItemKind.INT => 2
        case ItemKind.BOOL => 3
        case ItemKind.TKS => 4
    }
}

extend ItemKind <: Equatable<ItemKind> {
    public operator func ==(right: ItemKind): Bool {
        return ItemKindIndex(this) == ItemKindIndex(right)
    }

    public operator func !=(right: ItemKind): Bool {
        return !(this == right)
    }
}

public class ItemInfo {
    public var key: String = ""
    public var kind: ItemKind = ItemKind.STRING
    public var sValue: String = ""
    public var iValue: Int64 = 0
    public var bValue: Bool = false
    public let tValue: ArrayList<Token> = ArrayList<Token>()

    public init() {}

    public init(key: String, value: String) {
        this.key = key
        kind = ItemKind.STRING
        sValue = value
    }

    public init(key: String, value: Int64) {
        this.key = key
        kind = ItemKind.INT
        iValue = value
    }

    public init(key: String, value: Bool) {
        this.key = key
        kind = ItemKind.BOOL
        bValue = value
    }

    public init(key: String, value: ArrayList<Token>) {
        this.key = key
        kind = ItemKind.TKS
        for (token in value) {
            tValue.add(token)
        }
    }
}

public class ChildMessage {
    public var childName: String = ""
    public let items: ArrayList<ItemInfo> = ArrayList<ItemInfo>()

    public init() {}

    public init(childName: String, items: ArrayList<ItemInfo>) {
        this.childName = childName
        for (item in items) {
            this.items.add(item)
        }
    }
}

public enum ReplaceTargetKind {
    | NONE
    | EXPR_BOX
    | NODE_VECTOR
    | EXPR_VECTOR
    | DECL_VECTOR
    | PARAM_VECTOR
}

private func ReplaceTargetKindIndex(kind: ReplaceTargetKind): Int64 {
    return match (kind) {
        case ReplaceTargetKind.NONE => 0
        case ReplaceTargetKind.EXPR_BOX => 1
        case ReplaceTargetKind.NODE_VECTOR => 2
        case ReplaceTargetKind.EXPR_VECTOR => 3
        case ReplaceTargetKind.DECL_VECTOR => 4
        case ReplaceTargetKind.PARAM_VECTOR => 5
    }
}

extend ReplaceTargetKind <: Equatable<ReplaceTargetKind> {
    public operator func ==(right: ReplaceTargetKind): Bool {
        return ReplaceTargetKindIndex(this) == ReplaceTargetKindIndex(right)
    }

    public operator func !=(right: ReplaceTargetKind): Bool {
        return !(this == right)
    }
}

public enum ExprFieldKind {
    | NONE
    | FUNC_PARAM_ASSIGNMENT
    | FUNC_ARG_EXPR
    | CALL_BASE_FUNC
    | MEMBER_BASE_EXPR
    | RETURN_EXPR_VALUE
    | IF_COND_EXPR
    | BINARY_LEFT_EXPR
    | BINARY_RIGHT_EXPR
    | VAR_DECL_INITIALIZER
    | PAREN_EXPR_VALUE
    | UNARY_EXPR_VALUE
    | TYPE_CONV_EXPR_VALUE
    | SUBSCRIPT_BASE_EXPR
    | OPTIONAL_BASE_EXPR
    | OPTIONAL_CHAIN_EXPR_VALUE
    | LET_PATTERN_INITIALIZER
    | ASSIGN_RIGHT_EXPR
    | MATCH_SELECTOR
    | MATCH_CASE_GUARD
    | MATCH_CASE_OTHER_EXPR
    | WHILE_COND_EXPR
    | DO_WHILE_COND_EXPR
    | FOR_IN_EXPR_VALUE
    | FOR_IN_PATTERN_GUARD
    | THROW_EXPR_VALUE
    | PERFORM_EXPR_VALUE
    | SPAWN_TASK
    | TRAILING_CLOSURE_EXPR
    | IS_LEFT_EXPR
    | AS_LEFT_EXPR
    | RANGE_START_EXPR
    | RANGE_STOP_EXPR
    | RANGE_STEP_EXPR
    | VAR_WITH_PATTERN_INITIALIZER
}

private func ExprFieldKindIndex(kind: ExprFieldKind): Int64 {
    return match (kind) {
        case ExprFieldKind.NONE => 0
        case ExprFieldKind.FUNC_PARAM_ASSIGNMENT => 1
        case ExprFieldKind.FUNC_ARG_EXPR => 2
        case ExprFieldKind.CALL_BASE_FUNC => 3
        case ExprFieldKind.MEMBER_BASE_EXPR => 4
        case ExprFieldKind.RETURN_EXPR_VALUE => 5
        case ExprFieldKind.IF_COND_EXPR => 6
        case ExprFieldKind.BINARY_LEFT_EXPR => 7
        case ExprFieldKind.BINARY_RIGHT_EXPR => 8
        case ExprFieldKind.VAR_DECL_INITIALIZER => 9
        case ExprFieldKind.PAREN_EXPR_VALUE => 10
        case ExprFieldKind.UNARY_EXPR_VALUE => 11
        case ExprFieldKind.TYPE_CONV_EXPR_VALUE => 12
        case ExprFieldKind.SUBSCRIPT_BASE_EXPR => 13
        case ExprFieldKind.OPTIONAL_BASE_EXPR => 14
        case ExprFieldKind.OPTIONAL_CHAIN_EXPR_VALUE => 15
        case ExprFieldKind.LET_PATTERN_INITIALIZER => 16
        case ExprFieldKind.ASSIGN_RIGHT_EXPR => 17
        case ExprFieldKind.MATCH_SELECTOR => 18
        case ExprFieldKind.MATCH_CASE_GUARD => 19
        case ExprFieldKind.MATCH_CASE_OTHER_EXPR => 20
        case ExprFieldKind.WHILE_COND_EXPR => 21
        case ExprFieldKind.DO_WHILE_COND_EXPR => 22
        case ExprFieldKind.FOR_IN_EXPR_VALUE => 23
        case ExprFieldKind.FOR_IN_PATTERN_GUARD => 24
        case ExprFieldKind.THROW_EXPR_VALUE => 25
        case ExprFieldKind.PERFORM_EXPR_VALUE => 26
        case ExprFieldKind.SPAWN_TASK => 27
        case ExprFieldKind.TRAILING_CLOSURE_EXPR => 28
        case ExprFieldKind.IS_LEFT_EXPR => 29
        case ExprFieldKind.AS_LEFT_EXPR => 30
        case ExprFieldKind.RANGE_START_EXPR => 31
        case ExprFieldKind.RANGE_STOP_EXPR => 32
        case ExprFieldKind.RANGE_STEP_EXPR => 33
        case ExprFieldKind.VAR_WITH_PATTERN_INITIALIZER => 34
    }
}

extend ExprFieldKind <: Equatable<ExprFieldKind> {
    public operator func ==(right: ExprFieldKind): Bool {
        return ExprFieldKindIndex(this) == ExprFieldKindIndex(right)
    }

    public operator func !=(right: ExprFieldKind): Bool {
        return !(this == right)
    }
}

public class ExprBox {
    public var value: Option<Expr> = None
    public init() {}
    public init(value: Expr) {
        this.value = Some(value)
    }
}

public class ReplaceTarget {
    public var kind: ReplaceTargetKind = ReplaceTargetKind.NONE
    public var loc: Int64 = 0
    public var exprBox: Option<ExprBox> = None
    public var exprParent: Option<Node> = None
    public var exprField: ExprFieldKind = ExprFieldKind.NONE
    public var nodes: Option<ArrayList<Node>> = None
    public var exprs: Option<ArrayList<Expr>> = None
    public var decls: Option<ArrayList<Decl>> = None
    public var params: Option<ArrayList<FuncParam>> = None

    public init() {}
}

public class MacroCall {
    public var replaceLoc: ReplaceTarget = ReplaceTarget()
    public let children: ArrayList<MacroCall> = ArrayList<MacroCall>()
    public var status: MacroEvalStatus = MacroEvalStatus.INIT
    public var isOuterMost: Bool = false
    public var threadId: Int64 = 0
    public var isForInterpolation: Bool = false
    public var strKind: TokenKind = TokenKind.STRING_LITERAL
    public var newStr: String = ""
    public var invokeFuncName: String = ""
    public var invokeFunc: CPointer<Unit> = CPointer<Unit>()
    public var coroutineHandle: CPointer<Unit> = CPointer<Unit>()
    public var isDataReady: Bool = false
    public var useParentPos: Bool = false
    public var parentMacroCall: Option<MacroCall> = None
    public var ci: Option<CompilerInstance> = None
    public let parentNames: ArrayList<String> = ArrayList<String>()
    public let items: ArrayList<ItemInfo> = ArrayList<ItemInfo>()
    public let childMessages: ArrayList<ChildMessage> = ArrayList<ChildMessage>()
    public let assertParents: ArrayList<String> = ArrayList<String>()
    public var hasSend: Bool = false
    public var methodName: String = ""
    public var packageName: String = ""
    public var libPath: String = ""
    private var kind: MacroKind = MacroKind.UNINITIALIZED
    private var invocation: Option<MacroInvocation> = None
    private var node: Option<Node> = None
    private var definition: Option<FuncDecl> = None
    private var begin: Position = INVALID_POSITION
    private var end: Position = INVALID_POSITION

    public init(node: Node) {
        this.node = Some(node)
        begin = node.begin
        end = node.end
        if (let Some(expr) <- (node as MacroExpandExpr)) {
            kind = MacroKind.EXPR_KIND
            invocation = Some(expr.invocation)
        } else if (let Some(decl) <- (node as MacroExpandDecl)) {
            kind = MacroKind.DECL_KIND
            invocation = Some(decl.invocation)
        } else if (let Some(param) <- (node as MacroExpandParam)) {
            kind = MacroKind.PARAM_KIND
            invocation = Some(param.invocation)
        }
    }

    public func GetAnnotations(): ArrayList<Annotation> {
        let out = ArrayList<Annotation>()
        if (let Some(value) <- node) {
            if (let Some(expr) <- (value as MacroExpandExpr)) {
                for (anno in expr.annotations) {
                    out.add(anno)
                }
            } else if (let Some(decl) <- (value as MacroExpandDecl)) {
                for (anno in decl.annotations) {
                    out.add(anno)
                }
            } else if (let Some(param) <- (value as MacroExpandParam)) {
                for (anno in param.annotations) {
                    out.add(anno)
                }
            }
        }
        return out
    }

    public func GetInvocation(): Option<MacroInvocation> {
        return invocation
    }

    public func RequireInvocation(): MacroInvocation {
        if (let Some(value) <- invocation) {
            return value
        }
        return MacroInvocation()
    }

    public func GetModifiers(): ArrayList<Modifier> {
        let out = ArrayList<Modifier>()
        if (let Some(value) <- node) {
            if (let Some(expr) <- (value as MacroExpandExpr)) {
                for (modifier in expr.modifiers) {
                    out.add(modifier)
                }
            } else if (let Some(decl) <- (value as MacroExpandDecl)) {
                for (modifier in decl.modifiers) {
                    out.add(modifier)
                }
            } else if (let Some(param) <- (value as MacroExpandParam)) {
                for (modifier in param.modifiers) {
                    out.add(modifier)
                }
            }
        }
        return out
    }

    public func GetNode(): Option<Node> {
        return node
    }

    public func RequireNode(): Node {
        if (let Some(value) <- node) {
            return value
        }
        return Node()
    }

    public func GetBeginPos(): Position {
        return begin
    }

    public func GetEndPos(): Position {
        return end
    }

    public func GetFullName(): String {
        if (let Some(value) <- invocation) {
            return value.macroCallDiagInfo.fullName
        }
        return ""
    }

    public func GetIdentifier(): String {
        if (let Some(value) <- invocation) {
            return value.macroCallDiagInfo.identifier
        }
        return ""
    }

    public func GetDefinition(): Option<FuncDecl> {
        return definition
    }

    public func BindDefinition(fd: FuncDecl): Unit {
        definition = Some(fd)
    }

    public func HasAttribute(): Bool {
        if (let Some(value) <- invocation) {
            return value.HasAttr()
        }
        return false
    }

    public func GetMacroInfo(): String {
        var fileName = ""
        if (let Some(value) <- node) {
            if (let Some(file) <- value.curFile) {
                fileName = file.fileName
            }
        }
        return "@" + GetFullName() + " in " + fileName + ":" + begin.line.toString() + ":" + begin.column.toString()
    }

    public func CheckParentContext(parentStr: String, report: Bool): Bool {
        var success = false
        if (parentNames.isEmpty()) {
            success = TraverseParentMacroNode(this, parentStr)
        } else {
            for (parentName in parentNames) {
                if (parentName == parentStr) {
                    success = true
                    break
                }
            }
        }
        if (!success && report) {
            if (let Some(instance) <- ci) {
                instance.diag.Diagnose(begin, DiagKind.macro_assert_parent_context_failed,
                    args: [DiagArgument(GetFullName()), DiagArgument(parentStr)]).Emit()
            } else {
                assertParents.add(parentStr)
            }
        }
        return success
    }

    public func DiagReport(level: Int64, range: Range, message: String, hint: String): Unit {
        if (let Some(instance) <- ci) {
            if (level == 1) {
                instance.diag.Warn(range, message + hint)
            } else {
                instance.diag.Diagnose(range, message + hint)
            }
        }
    }

    public func SetStringItemMacroContext(key: String, value: String): Unit {
        items.add(ItemInfo(key, value))
    }

    public func SetIntItemMacroContext(key: String, value: Int64): Unit {
        items.add(ItemInfo(key, value))
    }

    public func SetBoolItemMacroContext(key: String, value: Bool): Unit {
        items.add(ItemInfo(key, value))
    }

    public func SetTokensItemMacroContext(key: String, value: ArrayList<Token>): Unit {
        items.add(ItemInfo(key, value))
    }

    public func GetChildMessagesFromMacroContext(childrenStr: String): ArrayList<ChildMessage> {
        let out = ArrayList<ChildMessage>()
        if (children.isEmpty() && childMessages.isEmpty()) {
            return out
        }
        TraverseMacroNode(this, childrenStr, out)
        return out
    }
}

public func TraverseParentMacroNode(mcNode: MacroCall, parentName: String): Bool {
    if (let Some(parent) <- mcNode.parentMacroCall) {
        if (parent.GetFullName() == parentName) {
            return true
        }
        return TraverseParentMacroNode(parent, parentName)
    }
    return false
}

public func TraverseMacroNode(macroNode: MacroCall, childName: String, macroInfos: ArrayList<ChildMessage>): Unit {
    if (!macroNode.childMessages.isEmpty()) {
        for (message in macroNode.childMessages) {
            if (message.childName == childName) {
                macroInfos.add(message)
            }
        }
        return
    }
    if (macroNode.GetFullName() == childName && !macroNode.items.isEmpty()) {
        macroInfos.add(ChildMessage(childName, macroNode.items))
    }
    for (child in macroNode.children) {
        TraverseMacroNode(child, childName, macroInfos)
    }
}
