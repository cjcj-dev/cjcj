package cangjie_compiler::sema.Plugin

import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange

private let PKG_NAME_OHOS_LABELS: String = "ohos.labels"
private let APILEVEL_ANNO_NAME: String = "APILevel"
private let SINCE_IDENTIFIER: String = "since"
private let LEVEL_IDENTIFIER: String = "level"
private let SYSCAP_IDENTIFIER: String = "syscap"
private let HIDE_ANNO_NAME: String = "Hide"
private let HIDE_ARG_NAME: String = "isChecked"
private let APILEVEL_MAJOR_MIN: UInt64 = 1u64
private let APILEVEL_MAJOR_MAX: UInt64 = 99u64

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

private func ToBasicRange(begin: Position, end: Position): BasicRange {
    var fixedEnd = end
    if (begin.fileID != end.fileID) {
        fixedEnd = begin + 1
    }
    return BasicRange(ToBasicPosition(begin), ToBasicPosition(fixedEnd))
}

private func NodeRange(node: Node): BasicRange {
    return ToBasicRange(node.begin, node.end)
}

private func Emit(diag: BasicDiagnosticEngine, kind: BasicDiagKindRefactor, node: Node,
    args!: Array<String> = Array<String>()): Unit {
    let builder = diag.DiagnoseRefactor(kind, NodeRange(node), arguments: args)
    builder.Emit()
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

public class PluginCustomAnnoChecker {
    private var diag: BasicDiagnosticEngine

    public init() {
        diag = BasicDiagnosticEngine()
    }

    public init(diag: BasicDiagnosticEngine) {
        this.diag = diag
    }

    public func IsAnnoAPILevel(annotation: Annotation, decl: Decl): Bool {
        if (decl.fullPackageName == PKG_NAME_OHOS_LABELS) {
            return annotation.identifier.Val() == APILEVEL_ANNO_NAME
        }
        return annotation.identifier.Val() == APILEVEL_ANNO_NAME
    }

    public func IsAnnoHide(annotation: Annotation): Bool {
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
        if (!cached.since.IsZero() && (annoInfo.since.IsZero() || cached.since < annoInfo.since)) {
            annoInfo.since = cached.since
        }
        if (!cached.syscap.isEmpty()) {
            annoInfo.syscap = cached.syscap
        }
        if (let Some(value) <- cached.hasHideAnno) {
            annoInfo.hasHideAnno = Some(value)
        }
    }

    public func ProcessOneAnnotation(decl: Decl, annotation: Annotation, hideSeen: BoolBox,
        annoInfo: PluginCustomAnnoInfo): Unit {
        if (IsAnnoAPILevel(annotation, decl)) {
            ParseAPILevelArgs(decl, annotation, annoInfo)
            return
        }
        if (IsAnnoHide(annotation)) {
            if (hideSeen.value) {
                Emit(diag, BasicDiagKindRefactor.sema_hide_multi_annotation, annotation)
            }
            hideSeen.value = true
            ParseHideArg(annotation, annoInfo)
        }
    }

    public func Parse(decl: Decl, annoInfo: PluginCustomAnnoInfo): Unit {
        let hideSeen = BoolBox(false)
        for (annotation in decl.annotations) {
            ProcessOneAnnotation(decl, annotation, hideSeen, annoInfo)
        }
    }

    public func Check(pkg: Package): Unit {
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(decl) <- (node as Decl)) {
                let info = PluginCustomAnnoInfo(since: APILevelVersion(), syscap: "", hasHideAnno: None)
                Parse(decl, info)
            }
            return VisitAction.WALK_CHILDREN
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

public func SelfhostPortStatus_Plugin_PluginCustomAnnoChecker(): Bool {
    return true
}
