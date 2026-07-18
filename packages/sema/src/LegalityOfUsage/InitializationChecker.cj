package cjcj::sema.LegalityOfUsage

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::option.GlobalOptions as OptionGlobalOptions
import cjcj::sema.*
import cjcj::sema.DiagCJMPCannotAssignToImmutableCommonInCtor
import cjcj::utils.JAVA_REF_FIELD_NAME

public enum InitializationIssueKind {
    | USED_BEFORE_INITIALIZATION
    | CAPTURE_BEFORE_INITIALIZATION
    | ILLEGAL_MEMBER_USE
    | ILLEGAL_SUPER_MEMBER_USE
    | UNINITIALIZED_FIELD
}

private func InitializationIssueKindIndex(kind: InitializationIssueKind): Int64 {
    return match (kind) {
        case InitializationIssueKind.USED_BEFORE_INITIALIZATION => 0
        case InitializationIssueKind.CAPTURE_BEFORE_INITIALIZATION => 1
        case InitializationIssueKind.ILLEGAL_MEMBER_USE => 2
        case InitializationIssueKind.ILLEGAL_SUPER_MEMBER_USE => 3
        case InitializationIssueKind.UNINITIALIZED_FIELD => 4
    }
}

extend InitializationIssueKind <: Equatable<InitializationIssueKind> {
    public operator func ==(right: InitializationIssueKind): Bool {
        return InitializationIssueKindIndex(this) == InitializationIssueKindIndex(right)
    }

    public operator func !=(right: InitializationIssueKind): Bool {
        return !(this == right)
    }
}

public class InitializationIssue {
    public var kind: InitializationIssueKind
    public var node: Node
    public var target: Option<Decl>
    public var message: String

    public init(kind: InitializationIssueKind, node: Node, target!: Option<Decl> = None, message!: String = "") {
        this.kind = kind
        this.node = node
        this.target = target
        this.message = message
    }
}

private class CollectDeclsInfo {
    public let nonFuncDecls: ArrayList<Decl> = ArrayList<Decl>()
    public let funcDecls: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public let staticFuncDecls: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public let initFuncDecls: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public let annotations: ArrayList<ArrayLit> = ArrayList<ArrayLit>()

    public init() {}
}

private class InitBoolBox {
    public var value: Bool

    public init(value: Bool) {
        this.value = value
    }
}

private class ScopedDecls {
    public var scopeGateName: String
    public let decls: ArrayList<Decl> = ArrayList<Decl>()

    public init(scopeGateName: String) {
        this.scopeGateName = scopeGateName
    }
}

private class TerminatedScopeInfo {
    public var scopeGateName: String
    public let variablesBeforeTerminator: ArrayList<Decl> = ArrayList<Decl>()
    public let initVarsAfterTerminator: ArrayList<Decl> = ArrayList<Decl>()
    public var terminationKind: ASTKind

    public init(scopeGateName: String, terminationKind: ASTKind) {
        this.scopeGateName = scopeGateName
        this.terminationKind = terminationKind
    }
}

private class CtorUninitVars {
    public var ctor: FuncDecl
    public let decls: ArrayList<Decl> = ArrayList<Decl>()

    public init(ctor: FuncDecl) {
        this.ctor = ctor
    }
}

private func ContainsInitDecl(values: ArrayList<Decl>, decl: Decl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func AddUniqueDecl(values: ArrayList<Decl>, decl: Decl): Unit {
    if (!ContainsInitDecl(values, decl)) {
        values.add(decl)
    }
}

private func SameFuncBody(left: FuncBody, right: FuncBody): Bool {
    if (let Some(leftDecl) <- left.funcDecl) {
        if (let Some(rightDecl) <- right.funcDecl) {
            return SameDecl(leftDecl, rightDecl)
        }
    }
    if (!left.scopeName.isEmpty() || !right.scopeName.isEmpty()) {
        return left.scopeName == right.scopeName && left.astKind == right.astKind
    }
    return left.begin == right.begin && left.end == right.end && left.astKind == right.astKind
}

private func FuncBodyScopeName(body: FuncBody): String {
    if (!body.scopeName.isEmpty()) {
        return body.scopeName
    }
    if (let Some(funcDecl) <- body.funcDecl) {
        return funcDecl.scopeName
    }
    return ""
}

// Return the scope path of a scope-gate name, i.e. the portion before the gate marker
// (CHILD_SCOPE_SEPARATOR). For a func body scope-gate name like "a0a_a" this yields "a0a",
// the scope under which the body's locals (and any nested function declarations) live.
private func ScopePathBeforeGate(scopeName: String): String {
    var idx = scopeName.size - 1
    while (idx >= 0) {
        if (scopeName[idx..(idx + 1)] == CHILD_SCOPE_SEPARATOR) {
            return scopeName[0..idx]
        }
        idx--
    }
    return scopeName
}

private func ScopeContains(parent: String, child: String): Bool {
    if (parent.isEmpty() || child.isEmpty()) {
        return false
    }
    return child == parent || child.startsWith(parent + SCOPE_NAME_SPLIT) ||
        child.startsWith(parent + CHILD_SCOPE_SEPARATOR)
}

private func IsRelatedTypeDecl(curComposite: Decl, outerDeclOfTarget: Decl): Bool {
    if (let Some(classDecl) <- (curComposite as ClassDecl)) {
        var current: Option<ClassDecl> = classDecl
        while (let Some(currentClass) <- current) {
            if (SameDecl(currentClass, outerDeclOfTarget)) {
                return true
            }
            current = currentClass.GetSuperClassDecl()
        }
        return false
    }
    return SameDecl(curComposite, outerDeclOfTarget)
}

private func CopyDeclList(dst: ArrayList<Decl>, src: ArrayList<Decl>): Unit {
    dst.clear()
    for (decl in src) {
        AddUniqueDecl(dst, decl)
    }
}

private func RemoveDecls(values: ArrayList<Decl>, toRemove: ArrayList<Decl>): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (ContainsInitDecl(toRemove, values[idx])) {
            values.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func RetainDeclIntersection(values: ArrayList<Decl>, other: ArrayList<Decl>): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (ContainsInitDecl(other, values[idx])) {
            idx++
        } else {
            values.remove(at: idx)
        }
    }
}

private func ContainsPatternVar(values: ArrayList<VarDecl>, decl: Decl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func IsInitializedButUnreachable(vd: VarDecl): Bool {
    if (!vd.TestAttr(Attribute.INITIALIZED)) {
        return false
    }
    if (let Some(initExpr) <- vd.initializer) {
        return initExpr.TestAttr(Attribute.UNREACHABLE)
    }
    return false
}

private func IsAllMembersInitialized(node: Node): Bool {
    if (let Some(decl) <- (node as Decl)) {
        if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.STRUCT_DECL) {
            for (member in decl.GetMemberDeclPtrs()) {
                if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(Attribute.INITIALIZED)) {
                    return false
                }
            }
        }
    }
    return true
}

private func NotAssignableVariable(vd: VarDecl, inInitFunction: Bool): Bool {
    if (vd.isVar) {
        return false
    }
    if (vd.TestAnyAttr(Attribute.GLOBAL, Attribute.INITIALIZED, Attribute.ENUM_CONSTRUCTOR)) {
        return true
    }
    if (vd.TestAnyAttr(Attribute.IN_STRUCT, Attribute.IN_CLASSLIKE) && !inInitFunction) {
        return true
    }
    return vd.TestAnyAttr(Attribute.IN_STRUCT, Attribute.IN_CLASSLIKE) && inInitFunction &&
        vd.TestAttr(Attribute.COMMON)
}

private func CanSkipInitCheck(node: Node): Bool {
    return node.TestAnyAttr(Attribute.IMPORTED, Attribute.FOREIGN, Attribute.ENUM_CONSTRUCTOR)
}

private func IsAssignLetDefinedOuterLoop(ctx: ASTContext, vd: VarDecl, curExpr: Expr): Bool {
    if (vd.isVar) {
        return false
    }
    if (let Some(assign) <- (curExpr as AssignExpr)) {
        if (!vd.TestAttr(Attribute.INITIALIZED)) {
            if (assign.isCompound) {
                return false
            }
            let occurredInRight = InitBoolBox(false)
            let walker = Walker(assign.rightExpr.getOrThrow(), visitPre: { node: Node =>
                if (let Some(target) <- node.GetTarget()) {
                    if (target == vd) {
                        occurredInRight.value = true
                        return VisitAction.STOP_NOW
                    }
                }
                VisitAction.WALK_CHILDREN
            })
            walker.Walk()
            if (occurredInRight.value) {
                return false
            }
        }
    }
    if (let Some(outerLoop) <- GetRefLoopSymbol(ctx, curExpr)) {
        let loopNode = outerLoop.node.getOrThrow()
        if (loopNode.begin > vd.begin) {
            return true
        }
    }
    return false
}

private func IsOtherInit(call: ConstructorCall): Bool {
    return match (call) {
        case ConstructorCall.OTHER_INIT => true
        case _ => false
    }
}

private func IsControlTransferNode(node: Node): Bool {
    return node.astKind == ASTKind.RETURN_EXPR || node.astKind == ASTKind.JUMP_EXPR ||
        node.astKind == ASTKind.THROW_EXPR
}

private func CurrentScopeGate(scopeName: String): String {
    let scopeGate = GetScopeGateName(scopeName)
    if (!scopeGate.isEmpty()) {
        return scopeGate
    }
    if (scopeName.contains(CHILD_SCOPE_SEPARATOR)) {
        return scopeName
    }
    return ""
}

private func FindScopedDecls(entries: ArrayList<ScopedDecls>, scopeGateName: String): Option<ScopedDecls> {
    for (entry in entries) {
        if (entry.scopeGateName == scopeGateName) {
            return entry
        }
    }
    return None
}

private func EnsureScopedDecls(entries: ArrayList<ScopedDecls>, scopeGateName: String): ScopedDecls {
    if (let Some(entry) <- FindScopedDecls(entries, scopeGateName)) {
        return entry
    }
    let entry = ScopedDecls(scopeGateName)
    entries.add(entry)
    return entry
}

private func RemoveScopedDecls(entries: ArrayList<ScopedDecls>, scopeGateName: String): Unit {
    var idx: Int64 = 0
    while (idx < entries.size) {
        if (entries[idx].scopeGateName == scopeGateName) {
            entries.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func FindTerminatedScope(entries: ArrayList<TerminatedScopeInfo>,
    scopeGateName: String): Option<TerminatedScopeInfo> {
    for (entry in entries) {
        if (entry.scopeGateName == scopeGateName) {
            return entry
        }
    }
    return None
}

private func AddVisibleContextDecls(contextVariables: ArrayList<ScopedDecls>, scopeGateName: String,
    out: ArrayList<Decl>): Unit {
    var currentGate = scopeGateName
    while (!currentGate.isEmpty()) {
        if (let Some(entry) <- FindScopedDecls(contextVariables, currentGate)) {
            for (decl in entry.decls) {
                AddUniqueDecl(out, decl)
            }
        }
        currentGate = GetScopeGateName(currentGate)
    }
}

private func UpdateContextVariables(contextVariables: ArrayList<ScopedDecls>, decl: Decl): Unit {
    if (decl.TestAnyAttr(Attribute.GLOBAL, Attribute.STATIC)) {
        return
    }
    let scopeGateName = CurrentScopeGate(decl.scopeName)
    if (scopeGateName.isEmpty()) {
        return
    }
    let entry = EnsureScopedDecls(contextVariables, scopeGateName)
    if (let Some(varDecl) <- (decl as VarDecl)) {
        AddUniqueDecl(entry.decls, varDecl)
    } else if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            let vars = ArrayList<VarDecl>()
            CollectPatternVars(pattern, vars)
            for (varDecl in vars) {
                AddUniqueDecl(entry.decls, varDecl)
            }
        }
    }
}

private func FindCtorUninitVars(entries: ArrayList<CtorUninitVars>, ctor: FuncDecl): Option<CtorUninitVars> {
    for (entry in entries) {
        if (SameDecl(entry.ctor, ctor)) {
            return entry
        }
    }
    return None
}

private func RemoveCtorUninitVars(entries: ArrayList<CtorUninitVars>, ctor: FuncDecl): Unit {
    var idx: Int64 = 0
    while (idx < entries.size) {
        if (SameDecl(entries[idx].ctor, ctor)) {
            entries.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func HasForeignOrJavaParent(body: FuncBody): Bool {
    if (let Some(parentClassLike) <- body.parentClassLike) {
        if (parentClassLike.TestAttr(Attribute.FOREIGN)) {
            return true
        }
        if (let Some(_) <- HasJavaAttr(parentClassLike)) {
            return true
        }
    }
    return false
}

private func MayBeStructTy(target: VarDecl): Bool {
    if (!Ty.IsTyCorrect(target.GetTy())) {
        return false
    }
    if (let Some(ty) <- target.GetTy()) {
        if (ty.IsStruct()) {
            return true
        }
        if (let Some(genericTy) <- (ty as GenericsTy)) {
            for (upperBound in genericTy.upperBounds) {
                if (upperBound.IsInterface()) {
                    return true
                }
            }
        }
    }
    return false
}

private func IsSameFile(left: Node, right: Node): Bool {
    if (let Some(leftFile) <- left.curFile) {
        if (let Some(rightFile) <- right.curFile) {
            return leftFile.fileHash == rightFile.fileHash
        }
    }
    return false
}

private func FromCommonPart(decl: Decl): Bool {
    if (decl.TestAttr(Attribute.FROM_COMMON_PART)) {
        return true
    }
    if (let Some(file) <- decl.curFile) {
        return file.TestAttr(Attribute.FROM_COMMON_PART)
    }
    return false
}

private func GetUnInitsInExpr(node: Node, unInitedNodes: ArrayList<Decl>): Unit {
    let walker = Walker(node, visitPre: { current: Node =>
        if (let Some(expr) <- (current as Expr)) {
            if (expr.IsReferenceExpr()) {
                if (let Some(target) <- expr.GetTarget()) {
                    if (!target.TestAttr(Attribute.INITIALIZED)) {
                        AddUniqueDecl(unInitedNodes, target)
                    }
                }
            }
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
}

private func CollectReferencedDeclsBeforeJumpExpr(block: Block): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let walker = Walker(block, visitPre: { node: Node =>
        if (let Some(_) <- (node as FuncBody)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(_) <- (node as WhileExpr)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(_) <- (node as DoWhileExpr)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(_) <- (node as ForInExpr)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(_) <- (node as JumpExpr)) {
            return VisitAction.STOP_NOW
        }
        if (let Some(expr) <- (node as Expr)) {
            if (expr.IsReferenceExpr()) {
                if (let Some(target) <- expr.GetTarget()) {
                    AddUniqueDecl(result, target)
                }
            }
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    return result
}

private func CollectPatternVarsInCondition(expr: Expr, out: ArrayList<VarDecl>): Unit {
    if (let Some(letPattern) <- (expr as LetPatternDestructor)) {
        for (pattern in letPattern.patterns) {
            CollectPatternVars(pattern, out)
        }
        return
    }
    if (let Some(binary) <- (expr as BinaryExpr)) {
        if (IsCondition(expr) && binary.op == TokenKind.AND) {
            if (let Some(left) <- binary.leftExpr) {
                CollectPatternVarsInCondition(left, out)
            }
            if (let Some(right) <- binary.rightExpr) {
                CollectPatternVarsInCondition(right, out)
            }
        }
        return
    }
    if (let Some(paren) <- (expr as ParenExpr)) {
        if (let Some(child) <- paren.expr) {
            CollectPatternVarsInCondition(child, out)
        }
    }
}

private func CollectPatternVars(pattern: Pattern, out: ArrayList<VarDecl>): Unit {
    if (let Some(varPattern) <- (pattern as VarPattern)) {
        if (let Some(varDecl) <- varPattern.varDecl) {
            out.add(varDecl)
        }
        return
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        for (child in tuplePattern.patterns) {
            CollectPatternVars(child, out)
        }
    } else if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        for (child in enumPattern.patterns) {
            CollectPatternVars(child, out)
        }
    } else if (let Some(typePattern) <- (pattern as TypePattern)) {
        if (let Some(child) <- typePattern.pattern) {
            CollectPatternVars(child, out)
        }
        if (let Some(desugared) <- typePattern.desugarVarPattern) {
            CollectPatternVars(desugared, out)
        }
    } else if (let Some(varOrEnumPattern) <- (pattern as VarOrEnumPattern)) {
        if (let Some(child) <- varOrEnumPattern.pattern) {
            CollectPatternVars(child, out)
        }
    } else if (let Some(exceptTypePattern) <- (pattern as ExceptTypePattern)) {
        if (let Some(child) <- exceptTypePattern.pattern) {
            CollectPatternVars(child, out)
        }
    } else if (let Some(commandTypePattern) <- (pattern as CommandTypePattern)) {
        if (let Some(child) <- commandTypePattern.pattern) {
            CollectPatternVars(child, out)
        }
    }
}

private func CollectConditionalInitializedDecls(node: Node, uninitsDecls: ArrayList<Decl>,
    patternVars: ArrayList<VarDecl>): ArrayList<Decl> {
    let conditionalInitialized = ArrayList<Decl>()
    if (uninitsDecls.isEmpty()) {
        return conditionalInitialized
    }
    let walker = Walker(node, visitPre: { current: Node =>
        if (let Some(expr) <- (current as Expr)) {
            if (expr.IsReferenceExpr()) {
                if (let Some(target) <- expr.GetTarget()) {
                    if (target.TestAttr(Attribute.INITIALIZED) && ContainsInitDecl(uninitsDecls, target)) {
                        AddUniqueDecl(conditionalInitialized, target)
                        if (!ContainsPatternVar(patternVars, target)) {
                            target.DisableAttr(Attribute.INITIALIZED)
                        }
                    }
                }
            }
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    return conditionalInitialized
}

private func MetControlTransferExpr(node: Node): Bool {
    if (node.astKind == ASTKind.RETURN_EXPR || node.astKind == ASTKind.JUMP_EXPR ||
        node.astKind == ASTKind.THROW_EXPR) {
        return true
    }
    if (let Some(block) <- (node as Block)) {
        for (child in block.body) {
            if (MetControlTransferExpr(child)) {
                return true
            }
        }
        return false
    }
    if (let Some(assign) <- (node as AssignExpr)) {
        if (let Some(right) <- assign.rightExpr) {
            return MetControlTransferExpr(right)
        }
        return false
    }
    if (let Some(doWhile) <- (node as DoWhileExpr)) {
        if (let Some(body) <- doWhile.body) {
            return MetControlTransferExpr(body)
        }
    }
    return false
}

private func IsInitialized(member: MemberAccess): Bool {
    let initialized = InitBoolBox(false)
    let walker = Walker(member, visitPre: { node: Node =>
        if (let Some(target) <- node.GetTarget()) {
            if (target.TestAttr(Attribute.INITIALIZED)) {
                initialized.value = true
                return VisitAction.STOP_NOW
            }
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    return initialized.value
}

public class InitializationChecker {
    private let ctx: ASTContext
    private let diag: BasicDiagnosticEngine
    private let opts: OptionGlobalOptions
    private let issues: ArrayList<InitializationIssue> = ArrayList<InitializationIssue>()
    private var currentInitializingVarDependencies: Option<ArrayList<Decl>> = None
    private let currentFuncBodies: ArrayList<FuncBody> = ArrayList<FuncBody>()
    private let contextVariables: ArrayList<ScopedDecls> = ArrayList<ScopedDecls>()
    private let terminatedScopes: ArrayList<TerminatedScopeInfo> = ArrayList<TerminatedScopeInfo>()
    private let ctorUninitVars: ArrayList<CtorUninitVars> = ArrayList<CtorUninitVars>()
    private var optionalCtxDepth: Int64 = 0
    private var tryDepth: Int64 = 0

    public init(ctx: ASTContext, diag: BasicDiagnosticEngine, opts!: OptionGlobalOptions = OptionGlobalOptions()) {
        this.ctx = ctx
        this.diag = diag
        this.opts = opts
    }

    public func Check(root: Node): ArrayList<InitializationIssue> {
        CheckInitialization(root)
        return issues
    }

    private func AddIssue(kind: InitializationIssueKind, node: Node, target!: Option<Decl> = None,
        message!: String = ""): Unit {
        issues.add(InitializationIssue(kind, node, target: target, message: message))
    }

    private func ClearScopeStatus(scopeName: String): Unit {
        let scopeGateName = CurrentScopeGate(scopeName)
        if (scopeGateName.isEmpty()) {
            return
        }
        RemoveScopedDecls(contextVariables, scopeGateName)
        if (let Some(terminated) <- FindTerminatedScope(terminatedScopes, scopeGateName)) {
            terminated.variablesBeforeTerminator.clear()
            terminated.initVarsAfterTerminator.clear()
        }
    }

    private func CheckExprOption(expr: Option<Expr>): Bool {
        if (let Some(value) <- expr) {
            return CheckInitInExpr(value)
        }
        return true
    }

    private func CheckBlockOption(block: Option<Block>): Bool {
        if (let Some(value) <- block) {
            CheckInitialization(value)
        }
        return true
    }

    private func CheckPatternOption(pattern: Option<Pattern>): Bool {
        if (let Some(value) <- pattern) {
            return CheckInitInPattern(value)
        }
        return true
    }

    private func CheckInitialization(node: Node): Unit {
        if (node.TestAttr(Attribute.HAS_BROKEN) || node.TestAttr(Attribute.IMPORTED)) {
            return
        }
        if (node.TestAttr(Attribute.GLOBAL) && node.TestAttr(Attribute.INITIALIZED)) {
            return
        }
        if (node.TestAttr(Attribute.INITIALIZATION_CHECKED) && node.astKind != ASTKind.PACKAGE &&
            node.astKind != ASTKind.FILE && node.astKind != ASTKind.BLOCK) {
            return
        }
        node.EnableAttr(Attribute.INITIALIZATION_CHECKED)
        if (let Some(decl) <- (node as Decl)) {
            UpdateContextVariables(contextVariables, decl)
            if (FromCommonPart(decl)) {
                if (node.scopeName.contains(CHILD_SCOPE_SEPARATOR)) {
                    ClearScopeStatus(node.scopeName)
                }
                return
            }
        }
        match (node.astKind) {
            case ASTKind.PACKAGE =>
                if (let Some(pkg) <- (node as Package)) {
                    for (file in pkg.files) {
                        CheckInitialization(file)
                    }
                }
            case ASTKind.FILE =>
                if (let Some(file) <- (node as File)) {
                    for (decl in file.decls) {
                        CheckInitialization(decl)
                    }
                }
            case ASTKind.BLOCK =>
                if (let Some(block) <- (node as Block)) {
                    for (child in block.body) {
                        CheckInitialization(child)
                    }
                }
            case ASTKind.FUNC_PARAM =>
                if (let Some(param) <- (node as FuncParam)) {
                    param.EnableAttr(Attribute.INITIALIZED)
                    CheckExprOption(param.assignment)
                }
            case ASTKind.VAR_DECL =>
                if (let Some(varDecl) <- (node as VarDecl)) {
                    CheckInitInVarDecl(varDecl)
                }
            case ASTKind.VAR_WITH_PATTERN_DECL =>
                if (let Some(vpd) <- (node as VarWithPatternDecl)) {
                    CheckInitInVarWithPatternDecl(vpd)
                }
            case ASTKind.FUNC_PARAM_LIST =>
                if (let Some(paramList) <- (node as FuncParamList)) {
                    for (param in paramList.params) {
                        CheckInitialization(param)
                    }
                }
            case ASTKind.MAIN_DECL =>
                // Faithful to the AST Walker's MAIN_DECL traversal (Walker.cpp:154-166):
                // descend into the desugared 'main' function when present, otherwise its
                // raw funcBody. The C++ InitializationChecker relies on the same
                // WALK_CHILDREN behaviour to analyse the body of 'main'.
                if (let Some(mainDecl) <- (node as MainDecl)) {
                    if (let Some(desugarDecl) <- mainDecl.desugarDecl) {
                        CheckInitialization(desugarDecl)
                    } else if (let Some(body) <- mainDecl.funcBody) {
                        CheckInitInFuncBody(body)
                    }
                }
            case ASTKind.MACRO_DECL =>
                if (let Some(macroDecl) <- (node as MacroDecl)) {
                    if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
                        CheckInitialization(desugarDecl)
                    } else if (let Some(body) <- macroDecl.funcBody) {
                        CheckInitInFuncBody(body)
                    }
                }
            case ASTKind.FUNC_DECL =>
                if (let Some(funcDecl) <- (node as FuncDecl)) {
                    if (funcDecl.TestAttr(Attribute.HAS_INITIAL)) {
                        if (let Some(_) <- funcDecl.ownerFunc) {
                            return
                        }
                    }
                    funcDecl.EnableAttr(Attribute.INITIALIZED)
                    if (let Some(body) <- funcDecl.funcBody) {
                        CheckInitInFuncBody(body)
                    }
                    if (let Some(array) <- funcDecl.annotationsArray) {
                        CheckInitInExpr(array)
                    }
                }
            case ASTKind.EXTEND_DECL =>
                if (let Some(extendDecl) <- (node as ExtendDecl)) {
                    CheckInitInExtendDecl(extendDecl)
                    extendDecl.EnableAttr(Attribute.INITIALIZED)
                }
            case ASTKind.INTERFACE_DECL =>
                if (let Some(interfaceDecl) <- (node as InterfaceDecl)) {
                    for (typeNode in interfaceDecl.inheritedTypes) {
                        if (let Some(target) <- typeNode.GetTarget()) {
                            CheckInitialization(target)
                        }
                    }
                    CheckInitInTypeDecl(interfaceDecl)
                    interfaceDecl.EnableAttr(Attribute.INITIALIZED)
                }
            case ASTKind.CLASS_DECL =>
                if (let Some(classDecl) <- (node as ClassDecl)) {
                    CheckInitInClassDecl(classDecl)
                    CheckNonCommonVariablesInitInCommonDecl(classDecl)
                    classDecl.EnableAttr(Attribute.INITIALIZED)
                }
            case ASTKind.ENUM_DECL =>
                if (let Some(enumDecl) <- (node as EnumDecl)) {
                    for (typeNode in enumDecl.inheritedTypes) {
                        if (let Some(target) <- typeNode.GetTarget()) {
                            CheckInitialization(target)
                        }
                    }
                    for (constructor in enumDecl.constructors) {
                        constructor.EnableAttr(Attribute.INITIALIZED)
                    }
                    CheckInitInTypeDecl(enumDecl)
                    enumDecl.EnableAttr(Attribute.INITIALIZED)
                }
            case ASTKind.STRUCT_DECL =>
                if (let Some(structDecl) <- (node as StructDecl)) {
                    CheckStaticInitForTypeDecl(structDecl)
                    CheckInitInTypeDecl(structDecl)
                    CheckNonCommonVariablesInitInCommonDecl(structDecl)
                    structDecl.EnableAttr(Attribute.INITIALIZED)
                }
            case _ =>
                if (let Some(expr) <- (node as Expr)) {
                    if (let Some(desugar) <- expr.desugarExpr) {
                        CheckInitInExpr(desugar)
                    } else {
                        CheckInitInExpr(expr)
                    }
                }
        }
        if (node.scopeName.contains(CHILD_SCOPE_SEPARATOR)) {
            ClearScopeStatus(node.scopeName)
        }
    }

    private func CheckStaticInitForTypeDecl(decl: InheritableDecl): Unit {
        var staticInit: Option<FuncDecl> = None
        let staticMembers = ArrayList<Decl>()
        for (member in decl.GetMemberDeclPtrs()) {
            if (!member.TestAttr(Attribute.STATIC)) {
                continue
            }
            if (member.astKind == ASTKind.VAR_DECL || member.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
                CheckInitialization(member)
                staticMembers.add(member)
            } else if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (IsStaticInitializer(funcDecl)) {
                    staticInit = funcDecl
                }
            }
        }
        if (let Some(initFunc) <- staticInit) {
            CheckInitialization(initFunc)
            if (let None <- initFunc.funcBody) {
                return
            }
            let body = initFunc.funcBody.getOrThrow()
            if (let Some(terminated) <- FindTerminatedScope(terminatedScopes, body.scopeName)) {
                if (terminated.terminationKind == ASTKind.THROW_EXPR) {
                    return
                }
            }
        }
        for (member in staticMembers) {
            if (member.TestAnyAttr(Attribute.INITIALIZED, Attribute.TOOL_ADD, Attribute.COMMON) || opts.compileCjd) {
                continue
            }
            let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_type_uninitialized_static_field,
                member, arguments: [member.identifier.Val()])
            let note = "you may add an initializer inline or "
            if (let Some(initFunc) <- staticInit) {
                builder.AddNote(note + "initialize the variable in the 'static init'")
                AddNote(builder, initFunc, MakeRange(initFunc.identifier.Begin(), initFunc.identifier.End()),
                    "static init defined here")
            } else {
                builder.AddNote(note + "define a 'static init' to perform initialization")
            }
            builder.Emit()
        }
    }

    private func CheckInitInClassDecl(classDecl: ClassDecl): Unit {
        let superClassNonFuncDecls = ArrayList<Decl>()
        let superClasses = HashSet<Decl>()
        for (typeNode in classDecl.inheritedTypes) {
            if (let Some(target) <- typeNode.GetTarget()) {
                if (let Some(superClass) <- (target as ClassDecl)) {
                    if (IsSameFile(classDecl, superClass)) {
                        CheckStaticInitForTypeDecl(classDecl)
                    }
                    CheckInitialization(superClass)
                    GetNonFuncDeclsInSuperClass(superClass, superClassNonFuncDecls, superClasses)
                } else if (let Some(superInterface) <- (target as InterfaceDecl)) {
                    CheckInitialization(superInterface)
                }
            }
        }
        CheckStaticInitForTypeDecl(classDecl)
        CheckInitInTypeDecl(classDecl, superClassNonFuncDecls)
    }

    private func CheckInitInExtendDecl(extendDecl: ExtendDecl): Unit {
        let temporarilyInitialized = ArrayList<Decl>()
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (let Some(typeDecl) <- Ty.GetDeclPtrOfTy(extendedType.GetTy())) {
                if (typeDecl.IsStructOrClassDecl()) {
                    for (member in typeDecl.GetMemberDecls()) {
                        if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(Attribute.INITIALIZED)) {
                            temporarilyInitialized.add(member)
                            member.EnableAttr(Attribute.INITIALIZED)
                        }
                    }
                }
            }
        }
        CheckInitInTypeDecl(extendDecl)
        for (member in temporarilyInitialized) {
            member.DisableAttr(Attribute.INITIALIZED)
        }
    }

    private func CheckInitInFuncBody(body: FuncBody): Unit {
        currentFuncBodies.add(body)
        if (let Some(generic) <- body.generic) {
            for (typeParam in generic.typeParameters) {
                CheckInitialization(typeParam)
            }
            for (constraint in generic.genericConstraints) {
                CheckInitialization(constraint)
            }
        }
        for (paramList in body.paramLists) {
            CheckInitialization(paramList)
        }
        // Faithful to C++ InitializationChecker::CheckInitInFuncBody (InitializationChecker.cpp:677-678):
        //   needCheckInLoop = !fb.funcDecl ||
        //       (fb.funcDecl->symbol && GetCurSymbolByKindCached(FUNC_LIKE, fb.funcDecl->scopeName))
        // i.e. loop-style unsetting of conditionally-initialized references is performed only when the
        // function body belongs to a named function that is *declared inside another function* (a local
        // or nested function/lambda). Top-level functions, class/struct members and constructors are
        // analysed with a plain CheckInitialization, so members assigned in a constructor body keep their
        // INITIALIZED state instead of being wrongly unset (which previously produced spurious
        // sema_class_uninitialized_field errors). The enclosing FUNC_LIKE symbol is recovered structurally
        // from the active func-body stack, which only contains an ancestor body when the function is nested.
        var needCheckInLoop = true
        if (let Some(funcDecl) <- body.funcDecl) {
            let hasSymbol = match (funcDecl.symbol) {
                case Some(_) => true
                case None => false
            }
            needCheckInLoop = hasSymbol && IsDeclaredInsideEnclosingFuncBody(funcDecl)
        }
        if (needCheckInLoop) {
            CheckInitInLoop(body.body)
        } else {
            CheckBlockOption(body.body)
        }
        currentFuncBodies.remove(at: currentFuncBodies.size - 1)
    }

    private func CheckInitInVarWithPatternDecl(vpd: VarWithPatternDecl): Unit {
        if (let Some(initExpr) <- vpd.initializer) {
            CheckInitInExpr(initExpr)
            vpd.EnableAttr(Attribute.INITIALIZED)
        }
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            CheckInitInPattern(pattern)
            let vars = ArrayList<VarDecl>()
            CollectPatternVars(pattern, vars)
            for (varDecl in vars) {
                if (let Some(_) <- vpd.initializer) {
                    varDecl.EnableAttr(Attribute.INITIALIZED)
                } else {
                    varDecl.DisableAttr(Attribute.INITIALIZED)
                }
                varDecl.EnableAttr(Attribute.INITIALIZATION_CHECKED)
            }
        }
        if (let Some(array) <- vpd.annotationsArray) {
            CheckInitInExpr(array)
        }
    }

    private func CheckInitInVarDecl(vd: VarDecl): Unit {
        if (let Some(initExpr) <- vd.initializer) {
            let collectingDependencies = IsInstanceMember(vd)
            if (collectingDependencies) {
                currentInitializingVarDependencies = ArrayList<Decl>()
            }
            CheckInitInExpr(initExpr)
            vd.EnableAttr(Attribute.INITIALIZED)
            if (let Some(deps) <- currentInitializingVarDependencies) {
                for (dep in deps) {
                    var foundDependency = false
                    for (existingDependency in vd.dependencies) {
                        if (let Some(existingDecl) <- existingDependency) {
                            if (SameDecl(existingDecl, dep)) {
                                foundDependency = true
                                break
                            }
                        }
                    }
                    if (!foundDependency) {
                        vd.dependencies.add(Some(dep))
                    }
                }
                currentInitializingVarDependencies = None
            }
        } else if (vd.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            vd.EnableAttr(Attribute.INITIALIZED)
        }
        if (let Some(array) <- vd.annotationsArray) {
            CheckInitInExpr(array)
        }
    }

    private func CheckLetFlag(assignOrInc: Expr, expr: Expr): Unit {
        let inInitFunction = IsUsedInInitFunction(expr)
        if (let Some(refExpr) <- (expr as RefExpr)) {
            if (let Some(target) <- refExpr.GetTarget()) {
                if (let Some(varDecl) <- (target as VarDecl)) {
                    if (NotAssignableVariable(varDecl, inInitFunction) ||
                        IsAssignLetDefinedOuterLoop(ctx, varDecl, assignOrInc)) {
                        if (varDecl.TestAttr(Attribute.COMMON) && inInitFunction) {
                            DiagCJMPCannotAssignToImmutableCommonInCtor(diag, assignOrInc, refExpr)
                        } else {
                            DiagCannotAssignToImmutable(diag, assignOrInc, refExpr)
                        }
                    }
                }
            }
        } else if (let Some(member) <- (expr as MemberAccess)) {
            CheckLetFlagInMemberAccess(assignOrInc, member, inInitFunction)
        } else if (let Some(subscript) <- (expr as SubscriptExpr)) {
            if (let Some(base) <- subscript.baseExpr) {
                if (let Some(baseTy) <- base.GetTy()) {
                    if (let Some(_) <- (baseTy as VArrayTy)) {
                        if (base.astKind == ASTKind.SUBSCRIPT_EXPR || base.astKind == ASTKind.CALL_EXPR) {
                            DiagCannotAssignToImmutable(diag, assignOrInc, base)
                        } else {
                            CheckLetFlag(assignOrInc, base)
                        }
                    }
                }
            }
        }
    }

    private func GetRealExpr(expr: Expr): Expr {
        if (let Some(desugar) <- expr.desugarExpr) {
            return desugar
        }
        return expr
    }

    private func IsStructBaseExpr(expr: Expr): Bool {
        if (let Some(baseTy) <- expr.GetTy()) {
            return baseTy.IsStruct()
        }
        return false
    }

    private func CheckLetFlagInMemberAccess(assignExpr: Expr, member: MemberAccess, inInitFunction: Bool): Unit {
        if (let None <- member.baseExpr) {
            return
        }
        let memberBase = member.baseExpr.getOrThrow()
        if (let Some(target) <- member.target) {
            if (let Some(varDecl) <- (target as VarDecl)) {
                if (NotAssignableVariable(varDecl, inInitFunction)) {
                    DiagCannotAssignToImmutable(diag, assignExpr, member)
                }
                let realBase = GetRealExpr(memberBase)
                let isStructBase = IsStructBaseExpr(realBase)
                if ((realBase.astKind == ASTKind.CALL_EXPR || realBase.astKind == ASTKind.SUBSCRIPT_EXPR) &&
                    isStructBase) {
                    DiagCannotAssignToImmutable(diag, assignExpr, realBase)
                }
                if (let Some(nameRef) <- (memberBase as NameReferenceExpr)) {
                    if (let Some(baseTarget) <- nameRef.GetTarget()) {
                        if (baseTarget.astKind == ASTKind.PROP_DECL && isStructBase) {
                            DiagCannotAssignToImmutable(diag, assignExpr, nameRef)
                        }
                    }
                }
            }
        }
        if (let Some(refExpr) <- (memberBase as RefExpr)) {
            if (let Some(target) <- refExpr.GetTarget()) {
                if (let Some(varDecl) <- (target as VarDecl)) {
                    if (!varDecl.isVar && MayBeStructTy(varDecl)) {
                        DiagCannotAssignToImmutable(diag, assignExpr, refExpr)
                    }
                }
            }
        } else if (let Some(baseMember) <- (memberBase as MemberAccess)) {
            if (let Some(target) <- baseMember.target) {
                if (let Some(varDecl) <- (target as VarDecl)) {
                    if (MayBeStructTy(varDecl)) {
                        if (!varDecl.isVar) {
                            DiagCannotAssignToImmutable(diag, assignExpr, member)
                        } else {
                            CheckLetFlag(assignExpr, memberBase)
                        }
                    }
                }
            }
        }
    }

    private func RecordInstanceVariableUsage(target: Decl): Unit {
        if (let Some(deps) <- currentInitializingVarDependencies) {
            if (let Some(varDecl) <- (target as VarDecl)) {
                if (IsInstanceMember(varDecl)) {
                    AddUniqueDecl(deps, varDecl)
                }
            }
        }
    }

    private func CurrentNamedFuncDecl(): Option<FuncDecl> {
        var idx = currentFuncBodies.size - 1
        while (idx >= 0) {
            if (let Some(funcDecl) <- currentFuncBodies[idx].funcDecl) {
                return funcDecl
            }
            idx--
        }
        return None
    }

    private func CurrentFuncBody(): Option<FuncBody> {
        if (currentFuncBodies.isEmpty()) {
            return None
        }
        return currentFuncBodies[currentFuncBodies.size - 1]
    }

    private func CurrentOutermostNamedFuncDecl(): Option<FuncDecl> {
        var idx: Int64 = 0
        while (idx < currentFuncBodies.size) {
            if (let Some(funcDecl) <- currentFuncBodies[idx].funcDecl) {
                return funcDecl
            }
            idx++
        }
        return None
    }

    private func CurrentFuncBodySameAs(funcDecl: FuncDecl): Bool {
        if (let Some(currentBody) <- CurrentFuncBody()) {
            if (let Some(currentDecl) <- currentBody.funcDecl) {
                return SameDecl(currentDecl, funcDecl)
            }
        }
        return false
    }

    private func CurrentNominalDeclForUsage(target: Decl): Option<Decl> {
        if (let Some(outerFunc) <- CurrentOutermostNamedFuncDecl()) {
            if (let Some(owner) <- outerFunc.outerDecl) {
                if (owner.IsNominalDecl()) {
                    return owner
                }
            }
        }
        if (let Some(currentBody) <- CurrentFuncBody()) {
            if (let Some(parentClassLike) <- currentBody.parentClassLike) {
                return parentClassLike
            }
            if (let Some(parentStruct) <- currentBody.parentStruct) {
                return parentStruct
            }
            if (let Some(parentEnum) <- currentBody.parentEnum) {
                return parentEnum
            }
        }
        if (let Some(targetOuter) <- target.outerDecl) {
            if (targetOuter.IsNominalDecl()) {
                return targetOuter
            }
        }
        return None
    }

    private func GetOwningFuncBodyForScope(scopeName: String): Option<FuncBody> {
        var idx = currentFuncBodies.size - 1
        while (idx >= 0) {
            let body = currentFuncBodies[idx]
            // A func body's scope name is a scope-gate name ("<path>_<gate>"); locals declared
            // directly inside the body carry the gate's *path* as their scope-name prefix. Compare
            // against that path (mirroring the upward FUNC_LIKE scope walk of
            // GetCurSymbolByKindCached in InitializationChecker.cpp:340) so a body containing the
            // target's declaration scope is recognised. The gate-suffixed name itself never prefixes
            // a child scope, so the previous comparison missed every local variable.
            let bodyScopePath = ScopePathBeforeGate(FuncBodyScopeName(body))
            if (!bodyScopePath.isEmpty() && ScopeContains(bodyScopePath, scopeName)) {
                return body
            }
            idx--
        }
        return None
    }

    // Structural reimplementation of `GetCurSymbolByKindCached(FUNC_LIKE, funcDecl.scopeName) != null`
    // (InitializationChecker.cpp:678): true iff `funcDecl` is declared inside the body scope of an
    // enclosing function. The InitializationChecker only reaches a nested/local function while walking
    // its enclosing function's body, so an ancestor body is present on `currentFuncBodies` exactly when
    // such an enclosing FUNC_LIKE symbol exists. The current body is the last stack element, so only the
    // ancestors are examined; each ancestor body's scope path (the portion before its scope-gate marker)
    // is matched against `funcDecl.scopeName`.
    private func IsDeclaredInsideEnclosingFuncBody(funcDecl: FuncDecl): Bool {
        var idx = currentFuncBodies.size - 2
        while (idx >= 0) {
            let ancestorScopePath = ScopePathBeforeGate(FuncBodyScopeName(currentFuncBodies[idx]))
            if (!ancestorScopePath.isEmpty() && ScopeContains(ancestorScopePath, funcDecl.scopeName)) {
                return true
            }
            idx--
        }
        return false
    }

    private func IsUsedInInitFunction(expr: Expr): Bool {
        if (let Some(decl) <- expr.GetTarget()) {
            if (decl.TestAnyAttr(Attribute.IN_STRUCT, Attribute.IN_CLASSLIKE)) {
                let symOfVdStruct = ScopeManager.GetCurSymbolByKind(SymbolKind.STRUCT, ctx, decl.scopeName)
                let symOfExprStruct = ScopeManager.GetCurSymbolByKind(SymbolKind.STRUCT, ctx, expr.scopeName)
                let symOfExprFunc = ScopeManager.GetOutMostSymbol(ctx, SymbolKind.FUNC, expr.scopeName)
                if ((let Some(vdStruct) <- symOfVdStruct) && (let Some(exprStruct) <- symOfExprStruct) &&
                    (let Some(exprFunc) <- symOfExprFunc)) {
                    let structOfExpr = (exprStruct.node.getOrThrow() as Decl).getOrThrow()
                    let structOfVd = (vdStruct.node.getOrThrow() as Decl).getOrThrow()
                    let currentFunc = exprFunc.node.getOrThrow()
                    let sameStaticStatus = currentFunc.TestAttr(Attribute.STATIC) ==
                        decl.TestAttr(Attribute.STATIC)
                    if (currentFunc.TestAttr(Attribute.CONSTRUCTOR) && sameStaticStatus &&
                        IsRelatedTypeDecl(structOfExpr, structOfVd)) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func IsMemberUseOutsideCtor(ctx: ASTContext, expr: Expr, decl: Decl): Bool {
        let isNotMemberVar = decl.outerDecl.isNone() || !decl.outerDecl.getOrThrow().IsNominalDecl() ||
            decl.astKind != ASTKind.VAR_DECL
        if (isNotMemberVar) {
            return false
        }
        if (let Some(outerMostSymbol) <- ScopeManager.GetOutMostSymbol(ctx, SymbolKind.FUNC, expr.scopeName)) {
            if (let Some(outerMostFunc) <- (outerMostSymbol.node.getOrThrow() as FuncDecl)) {
                return !outerMostFunc.TestAttr(Attribute.CONSTRUCTOR)
            }
        }
        return false
    }

    private func IsInDifferentFunction(usage: Expr, target: Decl): Bool {
        let usageSymbol = ScopeManager.GetCurSymbolByKind(SymbolKind.FUNC_LIKE, ctx, usage.scopeName)
        if (usageSymbol.isNone() || IsGlobalOrStaticVar(target)) {
            return false
        }
        let usageSym = usageSymbol.getOrThrow()
        if (let Some(declSym) <- ScopeManager.GetCurSymbolByKind(SymbolKind.FUNC_LIKE, ctx, target.scopeName)) {
            return !SameSymbol(usageSym, declSym)
        }
        if (let None <- target.outerDecl) {
            return true
        }
        let usageNode = usageSym.node.getOrThrow()
        if (let Some(usageDecl) <- (usageNode as FuncDecl)) {
            if (!usageDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                return target.outerDecl != usageDecl.outerDecl
            }
        }
        return usageNode.astKind == ASTKind.LAMBDA_EXPR
    }

    private func IsVarUsedBeforeDefinition(checkNode: Node, targetNode: Node): Bool {
        if (checkNode.begin == INVALID_POSITION || targetNode.begin == INVALID_POSITION) {
            return false
        }
        if (!IsSameFile(checkNode, targetNode)) {
            return false
        }
        if (targetNode.astKind != ASTKind.VAR_DECL) {
            return false
        }
        if (checkNode.IsStaticOrGlobal() && targetNode.IsStaticOrGlobal() && checkNode.begin < targetNode.begin) {
            return true
        }
        if (checkNode.scopeLevel == targetNode.scopeLevel && checkNode.begin < targetNode.begin) {
            return true
        }
        if (checkNode.scopeLevel > targetNode.scopeLevel && checkNode.begin < targetNode.begin) {
            if (let Some(varDecl) <- (targetNode as VarDecl)) {
                if (!IsInRelatedNominalDecl(varDecl) && ScopeContains(targetNode.scopeName, checkNode.scopeName)) {
                    return true
                }
            }
        }
        return false
    }

    private func IsInRelatedNominalDecl(varDecl: VarDecl): Bool {
        if (let Some(outer) <- varDecl.outerDecl) {
            return outer.IsNominalDecl()
        }
        return false
    }

    private func UpdateScopeStatus(node: Node): Unit {
        if (!IsControlTransferNode(node)) {
            return
        }
        let scopeGateName = CurrentScopeGate(node.scopeName)
        let mayNotGoOn = optionalCtxDepth != 0 && (node.astKind != ASTKind.THROW_EXPR || tryDepth == 0)
        if (scopeGateName.isEmpty() || mayNotGoOn) {
            return
        }
        if (let None <- FindTerminatedScope(terminatedScopes, scopeGateName)) {
            let terminated = TerminatedScopeInfo(scopeGateName, node.astKind)
            AddVisibleContextDecls(contextVariables, scopeGateName, terminated.variablesBeforeTerminator)
            terminatedScopes.add(terminated)
        }
        if (node.astKind != ASTKind.RETURN_EXPR) {
            return
        }
        let funcSymbol = match (ScopeManager.GetCurSymbolByKind(SymbolKind.FUNC_LIKE, ctx, node.scopeName)) {
            case Some(value) => value
            case None => return
        }
        let funcNode = match (funcSymbol.node) {
            case Some(value) => value
            case None => return
        }
        if (!IsInstanceConstructor(funcNode)) {
            return
        }
        let ctor = (funcNode as FuncDecl).getOrThrow()
        if (let Some(_) <- FindCtorUninitVars(ctorUninitVars, ctor)) {
            return
        }
        let ctorVars = CtorUninitVars(ctor)
        if (let Some(typeDecl) <- ctor.outerDecl) {
            for (member in typeDecl.GetMemberDecls()) {
                if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(Attribute.STATIC) &&
                    !member.TestAttr(Attribute.INITIALIZED)) {
                    AddUniqueDecl(ctorVars.decls, member)
                }
            }
        }
        ctorUninitVars.add(ctorVars)
    }

    private func UpdateInitializationStatus(assign: AssignExpr, decl: Decl): Unit {
        let scopeGateName = CurrentScopeGate(assign.scopeName)
        if (!scopeGateName.isEmpty()) {
            if (let Some(terminated) <- FindTerminatedScope(terminatedScopes, scopeGateName)) {
                if (ContainsInitDecl(terminated.variablesBeforeTerminator, decl)) {
                    if (terminated.terminationKind != ASTKind.THROW_EXPR || tryDepth != 0) {
                        AddUniqueDecl(terminated.initVarsAfterTerminator, decl)
                        return
                    }
                }
            }
        }
        decl.EnableAttr(Attribute.INITIALIZED)
    }

    private func HasInitVarsAfterTerminator(scopeName: String): Bool {
        let scopeGateName = CurrentScopeGate(scopeName)
        if (scopeGateName.isEmpty()) {
            return false
        }
        if (let Some(terminated) <- FindTerminatedScope(terminatedScopes, scopeGateName)) {
            return !terminated.initVarsAfterTerminator.isEmpty()
        }
        return false
    }

    private func IsOrderRelated(checkNode: Node, targetNode: Node, isClassLikeOrStruct: Bool): Bool {
        if (IsVarUsedBeforeDefinition(checkNode, targetNode)) {
            return true
        }
        return !(targetNode.scopeLevel == 0 || isClassLikeOrStruct)
    }

    private func AddIllegalMemberUse(expr: Expr, target: Decl): Unit {
        Diagnose(diag, expr, BasicDiagKind.sema_illegal_usage_of_member,
            args: [BasicDiagArgument(target.identifier.Val())]).Emit()
    }

    private func CheckIllegalMemberAccess(expr: Expr, target: Decl, targetStruct: Node): Bool {
        let curFuncBody = GetCurFuncBody(ctx, expr.scopeName)
        if (let None <- curFuncBody) {
            if (target.IsFuncOrProp()) {
                AddIllegalMemberUse(expr, target)
                return false
            }
            return true
        }
        let outerMostFunc: Option<FuncDecl> = if (let Some(symbol) <- ScopeManager.GetOutMostSymbol(
            ctx, SymbolKind.FUNC, expr.scopeName)) {
            symbol.node.getOrThrow() as FuncDecl
        } else {
            None
        }
        if (let None <- outerMostFunc) {
            AddIllegalMemberUse(expr, target)
            return false
        }
        let outerMostFuncDecl = outerMostFunc.getOrThrow()
        if (let None <- outerMostFuncDecl.outerDecl) {
            AddIllegalMemberUse(expr, target)
            return false
        }
        if (!outerMostFuncDecl.outerDecl.getOrThrow().IsNominalDecl()) {
            AddIllegalMemberUse(expr, target)
            return false
        }
        let leftVariable = expr.TestAttr(Attribute.LEFT_VALUE) && target.astKind == ASTKind.VAR_DECL
        if (IsAllMembersInitialized(targetStruct) || leftVariable) {
            return true
        }
        if (!IsInstanceConstructor(outerMostFuncDecl)) {
            return true
        }
        if (target.IsFuncOrProp()) {
            AddIllegalMemberUse(expr, target)
            return false
        }
        if (let None <- curFuncBody.getOrThrow().funcDecl) {
            AddIllegalMemberUse(expr, target)
            return false
        }
        if (curFuncBody.getOrThrow().funcDecl.getOrThrow() != outerMostFuncDecl) {
            AddIllegalMemberUse(expr, target)
            return false
        }
        return true
    }

    private func CheckIllegalRefExprAccess(refExpr: RefExpr, topLevelRef: Symbol, topLevelTarget: Symbol): Bool {
        let target = refExpr.GetTarget() ?? return true
        if (SameSymbol(topLevelRef, topLevelTarget)) {
            let targetStruct = topLevelRef.node ?? return true
            return CheckIllegalMemberAccess(refExpr, target, targetStruct)
        }
        let exprFunc = ScopeManager.GetOutMostSymbol(ctx, SymbolKind.FUNC_LIKE, refExpr.scopeName)
        if (target.astKind == ASTKind.VAR_DECL) {
            var hasInheritableOuter = false
            if ((let Some(funcSymbol) <- exprFunc) && funcSymbol.astKind == ASTKind.FUNC_DECL &&
                (let Some(funcNode) <- funcSymbol.node) && (let Some(funcDecl) <- (funcNode as FuncDecl)) &&
                (let Some(outerDecl) <- funcDecl.outerDecl) && (let Some(_) <- (outerDecl as InheritableDecl))) {
                hasInheritableOuter = true
            }
            if (!hasInheritableOuter) {
                AddIssue(InitializationIssueKind.ILLEGAL_SUPER_MEMBER_USE, refExpr, target: target,
                    message: refExpr.ref.identifier.Val())
                return false
            }
        } else if (target.IsFuncOrProp()) {
            let targetStruct = topLevelRef.node ?? return true
            if (!CheckIllegalMemberAccess(refExpr, target, targetStruct)) {
                return false
            }
        }
        return true
    }

    private func CheckInitInRefExpr(refExpr: RefExpr): Bool {
        if (let Some(target) <- GetRealTarget(refExpr.GetTarget())) {
            if (target.astKind == ASTKind.GENERIC_PARAM_DECL) {
                return true
            }
            let invalidThis = refExpr.isThis && refExpr.isAlone && target.IsStructOrClassDecl() &&
                !IsAllMembersInitialized(target)
            if (invalidThis) {
                Diagnose(diag, refExpr, BasicDiagKind.sema_illegal_usage_of_member,
                    args: [BasicDiagArgument("this")]).Emit()
                return false
            }
            RecordInstanceVariableUsage(target)
            if (CanSkipInitCheck(target) || !IsOrderRelated(refExpr, target, target.IsNominalDecl())) {
                return true
            }
            let topLevelTarget = ScopeManager.GetCurSymbolByKind(SymbolKind.TOPLEVEL, ctx, target.scopeName)
            if (let Some(targetSymbol) <- topLevelTarget) {
                if (let Some(targetNode) <- targetSymbol.node) {
                    if (CanSkipInitCheck(targetNode)) {
                        return true
                    }
                    let topLevelRef = ScopeManager.GetCurSymbolByKind(SymbolKind.TOPLEVEL, ctx, refExpr.scopeName)
                    if (let Some(refSymbol) <- topLevelRef) {
                        if (let Some(refNode) <- refSymbol.node) {
                            let referenceInside = refNode.IsStructOrClassDecl() && target.outerDecl.isSome() &&
                                target.outerDecl.getOrThrow().IsNominalDecl() &&
                                !target.TestAttr(Attribute.CONSTRUCTOR) && !target.TestAttr(Attribute.STATIC)
                            if (referenceInside && !CheckIllegalRefExprAccess(refExpr, refSymbol, targetSymbol)) {
                                return false
                            }
                            let inDifferentScope = !SameSymbol(refSymbol, targetSymbol) &&
                                !target.TestAttr(Attribute.STATIC)
                            if (inDifferentScope) {
                                return true
                            }
                        }
                    }
                }
            }
            if (let Some(_) <- (target as FuncParam)) {
                return true
            }
            if (target.IsFuncOrProp() || IsMemberUseOutsideCtor(ctx, refExpr, target)) {
                return true
            }
            if (refExpr.ShouldDiagnose(allowCompilerAdd: true) && target.TestAttr(Attribute.GLOBAL) &&
                IsSameFile(refExpr, target) && refExpr.begin < target.begin) {
                DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_undefined_variable,
                    refExpr, arguments: [refExpr.ref.identifier.Val()]).Emit()
                return false
            }
            if (!target.TestAttr(Attribute.INITIALIZED)) {
                if (HasInitVarsAfterTerminator(refExpr.scopeName)) {
                    return true
                }
                if (refExpr.ShouldDiagnose(allowCompilerAdd: true)) {
                    if (IsInDifferentFunction(refExpr, target)) {
                        DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_capture_before_initialization,
                            refExpr, arguments: [target.identifier.Val()]).Emit()
                        return false
                    }
                    if (!refExpr.TestAttr(Attribute.LEFT_VALUE)) {
                        Diagnose(diag, refExpr, BasicDiagKind.sema_used_before_initialization,
                            args: [BasicDiagArgument(refExpr.ref.identifier.Val())]).Emit()
                        return false
                    }
                }
                return false
            }
            return target.TestAttr(Attribute.INITIALIZED)
        }
        return true
    }

    private func CheckInitInMemberAccess(member: MemberAccess): Bool {
        var result = CheckExprOption(member.baseExpr)
        if (let Some(target) <- member.target) {
            RecordInstanceVariableUsage(target)
            if (!target.TestAttr(Attribute.STATIC)) {
                if (let Some(targetOuter) <- target.outerDecl) {
                    if (targetOuter.IsNominalDecl()) {
                        if (let Some(base) <- member.baseExpr) {
                            if (let Some(refExpr) <- (base as RefExpr)) {
                                if (refExpr.isThis) {
                                    if (let Some(baseTarget) <- refExpr.GetTarget()) {
                                        if (baseTarget.IsStructOrClassDecl()) {
                                            if (!CheckIllegalMemberAccess(member, target, baseTarget)) {
                                                return false
                                            }
                                        }
                                    }
                                }
                                if (refExpr.isSuper && target.IsFuncOrProp()) {
                                    if (let Some(currentNominal) <- CurrentNominalDeclForUsage(target)) {
                                        if (!CheckIllegalMemberAccess(member, target, currentNominal)) {
                                            return false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if (target.IsFuncOrProp() || IsMemberUseOutsideCtor(ctx, member, target)) {
                return result
            }
            if (target.TestAttr(Attribute.GLOBAL) && IsSameFile(member, target) && member.begin < target.begin) {
                AddIssue(InitializationIssueKind.USED_BEFORE_INITIALIZATION, member, target: target,
                    message: target.identifier.Val())
                return false
            }
            let memberStruct = ScopeManager.GetCurSymbolByKind(SymbolKind.STRUCT, ctx, member.scopeName)
            let targetStruct = ScopeManager.GetCurSymbolByKind(SymbolKind.STRUCT, ctx, target.scopeName)
            let isInSameDecl = if ((let Some(memberSymbol) <- memberStruct) &&
                (let Some(targetSymbol) <- targetStruct)) {
                SameSymbol(memberSymbol, targetSymbol)
            } else {
                false
            }
            if (isInSameDecl && !IsInitialized(member)) {
                AddIssue(InitializationIssueKind.USED_BEFORE_INITIALIZATION, member, target: target,
                    message: target.identifier.Val())
                return false
            }
        }
        return result
    }

    private func CheckInitInAssignExpr(assign: AssignExpr): Bool {
        if (let None <- assign.leftValue) {
            return false
        }
        if (let None <- assign.rightExpr) {
            return false
        }
        let left = assign.leftValue.getOrThrow()
        CheckLetFlag(assign, left)
        if (assign.isCompound) {
            left.DisableAttr(Attribute.LEFT_VALUE)
            CheckInitInExpr(left)
            left.EnableAttr(Attribute.LEFT_VALUE)
        }
        CheckExprOption(assign.rightExpr)
        if (let Some(member) <- (left as MemberAccess)) {
            CheckExprOption(member.baseExpr)
        }
        if (let Some(target) <- left.GetTarget()) {
            let hasNominalOuter = if (let Some(outer) <- target.outerDecl) { outer.IsNominalDecl() } else { false }
            let needCheck = target.scopeLevel == 0u32 || (target.astKind != ASTKind.VAR_DECL && hasNominalOuter) ||
                (left.astKind == ASTKind.REF_EXPR && !target.TestAttr(Attribute.INITIALIZED))
            if (!assign.isCompound && needCheck) {
                left.EnableAttr(Attribute.LEFT_VALUE)
                CheckInitInExpr(left)
                left.DisableAttr(Attribute.LEFT_VALUE)
            }
            if (target.TestAttr(Attribute.INITIALIZATION_CHECKED) && !IsInDifferentFunction(assign, target)) {
                UpdateInitializationStatus(assign, target)
            }
        }
        return true
    }

    private func CheckInitInExpr(expr: Expr): Bool {
        if (let Some(desugar) <- expr.desugarExpr) {
            return CheckInitInExpr(desugar)
        }
        return match (expr.astKind) {
            case ASTKind.REF_EXPR =>
                if (let Some(refExpr) <- (expr as RefExpr)) { CheckInitInRefExpr(refExpr) } else { true }
            case ASTKind.MEMBER_ACCESS =>
                if (let Some(member) <- (expr as MemberAccess)) { CheckInitInMemberAccess(member) } else { true }
            case ASTKind.ASSIGN_EXPR =>
                if (let Some(assign) <- (expr as AssignExpr)) { CheckInitInAssignExpr(assign) } else { true }
            case ASTKind.RETURN_EXPR =>
                if (let Some(ret) <- (expr as ReturnExpr)) {
                    let returnResult = CheckExprOption(ret.expr)
                    UpdateScopeStatus(ret)
                    returnResult
                } else { true }
            case ASTKind.TRY_EXPR =>
                if (let Some(tryExpr) <- (expr as TryExpr)) { CheckInitInTryExpr(tryExpr) } else { true }
            case ASTKind.MATCH_EXPR =>
                if (let Some(matchExpr) <- (expr as MatchExpr)) { CheckInitInMatchExpr(matchExpr) } else { true }
            case ASTKind.FOR_IN_EXPR =>
                if (let Some(forIn) <- (expr as ForInExpr)) { CheckInitInForInExpr(forIn) } else { true }
            case ASTKind.IF_EXPR =>
                if (let Some(ifExpr) <- (expr as IfExpr)) { CheckInitInIfExpr(ifExpr) } else { true }
            case ASTKind.WHILE_EXPR =>
                if (let Some(whileExpr) <- (expr as WhileExpr)) { CheckInitInWhileExpr(whileExpr) } else { true }
            case ASTKind.DO_WHILE_EXPR =>
                if (let Some(doWhile) <- (expr as DoWhileExpr)) {
                    CheckInitInLoop(doWhile.body, shouldUnset: false)
                    CheckExprOption(doWhile.condExpr)
                } else { true }
            case ASTKind.INC_OR_DEC_EXPR =>
                if (let Some(incOrDec) <- (expr as IncOrDecExpr)) {
                    if (let Some(inner) <- incOrDec.expr) {
                        CheckLetFlag(incOrDec, inner)
                        CheckInitInExpr(inner)
                    }
                    true
                } else { true }
            case ASTKind.UNARY_EXPR =>
                if (let Some(unary) <- (expr as UnaryExpr)) { CheckExprOption(unary.expr) } else { true }
            case ASTKind.BINARY_EXPR =>
                if (let Some(binary) <- (expr as BinaryExpr)) { CheckInitInBinaryExpr(binary) } else { true }
            case ASTKind.RANGE_EXPR =>
                if (let Some(range) <- (expr as RangeExpr)) {
                    var result = CheckExprOption(range.startExpr)
                    result = CheckExprOption(range.stopExpr) && result
                    result = CheckExprOption(range.stepExpr) && result
                    result
                } else { true }
            case ASTKind.SUBSCRIPT_EXPR =>
                if (let Some(subscript) <- (expr as SubscriptExpr)) {
                    var result = CheckExprOption(subscript.baseExpr)
                    for (indexExpr in subscript.indexExprs) {
                        result = CheckInitInExpr(indexExpr) && result
                    }
                    result
                } else { true }
            case ASTKind.CALL_EXPR =>
                if (let Some(call) <- (expr as CallExpr)) {
                    var result = CheckExprOption(call.baseFunc)
                    if (let Some(desugarArgs) <- call.desugarArgs) {
                        for (arg in desugarArgs) {
                            result = result && CheckExprOption(arg.getOrThrow().expr)
                        }
                    } else {
                        for (arg in call.args) {
                            result = result && CheckExprOption(arg.expr)
                        }
                    }
                    result
                } else { true }
            case ASTKind.PAREN_EXPR =>
                if (let Some(paren) <- (expr as ParenExpr)) { CheckExprOption(paren.expr) } else { true }
            case ASTKind.LAMBDA_EXPR =>
                if (let Some(lambda) <- (expr as LambdaExpr)) {
                    if (let Some(body) <- lambda.funcBody) {
                        CheckInitInFuncBody(body)
                    }
                    true
                } else { true }
            case ASTKind.ARRAY_LIT =>
                if (let Some(arrayLit) <- (expr as ArrayLit)) {
                    var result = true
                    for (child in arrayLit.children) {
                        result = CheckInitInExpr(child) && result
                    }
                    result
                } else { true }
            case ASTKind.ARRAY_EXPR =>
                if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
                    var result = true
                    for (arg in arrayExpr.args) {
                        result = CheckExprOption(arg.expr) && result
                    }
                    result
                } else { true }
            case ASTKind.POINTER_EXPR =>
                if (let Some(pointer) <- (expr as PointerExpr)) {
                    if (let Some(arg) <- pointer.arg) {
                        CheckExprOption(arg.expr)
                    } else { true }
                } else { true }
            case ASTKind.TUPLE_LIT =>
                if (let Some(tuple) <- (expr as TupleLit)) {
                    var result = true
                    for (child in tuple.children) {
                        result = CheckInitInExpr(child) && result
                    }
                    result
                } else { true }
            case ASTKind.TYPE_CONV_EXPR =>
                if (let Some(conv) <- (expr as TypeConvExpr)) { CheckExprOption(conv.expr) } else { true }
            case ASTKind.IF_AVAILABLE_EXPR =>
                if (let Some(ifAvailable) <- (expr as IfAvailableExpr)) {
                    var result = true
                    if (let Some(arg) <- ifAvailable.GetArg()) {
                        result = CheckExprOption(arg.expr) && result
                    }
                    if (let Some(lambda) <- ifAvailable.GetLambda1()) {
                        result = CheckInitInExpr(lambda) && result
                    }
                    if (let Some(lambda) <- ifAvailable.GetLambda2()) {
                        result = CheckInitInExpr(lambda) && result
                    }
                    result
                } else { true }
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(lit) <- (expr as LitConstExpr)) {
                    if (let Some(strInterp) <- lit.siExpr) {
                        var result = true
                        for (partExpr in strInterp.strPartExprs) {
                            if (let Some(interpolation) <- (partExpr as InterpolationExpr)) {
                                result = CheckBlockOption(interpolation.block) && result
                            } else {
                                result = CheckInitInExpr(partExpr) && result
                            }
                        }
                        result
                    } else { true }
                } else { true }
            case ASTKind.THROW_EXPR =>
                if (let Some(throwExpr) <- (expr as ThrowExpr)) {
                    let throwResult = CheckExprOption(throwExpr.expr)
                    UpdateScopeStatus(throwExpr)
                    throwResult
                } else { true }
            case ASTKind.JUMP_EXPR =>
                UpdateScopeStatus(expr)
                true
            case ASTKind.PERFORM_EXPR =>
                if (let Some(perform) <- (expr as PerformExpr)) { CheckExprOption(perform.expr) } else { true }
            case ASTKind.RESUME_EXPR =>
                if (let Some(resume) <- (expr as ResumeExpr)) {
                    var result = CheckExprOption(resume.withExpr)
                    result = CheckExprOption(resume.throwingExpr) && result
                    result
                } else { true }
            case ASTKind.LET_PATTERN_DESTRUCTOR =>
                if (let Some(letPattern) <- (expr as LetPatternDestructor)) {
                    var result = CheckExprOption(letPattern.initializer)
                    for (pattern in letPattern.patterns) {
                        result = CheckInitInPattern(pattern) && result
                    }
                    result
                } else { true }
            case ASTKind.INTERPOLATION_EXPR =>
                if (let Some(interpolation) <- (expr as InterpolationExpr)) { CheckBlockOption(interpolation.block) } else { true }
            case ASTKind.BLOCK =>
                CheckInitialization(expr)
                true
            case ASTKind.SPAWN_EXPR =>
                if (let Some(spawnExpr) <- (expr as SpawnExpr)) {
                    var result = CheckExprOption(spawnExpr.task)
                    result = CheckExprOption(spawnExpr.arg) && result
                    result
                } else { true }
            case ASTKind.SYNCHRONIZED_EXPR =>
                if (let Some(sync) <- (expr as SynchronizedExpr)) {
                    var result = CheckExprOption(sync.mutex)
                    CheckBlockOption(sync.body)
                    result
                } else { true }
            case ASTKind.IS_EXPR =>
                if (let Some(isExpr) <- (expr as IsExpr)) { CheckExprOption(isExpr.leftExpr) } else { true }
            case ASTKind.AS_EXPR =>
                if (let Some(asExpr) <- (expr as AsExpr)) { CheckExprOption(asExpr.leftExpr) } else { true }
            case _ => true
        }
    }

    private func CheckInitInPattern(pattern: Pattern): Bool {
        return match (pattern.astKind) {
            case ASTKind.VAR_PATTERN =>
                if (let Some(varPattern) <- (pattern as VarPattern)) {
                    if (let Some(varDecl) <- varPattern.varDecl) {
                        varDecl.EnableAttr(Attribute.INITIALIZED)
                    }
                }
                true
            case ASTKind.TUPLE_PATTERN =>
                if (let Some(tuple) <- (pattern as TuplePattern)) {
                    var result = true
                    for (child in tuple.patterns) {
                        result = CheckInitInPattern(child) && result
                    }
                    result
                } else { true }
            case ASTKind.ENUM_PATTERN =>
                if (let Some(enumPattern) <- (pattern as EnumPattern)) {
                    var result = true
                    for (child in enumPattern.patterns) {
                        result = CheckInitInPattern(child) && result
                    }
                    result
                } else { true }
            case ASTKind.VAR_OR_ENUM_PATTERN =>
                if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) { CheckPatternOption(varOrEnum.pattern) } else { true }
            case ASTKind.TYPE_PATTERN =>
                if (let Some(typePattern) <- (pattern as TypePattern)) { CheckPatternOption(typePattern.pattern) } else { true }
            case ASTKind.EXCEPT_TYPE_PATTERN =>
                if (let Some(exceptType) <- (pattern as ExceptTypePattern)) { CheckPatternOption(exceptType.pattern) } else { true }
            case ASTKind.COMMAND_TYPE_PATTERN =>
                if (let Some(commandType) <- (pattern as CommandTypePattern)) { CheckPatternOption(commandType.pattern) } else { true }
            case ASTKind.CONST_PATTERN =>
                if (let Some(constPattern) <- (pattern as ConstPattern)) { CheckExprOption(constPattern.literal) } else { true }
            case _ => true
        }
    }

    private func CheckInitInWhileExpr(whileExpr: WhileExpr): Bool {
        let result = CheckInitInConditionOption(whileExpr.condExpr)
        CheckInitInLoop(whileExpr.body)
        return result
    }

    private func CheckInitInForInExpr(forIn: ForInExpr): Bool {
        var result = CheckPatternOption(forIn.pattern)
        result = CheckExprOption(forIn.inExpression) && result
        result = CheckExprOption(forIn.patternGuard) && result
        CheckInitInLoop(forIn.body)
        return result
    }

    private func CheckInitInTryExpr(tryExpr: TryExpr): Bool {
        var result = true
        for (resource in tryExpr.resourceSpec) {
            CheckInitialization(resource)
        }
        tryDepth++
        if (let Some(lambda) <- tryExpr.tryLambda) {
            CheckInitialization(lambda)
        } else {
            CheckBlockOption(tryExpr.tryBlock)
        }
        tryDepth--
        for (pattern in tryExpr.catchPatterns) {
            result = CheckInitInPattern(pattern) && result
        }
        for (block in tryExpr.catchBlocks) {
            CheckInitialization(block)
        }
        for (handler in tryExpr.handlers) {
            result = CheckPatternOption(handler.commandPattern) && result
            if (let Some(lambda) <- handler.desugaredLambda) {
                CheckInitInExpr(lambda)
            } else {
                CheckBlockOption(handler.block)
            }
        }
        CheckBlockOption(tryExpr.finallyBlock)
        return result
    }

    private func CheckInitInConditionOption(expr: Option<Expr>): Bool {
        if (let Some(value) <- expr) {
            return CheckInitInCondition(value)
        }
        return true
    }

    private func CheckInitInCondition(expr: Expr): Bool {
        if (!IsCondition(expr)) {
            return CheckInitInExpr(expr)
        }
        if (let Some(letPattern) <- (expr as LetPatternDestructor)) {
            let result = CheckExprOption(letPattern.initializer)
            let vars = ArrayList<VarDecl>()
            for (pattern in letPattern.patterns) {
                CollectPatternVars(pattern, vars)
            }
            for (varDecl in vars) {
                varDecl.EnableAttr(Attribute.INITIALIZED)
            }
            return result
        }
        if (let Some(binary) <- (expr as BinaryExpr)) {
            if (binary.op == TokenKind.AND) {
                var binaryResult = CheckInitInConditionOption(binary.leftExpr)
                binaryResult = CheckInitInConditionOption(binary.rightExpr) && binaryResult
                return binaryResult
            }
        }
        if (let Some(paren) <- (expr as ParenExpr)) {
            if (let Some(child) <- paren.expr) {
                return CheckInitInCondition(child)
            }
            return true
        }
        return CheckInitInExpr(expr)
    }

    private func CheckAndGetConditionalInitDecls(expr: Expr, uninitsDecls: ArrayList<Decl>): ArrayList<Decl> {
        CheckInitInCondition(expr)
        if (uninitsDecls.isEmpty()) {
            return ArrayList<Decl>()
        }
        let patternVars = ArrayList<VarDecl>()
        CollectPatternVarsInCondition(expr, patternVars)
        return CollectConditionalInitializedDecls(expr, uninitsDecls, patternVars)
    }

    private func CheckInitInCondBlock(block: Block, uninitsDecls: ArrayList<Decl>,
        commonInitedDeclsOfBranches: ArrayList<Decl>, firstInitBranchInited: InitBoolBox): Unit {
        let initedInBlock = CheckAndGetConditionalInitDecls(block, uninitsDecls)
        if (MetControlTransferExpr(block)) {
            return
        }
        if (!firstInitBranchInited.value) {
            CopyDeclList(commonInitedDeclsOfBranches, initedInBlock)
            firstInitBranchInited.value = true
        } else {
            RetainDeclIntersection(commonInitedDeclsOfBranches, initedInBlock)
        }
    }

    private func UpdateInitCondition(commonInitedDecls: ArrayList<Decl>, uninitsDecls: ArrayList<Decl>): Unit {
        for (decl in commonInitedDecls) {
            if (ContainsInitDecl(uninitsDecls, decl)) {
                decl.EnableAttr(Attribute.INITIALIZED)
            }
        }
    }

    private func CheckInitInBinaryExpr(binary: BinaryExpr): Bool {
        if (let Some(desugar) <- binary.desugarExpr) {
            return CheckInitInExpr(desugar)
        }
        if (binary.op != TokenKind.AND && binary.op != TokenKind.OR && binary.op != TokenKind.COALESCING) {
            return CheckExprOption(binary.leftExpr) && CheckExprOption(binary.rightExpr)
        }
        var leftUninits = ArrayList<Decl>()
        if (let Some(left) <- binary.leftExpr) {
            GetUnInitsInExpr(left, leftUninits)
        }
        var rightUninits = ArrayList<Decl>()
        if (let Some(right) <- binary.rightExpr) {
            GetUnInitsInExpr(right, rightUninits)
        }
        var result = CheckExprOption(binary.leftExpr)
        optionalCtxDepth++
        result = result && CheckExprOption(binary.rightExpr)
        optionalCtxDepth--
        for (decl in rightUninits) {
            if (!ContainsInitDecl(leftUninits, decl)) {
                decl.DisableAttr(Attribute.INITIALIZED)
            }
        }
        return result
    }

    private func CheckInitInMatchExpr(matchExpr: MatchExpr): Bool {
        var result = CheckExprOption(matchExpr.selector)
        let uninitsDecls = ArrayList<Decl>()
        GetUnInitsInExpr(matchExpr, uninitsDecls)
        let commonInitedDeclsOfBranches = ArrayList<Decl>()
        let firstInitBranchInited = InitBoolBox(false)
        for (matchCase in matchExpr.matchCases) {
            if (matchCase.TestAttr(Attribute.UNREACHABLE)) {
                continue
            }
            for (pattern in matchCase.patterns) {
                result = CheckInitInPattern(pattern) && result
            }
            result = CheckExprOption(matchCase.patternGuard) && result
            if (result) {
                if (let Some(block) <- matchCase.exprOrDecls) {
                    CheckInitInCondBlock(block, uninitsDecls, commonInitedDeclsOfBranches, firstInitBranchInited)
                }
            }
        }
        for (other in matchExpr.matchCaseOthers) {
            if (other.TestAttr(Attribute.UNREACHABLE)) {
                continue
            }
            result = CheckExprOption(other.matchExpr) && result
            if (result) {
                if (let Some(block) <- other.exprOrDecls) {
                    CheckInitInCondBlock(block, uninitsDecls, commonInitedDeclsOfBranches, firstInitBranchInited)
                }
            }
        }
        UpdateInitCondition(commonInitedDeclsOfBranches, uninitsDecls)
        return result
    }

    private func CheckInitInIfExpr(ifExpr: IfExpr): Bool {
        let result = CheckInitInConditionOption(ifExpr.condExpr)
        let uninitsDecls = ArrayList<Decl>()
        GetUnInitsInExpr(ifExpr, uninitsDecls)
        let commonInitedDeclsOfBranches = ArrayList<Decl>()
        let firstInitBranchInited = InitBoolBox(false)
        let curUninits = ArrayList<Decl>()
        CopyDeclList(curUninits, uninitsDecls)
        var visitingIf = ifExpr
        var isFirstIf = true
        while (true) {
            if (let None <- visitingIf.thenBody) {
                break
            }
            if (!isFirstIf) {
                if (let Some(cond) <- visitingIf.condExpr) {
                    let initedInCondition = CheckAndGetConditionalInitDecls(cond, curUninits)
                    RemoveDecls(curUninits, initedInCondition)
                }
            }
            if (let Some(thenBlock) <- visitingIf.thenBody) {
                CheckInitInCondBlock(thenBlock, curUninits, commonInitedDeclsOfBranches, firstInitBranchInited)
            }
            if (!visitingIf.hasElse) {
                commonInitedDeclsOfBranches.clear()
                break
            }
            if (let Some(elseExpr) <- visitingIf.elseBody) {
                if (let Some(elseIf) <- (elseExpr as IfExpr)) {
                    visitingIf = elseIf
                    isFirstIf = false
                } else {
                    if (let Some(elseBlock) <- (elseExpr as Block)) {
                        CheckInitInCondBlock(elseBlock, curUninits, commonInitedDeclsOfBranches,
                            firstInitBranchInited)
                    } else {
                        CheckInitInExpr(elseExpr)
                    }
                    break
                }
            } else {
                break
            }
        }
        UpdateInitCondition(commonInitedDeclsOfBranches, uninitsDecls)
        return result
    }

    private func CheckInitInLoop(block: Option<Block>, shouldUnset!: Bool = true): Unit {
        if (let Some(loopBlock) <- block) {
            let uninitedDecls = ArrayList<Decl>()
            GetUnInitsInExpr(loopBlock, uninitedDecls)
            CheckInitialization(loopBlock)
            if (shouldUnset) {
                for (decl in uninitedDecls) {
                    if (decl.TestAttr(Attribute.INITIALIZED)) {
                        decl.DisableAttr(Attribute.INITIALIZED)
                    }
                }
            } else {
                let referencedBeforeJump = CollectReferencedDeclsBeforeJumpExpr(loopBlock)
                for (decl in uninitedDecls) {
                    if (!ContainsInitDecl(referencedBeforeJump, decl) && decl.TestAttr(Attribute.INITIALIZED)) {
                        decl.DisableAttr(Attribute.INITIALIZED)
                    }
                }
            }
        }
    }

    private func CheckInitInTypeDecl(inheritDecl: Decl): Unit {
        CheckInitInTypeDecl(inheritDecl, ArrayList<Decl>())
    }

    private func CheckNonCommonVariablesInitInCommonDecl(inheritDecl: InheritableDecl): Unit {
        if (!inheritDecl.TestAttr(Attribute.COMMON)) {
            return
        }
        let info = CollectDecls(inheritDecl)
        if (!info.initFuncDecls.isEmpty()) {
            return
        }
        for (decl in info.nonFuncDecls) {
            if (let Some(varDecl) <- (decl as VarDecl)) {
                if (!varDecl.TestAttr(Attribute.COMMON) && (let None <- varDecl.initializer)) {
                    AddIssue(InitializationIssueKind.UNINITIALIZED_FIELD, decl, target: decl,
                        message: decl.identifier.Val())
                }
            }
        }
    }

    private func CheckInitInTypeDecl(inheritDecl: Decl, superClassNonFuncDecls: ArrayList<Decl>): Unit {
        let info = CollectDecls(inheritDecl)
        for (nonFunc in info.nonFuncDecls) {
            CheckInitialization(nonFunc)
        }
        let uninitNonFuncDecls = ArrayList<Decl>()
        for (decl in info.nonFuncDecls) {
            if (let Some(varDecl) <- (decl as VarDecl)) {
                if (IsInitializedButUnreachable(varDecl)) {
                    uninitNonFuncDecls.add(decl)
                } else if (!decl.TestAttr(Attribute.INITIALIZED)) {
                    uninitNonFuncDecls.add(decl)
                    decl.EnableAttr(Attribute.INITIALIZED)
                }
            } else if (!decl.TestAttr(Attribute.INITIALIZED)) {
                uninitNonFuncDecls.add(decl)
                decl.EnableAttr(Attribute.INITIALIZED)
            }
        }
        for (decl in superClassNonFuncDecls) {
            if (!decl.TestAttr(Attribute.INITIALIZED)) {
                uninitNonFuncDecls.add(decl)
                decl.EnableAttr(Attribute.INITIALIZED)
            }
        }
        for (funcDecl in info.staticFuncDecls) {
            CheckInitialization(funcDecl)
        }
        for (initFunc in info.initFuncDecls) {
            if (initFunc.TestAttr(Attribute.INITIALIZATION_CHECKED) ||
                (initFunc.TestAttr(Attribute.COMMON) && !initFunc.TestAttr(Attribute.COMMON_WITH_DEFAULT))) {
                continue
            }
            CheckInitInConstructors(initFunc, uninitNonFuncDecls)
            RemoveCtorUninitVars(ctorUninitVars, initFunc)
        }
        for (funcDecl in info.funcDecls) {
            CheckInitialization(funcDecl)
        }
        for (annotationArray in info.annotations) {
            CheckInitInExpr(annotationArray)
        }
    }

    private func CheckInitInConstructors(fd: FuncDecl, uninitNonFuncDecls: ArrayList<Decl>): Unit {
        if (!IsOtherInit(fd.constructorCall)) {
            for (decl in uninitNonFuncDecls) {
                decl.DisableAttr(Attribute.INITIALIZED)
            }
        }
        CheckInitialization(fd)
        if (let None <- fd.funcBody) {
            return
        }
        if (opts.compileCjd) {
            return
        }
        if (IsOtherInit(fd.constructorCall)) {
            for (decl in uninitNonFuncDecls) {
                decl.EnableAttr(Attribute.INITIALIZED)
            }
            return
        }
        if (let Some(body) <- fd.funcBody) {
            if (HasForeignOrJavaParent(body)) {
                for (decl in uninitNonFuncDecls) {
                    decl.EnableAttr(Attribute.INITIALIZED)
                }
                return
            }
            if ((let Some(parentClassLike) <- body.parentClassLike) &&
                (let Some(classDecl) <- (parentClassLike as ClassDecl)) &&
                (let Some(superClass) <- classDecl.GetSuperClassDecl()) &&
                superClass.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
                for (decl in uninitNonFuncDecls) {
                    if (decl.astKind != ASTKind.VAR_DECL || !decl.TestAttr(Attribute.COMPILER_ADD)) {
                        continue
                    }
                    if (decl.identifier.Val() != JAVA_REF_FIELD_NAME) {
                        continue
                    }
                    decl.EnableAttr(Attribute.INITIALIZED)
                }
            }
            if (let Some(terminated) <- FindTerminatedScope(terminatedScopes, body.scopeName)) {
                if (terminated.terminationKind == ASTKind.THROW_EXPR) {
                    return
                }
            }
        }
        let definitelyUninitVars = if (let Some(entry) <- FindCtorUninitVars(ctorUninitVars, fd)) {
            entry.decls
        } else {
            ArrayList<Decl>()
        }
        for (decl in uninitNonFuncDecls) {
            if (decl.TestAnyAttr(Attribute.INITIALIZED, Attribute.COMMON) &&
                !ContainsInitDecl(definitelyUninitVars, decl)) {
                continue
            }
            if (fd.TestAttr(Attribute.COMPILER_ADD) && fd.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) {
                Diagnose(diag, fd, BasicDiagKind.sema_class_uninitialized_field,
                    args: [BasicDiagArgument(decl.identifier.Val())]).Emit()
            } else {
                let diagNode: Node = if (fd.TestAttr(Attribute.COMPILER_ADD)) { decl } else { fd }
                Diagnose(diag, diagNode, BasicDiagKind.sema_class_uninitialized_field,
                    args: [BasicDiagArgument(decl.identifier.Val())]).Emit()
            }
        }
    }

    private func CollectToDeclsInfo(decl: Decl, info: CollectDeclsInfo): Unit {
        if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL || decl.astKind == ASTKind.MACRO_EXPAND_DECL) {
            return
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            funcDecl.EnableAttr(Attribute.INITIALIZED)
            if (funcDecl.TestAttr(Attribute.STATIC)) {
                info.staticFuncDecls.add(funcDecl)
            } else if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                info.initFuncDecls.add(funcDecl)
            } else {
                info.funcDecls.add(funcDecl)
            }
        } else if (let Some(propDecl) <- (decl as PropDecl)) {
            propDecl.EnableAttr(Attribute.INITIALIZED)
            for (getter in propDecl.getters) {
                if (propDecl.TestAttr(Attribute.STATIC)) {
                    info.staticFuncDecls.add(getter)
                } else {
                    info.funcDecls.add(getter)
                }
            }
            for (setter in propDecl.setters) {
                if (propDecl.TestAttr(Attribute.STATIC)) {
                    info.staticFuncDecls.add(setter)
                } else {
                    info.funcDecls.add(setter)
                }
            }
        } else if (decl.TestAttr(Attribute.STATIC)) {
            CheckInitialization(decl)
        }
        if (let Some(annotationArray) <- decl.annotationsArray) {
            info.annotations.add(annotationArray)
        }
    }

    private func CollectDecls(decl: Decl): CollectDeclsInfo {
        let info = CollectDeclsInfo()
        if (let Some(annotationArray) <- decl.annotationsArray) {
            info.annotations.add(annotationArray)
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            for (constructor in enumDecl.constructors) {
                if (let Some(annotationArray) <- constructor.annotationsArray) {
                    info.annotations.add(annotationArray)
                }
            }
        }
        for (member in decl.GetMemberDecls()) {
            CollectToDeclsInfo(member, info)
        }
        for (entry in GetVarsInitializationOrderWithPositions(decl)) {
            if (let Some(member) <- entry.decl) {
                info.nonFuncDecls.add(member)
            }
        }
        return info
    }

    // C++ src/Sema/LegalityOfUsage/InitializationChecker.cpp:1721-1741.
    private func GetNonFuncDeclsInSuperClass(classDecl: ClassDecl, out: ArrayList<Decl>,
        superClasses: HashSet<Decl>): Unit {
        for (decl in classDecl.GetMemberDecls()) {
            if (let Some(varDecl) <- (decl as VarDecl)) {
                if (!varDecl.TestAttr(Attribute.PRIVATE) && varDecl.astKind != ASTKind.PROP_DECL) {
                    out.add(varDecl)
                }
            }
        }
        for (inheritedType in classDecl.inheritedTypes) {
            if ((let Some(target) <- inheritedType.GetTarget()) &&
                (let Some(superClass) <- (target as ClassDecl))) {
                if (superClasses.contains(superClass)) {
                    superClasses.add(superClass)
                    GetNonFuncDeclsInSuperClass(superClass, out, superClasses)
                } else {
                    return
                }
            }
        }
    }
}

public func CheckInitialization(
    ctx: ASTContext,
    diag: BasicDiagnosticEngine,
    root: Node,
    opts!: OptionGlobalOptions = OptionGlobalOptions()
): ArrayList<InitializationIssue> {
    return InitializationChecker(ctx, diag, opts: opts).Check(root)
}

public func SelfhostPortStatus_LegalityOfUsage_InitializationChecker(): Bool {
    return true
}
