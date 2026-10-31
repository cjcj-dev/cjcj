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
import cjcj::utils.{JAVA_REF_FIELD_NAME, OverflowStrategy}

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

private class InitFlowState {
    public var reachable: Bool
    public let definite: ArrayList<Decl> = ArrayList<Decl>()
    public let possible: ArrayList<Decl> = ArrayList<Decl>()
    public let writes: ArrayList<Decl> = ArrayList<Decl>()

    public init(reachable: Bool) {
        this.reachable = reachable
    }
}

private class InitFlowExit {
    public let node: Expr
    public let state: InitFlowState
    public let exceptional: Bool
    public var exceptions: Bool = true
    public var errors: Bool = true

    public init(node: Expr, state: InitFlowState, exceptional: Bool) {
        this.node = node
        this.state = state
        this.exceptional = exceptional
    }
}

private class InitConditionFlow {
    public let onTrue: InitFlowState
    public let onFalse: InitFlowState
    public let valid: Bool

    public init(onTrue: InitFlowState, onFalse: InitFlowState, valid: Bool) {
        this.onTrue = onTrue
        this.onFalse = onFalse
        this.valid = valid
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
    public let initializedDecls: ArrayList<Decl> = ArrayList<Decl>()

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
    if (vd.TestAnyAttr(Attribute.IN_STRUCT, Attribute.IN_CLASSLIKE, Attribute.IN_EXTEND) && !inInitFunction) {
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

private func HasForeignParent(body: FuncBody): Bool {
    if (let Some(parentClassLike) <- body.parentClassLike) {
        if (parentClassLike.TestAttr(Attribute.FOREIGN)) {
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
    private var currentInitializingVarDependencies: Option<ArrayList<Decl>> = None
    private let currentFuncBodies: ArrayList<FuncBody> = ArrayList<FuncBody>()
    private let contextVariables: ArrayList<ScopedDecls> = ArrayList<ScopedDecls>()
    private let terminatedScopes: ArrayList<TerminatedScopeInfo> = ArrayList<TerminatedScopeInfo>()
    private let ctorUninitVars: ArrayList<CtorUninitVars> = ArrayList<CtorUninitVars>()
    private var tryDepth: Int64 = 0
    private var flowTryDepth: Int64 = 0
    // Both sets describe paths reaching the current point, not all writes
    // encountered while visiting the function. Abrupt edges are kept separately.
    private var flowReachable: Bool = true
    private var flowDecls: ArrayList<Decl> = ArrayList<Decl>()
    private var flowExits: ArrayList<InitFlowExit> = ArrayList<InitFlowExit>()
    private let possibleReassignments: ArrayList<Decl> = ArrayList<Decl>()
    private let flowWrites: ArrayList<Decl> = ArrayList<Decl>()

    private func TrackFlowDecls(node: Node): Unit {
        GetUnInitsInExpr(node, flowDecls)
    }

    private func SaveFlow(): InitFlowState {
        let state = InitFlowState(flowReachable)
        for (decl in flowDecls) {
            if (decl.TestAttr(Attribute.INITIALIZED)) {
                state.definite.add(decl)
            }
        }
        CopyDeclList(state.possible, possibleReassignments)
        CopyDeclList(state.writes, flowWrites)
        return state
    }

    private func RestoreFlow(state: InitFlowState): Unit {
        flowReachable = state.reachable
        for (decl in flowDecls) {
            if (ContainsInitDecl(state.definite, decl)) {
                decl.EnableAttr(Attribute.INITIALIZED)
            } else {
                decl.DisableAttr(Attribute.INITIALIZED)
            }
        }
        CopyDeclList(possibleReassignments, state.possible)
        CopyDeclList(flowWrites, state.writes)
    }

    private func MergeFlow(left: InitFlowState, right: InitFlowState): InitFlowState {
        let result = InitFlowState(left.reachable || right.reachable)
        let first = if (left.reachable) { left } else { right }
        CopyDeclList(result.definite, first.definite)
        CopyDeclList(result.possible, first.possible)
        CopyDeclList(result.writes, first.writes)
        if (left.reachable && right.reachable) {
            RetainDeclIntersection(result.definite, right.definite)
            for (decl in right.possible) { AddUniqueDecl(result.possible, decl) }
            for (decl in right.writes) { AddUniqueDecl(result.writes, decl) }
        }
        return result
    }

    private func RecordFlowExit(expr: Expr, exceptional!: Bool = false, terminates!: Bool = true): Unit {
        if (flowReachable && (!exceptional || flowTryDepth > 0)) {
            flowExits.add(InitFlowExit(expr, SaveFlow(), exceptional))
        }
        if (terminates) { flowReachable = false }
    }

    private func TakeFlowExits(start: Int64): ArrayList<InitFlowExit> {
        let result = ArrayList<InitFlowExit>()
        while (flowExits.size > start) {
            result.add(flowExits[start])
            flowExits.remove(at: start)
        }
        return result
    }

    public init(ctx: ASTContext, diag: BasicDiagnosticEngine, opts!: OptionGlobalOptions = OptionGlobalOptions()) {
        this.ctx = ctx
        this.diag = diag
        this.opts = opts
    }

    public func Check(root: Node): Unit {
        // The later overflow pass marks operations, but the same annotation and
        // option resolver is needed now to construct their exceptional exits.
        SetOverflowStrategyForNode(root, OverflowStrategy.NA, opts.overflowStrategy)
        CheckInitialization(root)
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
                        if (child.TestAttr(Attribute.UNREACHABLE)) { continue }
                        if (!flowReachable && child.astKind != ASTKind.FUNC_DECL) { continue }
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
        let outerState = SaveFlow()
        let outerDecls = flowDecls
        let outerExits = flowExits
        let outerTryDepth = flowTryDepth
        let outerScopeTryDepth = tryDepth
        flowTryDepth = 0
        tryDepth = 0
        flowDecls = ArrayList<Decl>()
        flowExits = ArrayList<InitFlowExit>()
        flowReachable = true
        // Captured lets retain the enclosing point's possible assignments;
        // assignments made while checking this function never escape back out.
        flowWrites.clear()
        TrackFlowDecls(body)
        if (let Some(funcDecl) <- body.funcDecl) {
            if (IsInstanceConstructor(funcDecl)) {
                if (let Some(owner) <- funcDecl.outerDecl) {
                    for (member in owner.GetMemberDeclPtrs()) {
                        if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(Attribute.INITIALIZED)) {
                            AddUniqueDecl(flowDecls, member)
                        }
                    }
                }
            }
        }
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
        if (let Some(funcDecl) <- body.funcDecl) {
            if (IsInstanceConstructor(funcDecl)) {
                var completion = SaveFlow()
                for (exit in flowExits) {
                    if (!exit.exceptional && exit.node.astKind == ASTKind.RETURN_EXPR) {
                        completion = MergeFlow(completion, exit.state)
                    }
                }
                RemoveCtorUninitVars(ctorUninitVars, funcDecl)
                let uninitialized = CtorUninitVars(funcDecl)
                if (let Some(owner) <- funcDecl.outerDecl) {
                    for (member in owner.GetMemberDeclPtrs()) {
                        if (member.astKind != ASTKind.VAR_DECL || member.TestAttr(Attribute.STATIC)) { continue }
                        if (!completion.reachable || ContainsInitDecl(completion.definite, member)) {
                            member.EnableAttr(Attribute.INITIALIZED)
                            uninitialized.initializedDecls.add(member)
                        } else if (ContainsInitDecl(flowDecls, member)) {
                            member.DisableAttr(Attribute.INITIALIZED)
                            uninitialized.decls.add(member)
                        }
                    }
                }
                ctorUninitVars.add(uninitialized)
            }
        }
        currentFuncBodies.remove(at: currentFuncBodies.size - 1)
        flowDecls = outerDecls
        flowExits = outerExits
        flowTryDepth = outerTryDepth
        tryDepth = outerScopeTryDepth
        RestoreFlow(outerState)
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
                        (!varDecl.isVar && ContainsInitDecl(possibleReassignments, varDecl)) ||
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
                if (NotAssignableVariable(varDecl, inInitFunction) ||
                    (!varDecl.isVar && ContainsInitDecl(possibleReassignments, varDecl))) {
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
        if (scopeGateName.isEmpty() || !flowReachable) {
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

    private func UpdateInitializationStatus(decl: Decl): Unit {
        // A transfer in a conditional operand (for example `value ?? return`)
        // does not terminate the other path. The current flow, rather than a
        // scope-wide record of an earlier transfer, owns this assignment.
        if (!flowReachable) { return }
        decl.EnableAttr(Attribute.INITIALIZED)
        AddUniqueDecl(possibleReassignments, decl)
        AddUniqueDecl(flowWrites, decl)
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
                Diagnose(diag, refExpr, BasicDiagKind.sema_illegal_usage_of_super_member,
                    args: [BasicDiagArgument(refExpr.ref.identifier.Val())]).Emit()
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
                DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_undefined_variable,
                    member, arguments: [target.identifier.Val()]).Emit()
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
                Diagnose(diag, member, BasicDiagKind.sema_used_before_initialization,
                    args: [BasicDiagArgument(target.identifier.Val())]).Emit()
                return false
            }
        }
        return result
    }

    private func CheckAssignmentAddress(left: Expr): Unit {
        if (let Some(member) <- (left as MemberAccess)) {
            CheckExprOption(member.baseExpr)
        } else if (let Some(subscript) <- (left as SubscriptExpr)) {
            CheckExprOption(subscript.baseExpr)
            for (index in subscript.indexExprs) { CheckInitInExpr(index) }
        }
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
        var addressFirst = left.mapExpr.isSome()
        if (let Some(target) <- left.GetTarget()) {
            addressFirst = addressFirst || target.astKind == ASTKind.PROP_DECL
        }
        if (let Some(subscript) <- (left as SubscriptExpr)) {
            addressFirst = addressFirst || (!subscript.isTupleAccess && !subscript.IsVArrayAccess())
        }
        // AST2CHIR evaluates a setter's receiver and indices before its RHS;
        // trivial and VArray stores without a mapped address evaluate RHS first.
        if (!assign.isCompound && addressFirst) { CheckAssignmentAddress(left) }
        if (assign.isCompound && (assign.op == TokenKind.AND_ASSIGN || assign.op == TokenKind.OR_ASSIGN)) {
            let skipped = SaveFlow()
            CheckExprOption(assign.rightExpr)
            RestoreFlow(MergeFlow(skipped, SaveFlow()))
        } else {
            CheckExprOption(assign.rightExpr)
        }
        if (!assign.isCompound && !addressFirst) { CheckAssignmentAddress(left) }
        if (let Some(subscript) <- (left as SubscriptExpr)) {
            if (!subscript.isTupleAccess) { RecordFlowExit(assign, exceptional: true, terminates: false) }
        }
        if (assign.isCompound && OverloadableMayThrow(assign)) {
            RecordFlowExit(assign, exceptional: true, terminates: false)
        }
        if (let Some(target) <- left.GetTarget()) {
            if (target.astKind == ASTKind.PROP_DECL) {
                RecordFlowExit(assign, exceptional: true, terminates: false)
            }
            let hasNominalOuter = if (let Some(outer) <- target.outerDecl) { outer.IsNominalDecl() } else { false }
            let needCheck = target.scopeLevel == 0u32 || (target.astKind != ASTKind.VAR_DECL && hasNominalOuter) ||
                (left.astKind == ASTKind.REF_EXPR && !target.TestAttr(Attribute.INITIALIZED))
            if (!assign.isCompound && needCheck) {
                CheckInitInExpr(left)
            }
            if (target.TestAttr(Attribute.INITIALIZATION_CHECKED) && !IsInDifferentFunction(assign, target)) {
                UpdateInitializationStatus(target)
            }
        }
        return true
    }

    private func OverloadableMayThrow(expr: OverloadableExpr): Bool {
        let noException = expr.op == TokenKind.BITAND || expr.op == TokenKind.BITAND_ASSIGN ||
            expr.op == TokenKind.BITOR || expr.op == TokenKind.BITOR_ASSIGN ||
            expr.op == TokenKind.BITXOR || expr.op == TokenKind.BITXOR_ASSIGN || expr.op == TokenKind.NOT
        if (noException) { return false }
        var operand: Option<Expr> = None
        if (let Some(binary) <- (expr as BinaryExpr)) { operand = binary.leftExpr }
        if (let Some(unary) <- (expr as UnaryExpr)) { operand = unary.expr }
        if (let Some(assign) <- (expr as AssignExpr)) { operand = assign.leftValue }
        if (let Some(inc) <- (expr as IncOrDecExpr)) { operand = inc.expr }
        var integer = false
        if (expr.astKind == ASTKind.BINARY_EXPR || expr.astKind == ASTKind.UNARY_EXPR) {
            if (let Some(ty) <- expr.GetTy()) { integer = ty.IsInteger() }
        } else if (let Some(value) <- operand) {
            if (let Some(ty) <- value.GetTy()) { integer = ty.IsInteger() }
        }
        return (integer && expr.overflowStrategy == OverflowStrategy.THROWING) ||
            (integer && (expr.op == TokenKind.DIV || expr.op == TokenKind.DIV_ASSIGN ||
                expr.op == TokenKind.MOD || expr.op == TokenKind.MOD_ASSIGN)) ||
            expr.op == TokenKind.LSHIFT || expr.op == TokenKind.LSHIFT_ASSIGN ||
            expr.op == TokenKind.RSHIFT || expr.op == TokenKind.RSHIFT_ASSIGN
    }

    private func CheckInitInExpr(expr: Expr): Bool {
        if (!flowReachable || expr.TestAttr(Attribute.UNREACHABLE)) { return true }
        if (let Some(desugar) <- expr.desugarExpr) {
            return CheckInitInExpr(desugar)
        }
        let result = CheckInitInExprImpl(expr)
        // These operations can leave through an exception edge after their
        // operands have been evaluated. A plain local store is not such an edge.
        var mayThrow = expr.astKind == ASTKind.CALL_EXPR ||
            expr.astKind == ASTKind.ARRAY_EXPR || expr.astKind == ASTKind.ARRAY_LIT ||
            expr.astKind == ASTKind.SPAWN_EXPR || expr.astKind == ASTKind.PERFORM_EXPR ||
            expr.astKind == ASTKind.RESUME_EXPR || expr.astKind == ASTKind.SYNCHRONIZED_EXPR
        if (let Some(subscript) <- (expr as SubscriptExpr)) { mayThrow = !subscript.isTupleAccess }
        if (let Some(conv) <- (expr as TypeConvExpr)) {
            if (let Some(ty) <- conv.GetTy()) {
                mayThrow = !(ty.IsInteger() && conv.overflowStrategy != OverflowStrategy.THROWING)
            }
        }
        if (let Some(interpolation) <- (expr as InterpolationExpr)) {
            if (let Some(block) <- interpolation.block) {
                if (let Some(ty) <- block.GetTy()) {
                    // AfterTypeCheck creates the implicit conversion call only
                    // after initialization checking. Record it after this part's
                    // evaluation, before a later part can initialize a variable.
                    // Primitive and String appends do not call user ToString.
                    mayThrow = !ty.IsPrimitive() && !ty.IsString()
                }
            }
        }
        if (mayThrow) { RecordFlowExit(expr, exceptional: true, terminates: false) }
        if (let Some(overloadable) <- (expr as OverloadableExpr)) {
            if (expr.astKind != ASTKind.ASSIGN_EXPR && OverloadableMayThrow(overloadable)) {
                RecordFlowExit(expr, exceptional: true, terminates: false)
            }
        }
        if (expr.IsReferenceExpr() && !expr.TestAttr(Attribute.LEFT_VALUE)) {
            if (let Some(target) <- expr.GetTarget()) {
                if (target.astKind == ASTKind.PROP_DECL) {
                    RecordFlowExit(expr, exceptional: true, terminates: false)
                }
            }
        }
        return result
    }

    private func CheckInitInExprImpl(expr: Expr): Bool {
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
                    RecordFlowExit(ret)
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
                    CheckInitInDoWhileExpr(doWhile)
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
                            result = CheckExprOption(arg.getOrThrow().expr) && result
                        }
                    } else {
                        for (arg in call.args) {
                            result = CheckExprOption(arg.expr) && result
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
                            result = CheckInitInExpr(partExpr) && result
                        }
                        result
                    } else { true }
                } else { true }
            case ASTKind.THROW_EXPR =>
                if (let Some(throwExpr) <- (expr as ThrowExpr)) {
                    let throwResult = CheckExprOption(throwExpr.expr)
                    UpdateScopeStatus(throwExpr)
                    RecordFlowExit(throwExpr, exceptional: true)
                    throwResult
                } else { true }
            case ASTKind.JUMP_EXPR =>
                UpdateScopeStatus(expr)
                RecordFlowExit(expr)
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

    private func MergeLoopExits(loop: Expr, start: Int64, normal: InitFlowState,
        continues: InitFlowState): (InitFlowState, InitFlowState) {
        var outgoing = normal
        var condition = continues
        for (exit in TakeFlowExits(start)) {
            if (let Some(jump) <- (exit.node as JumpExpr)) {
                if (let Some(target) <- jump.refLoop) {
                    if (refEq(target, loop)) {
                        if (jump.isBreak) {
                            outgoing = MergeFlow(outgoing, exit.state)
                        } else {
                            condition = MergeFlow(condition, exit.state)
                        }
                        continue
                    }
                }
            }
            flowExits.add(exit)
        }
        return (outgoing, condition)
    }

    private func CheckInitInWhileExpr(whileExpr: WhileExpr): Bool {
        TrackFlowDecls(whileExpr)
        let start = flowExits.size
        let condition = CheckConditionFlow(whileExpr.condExpr)
        RestoreFlow(condition.onTrue)
        CheckBlockOption(whileExpr.body)
        let (outgoing, backedge) = MergeLoopExits(whileExpr, start, condition.onFalse, SaveFlow())
        // A later false condition can follow a completed iteration. Its writes
        // are possible, but the first false condition still permits zero trips.
        RestoreFlow(if (condition.onFalse.reachable) { MergeFlow(outgoing, backedge) } else { outgoing })
        return condition.valid
    }

    private func CheckInitInDoWhileExpr(loop: DoWhileExpr): Bool {
        TrackFlowDecls(loop)
        let start = flowExits.size
        CheckBlockOption(loop.body)
        let (breaks, conditionEntry) = MergeLoopExits(loop, start, InitFlowState(false), SaveFlow())
        RestoreFlow(conditionEntry)
        let condition = CheckConditionFlow(loop.condExpr)
        RestoreFlow(MergeFlow(breaks, condition.onFalse))
        return condition.valid
    }

    private func ForInInvokesIterator(forIn: ForInExpr): Bool {
        let input = forIn.inExpression ?? return true
        let ty = input.GetTy() ?? return true
        if (ty.IsString()) { return false }
        if (ty.IsRange() && !ty.typeArgs.isEmpty() && ty.typeArgs[0].IsInteger()) {
            if (let Some(range) <- (input as RangeExpr)) {
                if (let Some(step) <- range.stepExpr) {
                    if (step.isConst) {
                        let value = step.constNumValue.asInt.`Int64`()
                        return value != 1 && value != -1
                    }
                } else { return false }
            }
        }
        return true
    }

    private func CheckInitInForInExpr(forIn: ForInExpr): Bool {
        var result = CheckExprOption(forIn.inExpression)
        TrackFlowDecls(forIn)
        let entry = SaveFlow()
        let start = flowExits.size
        // Iterator lowering creates iterator() and next() only after SEMA.
        // Both can throw before the first body, and next() also runs on backedges.
        let invokesIterator = ForInInvokesIterator(forIn)
        if (invokesIterator) { RecordFlowExit(forIn, exceptional: true, terminates: false) }
        result = CheckPatternOption(forIn.pattern) && result
        let guard = CheckConditionFlow(forIn.patternGuard)
        RestoreFlow(guard.onTrue)
        CheckBlockOption(forIn.body)
        let (breaks, backedge) = MergeLoopExits(forIn, start, entry, SaveFlow())
        if (invokesIterator) {
            RestoreFlow(MergeFlow(backedge, guard.onFalse))
            RecordFlowExit(forIn, exceptional: true, terminates: false)
        }
        RestoreFlow(MergeFlow(MergeFlow(breaks, backedge), guard.onFalse))
        return guard.valid && result
    }

    private func ApplyFinallyState(input: InitFlowState, entry: InitFlowState,
        output: InitFlowState): InitFlowState {
        let result = InitFlowState(input.reachable && output.reachable)
        CopyDeclList(result.definite, input.definite)
        CopyDeclList(result.possible, input.possible)
        for (decl in output.definite) {
            if (!ContainsInitDecl(entry.definite, decl)) { AddUniqueDecl(result.definite, decl) }
        }
        CopyDeclList(result.writes, input.writes)
        for (decl in output.writes) {
            AddUniqueDecl(result.possible, decl)
            AddUniqueDecl(result.writes, decl)
        }
        return result
    }

    private func ClassDerivesFrom(ty: Ty, target: Decl): Bool {
        var current = ty as ClassTy
        while (let Some(classTy) <- current) {
            if (let Some(decl) <- classTy.decl) {
                if (SameDecl(decl, target)) { return true }
            }
            current = classTy.GetSuperClassTy()
        }
        return false
    }

    private func CatchTypes(pattern: Pattern): ArrayList<Ty> {
        let result = ArrayList<Ty>()
        if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            for (typeNode in exceptPattern.types) {
                if (let Some(ty) <- typeNode.GetTy()) { result.add(ty) }
            }
        } else if (let Some(ty) <- pattern.GetTy()) {
            result.add(ty)
        }
        return result
    }

    private func IsCoreExceptionRoot(ty: Ty, name: String): Bool {
        let decl = Ty.GetDeclPtrOfTy(ty) ?? return false
        return decl.fullPackageName == "std.core" && decl.identifier.Val() == name
    }

    private func ExceptionRoot(ty: Ty): String {
        var current = ty as ClassTy
        while (let Some(classTy) <- current) {
            if (IsCoreExceptionRoot(classTy, "Exception")) { return "Exception" }
            if (IsCoreExceptionRoot(classTy, "Error")) { return "Error" }
            current = classTy.GetSuperClassTy()
        }
        return ""
    }

    private func CatchMayReceive(pattern: Pattern, exit: InitFlowExit): Bool {
        if ((exit.node as ThrowExpr).isNone()) {
            for (ty in CatchTypes(pattern)) {
                let root = ExceptionRoot(ty)
                if ((root == "Exception" && exit.exceptions) || (root == "Error" && exit.errors) ||
                    root.isEmpty()) { return true }
            }
            return false
        }
        let throwExpr = (exit.node as ThrowExpr) ?? return true
        let thrown = throwExpr.expr ?? return true
        let thrownTy = thrown.GetTy() ?? return true
        let thrownDecl = Ty.GetDeclPtrOfTy(thrownTy) ?? return true
        for (caughtTy in CatchTypes(pattern)) {
            let caughtDecl = Ty.GetDeclPtrOfTy(caughtTy) ?? return true
            if (ClassDerivesFrom(thrownTy, caughtDecl) || ClassDerivesFrom(caughtTy, thrownDecl)) { return true }
        }
        return false
    }

    private func CatchCoversExit(pattern: Pattern, exit: InitFlowExit): Bool {
        if ((exit.node as ThrowExpr).isNone()) {
            for (ty in CatchTypes(pattern)) {
                if (IsCoreExceptionRoot(ty, "Exception")) { exit.exceptions = false }
                if (IsCoreExceptionRoot(ty, "Error")) { exit.errors = false }
            }
            return !exit.exceptions && !exit.errors
        }
        let throwExpr = (exit.node as ThrowExpr) ?? return false
        let thrown = throwExpr.expr ?? return false
        let thrownTy = thrown.GetTy() ?? return false
        for (caughtTy in CatchTypes(pattern)) {
            let caughtDecl = Ty.GetDeclPtrOfTy(caughtTy) ?? continue
            if (ClassDerivesFrom(thrownTy, caughtDecl)) { return true }
        }
        return false
    }

    private func CheckInitInTryExpr(tryExpr: TryExpr): Bool {
        TrackFlowDecls(tryExpr)
        var result = true
        let start = flowExits.size
        flowTryDepth++
        // Resource acquisition and the generated close calls are part of the
        // protected region. Keep acquisition failures separate from normal flow.
        for (resource in tryExpr.resourceSpec) { CheckInitialization(resource) }
        let entry = SaveFlow()
        tryDepth++
        if (let Some(lambda) <- tryExpr.tryLambda) {
            CheckInitialization(lambda)
            RecordFlowExit(tryExpr, exceptional: true, terminates: false)
        } else {
            CheckBlockOption(tryExpr.tryBlock)
        }
        tryDepth--
        if (!tryExpr.resourceSpec.isEmpty()) {
            RecordFlowExit(tryExpr, exceptional: true, terminates: false)
        }
        var normal = SaveFlow()
        let pending = ArrayList<InitFlowExit>()
        let exceptions = ArrayList<InitFlowExit>()
        for (exit in TakeFlowExits(start)) {
            if (exit.exceptional) { exceptions.add(exit) } else { pending.add(exit) }
            if (!tryExpr.resourceSpec.isEmpty() && !exit.exceptional) {
                // close() also runs on return/break/continue and can replace
                // that transfer with an exception consumed by this try's catch.
                exceptions.add(InitFlowExit(tryExpr, exit.state, true))
            }
        }
        for (idx in 0..tryExpr.catchBlocks.size) {
            var exceptional = InitFlowState(false)
            for (exit in exceptions) {
                if (idx >= tryExpr.catchPatterns.size || CatchMayReceive(tryExpr.catchPatterns[idx], exit)) {
                    exceptional = MergeFlow(exceptional, exit.state)
                }
            }
            RestoreFlow(exceptional)
            if (idx < tryExpr.catchPatterns.size) {
                let pattern = tryExpr.catchPatterns[idx]
                result = CheckInitInPattern(pattern) && result
                var i: Int64 = 0
                while (i < exceptions.size) {
                    if (CatchCoversExit(pattern, exceptions[i])) { exceptions.remove(at: i) } else { i++ }
                }
            }
            CheckInitialization(tryExpr.catchBlocks[idx])
            normal = MergeFlow(normal, SaveFlow())
            for (exit in TakeFlowExits(start)) { pending.add(exit) }
        }
        for (exit in exceptions) { pending.add(exit) }
        for (handler in tryExpr.handlers) {
            RestoreFlow(entry)
            result = CheckPatternOption(handler.commandPattern) && result
            if (let Some(lambda) <- handler.desugaredLambda) {
                CheckInitInExpr(lambda)
            } else {
                CheckBlockOption(handler.block)
            }
            // A handler is invoked through its own lambda, not by falling
            // through the surrounding try/catch. Its transfers remain local.
            let _ = TakeFlowExits(start)
            RestoreFlow(entry)
        }
        if (let Some(finallyBlock) <- tryExpr.finallyBlock) {
            var finallyEntry = normal
            for (exit in pending) { finallyEntry = MergeFlow(finallyEntry, exit.state) }
            RestoreFlow(finallyEntry)
            flowWrites.clear()
            CheckInitialization(finallyBlock)
            let finallyOutput = SaveFlow()
            for (exit in pending) {
                let state = ApplyFinallyState(exit.state, finallyEntry, finallyOutput)
                if (state.reachable) {
                    let outgoing = InitFlowExit(exit.node, state, exit.exceptional)
                    outgoing.exceptions = exit.exceptions
                    outgoing.errors = exit.errors
                    flowExits.add(outgoing)
                }
            }
            RestoreFlow(ApplyFinallyState(normal, finallyEntry, finallyOutput))
        } else {
            for (exit in pending) { flowExits.add(exit) }
            RestoreFlow(normal)
        }
        flowTryDepth--
        return result
    }

    private func CheckConditionFlow(expr: Option<Expr>): InitConditionFlow {
        if (let None <- expr) {
            return InitConditionFlow(SaveFlow(), InitFlowState(false), true)
        }
        let value = expr.getOrThrow()
        TrackFlowDecls(value)
        if (let Some(paren) <- (value as ParenExpr)) {
            return CheckConditionFlow(paren.expr)
        }
        if (let Some(binary) <- (value as BinaryExpr)) {
            if (binary.op == TokenKind.AND || binary.op == TokenKind.OR) {
                let left = CheckConditionFlow(binary.leftExpr)
                RestoreFlow(if (binary.op == TokenKind.AND) { left.onTrue } else { left.onFalse })
                let right = CheckConditionFlow(binary.rightExpr)
                if (binary.op == TokenKind.AND) {
                    return InitConditionFlow(right.onTrue, MergeFlow(left.onFalse, right.onFalse),
                        left.valid && right.valid)
                }
                return InitConditionFlow(MergeFlow(left.onTrue, right.onTrue), right.onFalse,
                    left.valid && right.valid)
            }
        }
        if (let Some(letPattern) <- (value as LetPatternDestructor)) {
            let valid = CheckExprOption(letPattern.initializer)
            let onFalse = SaveFlow()
            for (pattern in letPattern.patterns) { CheckInitInPattern(pattern) }
            return InitConditionFlow(SaveFlow(), onFalse, valid)
        }
        let valid = CheckInitInExpr(value)
        if (let Some(literal) <- (value as LitConstExpr)) {
            if (literal.kind == LitConstKind.BOOL) {
                if (literal.stringValue == "true") {
                    return InitConditionFlow(SaveFlow(), InitFlowState(false), valid)
                }
                if (literal.stringValue == "false") {
                    return InitConditionFlow(InitFlowState(false), SaveFlow(), valid)
                }
            }
        }
        return InitConditionFlow(SaveFlow(), SaveFlow(), valid)
    }

    private func CheckInitInBinaryExpr(binary: BinaryExpr): Bool {
        if (binary.op == TokenKind.AND || binary.op == TokenKind.OR) {
            let condition = CheckConditionFlow(Some(binary))
            RestoreFlow(MergeFlow(condition.onTrue, condition.onFalse))
            return condition.valid
        }
        TrackFlowDecls(binary)
        var result = CheckExprOption(binary.leftExpr)
        let left = SaveFlow()
        result = CheckExprOption(binary.rightExpr) && result
        if (binary.op == TokenKind.COALESCING) { RestoreFlow(MergeFlow(left, SaveFlow())) }
        return result
    }

    private func CheckInitInMatchExpr(matchExpr: MatchExpr): Bool {
        var result = CheckExprOption(matchExpr.selector)
        TrackFlowDecls(matchExpr)
        var nextCase = SaveFlow()
        var outgoing = InitFlowState(false)
        for (matchCase in matchExpr.matchCases) {
            if (matchCase.TestAttr(Attribute.UNREACHABLE)) { continue }
            RestoreFlow(nextCase)
            for (pattern in matchCase.patterns) {
                result = CheckInitInPattern(pattern) && result
            }
            let guard = CheckConditionFlow(matchCase.patternGuard)
            RestoreFlow(guard.onTrue)
            CheckBlockOption(matchCase.exprOrDecls)
            outgoing = MergeFlow(outgoing, SaveFlow())
            // A pattern mismatch skips the guard entirely; a failed guard does
            // not. Irrefutable patterns have no mismatch edge.
            var irrefutable = false
            for (pattern in matchCase.patterns) {
                if (pattern.astKind == ASTKind.WILDCARD_PATTERN || pattern.astKind == ASTKind.VAR_PATTERN) {
                    irrefutable = true
                }
            }
            nextCase = if (irrefutable) { guard.onFalse } else { MergeFlow(nextCase, guard.onFalse) }
            result = guard.valid && result
        }
        for (other in matchExpr.matchCaseOthers) {
            if (other.TestAttr(Attribute.UNREACHABLE)) { continue }
            RestoreFlow(nextCase)
            let condition = CheckConditionFlow(other.matchExpr)
            RestoreFlow(condition.onTrue)
            CheckBlockOption(other.exprOrDecls)
            outgoing = MergeFlow(outgoing, SaveFlow())
            nextCase = condition.onFalse
            result = condition.valid && result
        }
        RestoreFlow(outgoing)
        return result
    }

    private func CheckInitInIfExpr(ifExpr: IfExpr): Bool {
        TrackFlowDecls(ifExpr)
        let condition = CheckConditionFlow(ifExpr.condExpr)
        RestoreFlow(condition.onTrue)
        CheckBlockOption(ifExpr.thenBody)
        let thenExit = SaveFlow()
        RestoreFlow(condition.onFalse)
        if (ifExpr.hasElse) { CheckExprOption(ifExpr.elseBody) }
        RestoreFlow(MergeFlow(thenExit, SaveFlow()))
        return condition.valid
    }

    private func CheckInitInLoop(block: Option<Block>): Unit {
        if (let Some(loopBlock) <- block) {
            let uninitedDecls = ArrayList<Decl>()
            GetUnInitsInExpr(loopBlock, uninitedDecls)
            CheckInitialization(loopBlock)
            for (decl in uninitedDecls) { decl.DisableAttr(Attribute.INITIALIZED) }
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
                    Diagnose(diag, decl, BasicDiagKind.sema_class_uninitialized_field,
                        args: [BasicDiagArgument(decl.identifier.Val())]).Emit()
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
            if (HasForeignParent(body)) {
                for (decl in uninitNonFuncDecls) {
                    decl.EnableAttr(Attribute.INITIALIZED)
                }
                return
            }
            if ((let Some(parentClassLike) <- body.parentClassLike) &&
                (let Some(classDecl) <- (parentClassLike as ClassDecl)) &&
                (let Some(superClass) <- classDecl.GetSuperClassDecl()) &&
                superClass.TestAnyAttr(Attribute.JAVA_FOREIGN, Attribute.JAVA_EXPORT)) {
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
        }
        let completion = FindCtorUninitVars(ctorUninitVars, fd)
        for (decl in uninitNonFuncDecls) {
            // The constructor records its normal completions before restoring
            // the enclosing flow. That restoration can include these fields
            // when an earlier global initializer references them; its flags
            // describe that enclosing point, not this constructor's result.
            let initialized = if (let Some(state) <- completion) {
                ContainsInitDecl(state.initializedDecls, decl)
            } else { false }
            let uninitialized = if (let Some(state) <- completion) {
                ContainsInitDecl(state.decls, decl)
            } else { false }
            if ((initialized || decl.TestAnyAttr(Attribute.INITIALIZED, Attribute.COMMON)) && !uninitialized) {
                decl.EnableAttr(Attribute.INITIALIZED)
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
): Unit {
    InitializationChecker(ctx, diag, opts: opts).Check(root)
}

public func SelfhostPortStatus_LegalityOfUsage_InitializationChecker(): Bool {
    return true
}
