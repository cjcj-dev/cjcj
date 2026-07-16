package cjcj::sema.Plugin

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DEFAULT_POSITION as BasicDefaultPosition
import cjcj::option.GlobalOptions as OptionGlobalOptions
import cjcj::sema.TypeManager
import cjcj::utils.FileUtil

private let PKG_NAME_OHOS_LABELS: String = "ohos.labels"
private let APILEVEL_ANNO_NAME: String = "APILevel"
private let SINCE_IDENTIFIER: String = "since"
private let LEVEL_IDENTIFIER: String = "level"
private let SYSCAP_IDENTIFIER: String = "syscap"
private let CFG_PARAM_LEVEL_NAME: String = "APILevel_level"
private let CFG_PARAM_SYSCAP_NAME: String = "APILevel_syscap"
private let HIDE_ANNO_NAME: String = "Hide"
private let HIDE_ARG_NAME: String = "isChecked"
private let APILEVEL_MAJOR_MIN: UInt64 = 1u64
private let APILEVEL_MAJOR_MAX: UInt64 = 99u64
private let SYSCAP_DIAG_DISPLAY_LIMIT: Int64 = 3
private let IFAVAILABLE_LOWER_LIMITLEVEL: UInt32 = 19u32

private func Emit(diag: BasicDiagnosticEngine, kind: BasicDiagKindRefactor, node: Node,
    args!: Array<String> = Array<String>()): Unit {
    let builder = DiagnoseRefactor(diag, kind, node, arguments: args)
    builder.Emit()
}

private func GetModuleName(fullPackageName: String): String {
    if (let Some(dotPos) <- fullPackageName.indexOf(".")) {
        return fullPackageName[0..dotPos]
    }
    return fullPackageName
}

private func SortStrings(values: ArrayList<String>): ArrayList<String> {
    sort(values, by: { left: String, right: String =>
        if (left < right) {
            Ordering.LT
        } else if (left > right) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)
    return values
}

private func FormatSyscapsString(scopeSyscap: String, syscapSet: HashSet<String>): String {
    let rendered = ArrayList<String>()
    if (!scopeSyscap.isEmpty() && !syscapSet.contains(scopeSyscap)) {
        rendered.add(scopeSyscap)
    }
    let orderedSyscaps = ArrayList<String>()
    for (syscap in syscapSet) {
        orderedSyscaps.add(syscap)
    }
    for (syscap in SortStrings(orderedSyscaps)) {
        if (rendered.size >= SYSCAP_DIAG_DISPLAY_LIMIT) {
            break
        }
        rendered.add(syscap)
    }
    let builder = StringBuilder()
    for (idx in 0..rendered.size) {
        if (idx > 0) {
            builder.append(", ")
        }
        builder.append(rendered[idx])
    }
    let totalCandidates = orderedSyscaps.size + if (!scopeSyscap.isEmpty() && !syscapSet.contains(scopeSyscap)) {
        1
    } else {
        0
    }
    if (rendered.size >= SYSCAP_DIAG_DISPLAY_LIMIT && totalCandidates > rendered.size) {
        builder.append("...")
    }
    return builder.toString()
}

public func MarkFuncDeclMembersAsExternalWeak(fd: FuncDecl): Unit {
    if (let Some(body) <- fd.funcBody) {
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                if (let Some(defaultDecl) <- param.desugarDecl) {
                    defaultDecl.linkage = Linkage.EXTERNAL_WEAK
                }
            }
        }
    }
    if (let Some(propDecl) <- fd.propDecl) {
        propDecl.linkage = Linkage.EXTERNAL_WEAK
    }
}

public func MarkPropDeclMembersAsExternalWeak(pd: PropDecl): Unit {
    for (getter in pd.getters) {
        getter.linkage = Linkage.EXTERNAL_WEAK
    }
    for (setter in pd.setters) {
        setter.linkage = Linkage.EXTERNAL_WEAK
    }
}

public func SetLinkageAsExternalWeak(target: Decl): Unit {
    target.linkage = Linkage.EXTERNAL_WEAK
    if (let Some(funcDecl) <- (target as FuncDecl)) {
        MarkFuncDeclMembersAsExternalWeak(funcDecl)
    } else if (let Some(macroDecl) <- (target as MacroDecl)) {
        if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
            desugarDecl.linkage = Linkage.EXTERNAL_WEAK
        }
    } else if (let Some(propDecl) <- (target as PropDecl)) {
        MarkPropDeclMembersAsExternalWeak(propDecl)
    }
}

public func MarkTargetAsExternalWeak(node: Node): Unit {
    var targetOpt = node.GetTarget()
    if (let Some(callExpr) <- (node as CallExpr)) {
        if (let Some(resolved) <- callExpr.resolvedFunction) {
            targetOpt = Some(resolved)
        }
    }
    if (let Some(target) <- targetOpt) {
        SetLinkageAsExternalWeak(target)
        if (let Some(outer) <- target.outerDecl) {
            if (outer.IsNominalDecl()) {
                SetLinkageAsExternalWeak(outer)
            }
        }
    }
}

private func ParseUInt64(value: String): Option<UInt64> {
    if (value.isEmpty()) {
        return None
    }
    var out: UInt64 = 0u64
    for (byte in value.toArray()) {
        if (byte < b'0' || byte > b'9') {
            return None
        }
        out = out * 10u64 + UInt64(byte - b'0')
    }
    return Some(out)
}

public func ParseStrictLevelLiteral(lit: LitConstExpr): Option<APILevelVersion> {
    if (lit.kind == LitConstKind.INTEGER) {
        if (let Some(value) <- ParseUInt64(lit.stringValue)) {
            if (value >= APILEVEL_MAJOR_MIN && value <= APILEVEL_MAJOR_MAX) {
                return Some(APILevelVersion(UInt32(value)))
            }
        }
        return None
    }
    if (lit.kind == LitConstKind.STRING) {
        return APILevelVersion.ParseChecked(lit.stringValue, APILevelParseRule.TRIPLE_ONLY)
    }
    return None
}

public func ParseIfAvailableArgVersion(expr: Expr): Option<APILevelVersion> {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        return ParseStrictLevelLiteral(lit)
    }
    return None
}

private func LiteralFromExpr(expr: Expr): Option<LitConstExpr> {
    if (let Some(binary) <- (expr as BinaryExpr)) {
        if (let Some(right) <- binary.rightExpr) {
            return right as LitConstExpr
        }
        return None
    }
    return expr as LitConstExpr
}

public func ParseLevel(expr: Expr, annoInfo: PluginCustomAnnoInfo, diag: BasicDiagnosticEngine): Unit {
    if (let Some(lit) <- LiteralFromExpr(expr)) {
        if (lit.kind != LitConstKind.INTEGER) {
            Emit(diag, BasicDiagKindRefactor.sema_only_literal_support, expr, args: ["integer"])
            return
        }
        if (let Some(newLevel) <- ParseStrictLevelLiteral(lit)) {
            if (annoInfo.since.IsZero() || newLevel < annoInfo.since) {
                annoInfo.since = newLevel
            }
        } else {
            Emit(diag, BasicDiagKindRefactor.sema_apilevel_invalid_version_format, expr, args: [lit.stringValue])
        }
        return
    }
    Emit(diag, BasicDiagKindRefactor.sema_only_literal_support, expr, args: ["integer"])
}

public func ParseSince(expr: Expr, annoInfo: PluginCustomAnnoInfo, diag: BasicDiagnosticEngine): Unit {
    if (let Some(lit) <- LiteralFromExpr(expr)) {
        if (lit.kind != LitConstKind.STRING) {
            Emit(diag, BasicDiagKindRefactor.sema_only_literal_support, expr, args: ["string"])
            return
        }
        if (let Some(newLevel) <- APILevelVersion.ParseChecked(lit.stringValue, APILevelParseRule.MAJOR_OR_TRIPLE)) {
            if (annoInfo.since.IsZero() || newLevel < annoInfo.since) {
                annoInfo.since = newLevel
            }
        } else {
            Emit(diag, BasicDiagKindRefactor.sema_apilevel_invalid_version_format, expr, args: [lit.stringValue])
        }
        return
    }
    Emit(diag, BasicDiagKindRefactor.sema_only_literal_support, expr, args: ["string"])
}

public func ParseSysCap(expr: Expr, annoInfo: PluginCustomAnnoInfo, diag: BasicDiagnosticEngine): Unit {
    var literal: Option<LitConstExpr> = expr as LitConstExpr
    if (let Some(call) <- (expr as CallExpr)) {
        if (call.args.size == 1) {
            if (let Some(argExpr) <- call.args[0].expr) {
                literal = argExpr as LitConstExpr
            }
        }
    }
    if (let Some(lit) <- literal) {
        if (lit.kind == LitConstKind.STRING) {
            annoInfo.syscap = lit.stringValue
        } else {
            Emit(diag, BasicDiagKindRefactor.sema_only_literal_support, expr, args: ["string"])
        }
        return
    }
    Emit(diag, BasicDiagKindRefactor.sema_only_literal_support, expr, args: ["string"])
}

public func ParseCheckingHide(expr: Expr, annoInfo: PluginCustomAnnoInfo, diag: BasicDiagnosticEngine): Unit {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        if (lit.kind != LitConstKind.BOOL) {
            Emit(diag, BasicDiagKindRefactor.sema_only_literal_support, expr, args: ["Bool"])
            return
        }
        let value = lit.constNumValue.asBoolean || lit.stringValue == "true"
        let oldValue = if (let Some(current) <- annoInfo.hasHideAnno) { current } else { false }
        annoInfo.hasHideAnno = Some(oldValue || value)
        return
    }
    Emit(diag, BasicDiagKindRefactor.sema_only_literal_support, expr, args: ["Bool"])
}

private func CopyAnnoInfo(source: PluginCustomAnnoInfo): PluginCustomAnnoInfo {
    return PluginCustomAnnoInfo(since: source.since, syscap: source.syscap, hasHideAnno: source.hasHideAnno)
}

private class PluginAnnoCacheEntry {
    public var decl: Decl
    public var info: PluginCustomAnnoInfo

    public init(decl: Decl, info: PluginCustomAnnoInfo) {
        this.decl = decl
        this.info = info
    }
}

public class PluginCustomAnnoChecker {
    private var diag: BasicDiagnosticEngine
    private var typeManager: Option<TypeManager> = None
    private var globalOptions: OptionGlobalOptions = OptionGlobalOptions()
    private var curModuleName: String = ""
    private let levelCache: ArrayList<PluginAnnoCacheEntry> = ArrayList<PluginAnnoCacheEntry>()
    private var globalLevel: APILevelVersion = APILevelVersion()
    private var optionWithLevel: Bool = false
    private var optionWithSyscap: Bool = false
    private let unionSet: HashSet<String> = HashSet<String>()
    private let intersectionSet: HashSet<String> = HashSet<String>()

    public init() {
        diag = BasicDiagnosticEngine()
        ParseOption()
    }

    public init(diag: BasicDiagnosticEngine) {
        this.diag = diag
        ParseOption()
    }

    public init(diag: BasicDiagnosticEngine, globalOptions: OptionGlobalOptions) {
        this.diag = diag
        this.globalOptions = globalOptions
        ParseOption()
    }

    public init(diag: BasicDiagnosticEngine, typeManager: TypeManager) {
        this.diag = diag
        this.typeManager = typeManager
        ParseOption()
    }

    public init(diag: BasicDiagnosticEngine, typeManager: TypeManager, globalOptions: OptionGlobalOptions) {
        this.diag = diag
        this.typeManager = typeManager
        this.globalOptions = globalOptions
        ParseOption()
    }

    public func SetTypeManager(typeManager: TypeManager): Unit {
        this.typeManager = typeManager
    }

    public func IsAnnoAPILevel(annotation: Annotation, decl: Decl): Bool {
        if (decl.GetFullPackageName() == PKG_NAME_OHOS_LABELS) {
            return annotation.identifier.Val() == APILEVEL_ANNO_NAME
        }
        if (let Some(baseExpr) <- annotation.baseExpr) {
            if (let Some(target) <- baseExpr.GetTarget()) {
                if (let Some(outer) <- target.outerDecl) {
                    return target.GetFullPackageName() == PKG_NAME_OHOS_LABELS &&
                        outer.identifier.Val() == APILEVEL_ANNO_NAME
                }
                return false
            }
        }
        return annotation.identifier.Val() == APILEVEL_ANNO_NAME
    }

    public func IsAnnoHide(annotation: Annotation): Bool {
        return annotation.identifier.Val() == HIDE_ANNO_NAME
    }

    public func IsAnnoHide(annotation: Annotation, decl: Decl): Bool {
        if (decl.GetFullPackageName() == PKG_NAME_OHOS_LABELS) {
            return annotation.identifier.Val() == HIDE_ANNO_NAME
        }
        if (let Some(baseExpr) <- annotation.baseExpr) {
            if (let Some(target) <- baseExpr.GetTarget()) {
                if (let Some(outer) <- target.outerDecl) {
                    return target.GetFullPackageName() == PKG_NAME_OHOS_LABELS &&
                        outer.identifier.Val() == HIDE_ANNO_NAME
                }
                return false
            }
        }
        return annotation.identifier.Val() == HIDE_ANNO_NAME
    }

    public func ParseHideArg(annotation: Annotation, annoInfo: PluginCustomAnnoInfo): Unit {
        if (annotation.args.isEmpty()) {
            annoInfo.hasHideAnno = Some(false)
            return
        }
        let firstArg = annotation.args[0]
        if (firstArg.name.Val() != HIDE_ARG_NAME) {
            return
        }
        if (let Some(expr) <- firstArg.expr) {
            ParseCheckingHide(expr, annoInfo, diag)
        } else {
            annoInfo.hasHideAnno = Some(false)
        }
    }

    public func ParseAPILevelArgs(decl: Decl, annotation: Annotation, annoInfo: PluginCustomAnnoInfo): Unit {
        for (arg in annotation.args) {
            let argName = arg.name.Val()
            if (let Some(expr) <- arg.expr) {
                if (let Some(lit) <- (expr as LitConstExpr)) {
                    if (lit.kind == LitConstKind.INTEGER &&
                        (argName.isEmpty() || argName == SINCE_IDENTIFIER || argName == LEVEL_IDENTIFIER)) {
                        Emit(diag, BasicDiagKindRefactor.sema_apilevel_integer_form_unsupported, annotation)
                        continue
                    }
                }
                let previousSyscap = annoInfo.syscap
                if (argName == SINCE_IDENTIFIER) {
                    ParseSince(expr, annoInfo, diag)
                } else if (argName == LEVEL_IDENTIFIER) {
                    ParseLevel(expr, annoInfo, diag)
                } else if (argName == SYSCAP_IDENTIFIER) {
                    ParseSysCap(expr, annoInfo, diag)
                }
                if (!previousSyscap.isEmpty() && previousSyscap != annoInfo.syscap) {
                    Emit(diag, BasicDiagKindRefactor.sema_apilevel_multi_diff_syscap, decl)
                }
            }
        }
        if (annoInfo.since.IsZero()) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_apilevel_missing_arg,
                annotation.begin,
                arguments: ["since!: String"])
            builder.Emit()
        }
    }

    public static func MergeCachedAnnoInfo(cached: PluginCustomAnnoInfo, annoInfo: PluginCustomAnnoInfo): Unit {
        if (annoInfo.since.IsZero() || cached.since < annoInfo.since) {
            annoInfo.since = cached.since
        }
        annoInfo.syscap = cached.syscap
        if (let Some(value) <- cached.hasHideAnno) {
            annoInfo.hasHideAnno = Some(value)
        }
    }

    private func FindCachedInfo(decl: Decl): Option<PluginCustomAnnoInfo> {
        for (entry in levelCache) {
            if (SameDecl(entry.decl, decl)) {
                return Some(entry.info)
            }
        }
        return None
    }

    private func IsKnownIfAvailableArg(argName: String): Bool {
        return argName == SINCE_IDENTIFIER || argName == LEVEL_IDENTIFIER ||
            argName == SYSCAP_IDENTIFIER || argName == HIDE_ARG_NAME
    }

    private func IsPluginCustomAnnoMacroName(macroName: String): Bool {
        return macroName == APILEVEL_ANNO_NAME || macroName == HIDE_ANNO_NAME
    }

    private func ParseOption(): Unit {
        let options = globalOptions
        if (let Some(levelValue) <- options.passedWhenKeyValue.get(CFG_PARAM_LEVEL_NAME)) {
            if (levelValue == "0") {
                globalLevel = APILevelVersion()
                optionWithLevel = false
            } else {
                if (let Some(parsedLevel) <- APILevelVersion.ParseChecked(
                    levelValue, APILevelParseRule.MAJOR_OR_TRIPLE)) {
                    globalLevel = parsedLevel
                    optionWithLevel = !globalLevel.IsZero()
                } else {
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_apilevel_invalid_version_format,
                        BasicDefaultPosition,
                        arguments: [levelValue])
                    builder.Emit()
                    return
                }
            }
        }
        if (let Some(syscapsCfgPath) <- options.passedWhenKeyValue.get(CFG_PARAM_SYSCAP_NAME)) {
            let (_, jsonContent, failedReason) = FileUtil.ReadBinaryFileToBuffer(syscapsCfgPath)
            if (!failedReason.isEmpty()) {
                let builder = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.module_read_file_to_buffer_failed,
                    BasicDefaultPosition,
                    arguments: [syscapsCfgPath, failedReason])
                builder.Emit()
                return
            }
            optionWithSyscap = ParseJsonFile(jsonContent)
        }
    }

    private func ParseJsonFile(input: Array<UInt8>): Bool {
        var rootStartPos = input.size
        for (idx in 0..input.size) {
            if (input[idx] == b'{') {
                rootStartPos = idx
                break
            }
        }
        let rootPos: Array<Int64> = [rootStartPos]
        let root = ParseJsonObject(rootPos, input)
        let deviceSysCapObj = GetJsonObject(root, "deviceSysCap", 0)
        if (let None <- deviceSysCapObj) {
            return false
        }
        let dev2SyscapsMap = HashMap<String, HashSet<String>>()
        for (subObj in deviceSysCapObj.getOrThrow().pairs) {
            let syscapsOneDev = HashSet<String>()
            for (path in subObj.valueStr) {
                let (ok, buffer, failedReason) = FileUtil.ReadBinaryFileToBuffer(path)
                if (!ok || !failedReason.isEmpty()) {
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.module_read_file_to_buffer_failed,
                        BasicDefaultPosition,
                        arguments: [path, failedReason])
                    builder.Emit()
                    return false
                }
                var oneDeviceStartPos = buffer.size
                for (bufferIdx in 0..buffer.size) {
                    if (buffer[bufferIdx] == b'{') {
                        oneDeviceStartPos = bufferIdx
                        break
                    }
                }
                let oneDevicePos: Array<Int64> = [oneDeviceStartPos]
                let rootOneDevice = ParseJsonObject(oneDevicePos, buffer)
                let curSyscaps = GetJsonString(rootOneDevice, "SysCaps")
                for (syscap in curSyscaps) {
                    syscapsOneDev.add(syscap)
                }
            }
            if (!dev2SyscapsMap.contains(subObj.key)) {
                dev2SyscapsMap[subObj.key] = syscapsOneDev
            }
        }
        var lastSyscap: Option<HashSet<String>> = None
        for (devName in dev2SyscapsMap.keys()) {
            let curSyscaps = dev2SyscapsMap[devName]
            let intersection = HashSet<String>()
            if (let Some(previousSyscap) <- lastSyscap) {
                for (syscap in previousSyscap) {
                    if (curSyscaps.contains(syscap)) {
                        intersection.add(syscap)
                    }
                }
            } else {
                for (syscap in curSyscaps) {
                    intersection.add(syscap)
                }
            }
            lastSyscap = Some(intersection)
            for (syscap in curSyscaps) {
                unionSet.add(syscap)
            }
        }
        if (let Some(finalSyscap) <- lastSyscap) {
            intersectionSet.clear()
            for (syscap in finalSyscap) {
                intersectionSet.add(syscap)
            }
        }
        return true
    }

    public func CheckLevel(target: Decl, scopeAnnoInfo: PluginCustomAnnoInfo, node: Node,
        message!: String = "", reportDiag!: Bool = true): Bool {
        if (!optionWithLevel) {
            return true
        }
        let scopeLevel = if (!scopeAnnoInfo.since.IsZero()) { scopeAnnoInfo.since } else { globalLevel }
        let targetAnnoInfo = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
        Parse(target, targetAnnoInfo)
        if (targetAnnoInfo.since > scopeLevel) {
            if (reportDiag && !message.isEmpty() && !node.begin.IsZero()) {
                Emit(diag, BasicDiagKindRefactor.sema_apilevel_ref_higher, node,
                    args: [message, targetAnnoInfo.since.ToDisplayString(), scopeLevel.ToDisplayString()])
            }
            return false
        }
        return true
    }

    public func CheckSyscap(target: Decl, scopeAnnoInfo: PluginCustomAnnoInfo, node: Node,
        reportDiag!: Bool = true): Bool {
        if (!optionWithSyscap) {
            return true
        }
        let targetAnnoInfo = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
        Parse(target, targetAnnoInfo)
        let targetSyscap = targetAnnoInfo.syscap
        if (targetSyscap.isEmpty()) {
            return true
        }
        let scopeSyscap = scopeAnnoInfo.syscap
        let inUnionSet = unionSet.contains(targetSyscap) || (!scopeSyscap.isEmpty() && scopeSyscap == targetSyscap)
        if (!inUnionSet) {
            if (reportDiag && !node.begin.IsZero()) {
                let builder = DiagnoseRefactor(
                    diag,
                    BasicDiagKindRefactor.sema_apilevel_syscap_error,
                    node,
                    arguments: [targetSyscap])
                builder.AddNote("the following syscaps are supported: " + FormatSyscapsString(scopeSyscap, unionSet))
                builder.Emit()
            }
            return false
        }
        let inIntersectionSet = intersectionSet.contains(targetSyscap) ||
            (!scopeSyscap.isEmpty() && scopeSyscap == targetSyscap)
        if (!inIntersectionSet) {
            if (reportDiag && !node.begin.IsZero()) {
                let builder = DiagnoseRefactor(
                    diag,
                    BasicDiagKindRefactor.sema_apilevel_syscap_warning,
                    node,
                    arguments: [targetSyscap])
                builder.AddNote(
                    "the following syscaps are supported: " + FormatSyscapsString(scopeSyscap, intersectionSet))
                builder.Emit()
            }
            return false
        }
        return true
    }

    public func CheckCheckingHide(target: Decl, node: Node, message!: String = "", reportDiag!: Bool = true): Bool {
        let targetAnnoInfo = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
        Parse(target, targetAnnoInfo)
        if (let Some(hasHide) <- targetAnnoInfo.hasHideAnno) {
            if (hasHide && curModuleName != GetModuleName(target.GetFullPackageName())) {
                if (reportDiag && !message.isEmpty()) {
                    Emit(diag, BasicDiagKindRefactor.sema_undeclared_identifier, node, args: [message])
                }
                return false
            }
        }
        return true
    }

    public func MarkClassLikeMembersAsExternalWeakIfNeeded(target: Decl,
        scopeAnnoInfo: PluginCustomAnnoInfo): Unit {
        if (!target.IsClassLikeDecl() || !target.TestAttr(Attribute.IMPORTED)) {
            return
        }
        if (target.astKind == ASTKind.CLASS_DECL && !target.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN)) {
            return
        }
        if (let Some(classLikeDecl) <- (target as ClassLikeDecl)) {
            for (member in classLikeDecl.GetMemberDeclPtrs()) {
                if (!member.IsFuncOrProp() ||
                    member.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.FINALIZER, Attribute.ABSTRACT)) {
                    continue
                }
                let legalLevel = CheckLevel(member, scopeAnnoInfo, member, reportDiag: false)
                let legalSyscap = if (legalLevel) {
                    CheckSyscap(member, scopeAnnoInfo, member, reportDiag: false)
                } else {
                    false
                }
                if (!legalSyscap) {
                    SetLinkageAsExternalWeak(member)
                }
            }
            for (superDecl in classLikeDecl.GetAllSuperDecls()) {
                if (!SameDecl(superDecl, classLikeDecl)) {
                    MarkClassLikeMembersAsExternalWeakIfNeeded(superDecl, scopeAnnoInfo)
                }
            }
        }
    }

    public func CheckNode(node: Node, scopeAnnoInfo: PluginCustomAnnoInfo, reportDiag!: Bool = true): Bool {
        var targetOpt = node.GetTarget()
        if (let Some(callExpr) <- (node as CallExpr)) {
            if (let Some(resolvedFunction) <- callExpr.resolvedFunction) {
                if (callExpr.callKind == CallKind.CALL_SUPER_FUNCTION) {
                    return false
                }
                targetOpt = Some(resolvedFunction)
            }
        }
        if (let None <- targetOpt) {
            return true
        }
        let target = targetOpt.getOrThrow()
        var checkResult = true
        if (let Some(outer) <- target.outerDecl) {
            var identifier = outer.identifier.Val()
            if (identifier.isEmpty()) {
                identifier = target.identifier.Val()
            }
            checkResult = checkResult && CheckCheckingHide(outer, node, message: identifier, reportDiag: reportDiag)
            checkResult = checkResult && CheckLevel(outer, scopeAnnoInfo, node,
                message: identifier, reportDiag: reportDiag)
            checkResult = checkResult && CheckSyscap(outer, scopeAnnoInfo, node, reportDiag: reportDiag)
            if (!checkResult) {
                return false
            }
        }
        let targetName = target.identifier.Val()
        checkResult = checkResult && CheckCheckingHide(target, node, message: targetName, reportDiag: reportDiag)
        checkResult = checkResult && CheckLevel(target, scopeAnnoInfo, node, message: targetName, reportDiag: reportDiag)
        checkResult = checkResult && CheckSyscap(target, scopeAnnoInfo, node, reportDiag: reportDiag)
        MarkClassLikeMembersAsExternalWeakIfNeeded(target, scopeAnnoInfo)
        return checkResult
    }

    public func TryBuildIfAvailableScopeFromIfExpr(ifExpr: IfExpr,
        ifscopeAnnoInfo: PluginCustomAnnoInfo): Bool {
        if (let None <- ifExpr.condExpr) {
            return false
        }
        let condExpr = ifExpr.condExpr.getOrThrow()
        if (let Some(callExpr) <- (condExpr as CallExpr)) {
            if (let Some(resolvedFunction) <- callExpr.resolvedFunction) {
                if (resolvedFunction.identifier.Val() == "canIUse") {
                    ParseSysCap(callExpr, ifscopeAnnoInfo, diag)
                    return !ifscopeAnnoInfo.syscap.isEmpty()
                }
            }
        }
        if (let Some(binaryExpr) <- (condExpr as BinaryExpr)) {
            if (let Some(leftExpr) <- binaryExpr.leftExpr) {
                if (let Some(callExpr) <- (leftExpr as CallExpr)) {
                    if (let Some(resolvedFunction) <- callExpr.resolvedFunction) {
                        if (resolvedFunction.identifier.Val() == "sdkApiVersion") {
                            ParseSince(binaryExpr, ifscopeAnnoInfo, diag)
                            return !ifscopeAnnoInfo.since.IsZero()
                        }
                    }
                }
            }
        }
        return false
    }

    public func ParseIfAvailableLevelArg(arg: FuncArg, ifscopeAnnoInfo: PluginCustomAnnoInfo): Bool {
        if (let None <- arg.expr) {
            return false
        }
        let argExpr = arg.expr.getOrThrow()
        if (let None <- (argExpr as LitConstExpr)) {
            return false
        }
        if (let Some(parsedLevel) <- ParseIfAvailableArgVersion(argExpr)) {
            ifscopeAnnoInfo.since = parsedLevel
            return true
        }
        let literal = (argExpr as LitConstExpr).getOrThrow()
        Emit(diag, BasicDiagKindRefactor.sema_apilevel_invalid_version_format, arg, args: [literal.stringValue])
        return false
    }

    public func ValidateIfAvailableArgs(arg: FuncArg, lambda1: LambdaExpr, lambda2: LambdaExpr): Bool {
        if (let None <- lambda1.funcBody) {
            return false
        }
        if (let None <- lambda2.funcBody) {
            return false
        }
        let lambda1Body = lambda1.funcBody.getOrThrow()
        let lambda2Body = lambda2.funcBody.getOrThrow()
        if (let None <- lambda1Body.body) {
            return false
        }
        if (let None <- lambda2Body.body) {
            return false
        }
        let argName = arg.name.Val()
        if (let None <- arg.expr) {
            if (argName != SYSCAP_IDENTIFIER) {
                return false
            }
        }
        return IsKnownIfAvailableArg(argName)
    }

    public func BuildIfAvailableScope(arg: FuncArg, ifExprOpt: Option<IfExpr>,
        ifscopeAnnoInfo: PluginCustomAnnoInfo): Bool {
        let argName = arg.name.Val()
        if (argName == LEVEL_IDENTIFIER) {
            return ParseIfAvailableLevelArg(arg, ifscopeAnnoInfo)
        }
        if (argName == SYSCAP_IDENTIFIER) {
            if (let Some(ifExpr) <- ifExprOpt) {
                return TryBuildIfAvailableScopeFromIfExpr(ifExpr, ifscopeAnnoInfo)
            }
            return false
        }
        if (let None <- arg.expr) {
            return false
        }
        let argExpr = arg.expr.getOrThrow()
        if (argName == SINCE_IDENTIFIER) {
            ParseSince(argExpr, ifscopeAnnoInfo, diag)
            return true
        }
        if (argName == HIDE_ARG_NAME) {
            ParseCheckingHide(argExpr, ifscopeAnnoInfo, diag)
            return true
        }
        return false
    }

    private func WalkBranchBody(body: Block, checker: (Node) -> VisitAction): Unit {
        for (bodyNode in body.body) {
            let branchWalker = Walker(bodyNode, visitPre: checker)
            let _ = branchWalker.Walk()
        }
    }

    public func WalkIfAvailableBranches(ifExprOpt: Option<IfExpr>, lambda1: LambdaExpr, lambda2: LambdaExpr,
        ifscopeAnnoInfo: PluginCustomAnnoInfo, scopeAnnoInfo: PluginCustomAnnoInfo): Unit {
        let checkerIf = { branchNode: Node =>
            if (let Some(nestedIfAvailable) <- (branchNode as IfAvailableExpr)) {
                CheckIfAvailableExpr(nestedIfAvailable, ifscopeAnnoInfo)
                return VisitAction.SKIP_CHILDREN
            }
            let branchOk = CheckNode(branchNode, ifscopeAnnoInfo)
            if (branchOk && !CheckNode(branchNode, scopeAnnoInfo, reportDiag: false)) {
                MarkTargetAsExternalWeak(branchNode)
            }
            if (!branchOk) {
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        }
        let checkerElse = { branchNode: Node =>
            if (let Some(nestedIfAvailable) <- (branchNode as IfAvailableExpr)) {
                CheckIfAvailableExpr(nestedIfAvailable, scopeAnnoInfo)
                return VisitAction.SKIP_CHILDREN
            }
            if (!CheckNode(branchNode, scopeAnnoInfo)) {
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        }
        var thenBodyOpt: Option<Block> = None
        var elseBodyOpt: Option<Block> = None
        if (let Some(ifExpr) <- ifExprOpt) {
            thenBodyOpt = ifExpr.thenBody
            if (let Some(elseExpr) <- ifExpr.elseBody) {
                elseBodyOpt = elseExpr as Block
            }
        }
        if (let None <- thenBodyOpt) {
            if (let Some(lambdaBody1) <- lambda1.funcBody) {
                thenBodyOpt = lambdaBody1.body
            }
        }
        if (let None <- elseBodyOpt) {
            if (let Some(lambdaBody2) <- lambda2.funcBody) {
                elseBodyOpt = lambdaBody2.body
            }
        }
        if (let Some(thenBody) <- thenBodyOpt) {
            WalkBranchBody(thenBody, checkerIf)
        }
        if (let Some(elseBody) <- elseBodyOpt) {
            WalkBranchBody(elseBody, checkerElse)
        }
    }

    public func CheckIfAvailableExpr(ifAvailable: IfAvailableExpr, scopeAnnoInfo: PluginCustomAnnoInfo): Unit {
        if (let None <- ifAvailable.GetArg()) {
            return
        }
        if (let None <- ifAvailable.GetLambda1()) {
            return
        }
        if (let None <- ifAvailable.GetLambda2()) {
            return
        }
        let arg = ifAvailable.GetArg().getOrThrow()
        let lambda1 = ifAvailable.GetLambda1().getOrThrow()
        let lambda2 = ifAvailable.GetLambda2().getOrThrow()
        if (!ValidateIfAvailableArgs(arg, lambda1, lambda2)) {
            return
        }
        let ifExprOpt = ifAvailable.desugarExpr as IfExpr
        let ifscopeAnnoInfo = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
        if (!BuildIfAvailableScope(arg, ifExprOpt, ifscopeAnnoInfo)) {
            return
        }
        if (!ifscopeAnnoInfo.since.IsZero() &&
            ifscopeAnnoInfo.since < APILevelVersion(IFAVAILABLE_LOWER_LIMITLEVEL)) {
            Emit(diag, BasicDiagKindRefactor.sema_ifavailable_level_limit, arg)
            return
        }
        WalkIfAvailableBranches(ifExprOpt, lambda1, lambda2, ifscopeAnnoInfo, scopeAnnoInfo)
    }

    public func CheckAnnoBeforeMacro(pkg: Package): Unit {
        for (file in pkg.files) {
            for (macroNode in file.originalMacroCallNodes) {
                let macroWalker = Walker(macroNode, visitPre: { node: Node =>
                    if (node.astKind != ASTKind.MACRO_EXPAND_DECL) {
                        return VisitAction.WALK_CHILDREN
                    }
                    let macroExpand = (node as MacroExpandDecl).getOrThrow()
                    if (!IsPluginCustomAnnoMacroName(macroExpand.identifier.Val())) {
                        return VisitAction.WALK_CHILDREN
                    }
                    if (let Some(subDecl) <- macroExpand.invocation.decl) {
                        if (let Some(subMacroExpand) <- (subDecl as MacroExpandDecl)) {
                            if (!IsPluginCustomAnnoMacroName(subMacroExpand.identifier.Val())) {
                                let builder = diag.DiagnoseRefactor(
                                    BasicDiagKindRefactor.sema_hide_must_at_end,
                                    macroExpand.begin,
                                    arguments: [macroExpand.identifier.Val()])
                                builder.Emit()
                                return VisitAction.SKIP_CHILDREN
                            }
                        }
                    }
                    return VisitAction.WALK_CHILDREN
                })
                let _ = macroWalker.Walk()
            }
        }
    }

    public func CheckHideOfExtendDecl(decl: Decl, annoInfo: PluginCustomAnnoInfo): Unit {
        if (decl.astKind != ASTKind.EXTEND_DECL) {
            return
        }
        let extendedDecl = Ty.GetDeclPtrOfTy(decl.GetTy())
        if (let None <- extendedDecl) {
            return
        }
        let extended = extendedDecl.getOrThrow()
        let extendedInfo = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
        Parse(extended, extendedInfo)
        if (let Some(extendedHide) <- extendedInfo.hasHideAnno) {
            if (let None <- annoInfo.hasHideAnno) {
                let builder = DiagnoseRefactor(
                    diag,
                    BasicDiagKindRefactor.sema_hide_missing_hide,
                    decl)
                AddNote(builder, extended, "the extended declaration is marked with '@!Hide'")
                builder.Emit()
            } else if (let Some(currentHide) <- annoInfo.hasHideAnno) {
                if (extendedHide && !currentHide) {
                    let value = if (currentHide) { "true" } else { "false" }
                    let builder = DiagnoseRefactor(
                        diag,
                        BasicDiagKindRefactor.sema_hide_diff_param,
                        decl,
                        arguments: [value])
                    AddNote(builder, extended, "should be same with")
                    builder.Emit()
                }
            }
        }
        if (let None <- annoInfo.hasHideAnno) {
            return
        }
        let requiredHide = annoInfo.hasHideAnno.getOrThrow()
        for (member in decl.GetMemberDeclPtrs()) {
            let memberInfo = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
            Parse(member, memberInfo)
            if (let Some(memberHide) <- memberInfo.hasHideAnno) {
                if (memberHide != requiredHide) {
                    let value = if (memberHide) { "true" } else { "false" }
                    let builder = DiagnoseRefactor(
                        diag,
                        BasicDiagKindRefactor.sema_hide_diff_param,
                        member,
                        arguments: [value])
                    AddNote(builder, decl, "should be same with")
                    builder.Emit()
                }
            }
        }
    }

    public func CheckHideOfOverrideFunction(decl: Decl, annoInfo: PluginCustomAnnoInfo): Unit {
        if (decl.astKind != ASTKind.FUNC_DECL) {
            return
        }
        if (let None <- decl.outerDecl) {
            return
        }
        if (let None <- typeManager) {
            return
        }
        let fd = (decl as FuncDecl).getOrThrow()
        var functionWithHide = annoInfo.hasHideAnno
        if (let None <- functionWithHide) {
            let outerInfo = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
            Parse(decl.outerDecl.getOrThrow(), outerInfo)
            if (let Some(outerHide) <- outerInfo.hasHideAnno) {
                functionWithHide = Some(outerHide)
            }
        }

        let manager = typeManager.getOrThrow()
        let overriddenFdOpt = manager.GetTopOverriddenFuncDecl(Some(fd))
        if (let None <- overriddenFdOpt) {
            return
        }
        let overriddenFd = overriddenFdOpt.getOrThrow()
        let overriddenInfo = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
        Parse(overriddenFd, overriddenInfo)
        var overriddenFdWithHide = overriddenInfo.hasHideAnno
        if (let None <- overriddenFdWithHide) {
            if (let Some(overriddenOuter) <- overriddenFd.outerDecl) {
                let outerInfo = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
                Parse(overriddenOuter, outerInfo)
                if (let Some(outerHide) <- outerInfo.hasHideAnno) {
                    overriddenFdWithHide = Some(outerHide)
                }
            }
        }

        if (let Some(currentHide) <- functionWithHide) {
            if (let None <- overriddenFdWithHide) {
                let builder = DiagnoseRefactor(
                    diag,
                    BasicDiagKindRefactor.sema_hide_missing_hide,
                    overriddenFd)
                AddNote(builder, fd, "the override function is marked with '@!Hide'")
                builder.Emit()
            } else {
                let overriddenHide = overriddenFdWithHide.getOrThrow()
                if (currentHide != overriddenHide) {
                    let value = if (currentHide) { "true" } else { "false" }
                    let builder = DiagnoseRefactor(
                        diag,
                        BasicDiagKindRefactor.sema_hide_diff_param,
                        decl,
                        arguments: [value])
                    AddNote(builder, overriddenFd, "should be same with")
                    builder.Emit()
                }
            }
        }
    }

    public func ProcessOneAnnotation(decl: Decl, annotation: Annotation, hideSeen: BoolBox,
        annoInfo: PluginCustomAnnoInfo): Unit {
        if (IsAnnoAPILevel(annotation, decl)) {
            ParseAPILevelArgs(decl, annotation, annoInfo)
            return
        }
        if (IsAnnoHide(annotation, decl)) {
            if (hideSeen.value) {
                Emit(diag, BasicDiagKindRefactor.sema_hide_multi_annotation, decl)
                return
            }
            hideSeen.value = true
            if (let Some(param) <- (decl as FuncParam)) {
                if (!param.isMemberParam) {
                    Emit(diag, BasicDiagKindRefactor.sema_hide_at_func_param, decl)
                    return
                }
            }
            if (!annotation.isCompileTimeVisible) {
                Emit(diag, BasicDiagKindRefactor.sema_hide_compile_time_invisible, annotation)
            }
            ParseHideArg(annotation, annoInfo)
        }
    }

    public func Parse(decl: Decl, annoInfo: PluginCustomAnnoInfo): Unit {
        if (let Some(cached) <- FindCachedInfo(decl)) {
            PluginCustomAnnoChecker.MergeCachedAnnoInfo(cached, annoInfo)
            return
        }
        let hideSeen = BoolBox(false)
        for (annotation in decl.annotations) {
            ProcessOneAnnotation(decl, annotation, hideSeen, annoInfo)
        }
        levelCache.add(PluginAnnoCacheEntry(decl, CopyAnnoInfo(annoInfo)))
        CheckHideOfExtendDecl(decl, annoInfo)
        CheckHideOfOverrideFunction(decl, annoInfo)
    }

    public func Check(pkg: Package): Unit {
        curModuleName = GetModuleName(pkg.fullPackageName)
        CheckAnnoBeforeMacro(pkg)
        let scopeDecl = ArrayList<Decl>()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(decl) <- (node as Decl)) {
                if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL) {
                    return VisitAction.SKIP_CHILDREN
                }
                let info = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
                Parse(decl, info)
                scopeDecl.add(decl)
                return VisitAction.WALK_CHILDREN
            }
            let scopeAnnoInfo = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
            for (offset in 0..scopeDecl.size) {
                let scopeIdx = scopeDecl.size - 1 - offset
                Parse(scopeDecl[scopeIdx], scopeAnnoInfo)
            }
            if (let Some(ifAvailable) <- (node as IfAvailableExpr)) {
                if (scopeAnnoInfo.since.IsZero()) {
                    scopeAnnoInfo.since = globalLevel
                }
                CheckIfAvailableExpr(ifAvailable, scopeAnnoInfo)
                return VisitAction.SKIP_CHILDREN
            }
            if (!CheckNode(node, scopeAnnoInfo)) {
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        }, visitPost: { node: Node =>
            if (let Some(decl) <- (node as Decl)) {
                if (!scopeDecl.isEmpty() && SameDecl(scopeDecl[scopeDecl.size - 1], decl)) {
                    scopeDecl.remove(at: scopeDecl.size - 1)
                }
            }
            return VisitAction.KEEP_DECISION
        })
        let _ = walker.Walk()
    }
}

public class BoolBox {
    public var value: Bool
    public init(value: Bool) {
        this.value = value
    }
}
