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
import cjcj::utils.{DynamicCast, EraseIf as UtilsEraseIf}
import std.collection.*

let BACKEND_STR: String = "backend"
let ARCH_STR: String = "arch"
let OS_STR: String = "os"
let CJC_VERSION_STR: String = "cjc_version"
let DEBUG_STR: String = "debug"
let TEST_STR: String = "test"
let ENV_STR: String = "env"
let CONDITION_TRUE: String = "1"

private class VersionInfo {
    public var major: UInt32 = 0u32
    public var minor: UInt32 = 0u32
    public var patch: UInt32 = 0u32
    public var isValid: Bool = false

    public init() {}

    public init(major: UInt32, minor: UInt32, patch: UInt32) {
        this.major = major
        this.minor = minor
        this.patch = patch
        isValid = true
    }
}

class ConditionalCompilationImpl {
    private var backendType: BackendType = BackendType.CJNATIVE
    private var triple: TripleInfo = TripleInfo()
    private var cjcVersionInfo: VersionInfo = VersionInfo()
    private var debug: Bool = false
    private var test: Bool = false
    private let diag: BasicDiagnosticEngine
    private let passedCondition: HashMap<String, String> = HashMap<String, String>()

    public init(config: ConditionalCompilationConfig) {
        backendType = config.backendType
        triple = CopyTripleInfo(config.target)
        cjcVersionInfo = ParseVersion(config.cjcVersion)
        debug = config.debug
        test = config.test
        diag = config.diag
        for ((key, value) in config.passedCondition) {
            passedCondition.add(key, value)
        }
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
        return cjcVersionInfo.major.toString() + "." + cjcVersionInfo.minor.toString() + "." +
            cjcVersionInfo.patch.toString()
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
        if (target == ARCH_STR) { return Some(GetArchType()) }
        if (target == BACKEND_STR) { return Some(GetBackendType()) }
        if (target == CJC_VERSION_STR) { return Some(GetCJCVersion()) }
        if (target == DEBUG_STR) { return Some(GetDebug()) }
        if (target == ENV_STR) { return Some(GetEnv()) }
        if (target == TEST_STR) { return Some(GetTest()) }
        if (target == OS_STR) { return Some(GetOSType()) }
        return GetUserDefinedInfoByName(target)
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
        let left = EvalConditionExpr(be.leftExpr.getOrThrow())
        let right = EvalConditionExpr(be.rightExpr.getOrThrow())
        if (be.op == TokenKind.AND) {
            return left && right
        } else {
            return left || right
        }
    }

    private func EvalJudgeBinaryExpr(be: BinaryExpr): Bool {
        if (be.leftExpr.isNone() || be.rightExpr.isNone()) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin).Emit()
            return false
        }
        let leftExpr = be.leftExpr.getOrThrow()
        let rightExpr = be.rightExpr.getOrThrow()
        if (leftExpr.astKind != ASTKind.REF_EXPR) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, be.begin).Emit()
            return false
        }
        if (rightExpr.astKind != ASTKind.LIT_CONST_EXPR) {
            diag.DiagnoseRefactor(
                BasicDiagKindRefactor.conditional_compilation_invalid_condition_value, rightExpr.begin).Emit()
            return false
        }
        let right = (rightExpr as LitConstExpr).getOrThrow()
        if (right.kind != LitConstKind.STRING || right.siExpr.isSome()) {
            diag.DiagnoseRefactor(
                BasicDiagKindRefactor.conditional_compilation_invalid_condition_value, rightExpr.begin).Emit()
            return false
        }
        let left = (leftExpr as RefExpr).getOrThrow()
        let conditionStr = left.ref.identifier.Val()
        if (!ConditionCheck(conditionStr, be.begin, right.stringValue)) {
            return false
        }
        let relatedInfo = GetRelatedInfo(conditionStr)
        if (relatedInfo.isNone()) {
            return false
        }
        if (!ConditionSupportsOp(conditionStr, be.op)) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_not_support_op,
                be.begin, arguments: [conditionStr, TokenKindText(be.op)]).Emit()
            return false
        }
        if (conditionStr == CJC_VERSION_STR) {
            let rightVersion = ParseVersion(right.stringValue)
            if (!rightVersion.isValid) {
                diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.conditional_compilation_not_support_cjc_version_format, be.begin).Emit()
                return false
            }
            return EvalVersion(be, cjcVersionInfo, rightVersion)
        }
        return Eval(be, relatedInfo.getOrThrow(), right.stringValue)
    }

    private func EvalParenExpr(pe: ParenExpr): Bool {
        if (let Some(expr) <- pe.expr) {
            return EvalConditionExpr(expr)
        }
        return false
    }

    private func EvalUnaryExpr(ue: UnaryExpr): Bool {
        if (ue.expr.isNone() || ue.expr.getOrThrow().astKind != ASTKind.REF_EXPR) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, ue.begin).Emit()
            return false
        }
        let conditionExpr = (ue.expr.getOrThrow() as RefExpr).getOrThrow()
        let name = conditionExpr.ref.identifier.Val()
        if (name != DEBUG_STR && name != TEST_STR) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, ue.begin).Emit()
            return false
        }
        if (ue.op != TokenKind.NOT) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, ue.begin)
            builder.AddNote("debug and test builtin conditions only support the logic ! operator")
            builder.Emit()
            return false
        }
        if (let Some(relatedInfo) <- GetRelatedInfo(name)) {
            return relatedInfo != CONDITION_TRUE
        }
        return false
    }

    private func EvalRefExpr(re: RefExpr): Bool {
        let name = re.ref.identifier.Val()
        if (name != DEBUG_STR && name != TEST_STR) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_invalid_condition_expr, re.begin).Emit()
            return false
        }
        if (let Some(relatedInfo) <- GetRelatedInfo(name)) {
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

    private func EvalVersion(expr: BinaryExpr, left: VersionInfo, right: VersionInfo): Bool {
        let cmp = CompareVersion(left, right)
        match (expr.op) {
            case TokenKind.EQUAL => return cmp == 0
            case TokenKind.NOTEQ => return cmp != 0
            case TokenKind.GT => return cmp > 0
            case TokenKind.LT => return cmp < 0
            case TokenKind.GE => return cmp >= 0
            case TokenKind.LE => return cmp <= 0
            case _ => return false
        }
    }

    private func ConditionCheck(conditionStr: String, begin: Position, right: String): Bool {
        let isBuiltin = IsTargetCondition(conditionStr)
        let isUserDefined = !isBuiltin && passedCondition.contains(conditionStr)
        if (!isBuiltin && !isUserDefined) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.conditional_compilation_not_support_this_condition,
                begin, arguments: [conditionStr]).Emit()
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
                evalResult[0] = EvalConditionExpr(condExpr)
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
                evalResult[0] = EvalConditionExpr(condExpr)
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
                evalResult[0] = EvalConditionExpr(condExpr)
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

private func ParseVersionNumber(version: String, begin: Int64, end: Int64): Option<UInt32> {
    if (begin == end) {
        return None
    }
    var value = 0u32
    var idx = begin
    while (idx < end) {
        value = value * 10u32 + UInt32(version[idx] - b'0')
        if (value > 99u32) {
            return None
        }
        idx++
    }
    return Some(value)
}

// Parse the first major.minor.patch sequence and ignore a following prerelease suffix.
private func ParseVersion(version: String): VersionInfo {
    var searchBegin: Int64 = 0
    while (searchBegin < version.size) {
        while (searchBegin < version.size && (version[searchBegin] < b'0' || version[searchBegin] > b'9')) {
            searchBegin++
        }
        let majorBegin = searchBegin
        var majorEnd = majorBegin
        while (majorEnd < version.size && version[majorEnd] >= b'0' && version[majorEnd] <= b'9') {
            majorEnd++
        }
        if (majorEnd >= version.size || version[majorEnd] != b'.') {
            searchBegin = majorEnd
            continue
        }
        let minorBegin = majorEnd + 1
        var minorEnd = minorBegin
        while (minorEnd < version.size && version[minorEnd] >= b'0' && version[minorEnd] <= b'9') {
            minorEnd++
        }
        if (minorBegin == minorEnd || minorEnd >= version.size || version[minorEnd] != b'.') {
            searchBegin = majorEnd + 1
            continue
        }
        let patchBegin = minorEnd + 1
        var patchEnd = patchBegin
        while (patchEnd < version.size && version[patchEnd] >= b'0' && version[patchEnd] <= b'9') {
            patchEnd++
        }
        if (patchBegin == patchEnd) {
            searchBegin = minorEnd + 1
            continue
        }
        if (let Some(major) <- ParseVersionNumber(version, majorBegin, majorEnd)) {
            if (let Some(minor) <- ParseVersionNumber(version, minorBegin, minorEnd)) {
                if (let Some(patch) <- ParseVersionNumber(version, patchBegin, patchEnd)) {
                    return VersionInfo(major, minor, patch)
                }
            }
        }
        return VersionInfo()
    }
    return VersionInfo()
}

private func CompareVersion(left: VersionInfo, right: VersionInfo): Int64 {
    if (left.major != right.major) {
        return if (left.major < right.major) { -1 } else { 1 }
    }
    if (left.minor != right.minor) {
        return if (left.minor < right.minor) { -1 } else { 1 }
    }
    if (left.patch != right.patch) {
        return if (left.patch < right.patch) { -1 } else { 1 }
    }
    return 0
}
