package cjcj::conditional_compilation

import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.SplitString
import cjcj::option.BackendToString
import cjcj::option.BackendType
import cjcj::option.OSType
import cjcj::option.TripleInfo
import cjcj::utils.{CJC_ASSERT, DynamicCast, EraseIf as UtilsEraseIf}
import std.collection.*
import std.convert.*

let CJC_VERSION_LENGTH: Int64 = 6
let BACKEND_STR: String = "backend"
let ARCH_STR: String = "arch"
let OS_STR: String = "os"
let CJC_VERSION_STR: String = "cjc_version"
let DEBUG_STR: String = "debug"
let TEST_STR: String = "test"
let ENV_STR: String = "env"
let CONDITION_TRUE: String = "1"

class JudgeConditionInfo {
    public let conditionStr: String
    public let rightValue: String
    public let relatedInfo: Option<String>

    public init(conditionStr: String, rightValue: String, relatedInfo: Option<String>) {
        this.conditionStr = conditionStr
        this.rightValue = rightValue
        this.relatedInfo = relatedInfo
    }
}

class UnaryConditionInfo {
    public let relatedInfo: String
    public init(relatedInfo: String) {
        this.relatedInfo = relatedInfo
    }
}

class ConditionalCompilationImpl {
    private var backendType: BackendType = BackendType.CJNATIVE
    private var triple: TripleInfo = TripleInfo()
    private var cjcVersion: UInt64 = 0u64
    private var debug: Bool = false
    private var test: Bool = false
    private let diag: BasicDiagnosticEngine
    private let passedCondition: HashMap<String, String> = HashMap<String, String>()
    private let builtinConditionCache: HashMap<String, String> = HashMap<String, String>()
    private let judgeConditionCache: HashMap<String, Bool> = HashMap<String, Bool>()
    private let conditionExprCache: HashMap<String, Bool> = HashMap<String, Bool>()

    public init(config: ConditionalCompilationConfig) {
        backendType = config.backendType
        triple = CopyTripleInfo(config.target)
        cjcVersion = GetVersionUInt(config.cjcVersion)
        debug = config.debug
        test = config.test
        diag = config.diag
        for ((key, value) in config.passedCondition) {
            passedCondition.add(key, value)
        }
        InitBuiltinConditionCache()
    }

    private func InitBuiltinConditionCache(): Unit {
        builtinConditionCache.add(ARCH_STR, GetArchType())
        builtinConditionCache.add(BACKEND_STR, GetBackendType())
        builtinConditionCache.add(CJC_VERSION_STR, GetCJCVersion())
        builtinConditionCache.add(DEBUG_STR, GetDebug())
        builtinConditionCache.add(ENV_STR, GetEnv())
        builtinConditionCache.add(TEST_STR, GetTest())
        builtinConditionCache.add(OS_STR, GetOSType())
    }

    private func GetBackendType(): String {
        if (backendType == BackendType.CJNATIVE) {
            return "cjnative"
        }
        return BackendToString(backendType)
    }

    private func GetArchType(): String {
        return triple.ArchToString()
    }

    private func GetEnv(): String {
        return triple.EnvironmentToSimpleString()
    }

    private func GetOSType(): String {
        match (triple.os) {
            case OSType.DARWIN => return "macOS"
            case OSType.IOS => return "iOS"
            case OSType.WINDOWS => return "Windows"
            case OSType.LINUX => return "Linux"
            case OSType.UNKNOWN => return triple.OSToString()
        }
    }

    private func GetCJCVersion(): String {
        return RefreshVersionStr(cjcVersion.toString())
    }

    private func GetDebug(): String {
        return if (debug) { "1" } else { "0" }
    }

    private func GetTest(): String {
        return if (test) { "1" } else { "0" }
    }

    private func GetUserDefinedInfoByName(name: String): Option<String> {
        return passedCondition.get(name)
    }

    private func GetRelatedInfo(target: String): Option<String> {
        if (let Some(value) <- builtinConditionCache.get(target)) {
            return value
        }
        return GetUserDefinedInfoByName(target)
    }

    public func CheckConditionExpr(condition: Expr): Bool {
        match (condition.astKind) {
            case ASTKind.BINARY_EXPR =>
                return CheckBinaryExpr((condition as BinaryExpr).getOrThrow())
            case ASTKind.UNARY_EXPR =>
                return CheckUnaryExpr((condition as UnaryExpr).getOrThrow())
            case ASTKind.REF_EXPR =>
                return CheckRefExpr((condition as RefExpr).getOrThrow())
            case ASTKind.PAREN_EXPR =>
                return CheckParenExpr((condition as ParenExpr).getOrThrow())
            case _ =>
                diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, condition.begin).Emit()
                return false
        }
    }

    public func EvalCachedConditionExpr(condition: Expr): Bool {
        let cacheKey = MakeConditionExprCacheKey(condition)
        if (let Some(key) <- cacheKey) {
            if (let Some(cached) <- conditionExprCache.get(key)) {
                return cached
            }
        }
        let beforeErrCnt = diag.GetErrorCount()
        if (!CheckConditionExpr(condition)) {
            return false
        }
        let result = EvalConditionExpr(condition)
        if (let Some(key) <- cacheKey) {
            if (beforeErrCnt == diag.GetErrorCount()) {
                conditionExprCache.add(key, result)
            }
        }
        return result
    }

    private func EvalConditionExpr(condition: Expr): Bool {
        match (condition.astKind) {
            case ASTKind.BINARY_EXPR =>
                return EvalBinaryExpr((condition as BinaryExpr).getOrThrow())
            case ASTKind.UNARY_EXPR =>
                return EvalUnaryExpr((condition as UnaryExpr).getOrThrow())
            case ASTKind.REF_EXPR =>
                return EvalRefExpr((condition as RefExpr).getOrThrow())
            case ASTKind.PAREN_EXPR =>
                return EvalParenExpr((condition as ParenExpr).getOrThrow())
            case _ =>
                diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, condition.begin).Emit()
                return false
        }
    }

    private func EvalBinaryExpr(be: BinaryExpr): Bool {
        if (IsLogicBinaryExpr(be.op)) {
            return EvalLogicBinaryExpr(be)
        }
        if (IsJudgeBinaryExpr(be.op) || IsRangeBinaryExpr(be.op)) {
            return EvalJudgeBinaryExpr(be)
        }
        diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin).Emit()
        return false
    }

    private func EvalLogicBinaryExpr(be: BinaryExpr): Bool {
        if (be.op == TokenKind.AND) {
            return EvalConditionExpr(be.leftExpr.getOrThrow()) && EvalConditionExpr(be.rightExpr.getOrThrow())
        } else {
            return EvalConditionExpr(be.leftExpr.getOrThrow()) || EvalConditionExpr(be.rightExpr.getOrThrow())
        }
    }

    private func EvalJudgeBinaryExpr(be: BinaryExpr): Bool {
        let conditionInfo = GetJudgeConditionInfo(be)
        let cacheKey = MakeJudgeConditionCacheKey(conditionInfo.conditionStr, be.op, conditionInfo.rightValue)
        if (let Some(cached) <- judgeConditionCache.get(cacheKey)) {
            return cached
        }
        if (let Some(relatedInfo) <- conditionInfo.relatedInfo) {
            var evalRightValue = conditionInfo.rightValue
            if (conditionInfo.conditionStr == CJC_VERSION_STR) {
                evalRightValue = RefreshVersionStr(GetVersionUInt(conditionInfo.rightValue).toString())
            }
            let evalResult = Eval(be, relatedInfo, evalRightValue)
            judgeConditionCache.add(cacheKey, evalResult)
            return evalResult
        }
        return false
    }

    private func EvalParenExpr(pe: ParenExpr): Bool {
        if (let Some(expr) <- pe.expr) {
            return EvalConditionExpr(expr)
        }
        return false
    }

    private func EvalUnaryExpr(ue: UnaryExpr): Bool {
        if (let Some(info) <- CheckAndGetUnaryConditionInfo(ue)) {
            return info.relatedInfo != CONDITION_TRUE
        }
        return false
    }

    private func EvalRefExpr(re: RefExpr): Bool {
        if (let Some(relatedInfo) <- GetDebugOrTestRelatedInfo(re, re.begin)) {
            return relatedInfo == CONDITION_TRUE
        }
        return false
    }

    private func Eval(expr: BinaryExpr, left: String, right: String): Bool {
        match (expr.op) {
            case TokenKind.EQUAL => return left == right
            case TokenKind.NOTEQ => return left != right
            case TokenKind.GT => return left > right
            case TokenKind.LT => return left < right
            case TokenKind.GE => return left >= right
            case _ => return left <= right
        }
    }

    private func CheckBinaryExpr(be: BinaryExpr): Bool {
        if (be.leftExpr.isNone() || be.rightExpr.isNone()) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin).Emit()
            return false
        }
        if (IsLogicBinaryExpr(be.op)) {
            let leftValid = CheckConditionExpr(be.leftExpr.getOrThrow())
            let rightValid = CheckConditionExpr(be.rightExpr.getOrThrow())
            return leftValid && rightValid
        }
        if (IsJudgeBinaryExpr(be.op) || IsRangeBinaryExpr(be.op)) {
            return CheckJudgeConditionExpr(be)
        }
        diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin).Emit()
        return false
    }

    private func CheckParenExpr(pe: ParenExpr): Bool {
        if (let Some(expr) <- pe.expr) {
            return CheckConditionExpr(expr)
        }
        diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, pe.begin).Emit()
        return false
    }

    private func CheckUnaryExpr(ue: UnaryExpr): Bool {
        if (let Some(_) <- CheckAndGetUnaryConditionInfo(ue)) {
            return true
        }
        return false
    }

    private func CheckRefExpr(re: RefExpr): Bool {
        if (let Some(_) <- GetDebugOrTestRelatedInfo(re, re.begin)) {
            return true
        }
        return false
    }

    private func CheckJudgeConditionExpr(be: BinaryExpr): Bool {
        if (let Some(_) <- CheckAndGetJudgeConditionInfo(be)) {
            return true
        }
        return false
    }

    private func CheckJudgeBinaryExpr(be: BinaryExpr): Bool {
        if (be.leftExpr.isNone() || be.rightExpr.isNone()) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin).Emit()
            return false
        }
        let left = be.leftExpr.getOrThrow()
        let right = be.rightExpr.getOrThrow()
        if (left.astKind != ASTKind.REF_EXPR) {
            diag.DiagnoseRefactor(
                BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin).Emit()
            return false
        }
        if (right.astKind != ASTKind.LIT_CONST_EXPR) {
            diag.DiagnoseRefactor(
                BasicDiagKindRefactor.conditional_compilation_invalid_condition_value, right.begin).Emit()
            return false
        }
        let lit = (right as LitConstExpr).getOrThrow()
        if (lit.kind != LitConstKind.STRING || lit.siExpr.isSome()) {
            diag.DiagnoseRefactor(
                BasicDiagKindRefactor.conditional_compilation_invalid_condition_value, right.begin).Emit()
            return false
        }
        return true
    }

    private func GetJudgeConditionInfo(be: BinaryExpr): JudgeConditionInfo {
        let right = (be.rightExpr.getOrThrow() as LitConstExpr).getOrThrow()
        let left = (be.leftExpr.getOrThrow() as RefExpr).getOrThrow()
        let conditionStr = left.ref.identifier.Val()
        let rightValue = right.stringValue
        return JudgeConditionInfo(conditionStr, rightValue, GetRelatedInfo(conditionStr))
    }

    private func CheckAndGetJudgeConditionInfo(be: BinaryExpr): Option<JudgeConditionInfo> {
        if (!CheckJudgeBinaryExpr(be)) {
            return None
        }
        let conditionInfo = GetJudgeConditionInfo(be)
        if (!ConditionCheck(conditionInfo.conditionStr, be.begin, conditionInfo.rightValue)) {
            return None
        }
        if (conditionInfo.relatedInfo.isNone()) {
            return None
        }
        if (!CheckConditionOp(be, conditionInfo.conditionStr)) {
            return None
        }
        return conditionInfo
    }

    private func CheckAndGetUnaryConditionInfo(ue: UnaryExpr): Option<UnaryConditionInfo> {
        if (ue.expr.isNone() || ue.expr.getOrThrow().astKind != ASTKind.REF_EXPR) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, ue.begin).Emit()
            return None
        }
        if (let Some(conditionExpr) <- (ue.expr.getOrThrow() as RefExpr)) {
            if (let Some(relatedInfo) <- GetDebugOrTestRelatedInfo(conditionExpr, ue.begin)) {
                if (ue.op != TokenKind.NOT) {
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, ue.begin)
                    builder.AddNote("debug and test builtin conditions only support the logic ! operator")
                    builder.Emit()
                    return None
                }
                return UnaryConditionInfo(relatedInfo)
            }
            return None
        }
        diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, ue.begin).Emit()
        return None
    }

    private func GetDebugOrTestRelatedInfo(re: RefExpr, diagnosePos: Position): Option<String> {
        let name = re.ref.identifier.Val()
        if (name != DEBUG_STR && name != TEST_STR) {
            diag.DiagnoseRefactor(
                BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, diagnosePos).Emit()
            return None
        }
        return GetRelatedInfo(name)
    }

    private func ConditionCheck(conditionStr: String, begin: Position, right: String): Bool {
        let isBuiltin = IsTargetCondition(conditionStr)
        let isUserDefined = !isBuiltin && passedCondition.contains(conditionStr)
        if (!isBuiltin && !isUserDefined) {
            return false
        }
        if (!ConditionSupportsValue(conditionStr, right)) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_not_support_builtin_value,
                begin, arguments: [conditionStr, right, SupportedValuesText(conditionStr)]).Emit()
            return false
        }
        if (conditionStr == CJC_VERSION_STR && !IsCJCVersionLiteral(right)) {
            diag.DiagnoseRefactor(
                BasicDiagKindRefactor.conditional_compilation_not_support_cjc_version_format, begin).Emit()
            return false
        }
        return true
    }

    private func CheckConditionOp(be: BinaryExpr, conditionStr: String): Bool {
        if (!ConditionSupportsOp(conditionStr, be.op)) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_not_support_op,
                be.begin, arguments: [conditionStr, TokenKindText(be.op)]).Emit()
            return false
        }
        return true
    }

    public func HandleConditionalCompilation(root: Package): Unit {
        for (file in root.files) {
            HandleFileConditionalCompilation(file)
            if (file.hasMacro) {
                file.hasMacro = false
                let action = { curNode: Node =>
                    if (curNode.astKind == ASTKind.MACRO_EXPAND_DECL ||
                        curNode.astKind == ASTKind.MACRO_EXPAND_EXPR ||
                        curNode.astKind == ASTKind.MACRO_EXPAND_PARAM) {
                        file.hasMacro = true
                        return VisitAction.STOP_NOW
                    }
                    return VisitAction.WALK_CHILDREN
                }
                Walker(file, visitPre: action).Walk()
            }
        }
    }

    public func HandleFileConditionalCompilation(file: File): Unit {
        let pred = { node: Node =>
            if (let Some(decl) <- DynamicCast<Decl>(node)) {
                return EvalNodeCondition(decl)
            } else if (let Some(importSpec) <- DynamicCast<ImportSpec>(node)) {
                return EvalNodeCondition(importSpec)
            } else if (let Some(macroExpr) <- DynamicCast<MacroExpandExpr>(node)) {
                return EvalNodeCondition(macroExpr)
            }
            return true
        }
        let action = { curNode: Node =>
            match (curNode.astKind) {
                case ASTKind.FILE =>
                    let fileNode = (curNode as File).getOrThrow()
                    EraseConditionalIf<ImportSpec>(fileNode.imports, { node => !pred(node) })
                    EraseConditionalIf<Decl>(fileNode.decls, { node => !pred(node) })
                case ASTKind.INTERFACE_BODY =>
                    let body = (curNode as InterfaceBody).getOrThrow()
                    EraseConditionalIf<Decl>(body.decls, { node => !pred(node) })
                case ASTKind.CLASS_BODY =>
                    let body = (curNode as ClassBody).getOrThrow()
                    EraseConditionalIf<Decl>(body.decls, { node => !pred(node) })
                case ASTKind.STRUCT_BODY =>
                    let body = (curNode as StructBody).getOrThrow()
                    EraseConditionalIf<Decl>(body.decls, { node => !pred(node) })
                case ASTKind.ENUM_DECL =>
                    let enumDecl = (curNode as EnumDecl).getOrThrow()
                    EraseConditionalIf<Decl>(enumDecl.members, { node => !pred(node) })
                    EraseConditionalIf<Decl>(enumDecl.constructors, { node => !pred(node) })
                case ASTKind.EXTEND_DECL =>
                    let extendDecl = (curNode as ExtendDecl).getOrThrow()
                    EraseConditionalIf<Decl>(extendDecl.members, { node => !pred(node) })
                case ASTKind.PROP_DECL =>
                    let propDecl = (curNode as PropDecl).getOrThrow()
                    EraseConditionalIf<FuncDecl>(propDecl.setters, { node => !pred(node) })
                    EraseConditionalIf<FuncDecl>(propDecl.getters, { node => !pred(node) })
                case ASTKind.FUNC_PARAM_LIST =>
                    let paramList = (curNode as FuncParamList).getOrThrow()
                    EraseConditionalIf<FuncParam>(paramList.params, { node => !pred(node) })
                case ASTKind.BLOCK =>
                    let block = (curNode as Block).getOrThrow()
                    EraseConditionalIf<Node>(block.body, { node => !pred(node) })
                case ASTKind.MACRO_EXPAND_DECL | ASTKind.MACRO_EXPAND_EXPR | ASTKind.MACRO_EXPAND_PARAM =>
                    return VisitAction.SKIP_CHILDREN
                case _ => ()
            }
            return VisitAction.WALK_CHILDREN
        }
        Walker(file, visitPre: action).Walk()
    }

    private func EvalNodeCondition(node: Decl): Bool {
        let evalResult = ArrayList<Bool>()
        evalResult.add(true)
        UtilsEraseIf<Annotation>(node.annotations, { anno: Annotation =>
            if (anno.kind != AstAnnotationKind.WHEN) {
                return false
            }
            if (let Some(condExpr) <- anno.condExpr) {
                evalResult[0] = EvalCachedConditionExpr(condExpr)
            } else {
                diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.conditional_compilation_not_have_condition_expr, anno.begin).Emit()
            }
            return true
        })
        return evalResult[0]
    }

    private func EvalNodeCondition(node: ImportSpec): Bool {
        let evalResult = ArrayList<Bool>()
        evalResult.add(true)
        UtilsEraseIf<Annotation>(node.annotations, { anno: Annotation =>
            if (anno.kind != AstAnnotationKind.WHEN) {
                return false
            }
            if (let Some(condExpr) <- anno.condExpr) {
                evalResult[0] = EvalCachedConditionExpr(condExpr)
            } else {
                diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.conditional_compilation_not_have_condition_expr, anno.begin).Emit()
            }
            return true
        })
        return evalResult[0]
    }

    private func EvalNodeCondition(node: MacroExpandExpr): Bool {
        let evalResult = ArrayList<Bool>()
        evalResult.add(true)
        UtilsEraseIf<Annotation>(node.annotations, { anno: Annotation =>
            if (anno.kind != AstAnnotationKind.WHEN) {
                return false
            }
            if (let Some(condExpr) <- anno.condExpr) {
                evalResult[0] = EvalCachedConditionExpr(condExpr)
            } else {
                diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.conditional_compilation_not_have_condition_expr, anno.begin).Emit()
            }
            return true
        })
        return evalResult[0]
    }
}

func EraseConditionalIf<T>(container: ArrayList<T>, pred: (T) -> Bool): Unit {
    var idx: Int64 = 0
    while (idx < container.size) {
        if (pred(container[idx])) {
            container.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func IsCJCVersionLiteral(value: String): Bool {
    let parts = SplitString(value, ".")
    if (parts.size != 3) {
        return false
    }
    for (part in parts) {
        if (part.isEmpty() || part.size > 2) {
            return false
        }
        var idx: Int64 = 0
        while (idx < part.size) {
            if (part[idx] < b'0' || part[idx] > b'9') {
                return false
            }
            idx++
        }
    }
    return true
}

private func GetVersionUInt(version: String): UInt64 {
    var res = ""
    let digitSize: Int64 = 2
    for (part in SplitString(version, ".")) {
        if (part.size == digitSize) {
            res += part
        } else if (part.size == 1) {
            res += "0" + part
        }
    }
    let iRes = Int64.parse(res)
    CJC_ASSERT(iRes >= 0)
    return UInt64(iRes)
}

private func RefreshVersionStr(version: String): String {
    var out = version
    while (out.size < CJC_VERSION_LENGTH) {
        out = "0" + out
    }
    return out
}
