package cangjie_compiler::sema.LegalityOfUsage

import std.collection.*
import cangjie_compiler::ast.*

public enum InitializationIssueKind {
    | USED_BEFORE_INITIALIZATION
    | ASSIGN_IMMUTABLE
    | CAPTURE_BEFORE_INITIALIZATION
    | ILLEGAL_MEMBER_USE
    | UNINITIALIZED_FIELD
}

private func InitializationIssueKindIndex(kind: InitializationIssueKind): Int64 {
    return match (kind) {
        case InitializationIssueKind.USED_BEFORE_INITIALIZATION => 0
        case InitializationIssueKind.ASSIGN_IMMUTABLE => 1
        case InitializationIssueKind.CAPTURE_BEFORE_INITIALIZATION => 2
        case InitializationIssueKind.ILLEGAL_MEMBER_USE => 3
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

private func IsOtherInit(call: ConstructorCall): Bool {
    return match (call) {
        case ConstructorCall.OTHER_INIT => true
        case _ => false
    }
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
            var hasNonInterfaceBound = false
            for (upperBound in genericTy.upperBounds) {
                if (upperBound.IsStruct()) {
                    return true
                }
                if (!upperBound.IsInterface()) {
                    hasNonInterfaceBound = true
                }
            }
            return !hasNonInterfaceBound
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

private func CollectUninitializedReferences(node: Node, excluded: ArrayList<Decl>): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let walker = Walker(node, visitPre: { current: Node =>
        if (let Some(expr) <- (current as Expr)) {
            if (expr.IsReferenceExpr()) {
                if (let Some(target) <- expr.GetTarget()) {
                    if (!target.TestAttr(Attribute.INITIALIZED) && !ContainsInitDecl(excluded, target)) {
                        AddUniqueDecl(result, target)
                    }
                }
            }
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
    return result
}

private func CollectUninitializedReferences(node: Node): ArrayList<Decl> {
    return CollectUninitializedReferences(node, ArrayList<Decl>())
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

public class InitializationChecker {
    private let issues: ArrayList<InitializationIssue> = ArrayList<InitializationIssue>()
    private var currentInitializingVarDependencies: Option<ArrayList<Decl>> = None
    private var constructorDepth: Int64 = 0

    public init() {}

    public func Check(root: Node): ArrayList<InitializationIssue> {
        CheckInitialization(root)
        return issues
    }

    private func AddIssue(kind: InitializationIssueKind, node: Node, target!: Option<Decl> = None,
        message!: String = ""): Unit {
        issues.add(InitializationIssue(kind, node, target: target, message: message))
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
            if (FromCommonPart(decl)) {
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
        }
        for (member in staticMembers) {
            if (!member.TestAnyAttr(Attribute.INITIALIZED, Attribute.TOOL_ADD, Attribute.COMMON)) {
                AddIssue(InitializationIssueKind.UNINITIALIZED_FIELD, member, target: member)
            }
        }
    }

    private func CheckInitInClassDecl(classDecl: ClassDecl): Unit {
        let superClassNonFuncDecls = ArrayList<Decl>()
        for (typeNode in classDecl.inheritedTypes) {
            if (let Some(target) <- typeNode.GetTarget()) {
                if (let Some(superClass) <- (target as ClassDecl)) {
                    if (IsSameFile(classDecl, superClass)) {
                        CheckStaticInitForTypeDecl(classDecl)
                    }
                    CheckInitialization(superClass)
                    GetNonFuncDeclsInSuperClass(superClass, superClassNonFuncDecls)
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
        var needCheckInLoop = true
        if (let Some(funcDecl) <- body.funcDecl) {
            if (let None <- funcDecl.symbol) {
                needCheckInLoop = false
            }
        }
        if (needCheckInLoop) {
            CheckInitInLoop(body.body)
        } else {
            CheckBlockOption(body.body)
        }
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
                    if (!ContainsInitDecl(vd.dependencies, dep)) {
                        vd.dependencies.add(dep)
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
        let inInitFunction = constructorDepth > 0
        if (let Some(refExpr) <- (expr as RefExpr)) {
            if (let Some(target) <- refExpr.GetTarget()) {
                if (let Some(varDecl) <- (target as VarDecl)) {
                    if (NotAssignableVariable(varDecl, inInitFunction)) {
                        AddIssue(InitializationIssueKind.ASSIGN_IMMUTABLE, assignOrInc, target: varDecl)
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
                            AddIssue(InitializationIssueKind.ASSIGN_IMMUTABLE, assignOrInc, target: base.GetTarget())
                        } else {
                            CheckLetFlag(assignOrInc, base)
                        }
                    }
                }
            }
        }
    }

    private func CheckLetFlagInMemberAccess(assignExpr: Expr, member: MemberAccess, inInitFunction: Bool): Unit {
        if (let Some(target) <- member.target) {
            if (let Some(varDecl) <- (target as VarDecl)) {
                if (NotAssignableVariable(varDecl, inInitFunction)) {
                    AddIssue(InitializationIssueKind.ASSIGN_IMMUTABLE, assignExpr, target: varDecl)
                }
            }
        }
        if (let Some(base) <- member.baseExpr) {
            if (let Some(refExpr) <- (base as RefExpr)) {
                if (let Some(target) <- refExpr.GetTarget()) {
                    if (let Some(varDecl) <- (target as VarDecl)) {
                        if (!varDecl.isVar && MayBeStructTy(varDecl)) {
                            AddIssue(InitializationIssueKind.ASSIGN_IMMUTABLE, assignExpr, target: varDecl)
                        }
                    }
                }
            } else if (let Some(baseMember) <- (base as MemberAccess)) {
                if (let Some(target) <- baseMember.target) {
                    if (let Some(varDecl) <- (target as VarDecl)) {
                        if (MayBeStructTy(varDecl)) {
                            if (!varDecl.isVar) {
                                AddIssue(InitializationIssueKind.ASSIGN_IMMUTABLE, assignExpr, target: varDecl)
                            } else {
                                CheckLetFlag(assignExpr, base)
                            }
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

    private func IsVarUsedBeforeDefinition(checkNode: Node, targetNode: Node): Bool {
        if (checkNode.begin == INVALID_POSITION || targetNode.begin == INVALID_POSITION) {
            return false
        }
        if (!IsSameFile(checkNode, targetNode)) {
            return false
        }
        if (checkNode.IsStaticOrGlobal() && targetNode.IsStaticOrGlobal() && checkNode.begin < targetNode.begin) {
            return true
        }
        return checkNode.scopeLevel == targetNode.scopeLevel && checkNode.begin < targetNode.begin
    }

    private func IsOrderRelated(checkNode: Node, targetNode: Node, isClassLikeOrStruct: Bool): Bool {
        if (IsVarUsedBeforeDefinition(checkNode, targetNode)) {
            return true
        }
        return !(targetNode.scopeLevel == 0 || isClassLikeOrStruct)
    }

    private func CheckInitInRefExpr(refExpr: RefExpr): Bool {
        if (let Some(target) <- refExpr.GetTarget()) {
            if (target.astKind == ASTKind.GENERIC_PARAM_DECL) {
                return true
            }
            let invalidThis = refExpr.isThis && refExpr.isAlone && target.IsStructOrClassDecl() &&
                !IsAllMembersInitialized(target)
            if (invalidThis) {
                AddIssue(InitializationIssueKind.ILLEGAL_MEMBER_USE, refExpr, target: target, message: "this")
                return false
            }
            RecordInstanceVariableUsage(target)
            if (CanSkipInitCheck(target) || !IsOrderRelated(refExpr, target, target.IsNominalDecl())) {
                return true
            }
            if (let Some(_) <- (target as FuncParam)) {
                return true
            }
            if (target.IsFuncOrProp()) {
                return true
            }
            if (!target.TestAttr(Attribute.INITIALIZED) && !refExpr.TestAttr(Attribute.LEFT_VALUE)) {
                AddIssue(InitializationIssueKind.USED_BEFORE_INITIALIZATION, refExpr, target: target,
                    message: target.identifier.Val())
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
            if (target.IsFuncOrProp()) {
                return result
            }
            if (target.TestAttr(Attribute.GLOBAL) && IsSameFile(member, target) && member.begin < target.begin) {
                AddIssue(InitializationIssueKind.USED_BEFORE_INITIALIZATION, member, target: target,
                    message: target.identifier.Val())
                return false
            }
            if (!target.TestAttr(Attribute.INITIALIZED) && !member.TestAttr(Attribute.LEFT_VALUE)) {
                AddIssue(InitializationIssueKind.USED_BEFORE_INITIALIZATION, member, target: target,
                    message: target.identifier.Val())
                result = false
            }
        }
        return result
    }

    private func CheckInitInAssignExpr(assign: AssignExpr): Bool {
        if (let Some(left) <- assign.leftValue) {
            CheckLetFlag(assign, left)
            if (assign.isCompound) {
                left.DisableAttr(Attribute.LEFT_VALUE)
                CheckInitInExpr(left)
                left.EnableAttr(Attribute.LEFT_VALUE)
            }
        }
        CheckExprOption(assign.rightExpr)
        if (let Some(left) <- assign.leftValue) {
            if (let Some(member) <- (left as MemberAccess)) {
                CheckExprOption(member.baseExpr)
            }
            if (let Some(target) <- left.GetTarget()) {
                if (!assign.isCompound && !target.TestAttr(Attribute.INITIALIZED)) {
                    left.EnableAttr(Attribute.LEFT_VALUE)
                    CheckInitInExpr(left)
                    left.DisableAttr(Attribute.LEFT_VALUE)
                }
                target.EnableAttr(Attribute.INITIALIZED)
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
                if (let Some(ret) <- (expr as ReturnExpr)) { CheckExprOption(ret.expr) } else { true }
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
                    for (arg in call.args) {
                        result = CheckExprOption(arg.expr) && result
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
                if (let Some(throwExpr) <- (expr as ThrowExpr)) { CheckExprOption(throwExpr.expr) } else { true }
            case ASTKind.JUMP_EXPR => true
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
        let result = CheckExprOption(whileExpr.condExpr)
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
        if (let Some(lambda) <- tryExpr.tryLambda) {
            CheckInitInExpr(lambda)
        } else {
            CheckBlockOption(tryExpr.tryBlock)
        }
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

    private func CheckInitInBinaryExpr(binary: BinaryExpr): Bool {
        if (let Some(desugar) <- binary.desugarExpr) {
            return CheckInitInExpr(desugar)
        }
        if (binary.op != TokenKind.AND && binary.op != TokenKind.OR && binary.op != TokenKind.COALESCING) {
            var simpleResult = CheckExprOption(binary.leftExpr)
            simpleResult = CheckExprOption(binary.rightExpr) && simpleResult
            return simpleResult
        }
        var leftUninits = ArrayList<Decl>()
        if (let Some(left) <- binary.leftExpr) {
            leftUninits = CollectUninitializedReferences(left)
        }
        var rightUninits = ArrayList<Decl>()
        if (let Some(right) <- binary.rightExpr) {
            rightUninits = CollectUninitializedReferences(right, leftUninits)
        }
        var result = CheckExprOption(binary.leftExpr)
        result = CheckExprOption(binary.rightExpr) && result
        for (decl in rightUninits) {
            decl.DisableAttr(Attribute.INITIALIZED)
        }
        return result
    }

    private func CheckInitInMatchExpr(matchExpr: MatchExpr): Bool {
        var result = CheckExprOption(matchExpr.selector)
        for (matchCase in matchExpr.matchCases) {
            if (matchCase.TestAttr(Attribute.UNREACHABLE)) {
                continue
            }
            for (pattern in matchCase.patterns) {
                result = CheckInitInPattern(pattern) && result
            }
            result = CheckExprOption(matchCase.patternGuard) && result
            CheckBlockOption(matchCase.exprOrDecls)
        }
        for (other in matchExpr.matchCaseOthers) {
            if (other.TestAttr(Attribute.UNREACHABLE)) {
                continue
            }
            result = CheckExprOption(other.matchExpr) && result
            CheckBlockOption(other.exprOrDecls)
        }
        return result
    }

    private func CheckInitInIfExpr(ifExpr: IfExpr): Bool {
        var result = CheckExprOption(ifExpr.condExpr)
        CheckBlockOption(ifExpr.thenBody)
        result = CheckExprOption(ifExpr.elseBody) && result
        return result
    }

    private func CheckInitInLoop(block: Option<Block>, shouldUnset!: Bool = true): Unit {
        if (let Some(loopBlock) <- block) {
            let uninitedDecls = CollectUninitializedReferences(loopBlock)
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
            CheckInitInConstructor(initFunc, uninitNonFuncDecls)
        }
        for (funcDecl in info.funcDecls) {
            CheckInitialization(funcDecl)
        }
        for (annotationArray in info.annotations) {
            CheckInitInExpr(annotationArray)
        }
    }

    private func CheckInitInConstructor(fd: FuncDecl, uninitNonFuncDecls: ArrayList<Decl>): Unit {
        if (!IsOtherInit(fd.constructorCall)) {
            for (decl in uninitNonFuncDecls) {
                decl.DisableAttr(Attribute.INITIALIZED)
            }
        }
        constructorDepth++
        CheckInitialization(fd)
        constructorDepth--
        if (IsOtherInit(fd.constructorCall)) {
            for (decl in uninitNonFuncDecls) {
                decl.EnableAttr(Attribute.INITIALIZED)
            }
            return
        }
        for (decl in uninitNonFuncDecls) {
            if (decl.TestAnyAttr(Attribute.INITIALIZED, Attribute.COMMON)) {
                continue
            }
            AddIssue(InitializationIssueKind.UNINITIALIZED_FIELD, fd, target: decl, message: decl.identifier.Val())
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
        for (member in decl.GetMemberDecls()) {
            if (member.astKind == ASTKind.VAR_DECL || member.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
                if (!member.TestAttr(Attribute.STATIC)) {
                    info.nonFuncDecls.add(member)
                }
            }
        }
        return info
    }

    private func GetNonFuncDeclsInSuperClass(classDecl: ClassDecl, out: ArrayList<Decl>): Unit {
        for (decl in classDecl.GetMemberDecls()) {
            if (let Some(varDecl) <- (decl as VarDecl)) {
                if (!varDecl.TestAttr(Attribute.PRIVATE) && varDecl.astKind != ASTKind.PROP_DECL) {
                    out.add(varDecl)
                }
            }
        }
        if (let Some(superClass) <- classDecl.GetSuperClassDecl()) {
            GetNonFuncDeclsInSuperClass(superClass, out)
        }
    }
}

public func CheckInitialization(root: Node): ArrayList<InitializationIssue> {
    return InitializationChecker().Check(root)
}

public func SelfhostPortStatus_LegalityOfUsage_InitializationChecker(): Bool {
    return true
}
