package cangjie_compiler::conditional_compilation

import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::option.BackendToString
import cangjie_compiler::option.BackendType
import cangjie_compiler::option.OSType
import cangjie_compiler::option.TripleInfo
import cangjie_compiler::option.TryParseUInt64
import std.collection.*

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
    private let diag: ConditionalDiagnosticReporter
    private let passedCondition: HashMap<String, String> = HashMap<String, String>()
    private let builtinConditionCache: HashMap<String, String> = HashMap<String, String>()
    private let judgeConditionCache: HashMap<String, Bool> = HashMap<String, Bool>()
    private let conditionExprCache: HashMap<String, Bool> = HashMap<String, Bool>()

    public init(config: ConditionalCompilationConfig) {
        // TODO(selfhost:ConditionalCompilation): add the C++ CompilerInstance constructor once Frontend.CompilerInstance is ported.
        backendType = config.backendType
        triple = CopyTripleInfo(config.target)
        cjcVersion = GetVersionUInt(config.cjcVersion)
        debug = config.debug
        test = config.test
        diag = ConditionalDiagnosticReporter(config.diag)
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
        if (condition.astKind == ASTKind.BINARY_EXPR) {
            if (let Some(be) <- (condition as BinaryExpr)) { return CheckBinaryExpr(be) }
        } else if (condition.astKind == ASTKind.UNARY_EXPR) {
            if (let Some(ue) <- (condition as UnaryExpr)) { return CheckUnaryExpr(ue) }
        } else if (condition.astKind == ASTKind.REF_EXPR) {
            if (let Some(re) <- (condition as RefExpr)) { return CheckRefExpr(re) }
        } else if (condition.astKind == ASTKind.PAREN_EXPR) {
            if (let Some(pe) <- (condition as ParenExpr)) { return CheckParenExpr(pe) }
        }
        diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, condition.begin)
        return false
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
        if (condition.astKind == ASTKind.BINARY_EXPR) {
            if (let Some(be) <- (condition as BinaryExpr)) { return EvalBinaryExpr(be) }
        } else if (condition.astKind == ASTKind.UNARY_EXPR) {
            if (let Some(ue) <- (condition as UnaryExpr)) { return EvalUnaryExpr(ue) }
        } else if (condition.astKind == ASTKind.REF_EXPR) {
            if (let Some(re) <- (condition as RefExpr)) { return EvalRefExpr(re) }
        } else if (condition.astKind == ASTKind.PAREN_EXPR) {
            if (let Some(pe) <- (condition as ParenExpr)) { return EvalParenExpr(pe) }
        }
        diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, condition.begin)
        return false
    }

    private func EvalBinaryExpr(be: BinaryExpr): Bool {
        if (IsLogicBinaryExpr(be.op)) {
            return EvalLogicBinaryExpr(be)
        }
        if (IsJudgeBinaryExpr(be.op) || IsRangeBinaryExpr(be.op)) {
            return EvalJudgeBinaryExpr(be)
        }
        diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin)
        return false
    }

    private func EvalLogicBinaryExpr(be: BinaryExpr): Bool {
        if (let Some(left) <- be.leftExpr) {
            if (let Some(right) <- be.rightExpr) {
                if (be.op == TokenKind.AND) {
                    return EvalConditionExpr(left) && EvalConditionExpr(right)
                }
                return EvalConditionExpr(left) || EvalConditionExpr(right)
            }
        }
        return false
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
        if (let Some(left) <- be.leftExpr) {
            if (let Some(right) <- be.rightExpr) {
                if (IsLogicBinaryExpr(be.op)) {
                    let leftValid = CheckConditionExpr(left)
                    let rightValid = CheckConditionExpr(right)
                    return leftValid && rightValid
                }
                if (IsJudgeBinaryExpr(be.op) || IsRangeBinaryExpr(be.op)) {
                    return CheckJudgeConditionExpr(be)
                }
            }
        }
        diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin)
        return false
    }

    private func CheckParenExpr(pe: ParenExpr): Bool {
        if (let Some(expr) <- pe.expr) {
            return CheckConditionExpr(expr)
        }
        diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, pe.begin)
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
        if (let Some(left) <- be.leftExpr) {
            if (let Some(right) <- be.rightExpr) {
                if (left.astKind != ASTKind.REF_EXPR) {
                    diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin)
                    return false
                }
                if (right.astKind != ASTKind.LIT_CONST_EXPR) {
                    diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_value, right.begin)
                    return false
                }
                if (let Some(lit) <- (right as LitConstExpr)) {
                    if (lit.kind != LitConstKind.STRING || lit.siExpr.isSome()) {
                        diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_value, right.begin)
                        return false
                    }
                    return true
                }
            }
        }
        diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin)
        return false
    }

    private func GetJudgeConditionInfo(be: BinaryExpr): JudgeConditionInfo {
        var conditionStr = ""
        var rightValue = ""
        if (let Some(left) <- be.leftExpr) {
            if (let Some(refExpr) <- (left as RefExpr)) {
                conditionStr = refExpr.ref.identifier.Val()
            }
        }
        if (let Some(right) <- be.rightExpr) {
            if (let Some(lit) <- (right as LitConstExpr)) {
                rightValue = lit.stringValue
            }
        }
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
        if (let Some(expr) <- ue.expr) {
            if (let Some(conditionExpr) <- (expr as RefExpr)) {
                if (let Some(relatedInfo) <- GetDebugOrTestRelatedInfo(conditionExpr, ue.begin)) {
                    if (ue.op != TokenKind.NOT) {
                        diag.DiagnoseWithNote(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr,
                            ue.begin, "debug and test builtin conditions only support the logic ! operator")
                        return None
                    }
                    return UnaryConditionInfo(relatedInfo)
                }
                return None
            }
        }
        diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, ue.begin)
        return None
    }

    private func GetDebugOrTestRelatedInfo(re: RefExpr, diagnosePos: Position): Option<String> {
        let name = re.ref.identifier.Val()
        if (name != DEBUG_STR && name != TEST_STR) {
            diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, diagnosePos)
            return None
        }
        return GetRelatedInfo(name)
    }

    private func ConditionCheck(conditionStr: String, begin: Position, right: String): Bool {
        let isBuiltin = IsTargetCondition(conditionStr)
        let isUserDefined = !isBuiltin && passedCondition.contains(conditionStr)
        if (!isBuiltin && !isUserDefined) {
            diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_not_support_this_condition,
                begin, args: [conditionStr])
            return false
        }
        if (!ConditionSupportsValue(conditionStr, right)) {
            diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_not_support_builtin_value,
                begin, args: [conditionStr, right, SupportedValuesText(conditionStr)])
            return false
        }
        if (conditionStr == CJC_VERSION_STR && !IsCJCVersionLiteral(right)) {
            diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_not_support_cjc_version_format, begin)
            return false
        }
        return true
    }

    private func CheckConditionOp(be: BinaryExpr, conditionStr: String): Bool {
        if (!ConditionSupportsOp(conditionStr, be.op)) {
            diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_not_support_op,
                be.begin, args: [conditionStr, TokenKindText(be.op)])
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
        let action = { curNode: Node =>
            if (curNode.astKind == ASTKind.FILE) {
                if (let Some(fileNode) <- (curNode as File)) {
                    EraseConditionalIf<ImportSpec>(fileNode.imports, { node => !EvalImportSpecCondition(node) })
                    EraseConditionalIf<Decl>(fileNode.decls, { node => !EvalDeclCondition(node) })
                }
            } else if (curNode.astKind == ASTKind.INTERFACE_BODY) {
                if (let Some(body) <- (curNode as InterfaceBody)) {
                    EraseConditionalIf<Decl>(body.decls, { node => !EvalDeclCondition(node) })
                }
            } else if (curNode.astKind == ASTKind.CLASS_BODY) {
                if (let Some(body) <- (curNode as ClassBody)) {
                    EraseConditionalIf<Decl>(body.decls, { node => !EvalDeclCondition(node) })
                }
            } else if (curNode.astKind == ASTKind.STRUCT_BODY) {
                if (let Some(body) <- (curNode as StructBody)) {
                    EraseConditionalIf<Decl>(body.decls, { node => !EvalDeclCondition(node) })
                }
            } else if (curNode.astKind == ASTKind.ENUM_DECL) {
                if (let Some(enumDecl) <- (curNode as EnumDecl)) {
                    EraseConditionalIf<Decl>(enumDecl.members, { node => !EvalDeclCondition(node) })
                    EraseConditionalIf<Decl>(enumDecl.constructors, { node => !EvalDeclCondition(node) })
                }
            } else if (curNode.astKind == ASTKind.EXTEND_DECL) {
                if (let Some(extendDecl) <- (curNode as ExtendDecl)) {
                    EraseConditionalIf<Decl>(extendDecl.members, { node => !EvalDeclCondition(node) })
                }
            } else if (curNode.astKind == ASTKind.PROP_DECL) {
                if (let Some(propDecl) <- (curNode as PropDecl)) {
                    EraseConditionalIf<FuncDecl>(propDecl.setters, { node => !EvalDeclCondition(node) })
                    EraseConditionalIf<FuncDecl>(propDecl.getters, { node => !EvalDeclCondition(node) })
                }
            } else if (curNode.astKind == ASTKind.FUNC_PARAM_LIST) {
                if (let Some(paramList) <- (curNode as FuncParamList)) {
                    EraseConditionalIf<FuncParam>(paramList.params, { node => !EvalDeclCondition(node) })
                }
            } else if (curNode.astKind == ASTKind.BLOCK) {
                if (let Some(block) <- (curNode as Block)) {
                    EraseConditionalIf<Node>(block.body, { node => !EvalBlockNodeCondition(node) })
                }
            } else if (curNode.astKind == ASTKind.MACRO_EXPAND_DECL ||
                curNode.astKind == ASTKind.MACRO_EXPAND_EXPR || curNode.astKind == ASTKind.MACRO_EXPAND_PARAM) {
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        }
        Walker(file, visitPre: action).Walk()
    }

    private func EvalDeclCondition(node: Decl): Bool {
        return EvalAnnotations(node.annotations)
    }

    private func EvalImportSpecCondition(node: ImportSpec): Bool {
        return EvalAnnotations(node.annotations)
    }

    private func EvalMacroExpandExprCondition(node: MacroExpandExpr): Bool {
        return EvalAnnotations(node.annotations)
    }

    private func EvalBlockNodeCondition(node: Node): Bool {
        if (let Some(decl) <- (node as Decl)) {
            return EvalDeclCondition(decl)
        }
        if (let Some(importSpec) <- (node as ImportSpec)) {
            return EvalImportSpecCondition(importSpec)
        }
        if (let Some(macroExpr) <- (node as MacroExpandExpr)) {
            return EvalMacroExpandExprCondition(macroExpr)
        }
        return true
    }

    private func EvalAnnotations(annotations: ArrayList<Annotation>): Bool {
        var evalResult = true
        var idx: Int64 = 0
        while (idx < annotations.size) {
            let anno = annotations[idx]
            if (anno.kind != AstAnnotationKind.WHEN) {
                idx++
                continue
            }
            if (let Some(condExpr) <- anno.condExpr) {
                evalResult = EvalCachedConditionExpr(condExpr)
            } else {
                diag.Diagnose(BasicDiagKindRefactor.conditional_compilation_not_have_condition_expr, anno.begin)
                evalResult = false
            }
            annotations.remove(at: idx)
        }
        return evalResult
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

func IsTargetCondition(name: String): Bool {
    return name == BACKEND_STR || name == ARCH_STR || name == OS_STR || name == CJC_VERSION_STR ||
        name == DEBUG_STR || name == TEST_STR || name == ENV_STR
}

func IsLogicBinaryExpr(op: TokenKind): Bool {
    return TokenKindIndex(op) >= TokenKindIndex(TokenKind.AND) && TokenKindIndex(op) <= TokenKindIndex(TokenKind.OR)
}

func IsJudgeBinaryExpr(op: TokenKind): Bool {
    return TokenKindIndex(op) >= TokenKindIndex(TokenKind.NOTEQ) &&
        TokenKindIndex(op) <= TokenKindIndex(TokenKind.EQUAL)
}

func IsRangeBinaryExpr(op: TokenKind): Bool {
    return TokenKindIndex(op) >= TokenKindIndex(TokenKind.LT) && TokenKindIndex(op) <= TokenKindIndex(TokenKind.GE)
}

func ConditionSupportsOp(conditionStr: String, op: TokenKind): Bool {
    if (conditionStr == BACKEND_STR || conditionStr == ARCH_STR || conditionStr == OS_STR || conditionStr == ENV_STR) {
        return op == TokenKind.EQUAL || op == TokenKind.NOTEQ
    }
    if (conditionStr == CJC_VERSION_STR) {
        return op == TokenKind.EQUAL || op == TokenKind.NOTEQ || op == TokenKind.GT ||
            op == TokenKind.LT || op == TokenKind.GE || op == TokenKind.LE
    }
    if (conditionStr == DEBUG_STR || conditionStr == TEST_STR) {
        return false
    }
    return true
}

func ConditionSupportsValue(conditionStr: String, right: String): Bool {
    let values = ConditionValues(conditionStr)
    if (values.isEmpty()) {
        return true
    }
    return values.contains(right)
}

func SupportedValuesText(conditionStr: String): String {
    let values = ConditionValues(conditionStr)
    var out = ""
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            out += " "
        }
        out += values[idx]
        idx++
    }
    return out
}

private func ConditionValues(conditionStr: String): Array<String> {
    if (conditionStr == BACKEND_STR) {
        return ["cjnative"]
    }
    if (conditionStr == ARCH_STR) {
        return ["x86_64", "aarch64", "arm"]
    }
    if (conditionStr == OS_STR) {
        return ["Windows", "Linux", "macOS", "iOS"]
    }
    if (conditionStr == ENV_STR) {
        return ["", "gnu", "ohos", "simulator", "android"]
    }
    return []
}

private func IsCJCVersionLiteral(value: String): Bool {
    let parts = SplitByDot(value)
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
    for (part in SplitByDot(version)) {
        if (part.size == digitSize) {
            res += part
        } else if (part.size == 1) {
            res += "0" + part
        }
    }
    let parsed = TryParseUInt64(res)
    if (parsed.hasValue) {
        return parsed.value
    }
    return 0u64
}

private func RefreshVersionStr(version: String): String {
    var out = version
    while (out.size < CJC_VERSION_LENGTH) {
        out = "0" + out
    }
    return out
}

private func SplitByDot(value: String): Array<String> {
    let parts = ArrayList<String>()
    var pos: Int64 = 0
    var foundPos = value.indexOf(".")
    while (let Some(found) <- foundPos) {
        parts.add(value[pos..found])
        pos = found + 1
        foundPos = value.indexOf(".", pos)
    }
    if (pos < value.size) {
        parts.add(value[pos..])
    } else if (pos == value.size) {
        parts.add("")
    }
    return parts.toArray()
}
