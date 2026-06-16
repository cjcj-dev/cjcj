package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind

private let CORE_PACKAGE_NAME: String = "std.core"

public enum ConstEvaluationIssueKind {
    | EXPECT_CONST_FUNCTION
    | EXPECT_CONST_EXPRESSION
    | CANNOT_DEFINE_VAR_IN_CONST_FUNCTION
    | NO_CONST_INIT
    | CONST_INIT_WITH_VAR_MEMBER
}

private func ConstEvaluationIssueKindIndex(kind: ConstEvaluationIssueKind): Int64 {
    return match (kind) {
        case ConstEvaluationIssueKind.EXPECT_CONST_FUNCTION => 0
        case ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION => 1
        case ConstEvaluationIssueKind.CANNOT_DEFINE_VAR_IN_CONST_FUNCTION => 2
        case ConstEvaluationIssueKind.NO_CONST_INIT => 3
        case ConstEvaluationIssueKind.CONST_INIT_WITH_VAR_MEMBER => 4
    }
}

extend ConstEvaluationIssueKind <: Equatable<ConstEvaluationIssueKind> {
    public operator func ==(right: ConstEvaluationIssueKind): Bool {
        return ConstEvaluationIssueKindIndex(this) == ConstEvaluationIssueKindIndex(right)
    }

    public operator func !=(right: ConstEvaluationIssueKind): Bool {
        return !(this == right)
    }
}

public class ConstEvaluationIssue {
    public var kind: ConstEvaluationIssueKind
    public var node: Node
    public var target: Option<Decl>
    public var message: String

    public init(kind: ConstEvaluationIssueKind, node: Node, target!: Option<Decl> = None, message!: String = "") {
        this.kind = kind
        this.node = node
        this.target = target
        this.message = message
    }
}

private class ConstBoolBox {
    public var value: Bool

    public init(value: Bool) {
        this.value = value
    }
}

private func SameNodeForConst(left: Node, right: Node): Bool {
    return left.astKind == right.astKind && left.begin == right.begin && left.end == right.end
}

private func ContainsConstDecl(values: ArrayList<Decl>, decl: Decl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func ContainsConstNode(values: ArrayList<Node>, node: Node): Bool {
    for (value in values) {
        if (SameNodeForConst(value, node)) {
            return true
        }
    }
    return false
}

private func ContainsConstRef(values: ArrayList<RefExpr>, refExpr: RefExpr): Bool {
    for (value in values) {
        if (SameNodeForConst(value, refExpr)) {
            return true
        }
    }
    return false
}

private func IsStructArrayExpr(expr: Expr): Bool {
    if (let Some(ty) <- expr.GetTy()) {
        return ty.IsStructArray()
    }
    return false
}

private func IsTupleOrVArrayExpr(expr: Expr): Bool {
    if (let Some(ty) <- expr.GetTy()) {
        if (ty.IsTuple()) {
            return true
        }
        if (let Some(_) <- (ty as VArrayTy)) {
            return true
        }
    }
    return false
}

private func IsStringBinaryExpr(expr: Expr): Bool {
    if (expr.astKind != ASTKind.BINARY_EXPR) {
        return false
    }
    if (!Ty.IsTyCorrect(expr.GetTy())) {
        return false
    }
    if (let Some(desugar) <- expr.desugarExpr) {
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                    if (let Some(baseExpr) <- memberAccess.baseExpr) {
                        if (let Some(baseTy) <- baseExpr.GetTy()) {
                            if (!baseTy.IsString()) {
                                return false
                            }
                        } else {
                            return false
                        }
                        if (let Some(target) <- memberAccess.GetTarget()) {
                            return target.fullPackageName == CORE_PACKAGE_NAME && !callExpr.args.isEmpty()
                        }
                    }
                }
            }
        }
    }
    return false
}

private func IsConstSafeDecl(decl: Decl): Bool {
    for (annotation in decl.annotations) {
        if (annotation.kind == AstAnnotationKind.CONSTSAFE) {
            return true
        }
    }
    return false
}

private func HasAnnotationDeclTarget(anno: Annotation): Bool {
    if (anno.kind != AstAnnotationKind.ANNOTATION || anno.args.size != 1) {
        return false
    }
    let firstArg = anno.args[0]
    if (firstArg.name.Val() != "target") {
        return false
    }
    if (let Some(expr) <- firstArg.expr) {
        return expr.astKind == ASTKind.ARRAY_LIT
    }
    return false
}

private func CollectInstanceMembers(decls: ArrayList<Decl>): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    for (decl in decls) {
        if (decl.astKind == ASTKind.VAR_DECL && !decl.TestAttr(Attribute.STATIC)) {
            result.add(decl)
        }
    }
    return result
}

private func HasConstInit(decls: ArrayList<Decl>): Bool {
    for (decl in decls) {
        if (decl.IsConst() && decl.TestAttr(Attribute.CONSTRUCTOR)) {
            return true
        }
    }
    return false
}

public class ConstEvaluationChecker {
    private let issues: ArrayList<ConstEvaluationIssue> = ArrayList<ConstEvaluationIssue>()
    private let inConstContext: ArrayList<Node> = ArrayList<Node>()
    private let inConstFunc: ArrayList<Decl> = ArrayList<Decl>()
    private let constThisOrSuper: ArrayList<RefExpr> = ArrayList<RefExpr>()
    private var structOrClassMembers: ArrayList<Decl> = ArrayList<Decl>()
    private var inInit: Bool = false

    public init() {}

    public func Check(pkg: Package): ArrayList<ConstEvaluationIssue> {
        ChkAllDeclsByWalk(pkg)
        return issues
    }

    private func AddIssue(kind: ConstEvaluationIssueKind, node: Node, target!: Option<Decl> = None,
        message!: String = ""): Unit {
        issues.add(ConstEvaluationIssue(kind, node, target: target, message: message))
    }

    private func ChkAllDeclsByWalk(root: Node): Bool {
        let result = ConstBoolBox(true)
        let walker = Walker(root, visitPre: { node: Node =>
            if (node.TestAnyAttr(Attribute.IMPORTED, Attribute.IS_BROKEN, Attribute.HAS_BROKEN)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(decl) <- (node as Decl)) {
                result.value = ChkAnnotations(decl) && result.value
                if (IsConstSafeDecl(decl)) {
                    return VisitAction.SKIP_CHILDREN
                }
                if (decl.IsConst()) {
                    result.value = ChkConstDecl(decl) && result.value
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(structDecl) <- (decl as StructDecl)) {
                    result.value = ChkStructDecl(structDecl) && result.value
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(classDecl) <- (decl as ClassDecl)) {
                    result.value = ChkClassDecl(classDecl) && result.value
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                    result.value = ChkExtendDecl(extendDecl) && result.value
                    return VisitAction.SKIP_CHILDREN
                }
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
        return result.value
    }

    private func ChkAnnotations(decl: Decl): Bool {
        var result = true
        for (annotation in decl.annotations) {
            if (HasAnnotationDeclTarget(annotation)) {
                let firstArg = annotation.args[0]
                if (let Some(expr) <- firstArg.expr) {
                    if (let Some(arrayLit) <- (expr as ArrayLit)) {
                        result = ChkExprChildren(arrayLit.children, true) && result
                    }
                }
            }
        }
        if (let Some(array) <- decl.annotationsArray) {
            result = ChkExprChildren(array.children, true) && result
        }
        return result
    }

    private func ChkConstDecl(decl: Decl): Bool {
        if (decl.TestAnyAttr(Attribute.IS_BROKEN, Attribute.HAS_BROKEN)) {
            return false
        }
        if (let Some(varDecl) <- (decl as VarDecl)) {
            return ChkVarDecl(varDecl)
        }
        if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
            return ChkVarWithPatternDecl(vpd)
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            return ChkFuncDecl(funcDecl)
        }
        return false
    }

    private func MarkConstContextForVar(vd: VarDeclAbstract): Unit {
        if (!vd.isConst) {
            return
        }
        let walker = Walker(vd, visitPre: { node: Node =>
            if (ContainsConstNode(inConstContext, node)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(innerVar) <- (node as VarDeclAbstract)) {
                if (innerVar.isConst) {
                    inConstContext.add(node)
                }
            } else if (node.astKind == ASTKind.FUNC_BODY || node.astKind == ASTKind.RETURN_EXPR) {
                inConstContext.add(node)
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    private func ChkVarDeclAbstract(vd: VarDeclAbstract): Bool {
        MarkConstContextForVar(vd)
        if (vd.isVar) {
            AddIssue(ConstEvaluationIssueKind.CANNOT_DEFINE_VAR_IN_CONST_FUNCTION, vd)
            vd.isConst = true
            return false
        }
        if (let Some(initExpr) <- vd.initializer) {
            return ChkExpr(initExpr, !vd.isConst)
        }
        return true
    }

    private func ChkVarDecl(vd: VarDecl): Bool {
        return ChkVarDeclAbstract(vd)
    }

    private func MarkPatternVarsConst(pattern: Pattern): Unit {
        let walker = Walker(pattern, visitPre: { node: Node =>
            if (let Some(varDecl) <- (node as VarDecl)) {
                varDecl.isConst = true
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    private func ChkVarWithPatternDecl(vpd: VarWithPatternDecl): Bool {
        if (vpd.IsConst()) {
            if (let Some(pattern) <- vpd.irrefutablePattern) {
                MarkPatternVarsConst(pattern)
            }
        }
        return ChkVarDeclAbstract(vpd)
    }

    private func CollectConstFunctionContext(fb: FuncBody): Unit {
        if (let Some(funcDecl) <- fb.funcDecl) {
            if (!funcDecl.IsConst()) {
                return
            }
        }
        let walker = Walker(fb, visitPre: { node: Node =>
            if (let Some(decl) <- (node as Decl)) {
                if (!ContainsConstDecl(inConstFunc, decl)) {
                    inConstFunc.add(decl)
                }
            } else if (let Some(refExpr) <- (node as RefExpr)) {
                if (let Some(target) <- refExpr.GetTarget()) {
                    if (!IsClassOrEnumConstructor(target) &&
                        (refExpr.isThis || refExpr.isSuper || IsInstanceMember(target))) {
                        if (!ContainsConstRef(constThisOrSuper, refExpr)) {
                            constThisOrSuper.add(refExpr)
                        }
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    private func ChkFuncBody(fb: FuncBody): Bool {
        if (fb.TestAnyAttr(Attribute.IS_BROKEN, Attribute.HAS_BROKEN)) {
            return false
        }
        CollectConstFunctionContext(fb)
        var result = true
        if (!fb.paramLists.isEmpty()) {
            for (param in fb.paramLists[0].params) {
                if (let Some(defaultValue) <- param.assignment) {
                    let paramIsConst = ChkExpr(defaultValue, true)
                    if (let Some(desugarDecl) <- param.desugarDecl) {
                        desugarDecl.isConst = paramIsConst
                    }
                    result = paramIsConst && result
                }
            }
        }
        if (let Some(body) <- fb.body) {
            result = ChkBlock(body, true) && result
        }
        return result
    }

    private func ChkFuncDecl(fd: FuncDecl): Bool {
        if (!fd.isConst) {
            AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_FUNCTION, fd, target: fd)
            fd.isConst = true
            return false
        }
        let oldInInit = inInit
        if (fd.TestAttr(Attribute.CONSTRUCTOR)) {
            inInit = true
        }
        var result = true
        if (let Some(body) <- fd.funcBody) {
            result = ChkFuncBody(body)
        }
        inInit = oldInInit
        return result
    }

    private func ChkDeclHasConstAllConstInitializers(decls: ArrayList<Decl>): Bool {
        var hasStaticConstInit = false
        var hasNonStaticConstInit = false
        for (decl in decls) {
            if (decl.IsConst() && decl.TestAttr(Attribute.CONSTRUCTOR)) {
                if (decl.TestAttr(Attribute.STATIC)) {
                    hasStaticConstInit = true
                } else {
                    hasNonStaticConstInit = true
                }
            }
        }
        var result = true
        for (decl in decls) {
            if (let Some(vda) <- (decl as VarDeclAbstract)) {
                if (vda.astKind != ASTKind.PROP_DECL) {
                    if (let Some(initExpr) <- vda.initializer) {
                        if ((hasStaticConstInit && vda.TestAttr(Attribute.STATIC)) ||
                            (hasNonStaticConstInit && !vda.TestAttr(Attribute.STATIC))) {
                            result = ChkExpr(initExpr, false) && result
                        }
                    }
                }
            }
        }
        return result
    }

    private func ChkDeclNoConstInitNoConstFunc(decls: ArrayList<Decl>): Bool {
        var result = true
        for (decl in decls) {
            if (decl.IsConst() && decl.IsFunc() && !decl.TestAttr(Attribute.STATIC)) {
                AddIssue(ConstEvaluationIssueKind.NO_CONST_INIT, decl, target: decl)
                result = false
            }
        }
        return result
    }

    private func ChkStructDecl(sd: StructDecl): Bool {
        let oldMembers = structOrClassMembers
        let members = sd.GetMemberDecls()
        structOrClassMembers = CollectInstanceMembers(members)
        var result = true
        for (decl in members) {
            result = ChkAllDeclsByWalk(decl) && result
        }
        if (HasConstInit(members)) {
            result = ChkDeclHasConstAllConstInitializers(members) && result
        } else {
            result = ChkDeclNoConstInitNoConstFunc(members) && result
        }
        structOrClassMembers = oldMembers
        return result
    }

    private func ChkClassDeclHasConstInitNoVarMember(cd: ClassDecl): Bool {
        let members = cd.GetMemberDecls()
        let vars = ArrayList<Decl>()
        for (decl in members) {
            if (let Some(vda) <- (decl as VarDeclAbstract)) {
                if (vda.isVar && vda.astKind != ASTKind.PROP_DECL) {
                    vars.add(vda)
                }
            }
        }
        if (vars.isEmpty()) {
            return true
        }
        for (decl in members) {
            if (decl.IsConst() && decl.TestAttr(Attribute.CONSTRUCTOR) &&
                !decl.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) {
                AddIssue(ConstEvaluationIssueKind.CONST_INIT_WITH_VAR_MEMBER, decl, target: decl)
            }
        }
        return false
    }

    private func ChkClassDecl(cd: ClassDecl): Bool {
        let oldMembers = structOrClassMembers
        let members = cd.GetMemberDecls()
        structOrClassMembers = CollectInstanceMembers(members)
        var result = true
        for (decl in members) {
            result = ChkAllDeclsByWalk(decl) && result
        }
        if (HasConstInit(members)) {
            result = ChkClassDeclHasConstInitNoVarMember(cd) && result
            result = ChkDeclHasConstAllConstInitializers(members) && result
        } else {
            result = ChkDeclNoConstInitNoConstFunc(members) && result
        }
        structOrClassMembers = oldMembers
        return result
    }

    private func ChkExtendDecl(ed: ExtendDecl): Bool {
        var result = true
        for (decl in ed.members) {
            result = ChkAllDeclsByWalk(decl) && result
        }
        var hasConstConstructor = true
        if (let Some(extendedType) <- ed.extendedType) {
            if (let Some(target) <- Ty.GetDeclPtrOfTy(extendedType.GetTy())) {
                if (let Some(structDecl) <- (target as StructDecl)) {
                    hasConstConstructor = HasConstInit(structDecl.GetMemberDecls())
                } else if (let Some(classDecl) <- (target as ClassDecl)) {
                    hasConstConstructor = HasConstInit(classDecl.GetMemberDecls())
                }
            }
        }
        if (!hasConstConstructor) {
            result = ChkDeclNoConstInitNoConstFunc(ed.members) && result
        }
        return result
    }

    private func ChkDesugarExpr(expr: Expr, isWeak: Bool): Bool {
        if (IsStringBinaryExpr(expr)) {
            if (let Some(desugar) <- expr.desugarExpr) {
                if (let Some(callExpr) <- (desugar as CallExpr)) {
                    if (let Some(baseFunc) <- callExpr.baseFunc) {
                        if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                                var result = ChkExpr(baseExpr, isWeak)
                                for (arg in callExpr.args) {
                                    result = ChkOptionalExpr(arg.expr, isWeak) && result
                                }
                                return result
                            }
                        }
                    }
                }
            }
        }
        if (let Some(desugar) <- expr.desugarExpr) {
            if (expr.astKind == ASTKind.INC_OR_DEC_EXPR || expr.astKind == ASTKind.TRAIL_CLOSURE_EXPR) {
                return ChkExpr(desugar, isWeak)
            }
            if (desugar.astKind == ASTKind.CALL_EXPR) {
                if (let Some(callExpr) <- (desugar as CallExpr)) {
                    return ChkCallExpr(callExpr, isWeak)
                }
            }
            if (expr.astKind == ASTKind.ASSIGN_EXPR) {
                if (let Some(block) <- (desugar as Block)) {
                    return ChkDesugaredMultipleAssignment(block, isWeak)
                }
                return ChkExpr(desugar, isWeak)
            }
        }
        AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, expr)
        return false
    }

    private func ChkDesugaredMultipleAssignment(block: Block, isWeak: Bool): Bool {
        var result = true
        for (node in block.body) {
            if (let Some(decl) <- (node as Decl)) {
                result = ChkConstDecl(decl) && result
            } else if (let Some(expr) <- (node as Expr)) {
                result = ChkExpr(expr, isWeak) && result
            }
        }
        return result
    }

    private func ChkExpr(expr: Expr, isWeak: Bool): Bool {
        if (expr.TestAnyAttr(Attribute.IS_BROKEN, Attribute.HAS_BROKEN)) {
            return false
        }
        if (let Some(_) <- expr.desugarExpr) {
            return ChkDesugarExpr(expr, isWeak)
        }
        return match (expr.astKind) {
            case ASTKind.WILDCARD_EXPR => true
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(lit) <- (expr as LitConstExpr)) { ChkLitConstExpr(lit) } else { false }
            case ASTKind.RETURN_EXPR =>
                if (let Some(ret) <- (expr as ReturnExpr)) { ChkReturnExpr(ret, isWeak) } else { false }
            case ASTKind.THROW_EXPR =>
                if (let Some(throwExpr) <- (expr as ThrowExpr)) { ChkOptionalExpr(throwExpr.expr, isWeak) } else { false }
            case ASTKind.PERFORM_EXPR =>
                if (let Some(perform) <- (expr as PerformExpr)) { ChkOptionalExpr(perform.expr, isWeak) } else { false }
            case ASTKind.RESUME_EXPR =>
                if (let Some(resume) <- (expr as ResumeExpr)) { ChkResumeExpr(resume, isWeak) } else { false }
            case ASTKind.PAREN_EXPR =>
                if (let Some(paren) <- (expr as ParenExpr)) { ChkOptionalExpr(paren.expr, isWeak) } else { false }
            case ASTKind.UNARY_EXPR =>
                if (let Some(unary) <- (expr as UnaryExpr)) { ChkOptionalExpr(unary.expr, isWeak) } else { false }
            case ASTKind.IS_EXPR =>
                if (let Some(isExpr) <- (expr as IsExpr)) { ChkOptionalExpr(isExpr.leftExpr, isWeak) } else { false }
            case ASTKind.AS_EXPR =>
                if (let Some(asExpr) <- (expr as AsExpr)) { ChkOptionalExpr(asExpr.leftExpr, isWeak) } else { false }
            case ASTKind.ARRAY_LIT =>
                if (let Some(arrayLit) <- (expr as ArrayLit)) { ChkArrayLit(arrayLit, isWeak) } else { false }
            case ASTKind.TUPLE_LIT =>
                if (let Some(tupleLit) <- (expr as TupleLit)) { ChkExprChildren(tupleLit.children, isWeak) } else { false }
            case ASTKind.REF_EXPR =>
                if (let Some(refExpr) <- (expr as RefExpr)) { ChkRefExpr(refExpr, isWeak) } else { false }
            case ASTKind.CALL_EXPR =>
                if (let Some(callExpr) <- (expr as CallExpr)) { ChkCallExpr(callExpr, isWeak) } else { false }
            case ASTKind.BINARY_EXPR =>
                if (let Some(binary) <- (expr as BinaryExpr)) { ChkBinaryExpr(binary, isWeak) } else { false }
            case ASTKind.IF_EXPR =>
                if (let Some(ifExpr) <- (expr as IfExpr)) { ChkIfExpr(ifExpr, isWeak) } else { false }
            case ASTKind.MATCH_EXPR =>
                if (let Some(matchExpr) <- (expr as MatchExpr)) { ChkMatchExpr(matchExpr, isWeak) } else { false }
            case ASTKind.TRY_EXPR =>
                if (let Some(tryExpr) <- (expr as TryExpr)) { ChkTryExpr(tryExpr, isWeak) } else { false }
            case ASTKind.MEMBER_ACCESS =>
                if (let Some(member) <- (expr as MemberAccess)) { ChkMemberAccess(member, isWeak) } else { false }
            case ASTKind.SUBSCRIPT_EXPR =>
                if (let Some(subscript) <- (expr as SubscriptExpr)) { ChkSubscriptExpr(subscript, isWeak) } else { false }
            case ASTKind.LAMBDA_EXPR =>
                if (let Some(lambda) <- (expr as LambdaExpr)) { ChkLambdaExpr(lambda) } else { false }
            case ASTKind.BLOCK =>
                if (let Some(block) <- (expr as Block)) { ChkBlock(block, isWeak) } else { false }
            case ASTKind.ASSIGN_EXPR =>
                if (let Some(assign) <- (expr as AssignExpr)) { ChkAssignExpr(assign, isWeak) } else { false }
            case ASTKind.INC_OR_DEC_EXPR =>
                if (let Some(incOrDec) <- (expr as IncOrDecExpr)) { ChkIncOrDecExpr(incOrDec) } else { false }
            case _ =>
                AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, expr)
                false
        }
    }

    private func ChkOptionalExpr(expr: Option<Expr>, isWeak: Bool): Bool {
        if (let Some(value) <- expr) {
            return ChkExpr(value, isWeak)
        }
        return true
    }

    private func ChkExprChildren(children: ArrayList<Expr>, isWeak: Bool): Bool {
        var result = true
        for (child in children) {
            result = ChkExpr(child, isWeak) && result
        }
        return result
    }

    private func ChkLitConstExpr(lit: LitConstExpr): Bool {
        if (!Ty.IsTyCorrect(lit.GetTy())) {
            return false
        }
        if (IsStructArrayExpr(lit)) {
            AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, lit, message: "Array literal is not const")
            return false
        }
        if (let Some(_) <- lit.siExpr) {
            AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, lit, message: "string interpolation is not const")
            return false
        }
        return true
    }

    private func ChkReturnExpr(ret: ReturnExpr, isWeak: Bool): Bool {
        if (ContainsConstNode(inConstContext, ret)) {
            if (let Some(refFuncBody) <- ret.refFuncBody) {
                if (!ContainsConstNode(inConstContext, refFuncBody)) {
                    AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, ret)
                    return false
                }
            }
        }
        return ChkOptionalExpr(ret.expr, isWeak)
    }

    private func ChkArrayLit(arrayLit: ArrayLit, isWeak: Bool): Bool {
        if (!Ty.IsTyCorrect(arrayLit.GetTy())) {
            return false
        }
        if (IsStructArrayExpr(arrayLit)) {
            AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, arrayLit, message: "Array literal is not const")
            return false
        }
        return ChkExprChildren(arrayLit.children, isWeak)
    }

    private func ChkRefExpr(refExpr: RefExpr, isWeak: Bool): Bool {
        if (let Some(target) <- refExpr.GetTarget()) {
            if (!IsClassOrEnumConstructor(target) &&
                (refExpr.isThis || refExpr.isSuper || IsInstanceMember(target)) &&
                !ContainsConstRef(constThisOrSuper, refExpr)) {
                AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, refExpr, target: target)
                return false
            }
            if ((refExpr.isThis || refExpr.isSuper) && target.IsNominalDecl()) {
                return true
            }
            if (target.TestAttr(Attribute.ENUM_CONSTRUCTOR) || target.IsConst()) {
                return true
            }
            if (ContainsConstDecl(structOrClassMembers, target)) {
                return true
            }
            if (isWeak && ContainsConstDecl(inConstFunc, target)) {
                return true
            }
            AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, refExpr, target: target)
        }
        return false
    }

    private func ChkCallExpr(callExpr: CallExpr, isWeak: Bool): Bool {
        var result = ChkOptionalExpr(callExpr.baseFunc, isWeak)
        for (arg in callExpr.args) {
            result = ChkOptionalExpr(arg.expr, isWeak) && result
        }
        return result
    }

    private func ChkLambdaExpr(lambda: LambdaExpr): Bool {
        if (let Some(body) <- lambda.funcBody) {
            return ChkFuncBody(body)
        }
        return true
    }

    private func ChkBinaryExpr(binary: BinaryExpr, isWeak: Bool): Bool {
        var result = ChkOptionalExpr(binary.leftExpr, isWeak)
        result = ChkOptionalExpr(binary.rightExpr, isWeak) && result
        return result
    }

    private func ChkIfExpr(ifExpr: IfExpr, isWeak: Bool): Bool {
        var result = ChkOptionalExpr(ifExpr.condExpr, isWeak)
        if (let Some(thenBody) <- ifExpr.thenBody) {
            result = ChkBlock(thenBody, isWeak) && result
        }
        result = ChkOptionalExpr(ifExpr.elseBody, isWeak) && result
        return result
    }

    private func ChkMatchCase(matchCase: MatchCase, isWeak: Bool): Bool {
        if (matchCase.TestAnyAttr(Attribute.IS_BROKEN, Attribute.HAS_BROKEN)) {
            return false
        }
        var result = ChkOptionalExpr(matchCase.patternGuard, isWeak)
        if (let Some(block) <- matchCase.exprOrDecls) {
            result = ChkBlock(block, isWeak) && result
        }
        return result
    }

    private func ChkMatchCaseOther(other: MatchCaseOther, isWeak: Bool): Bool {
        if (other.TestAnyAttr(Attribute.IS_BROKEN, Attribute.HAS_BROKEN)) {
            return false
        }
        var result = ChkOptionalExpr(other.matchExpr, isWeak)
        if (let Some(block) <- other.exprOrDecls) {
            result = ChkBlock(block, isWeak) && result
        }
        return result
    }

    private func ChkMatchExpr(matchExpr: MatchExpr, isWeak: Bool): Bool {
        var result = ChkOptionalExpr(matchExpr.selector, isWeak)
        for (matchCase in matchExpr.matchCases) {
            result = ChkMatchCase(matchCase, isWeak) && result
        }
        for (other in matchExpr.matchCaseOthers) {
            result = ChkMatchCaseOther(other, isWeak) && result
        }
        return result
    }

    private func ChkTryExpr(tryExpr: TryExpr, isWeak: Bool): Bool {
        if (tryExpr.isDesugaredFromTryWithResources) {
            AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, tryExpr,
                message: "try-with-resources is not const")
            return false
        }
        var result = true
        if (let Some(block) <- tryExpr.tryBlock) {
            result = ChkBlock(block, isWeak)
        }
        for (block in tryExpr.catchBlocks) {
            result = ChkBlock(block, isWeak) && result
        }
        if (let Some(block) <- tryExpr.finallyBlock) {
            result = ChkBlock(block, isWeak) && result
        }
        return result
    }

    private func ChkMemberAccess(member: MemberAccess, isWeak: Bool): Bool {
        if (let Some(target) <- member.GetTarget()) {
            if (let Some(base) <- member.baseExpr) {
                let baseTarget = base.GetTarget()
                if (let Some(realBaseTarget) <- baseTarget) {
                    if ((realBaseTarget.astKind == ASTKind.PACKAGE_DECL || realBaseTarget.IsTypeDecl()) &&
                        ((target.IsConst() && (IsInstanceConstructor(target) || target.IsStaticOrGlobal())) ||
                            target.TestAttr(Attribute.ENUM_CONSTRUCTOR))) {
                        return true
                    }
                }
                if (ChkExpr(base, isWeak)) {
                    if (target.TestAttr(Attribute.ENUM_CONSTRUCTOR) || target.astKind == ASTKind.VAR_DECL ||
                        (target.astKind == ASTKind.FUNC_DECL && target.IsConst())) {
                        return true
                    }
                }
            }
            AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, member, target: target)
        }
        return false
    }

    private func ChkSubscriptExpr(subscript: SubscriptExpr, isWeak: Bool): Bool {
        if (let Some(base) <- subscript.baseExpr) {
            if (!Ty.IsTyCorrect(base.GetTy()) || !IsTupleOrVArrayExpr(base)) {
                AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, subscript)
                return false
            }
            var result = ChkExpr(base, isWeak)
            for (indexExpr in subscript.indexExprs) {
                result = ChkExpr(indexExpr, isWeak) && result
            }
            return result
        }
        return false
    }

    private func ChkBlock(block: Block, isWeak: Bool): Bool {
        if (block.TestAttr(Attribute.UNSAFE)) {
            AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, block, message: "unsafe block is not const")
            return false
        }
        var result = true
        for (node in block.body) {
            if (let Some(decl) <- (node as Decl)) {
                result = ChkConstDecl(decl) && result
            } else if (let Some(expr) <- (node as Expr)) {
                result = ChkExpr(expr, isWeak) && result
            }
        }
        return result
    }

    private func ChkAssignExpr(assign: AssignExpr, isWeak: Bool): Bool {
        if (inInit) {
            if (let Some(left) <- assign.leftValue) {
                if (let Some(target) <- left.GetTarget()) {
                    if (ContainsConstDecl(structOrClassMembers, target)) {
                        return ChkOptionalExpr(assign.rightExpr, isWeak)
                    }
                }
            }
        }
        AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, assign)
        return false
    }

    private func ChkIncOrDecExpr(incOrDec: IncOrDecExpr): Bool {
        if (inInit) {
            if (let Some(inner) <- incOrDec.expr) {
                if (let Some(target) <- inner.GetTarget()) {
                    if (ContainsConstDecl(structOrClassMembers, target)) {
                        return true
                    }
                }
            }
        }
        AddIssue(ConstEvaluationIssueKind.EXPECT_CONST_EXPRESSION, incOrDec)
        return false
    }

    private func ChkResumeExpr(resume: ResumeExpr, isWeak: Bool): Bool {
        var result = ChkOptionalExpr(resume.withExpr, isWeak)
        result = ChkOptionalExpr(resume.throwingExpr, isWeak) && result
        return result
    }
}

public func CheckConstEvaluation(pkg: Package): ArrayList<ConstEvaluationIssue> {
    return ConstEvaluationChecker().Check(pkg)
}

public func SelfhostPortStatus_ConstEvaluationChecker(): Bool {
    return true
}
