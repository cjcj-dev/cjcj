package cangjie_compiler::chir

import std.collection.*
import cangjie_compiler::basic.DiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Linkage as BasicLinkage
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::basic.WarnGroup
import cangjie_compiler::basic.WarnGroupIndex
import cangjie_compiler::basic.WarningOptionMgr
import cangjie_compiler::option.{CompileTarget, GlobalOptions, OutputMode}
import cangjie_compiler::utils.{ANNOTATION_VAR_POSTFIX, CJC_ABORT, InternalError, OverflowStrategy,
    REFLECT_PACKAGE_NAME}

private let STD_CORE_FUTURE_MANGLED_NAME: String = "_CNat6Future"
private let USER_MAIN_MANGLED_NAME: String = "user.main"

public func ShouldReportUnusedCodeWarnings(): Bool {
    return !WarningOptionMgr.GetInstance().IsSuppressed(UInt64(WarnGroupIndex(WarnGroup.UNUSED)))
}

public class DeadCodeElimination {
    private let builder: CHIRBuilder
    private var diag: Option<BasicDiagnosticEngine> = None
    private var curPkg: Option<Package> = None
    private var curPkgName: String = ""
    private let crossPackageCache: HashMap<UInt64, Bool> = HashMap<UInt64, Bool>()

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public init(builder: CHIRBuilder, diag: BasicDiagnosticEngine, curPkg: Package) {
        this.builder = builder
        this.diag = Some(diag)
        this.curPkg = Some(curPkg)
        curPkgName = curPkg.GetName()
    }

    public func RunOnPackage(pkg: Package): Int64 {
        var removed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            removed += RunOnFunction(fn)
        }
        return removed
    }

    public func RunOnFunction(fn: Function): Int64 {
        var removed: Int64 = 0
        if (let Some(body) <- fn.GetBody()) {
            var passRemoved: Int64 = -1
            while (passRemoved != 0) {
                passRemoved = RunOnBody(body)
                removed += passRemoved
            }
        }
        return removed
    }

    public func ReportUnusedCode(pkg: Package, opts: GlobalOptions): Unit {
        let usingReflectPackage = ReflectPackageIsUsed(curPkg.getOrThrow())
        for (globalVar in pkg.GetGlobalVarsRef()) {
            if (globalVar.GetInitializerValue().isNone()) {
                continue
            }
            ReportUnusedGlobalVar(globalVar)
        }

        for (fn in pkg.GetGlobalFunctionsRef()) {
            if (fn.GetBody().isNone()) {
                continue
            }
            ReportUnusedFunc(fn, opts, usingReflectPackage)
            let isCommonFunctionWithoutBody = fn.TestAttr(Attribute.SKIP_ANALYSIS)
            if (isCommonFunctionWithoutBody) {
                continue
            }
            ReportUnusedCodeInFunc(fn.GetBody().getOrThrow(), opts)
        }
    }

    private func TryReportUnusedOnExpr(expr: Expression, opts: GlobalOptions, blockUsed: Bool): Unit {
        let kind = expr.GetExprKind()
        if (kind == ExprKind.DEBUGEXPR) {
            ReportUnusedLocalVariable(expr, opts.enableCompileDebug)
        } else if (blockUsed) {
            ReportUnusedExpression(expr)
        }
        if (kind == ExprKind.LAMBDA) {
            ReportUnusedCodeInFunc((expr as Lambda).getOrThrow().GetBody().getOrThrow(), opts)
        }
    }

    private func IsCrossPackageCached(pos: BasicPosition): Bool {
        if (let Some(found) <- crossPackageCache.get(pos.fileID)) {
            return found
        }
        let result = IsCrossPackage(pos, curPkgName, diag.getOrThrow())
        crossPackageCache[pos.fileID] = result
        return result
    }

    private func ReportUnusedCodeInFunc(body: BlockGroup, opts: GlobalOptions): Unit {
        for (block in body.GetBlocksRef()) {
            let blockUsed = !CheckUselessBlock(block)
            for (expr in block.GetExpressionsRef()) {
                TryReportUnusedOnExpr(expr, opts, blockUsed)
            }
        }
    }

    private func ReportUnusedFunc(fn: Function, opts: GlobalOptions, usingReflectPackage: Bool): Unit {
        if (fn.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) {
            return
        }

        if (fn.TestAttr(Attribute.GENERIC_INSTANTIATED) || fn.TestAttr(Attribute.GENERIC)) {
            return
        }

        if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) {
            if (parentDef.TestAttr(Attribute.GENERIC_INSTANTIATED) || parentDef.TestAttr(Attribute.GENERIC)) {
                return
            }
        }

        for (param in fn.GetParams()) {
            if (!param.GetType().getOrThrow().IsNothing()) {
                continue
            }
            let expr = param.GetDebugExpr()
            if (expr.isNone()) {
                continue
            }
            let nodeRange = GetDebugPos(expr.getOrThrow())
            if (nodeRange[0] && !IsCrossPackageCached(nodeRange[1].begin)) {
                diag.getOrThrow().DiagnoseRefactor(DiagKindRefactor.chir_dce_unreachable_function,
                    nodeRange[1]).Emit()
            }
            continue
        }
        let funcKind = fn.GetFuncKind()
        if (funcKind == FuncKind.DEFAULT_PARAMETER_FUNC || funcKind == FuncKind.FINALIZER) {
            return
        }
        if (!fn.TestAttr(Attribute.COMPILER_ADD) && CheckUselessFunc(fn, opts, usingReflectPackage)) {
            let ident = GetFuncIdent(fn)
            let debugPos = GetDebugPos(fn)
            if (ident == "main") {
                DiagUnusedCode(debugPos, DiagKindRefactor.chir_dce_unused_function_main)
            } else {
                DiagUnusedCode(debugPos, DiagKindRefactor.chir_dce_unused_function, ident)
            }
        }
    }

    private func ReportUnusedGlobalVar(globalVar: GlobalVar): Unit {
        if (IsExternalDecl(globalVar)) {
            return
        }
        if (globalVar.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) {
            return
        }
        let gvUsers = globalVar.GetUsersRef()
        if (globalVar.TestAttr(Attribute.CONST) || globalVar.TestAttr(Attribute.READONLY)) {
            if (gvUsers.isEmpty()) {
                DiagUnusedCode(GetDebugPos(globalVar), DiagKindRefactor.chir_dce_unused_variable,
                    globalVar.GetSrcCodeIdentifier())
            }
        }
        if (gvUsers.size == 1 && gvUsers[0].GetExprKind() == ExprKind.STORE) {
            DiagUnusedCode(GetDebugPos(globalVar), DiagKindRefactor.chir_dce_unused_variable,
                globalVar.GetSrcCodeIdentifier())
            return
        }
    }

    private func DiagUnusedVariableForParam(expr: Debug, users: ArrayList<Expression>): Unit {
        let operand = expr.GetOperand(0)
        if (operand.GetSrcCodeIdentifier() == "_") {
            return
        }
        if (CheckOneUsers(users)) {
            DiagUnusedVariable(expr)
        }
    }

    private func DiagUnusedVariableForLocalVar(expr: Debug, isDebug: Bool, users: ArrayList<Expression>): Unit {
        let operand = expr.GetOperand(0)
        let localOperand = (operand as LocalVar).getOrThrow()
        let debugExprIsSelf = if (let Some(debugExpr) <- localOperand.GetDebugExpr()) {
            refEq(debugExpr, expr)
        } else {
            false
        }
        if (!expr.GetResult().getOrThrow().TestAttr(Attribute.READONLY)) {
            if (CheckOneUsers(users) || CheckTwoUsers(users) ||
                (debugExprIsSelf && DeadCodeElimination.CheckAllUsersIsNotUse(operand, users))) {
                DiagUnusedVariable(expr)
                return
            }
        } else {
            if (isDebug && CheckTwoUsers(users)) {
                DiagUnusedVariable(expr)
            } else {
                if (debugExprIsSelf && DeadCodeElimination.CheckAllUsersIsNotUse(operand, users)) {
                    DiagUnusedVariable(expr)
                }
            }
        }
    }

    private func DiagUnusedVariable(expr: Debug): Unit {
        let nodeRange = GetDebugPos(expr)
        if (nodeRange[0] && !IsCrossPackageCached(nodeRange[1].begin)) {
            diag.getOrThrow().DiagnoseRefactor(DiagKindRefactor.chir_dce_unused_variable, nodeRange[1],
                expr.GetSrcCodeIdentifier()).Emit()
        }
    }

    private func ReportUnusedLocalVariable(expr: Expression, isDebug: Bool): Unit {
        let kind = expr.GetExprKind()
        if (kind != ExprKind.DEBUGEXPR) {
            return
        }
        let debugExpr = (expr as Debug).getOrThrow()
        let operand = debugExpr.GetOperand(0)
        if (operand.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING ||
            debugExpr.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) {
            return
        }
        if (operand.GetType().getOrThrow().IsVArray()) {
            return
        }
        let users = operand.GetUsersRef()
        if (operand.IsParameter()) {
            DiagUnusedVariableForParam(debugExpr, users)
        } else if (operand.IsLocalVar()) {
            DiagUnusedVariableForLocalVar(debugExpr, isDebug, users)
        }
    }

    private func CheckOneUsers(users: ArrayList<Expression>): Bool {
        return users.size == 1 && users[0].GetExprKind() == ExprKind.DEBUGEXPR
    }

    private func CheckTwoUsers(users: ArrayList<Expression>): Bool {
        return users.size == 2 && users[0].GetExprKind() == ExprKind.DEBUGEXPR &&
            users[1].GetExprKind() == ExprKind.STORE
    }

    private static func CheckAllUsersIsNotUse(value: Value, users: ArrayList<Expression>): Bool {
        for (user in users) {
            if (user.GetExprKind() == ExprKind.LOAD) {
                if (!user.GetResult().getOrThrow().GetUsersRef().isEmpty()) {
                    return false
                }
                continue
            }
            if (let Some(store) <- (user as Store)) {
                if (let Some(varValue) <- (store.GetLocation() as LocalVar)) {
                    if (varValue.IsRetValue()) {
                        return false
                    }
                }
                if (refEq(store.GetValue(), value)) {
                    return false
                }
                continue
            }
            if (user.GetExprKind() != ExprKind.DEBUGEXPR) {
                return false
            }
        }
        return true
    }

    private func ReportUnusedExpression(expr: Expression): Unit {
        if (expr.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) {
            return
        }
        if (let Some(result) <- expr.GetResult()) {
            if (result.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING) {
                return
            }
        }
        if (CheckUselessExpr(expr, isReportWarning: true)) {
            let res = GetDebugPos(expr)
            if (res[0]) {
                if (IsCrossPackageCached(res[1].begin)) {
                    return
                }
                if (expr.GetExprKind() == ExprKind.LAMBDA) {
                    DiagUnusedCode(res, DiagKindRefactor.chir_dce_unused_function,
                        (expr as Lambda).getOrThrow().GetSrcCodeIdentifier())
                } else if (expr.IsUnaryExpr() || expr.IsBinaryExpr() || expr.IsIntOpWithException()) {
                    let kind = if (expr.GetExprKind() == ExprKind.INT_OP_WITH_EXCEPTION) {
                        GetLiteralFromExprKind((expr as IntOpWithException).getOrThrow().GetOpKind())
                    } else {
                        GetLiteralFromExprKind(expr.GetExprKind())
                    }
                    diag.getOrThrow().DiagnoseRefactor(DiagKindRefactor.chir_dce_unused_operator, res[1],
                        kind).Emit()
                } else {
                    diag.getOrThrow().DiagnoseRefactor(DiagKindRefactor.chir_dce_unused_expression, res[1]).Emit()
                }
            }
        }
    }

    private func CheckUselessFunc(fn: Function, opts: GlobalOptions, usingReflectPackage: Bool): Bool {
        if (!fn.GetUsersRef().isEmpty()) {
            return false
        }
        if (fn.GetFuncKind() == FuncKind.ANNOFACTORY_FUNC) {
            return false
        }
        let identifier = fn.GetIdentifier()
        if (IdentifierWithoutPrefixIs(identifier, USER_MAIN_MANGLED_NAME)) {
            return false
        }
        let pkg = curPkg.getOrThrow()
        if (let Some(packageInitFunc) <- pkg.GetPackageInitFunc()) {
            if (refEq(fn, packageInitFunc)) {
                return false
            }
        }
        if (let Some(packageLiteralInitFunc) <- pkg.GetPackageLiteralInitFunc()) {
            if (refEq(fn, packageLiteralInitFunc)) {
                return false
            }
        }
        if (identifier.contains(STD_CORE_FUTURE_MANGLED_NAME)) {
            return false
        }
        if (identifier.contains(ANNOTATION_VAR_POSTFIX)) {
            return false
        }
        if (fn.GetFuncKind() == FuncKind.MAIN_ENTRY && !opts.interpreter) {
            return opts.outputMode == OutputMode.STATIC_LIB ||
                opts.outputMode == OutputMode.SHARED_LIB ||
                (opts.outputMode == OutputMode.OBJ && opts.compileTarget != CompileTarget.EXECUTABLE)
        }
        if (fn.IsCFunc() && fn.TestAttr(Attribute.PUBLIC)) {
            return false
        }
        if (fn.IsVirtualFunc()) {
            return false
        }
        if (fn.GetFuncKind() == FuncKind.CLASS_CONSTRUCTOR) {
            return false
        }
        if (fn.GetFuncKind() == FuncKind.FINALIZER) {
            return false
        }
        if (usingReflectPackage && !opts.disableReflection && fn.TestAttr(Attribute.PUBLIC) &&
            !fn.TestAttr(Attribute.NO_REFLECT_INFO)) {
            return false
        }
        if (IsExternalDecl(fn) && !opts.CompileExecutable()) {
            return false
        }
        return true
    }

    private func DiagUnusedCode(nodeRange: (Bool, BasicRange), diagKind: DiagKindRefactor): Unit {
        if (nodeRange[0] && !IsCrossPackageCached(nodeRange[1].begin)) {
            diag.getOrThrow().DiagnoseRefactor(diagKind, nodeRange[1]).Emit()
        }
    }

    private func DiagUnusedCode(nodeRange: (Bool, BasicRange), diagKind: DiagKindRefactor, arg: String): Unit {
        if (nodeRange[0] && !IsCrossPackageCached(nodeRange[1].begin)) {
            diag.getOrThrow().DiagnoseRefactor(diagKind, nodeRange[1], arg).Emit()
        }
    }

    private func GetLiteralFromExprKind(kind: ExprKind): String {
        return match (kind) {
            case ExprKind.NEG => "-"
            case ExprKind.NOT => "!"
            case ExprKind.BITNOT => "~"
            case ExprKind.ADD => "+"
            case ExprKind.SUB => "-"
            case ExprKind.MUL => "*"
            case ExprKind.DIV => "/"
            case ExprKind.MOD => "%"
            case ExprKind.EXP => "**"
            case ExprKind.LSHIFT => "<<"
            case ExprKind.RSHIFT => ">>"
            case ExprKind.BITAND => "&"
            case ExprKind.BITOR => "|"
            case ExprKind.BITXOR => "^"
            case ExprKind.LT => "<"
            case ExprKind.GT => ">"
            case ExprKind.LE => "<="
            case ExprKind.GE => ">="
            case ExprKind.EQUAL => "=="
            case ExprKind.NOTEQUAL => "!="
            case ExprKind.AND => "&&"
            case ExprKind.OR => "||"
            case _ =>
                CJC_ABORT()
                ""
        }
    }

    public func UnreachableBlockEliminationForPackage(pkg: Package, isDebug!: Bool = false): Unit {
        for (fn in pkg.GetGlobalFunctionsRef()) {
            if (fn.GetBody().isNone() || fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
            if (let Some(body) <- fn.GetBody()) {
                UnreachableBlockEliminationForFunc(body, isDebug: isDebug)
            }
        }
    }

    public func UnreachableBlockEliminationForFunc(body: BlockGroup, isDebug!: Bool = false): Unit {
        let entryBlock = body.GetEntryBlock().getOrThrow()
        let unreachable = body.GetBlocks()
        let workList = ArrayList<Block>()
        workList.add(entryBlock)
        var entryIdx: Int64 = 0
        while (entryIdx < unreachable.size) {
            if (refEq(unreachable[entryIdx], entryBlock)) {
                unreachable.remove(at: entryIdx)
                break
            }
            entryIdx++
        }

        var workIdx: Int64 = 0
        while (workIdx < workList.size) {
            let block = workList[workIdx]
            workIdx++

            for (expr in block.GetExpressionsRef()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        UnreachableBlockEliminationForFunc(lambdaBody, isDebug: isDebug)
                    }
                }
            }

            let terminator = block.GetTerminator().getOrThrow()
            var targetSucc: Option<Block> = None
            if (let Some(branch) <- (terminator as Branch)) {
                targetSucc = GetBranchTargetSucc(branch)
            } else if (let Some(multiBranch) <- (terminator as MultiBranch)) {
                targetSucc = GetMultiBranchTargetSucc(multiBranch)
            }
            if (let Some(target) <- targetSucc) {
                let cond = terminator.GetOperand(0)
                terminator.RemoveSelfFromBlock()
                if (cond.IsLocalVar() && cond.GetUsersRef().isEmpty()) {
                    let expr = (cond as LocalVar).getOrThrow().GetExpr().getOrThrow()
                    expr.RemoveSelfFromBlock()
                }
                builder.CreateGoTo(target, block)
            }

            let updatedTerminator = block.GetTerminator().getOrThrow()
            var succIdx: Int64 = 0
            while (succIdx < updatedTerminator.GetNumOfSuccessor()) {
                let successor = updatedTerminator.GetSuccessor(succIdx)
                var removed = false
                var idx: Int64 = 0
                while (idx < unreachable.size) {
                    if (refEq(unreachable[idx], successor)) {
                        unreachable.remove(at: idx)
                        removed = true
                        break
                    }
                    idx++
                }
                if (removed) {
                    workList.add(successor)
                }
                succIdx++
            }
        }

        for (block in unreachable) {
            block.RemoveSelfFromBlockGroup()
        }
    }

    public func ClearUnreachableMarkBlock(pkg: Package): Unit {
        for (fn in pkg.GetGlobalFunctionsRef()) {
            if (fn.GetBody().isNone() || fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
            if (let Some(body) <- fn.GetBody()) {
                ClearUnreachableMarkBlockForFunc(body)
            }
        }
    }

    private func RunOnBody(body: BlockGroup): Int64 {
        var removed: Int64 = 0
        for (block in body.GetBlocksRef()) {
            removed += RunOnBlock(block)
        }
        return removed
    }

    private func RunOnBlock(block: Block): Int64 {
        var removed: Int64 = 0
        let exprs = block.GetExpressionsRef()
        var idx: Int64 = 0
        while (idx < exprs.size) {
            let expr = exprs[idx]
            if (CheckUselessExpr(expr)) {
                expr.RemoveSelfFromBlock()
                removed++
            } else {
                idx++
            }
        }
        return removed
    }

    private func CheckUselessBlock(block: Block): Bool {
        return !block.IsEntry() && block.GetPredecessorsRef().isEmpty() && !block.TestAttr(Attribute.UNREACHABLE)
    }

    private func CheckUselessExpr(expr: Expression, isReportWarning!: Bool = false): Bool {
        if (let Some(result) <- expr.GetResult()) {
            if (!result.GetUsersRef().isEmpty()) {
                return false
            }
        }
        if (expr.GetExprKind() == ExprKind.INT_OP_WITH_EXCEPTION && expr.GetNeverOverflowInfo() && isReportWarning) {
            return true
        }
        if (expr.IsTerminator()) {
            return false
        }
        if (expr.GetNeverOverflowInfo()) {
            return true
        }
        let kind = expr.GetExprKind()
        match (expr.GetExprMajorKind()) {
            case ExprMajorKind.UNARY_EXPR =>
                let unary = (expr as UnaryExpression).getOrThrow()
                return kind != ExprKind.NEG || unary.GetOverflowStrategy() != OverflowStrategy.THROWING
            case ExprMajorKind.BINARY_EXPR =>
                if (kind == ExprKind.MOD || kind == ExprKind.DIV || kind == ExprKind.LSHIFT ||
                    kind == ExprKind.RSHIFT) {
                    return false
                }
                let kindIndex = ExprKindIndex(kind)
                if (kindIndex >= ExprKindIndex(ExprKind.ADD) && kindIndex <= ExprKindIndex(ExprKind.EXP)) {
                    let binary = (expr as BinaryExpression).getOrThrow()
                    return binary.GetOverflowStrategy() != OverflowStrategy.THROWING
                }
                return true
            case ExprMajorKind.MEMORY_EXPR => return kind == ExprKind.LOAD || kind == ExprKind.GET_ELEMENT_REF
            case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR => return kind == ExprKind.LAMBDA
            case ExprMajorKind.OTHERS => return kind == ExprKind.CONSTANT || kind == ExprKind.TUPLE ||
                kind == ExprKind.FIELD || kind == ExprKind.VARRAY
            case _ =>
                CJC_ABORT()
                return false
        }
    }

    private func BreakBranchConnection(block: Block): Unit {
        for (pred in block.GetPredecessors()) {
            let predTerminator = pred.GetTerminator().getOrThrow()
            if (predTerminator.GetExprKind() == ExprKind.BRANCH) {
                let oprand = predTerminator.GetOperand(0)
                let branch = (predTerminator as Branch).getOrThrow()
                if (block.nodeId != branch.GetFalseBlock().nodeId) {
                    InternalError("Unexpected branch connection")
                }
                let target = branch.GetTrueBlock()
                branch.RemoveSelfFromBlock()
                if (oprand.GetUsersRef().isEmpty()) {
                    let expr = (oprand as LocalVar).getOrThrow().GetExpr().getOrThrow()
                    expr.RemoveSelfFromBlock()
                }
                builder.CreateGoTo(target, pred)
            } else {
                let multi = (predTerminator as MultiBranch).getOrThrow()
                if (block.nodeId != multi.GetDefaultBlock().nodeId) {
                    InternalError("Unexpected multibranch connection")
                }
                multi.ReplaceSuccessor(0, multi.GetSuccessor(1))
            }
        }
    }

    private func ClearUnreachableMarkBlockForFunc(body: BlockGroup): Unit {
        for (block in body.GetBlocks()) {
            if (!block.TestAttr(Attribute.UNREACHABLE)) {
                for (expr in block.GetExpressionsRef()) {
                    if (let Some(lambdaExpr) <- (expr as Lambda)) {
                        if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                            ClearUnreachableMarkBlockForFunc(lambdaBody)
                        }
                    }
                }
                continue
            }
            BreakBranchConnection(block)
            block.RemoveSelfFromBlockGroup()
        }
    }
}

private func GetFuncIdent(fn: Function): String {
    if (fn.GetFuncKind() == FuncKind.GETTER) {
        return "get"
    } else if (fn.GetFuncKind() == FuncKind.SETTER) {
        return "set"
    }
    return fn.GetSrcCodeIdentifier()
}

private func ReflectPackageIsUsed(pkg: Package): Bool {
    for (def in pkg.GetImportedStructsRef()) {
        if (def.GetPackageName() == REFLECT_PACKAGE_NAME) {
            return true
        }
    }
    for (def in pkg.GetImportedClassesRef()) {
        if (def.GetPackageName() == REFLECT_PACKAGE_NAME) {
            return true
        }
    }
    for (def in pkg.GetImportedEnumsRef()) {
        if (def.GetPackageName() == REFLECT_PACKAGE_NAME) {
            return true
        }
    }
    for (def in pkg.GetImportedExtendsRef()) {
        if (def.GetPackageName() == REFLECT_PACKAGE_NAME) {
            return true
        }
    }
    for (fn in pkg.GetGlobalFunctionsRef()) {
        if (fn.GetBody().isSome() && fn.IsImportedFunc() && fn.GetPackageName() == REFLECT_PACKAGE_NAME) {
            return true
        }
    }
    for (globalVar in pkg.GetGlobalVarsRef()) {
        if (globalVar.GetInitializerValue().isSome() && globalVar.IsImportedVar() &&
            globalVar.GetPackageName() == REFLECT_PACKAGE_NAME) {
            return true
        }
    }
    return false
}

private func IdentifierWithoutPrefixIs(identifier: String, expected: String): Bool {
    return identifier.size == expected.size + 1 && identifier[1..identifier.size] == expected
}

private func IsExternalDecl(value: GlobalValue): Bool {
    if (value.GetLinkTypeInfo() == BasicLinkage.EXTERNAL) {
        return true
    }
    if (!value.TestAttr(Attribute.PRIVATE) && value.TestAttr(Attribute.CONST)) {
        if (value.IsGlobalVarWithInitializer()) {
            let globalVar = value.AsGlobalVar().getOrThrow()
            return !globalVar.IsLocalConst()
        }
        return true
    }
    return false
}

private func GetBranchTargetSucc(branch: Branch): Option<Block> {
    if (!branch.GetCondition().IsLocalVar()) {
        return None
    }
    let condExpr = (branch.GetCondition() as LocalVar).getOrThrow().GetExpr().getOrThrow()
    if (condExpr.GetExprKind() != ExprKind.CONSTANT) {
        return None
    }
    let constant = (condExpr as Constant).getOrThrow()
    return if (constant.GetBoolLitVal()) { branch.GetTrueBlock() } else { branch.GetFalseBlock() }
}

private func GetMultiBranchTargetSucc(branch: MultiBranch): Option<Block> {
    if (!branch.GetCondition().IsLocalVar()) {
        return None
    }
    var condExpr = (branch.GetCondition() as LocalVar).getOrThrow().GetExpr().getOrThrow()
    if (condExpr.GetExprKind() == ExprKind.TYPECAST) {
        if (!condExpr.GetOperand(0).IsLocalVar()) {
            return None
        }
        condExpr = (condExpr.GetOperand(0) as LocalVar).getOrThrow().GetExpr().getOrThrow()
    }
    if (condExpr.GetExprKind() != ExprKind.CONSTANT) {
        return None
    }
    let constant = (condExpr as Constant).getOrThrow()
    let condVal = if (constant.IsBoolLit()) {
        if (constant.GetBoolLitVal()) { 1u64 } else { 0u64 }
    } else if (constant.IsIntLit()) {
        constant.GetUnsignedIntLitVal()
    } else if (constant.IsRuneLit()) {
        UInt64(UInt32(constant.GetRuneLitVal()))
    } else {
        InternalError("Unexpected const val kind")
        0u64
    }
    let cases = branch.GetCaseVals()
    var idx: Int64 = 0
    while (idx < cases.size) {
        if (condVal == cases[idx]) {
            return branch.GetSuccessor(idx + 1)
        }
        idx++
    }
    return branch.GetDefaultBlock()
}
