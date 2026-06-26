package cangjie_compiler::frontend

public import cangjie_compiler::basic.{
    BEGIN_POSITION, DEFAULT_POSITION, INVALID_POSITION, DiagCategory, DiagColor, DiagKindRefactor, DiagSeverity,
    IntegratedString, MakeRange, Position, PositionStatus, Range, Source, SourceManager
}
public import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::basic.StringConvertor
import cangjie_compiler::basic.Diagnostic as BasicDiagnostic
import cangjie_compiler::basic.DiagFormat as BasicDiagFormat
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::chir.CHIRContext as RealCHIRContext
import cangjie_compiler::chir.Package as RealCHIRPackage
import cangjie_compiler::utils.FileUtil
import std.collection.*
import std.sort.*

public class DiagnosticEngine {
    private let impl: BasicDiagnosticEngine = BasicDiagnosticEngine()

    public init() {}

    public func SetSourceManager(sourceManager: SourceManager): Unit {
        impl.SetSourceManager(sourceManager)
    }

    public func GetSourceManager(): SourceManager {
        return impl.GetSourceManager()
    }

    public func RegisterHandler(format: BasicDiagFormat): Unit {
        impl.RegisterHandler(format)
    }

    public func SetErrorCountLimit(errorCountLimit: Option<UInt64>): Unit {
        impl.SetErrorCountLimit(errorCountLimit)
    }

    func AsBasicDiagnosticEngine(): BasicDiagnosticEngine {
        return impl
    }

    public func Diagnose(category: DiagCategory, position: Position, message: String): Unit {
        emitFrontendDiagnostic(this, category, position, message, DiagSeverity.DS_ERROR)
    }

    public func DiagnoseRefactor(kind: DiagKindRefactor, position: Position,
        arguments!: Array<String> = Array<String>()): Unit {
        impl.DiagnoseRefactor(kind, position, arguments: arguments).Emit()
    }

    public func Warn(category: DiagCategory, position: Position, message: String): Unit {
        emitFrontendDiagnostic(this, category, position, message, DiagSeverity.DS_WARNING)
    }

    public func Note(category: DiagCategory, position: Position, message: String): Unit {
        emitFrontendDiagnostic(this, category, position, message, DiagSeverity.DS_NOTE)
    }

    public func GetErrorCount(): UInt64 {
        return impl.GetErrorCount()
    }

    public func GetWarningCount(): UInt64 {
        return impl.GetWarningCount()
    }

    public func EmitCategoryDiagnostics(category: DiagCategory): Unit {
        impl.EmitCategoryDiagnostics(category)
    }

    public func EmitCategoryGroup(): Unit {
        impl.EmitCategoryGroup()
    }

    public func ReportErrorAndWarningCount(): Unit {
        impl.ReportErrorAndWarningCount()
    }

    public func HandleDiagnostic(diagnostic: BasicDiagnostic): Unit {
        impl.HandleDiagnostic(diagnostic)
    }
}

private func emitFrontendDiagnostic(
    diag: DiagnosticEngine,
    category: DiagCategory,
    position: Position,
    message: String,
    severity: DiagSeverity
): Unit {
    let diagnostic = BasicDiagnostic()
    diagnostic.isRefactor = true
    diagnostic.diagCategory = category
    diagnostic.diagSeverity = severity
    diagnostic.errorMessage = message
    diagnostic.start = INVALID_POSITION
    diagnostic.end = INVALID_POSITION
    diagnostic.mainHint = IntegratedString(frontendDiagnosticRange(position), "", frontendDiagnosticColor(severity))
    diag.HandleDiagnostic(diagnostic)
}

private func frontendDiagnosticRange(position: Position): BasicRange {
    if (position == DEFAULT_POSITION || position.IsZero()) {
        return MakeRange(DEFAULT_POSITION, DEFAULT_POSITION)
    }
    return MakeRange(position, position + 1)
}

private func frontendDiagnosticColor(severity: DiagSeverity): DiagColor {
    return match (severity) {
        case DiagSeverity.DS_ERROR => DiagColor.RED
        case DiagSeverity.DS_WARNING => DiagColor.YELLOW
        case DiagSeverity.DS_NOTE => DiagColor.BLUE
        case DiagSeverity.DS_HINT => DiagColor.GREEN
    }
}

public enum FrontendTokenKind {
    | IDENTIFIER
    | KEYWORD
    | INTEGER_LITERAL
    | FLOAT_LITERAL
    | STRING_LITERAL
    | BOOL_LITERAL
    | COMMENT
    | NL
    | OPERATOR
    | END
}

private func FrontendTokenKindIndex(kind: FrontendTokenKind): Int64 {
    return match (kind) {
        case FrontendTokenKind.IDENTIFIER => 0
        case FrontendTokenKind.KEYWORD => 1
        case FrontendTokenKind.INTEGER_LITERAL => 2
        case FrontendTokenKind.FLOAT_LITERAL => 3
        case FrontendTokenKind.STRING_LITERAL => 4
        case FrontendTokenKind.BOOL_LITERAL => 5
        case FrontendTokenKind.COMMENT => 6
        case FrontendTokenKind.NL => 7
        case FrontendTokenKind.OPERATOR => 8
        case FrontendTokenKind.END => 9
    }
}

extend FrontendTokenKind <: Equatable<FrontendTokenKind> {
    public operator func ==(rhs: FrontendTokenKind): Bool {
        return FrontendTokenKindIndex(this) == FrontendTokenKindIndex(rhs)
    }

    public operator func !=(rhs: FrontendTokenKind): Bool {
        return !(this == rhs)
    }
}

public func FrontendTokenKindName(kind: FrontendTokenKind): String {
    return match (kind) {
        case FrontendTokenKind.IDENTIFIER => "IDENTIFIER"
        case FrontendTokenKind.KEYWORD => "KEYWORD"
        case FrontendTokenKind.INTEGER_LITERAL => "INTEGER_LITERAL"
        case FrontendTokenKind.FLOAT_LITERAL => "FLOAT_LITERAL"
        case FrontendTokenKind.STRING_LITERAL => "STRING_LITERAL"
        case FrontendTokenKind.BOOL_LITERAL => "BOOL_LITERAL"
        case FrontendTokenKind.COMMENT => "COMMENT"
        case FrontendTokenKind.NL => "NL"
        case FrontendTokenKind.OPERATOR => "OPERATOR"
        case FrontendTokenKind.END => "END"
    }
}

public class FrontendToken {
    private var beginPos: Position
    private var endPos: Position
    public var kind: FrontendTokenKind
    public var value: String
    private var rawKindName: String = ""

    public init(kind: FrontendTokenKind, value: String, begin: Position, end: Position,
        rawKindName!: String = "") {
        this.kind = kind
        this.value = value
        this.rawKindName = rawKindName
        beginPos = begin
        endPos = end
    }

    public func Begin(): Position {
        return beginPos
    }

    public func End(): Position {
        return endPos
    }

    public func KindName(): String {
        return if (rawKindName.isEmpty()) { FrontendTokenKindName(kind) } else { rawKindName }
    }
}

public class CompilationCache {
    public var compileArgs: String = ""
    public var lambdaCounter: Int64 = 0
    public let bitcodeFilesName: ArrayList<String> = ArrayList<String>()
    public let fileSummaries: ArrayList<String> = ArrayList<String>()
    public let declSummaries: ArrayList<String> = ArrayList<String>()
    public init() {}
}

public class CHIRPackage {
    public var name: String
    public var fileCount: Int64 = 0
    public var declCount: Int64 = 0
    public let mangleNames: ArrayList<String> = ArrayList<String>()
    public let implicitFuncs: HashMap<String, String> = HashMap<String, String>()
    public let constVarInitFuncs: ArrayList<String> = ArrayList<String>()

    public init(name: String) {
        this.name = name
    }
}

public class CHIRContext {
    public let packages: ArrayList<CHIRPackage> = ArrayList<CHIRPackage>()
    public var threadNum: Int64 = 1
    public init() {}
}

public class CHIRData {
    private let context: CHIRContext = CHIRContext()
    private let chirPkgs: ArrayList<CHIRPackage> = ArrayList<CHIRPackage>()
    private var curCodegenPkg: Option<CHIRPackage> = None
    private let realContext: RealCHIRContext = RealCHIRContext()
    private let realChirPkgs: ArrayList<RealCHIRPackage> = ArrayList<RealCHIRPackage>()
    private var curRealCodegenPkg: Option<RealCHIRPackage> = None
    private let implicitFuncs: HashMap<String, String> = HashMap<String, String>()
    private let constVarInitFuncs: ArrayList<String> = ArrayList<String>()
    private let implicitFuncsPerPkg: HashMap<String, HashMap<String, String>> =
        HashMap<String, HashMap<String, String>>()
    private let constVarInitFuncsPerPkg: HashMap<String, ArrayList<String>> =
        HashMap<String, ArrayList<String>>()

    public init() {}

    public func InitData(fileNameMap: HashMap<UInt64, String>, threadNum: Int64): Unit {
        let _ = fileNameMap
        context.threadNum = threadNum
    }

    public func GetCHIRContext(): CHIRContext {
        return context
    }

    public func GetRealCHIRContext(): RealCHIRContext {
        return realContext
    }

    public func AppendNewPackage(pkg: CHIRPackage): Unit {
        chirPkgs.add(pkg)
        context.packages.add(pkg)
    }

    public func GetAllCHIRPackages(): ArrayList<CHIRPackage> {
        return chirPkgs
    }

    public func AppendNewRealPackage(pkg: RealCHIRPackage): Unit {
        realChirPkgs.add(pkg)
        if (let None <- curRealCodegenPkg) {
            curRealCodegenPkg = Some(pkg)
        }
    }

    public func ClearRealPackages(): Unit {
        realChirPkgs.clear()
        curRealCodegenPkg = None
    }

    public func GetAllRealCHIRPackages(): ArrayList<RealCHIRPackage> {
        return realChirPkgs
    }

    public func GetCurrentRealCHIRPackage(): Option<RealCHIRPackage> {
        if (let Some(pkg) <- curRealCodegenPkg) {
            return Some(pkg)
        }
        if (realChirPkgs.isEmpty()) {
            return None
        }
        return Some(realChirPkgs[0])
    }

    public func SetCurrentRealCHIRPackage(pkg: Option<RealCHIRPackage>): Unit {
        curRealCodegenPkg = pkg
    }

    public func GetCurrentCHIRPackage(): Option<CHIRPackage> {
        if (let Some(pkg) <- curCodegenPkg) {
            return Some(pkg)
        }
        if (chirPkgs.isEmpty()) {
            return None
        }
        return Some(chirPkgs[0])
    }

    public func SetCurrentCHIRPackage(pkg: Option<CHIRPackage>): Unit {
        curCodegenPkg = pkg
    }

    public func SetImplicitFuncs(pkg: CHIRPackage, funcs: HashMap<String, String>): Unit {
        implicitFuncs.clear()
        for ((key, value) in funcs) {
            implicitFuncs.add(key, value)
        }
        let copy = HashMap<String, String>()
        for ((key, value) in funcs) {
            copy.add(key, value)
        }
        if (implicitFuncsPerPkg.contains(pkg.name)) {
            implicitFuncsPerPkg.remove(pkg.name)
        }
        implicitFuncsPerPkg.add(pkg.name, copy)
    }

    public func GetImplicitFuncs(): HashMap<String, String> {
        return implicitFuncs
    }

    public func SetConstVarInitFuncs(pkg: CHIRPackage, funcs: ArrayList<String>): Unit {
        constVarInitFuncs.clear()
        for (funcName in funcs) {
            constVarInitFuncs.add(funcName)
        }
        let copy = ArrayList<String>()
        for (funcName in funcs) {
            copy.add(funcName)
        }
        if (constVarInitFuncsPerPkg.contains(pkg.name)) {
            constVarInitFuncsPerPkg.remove(pkg.name)
        }
        constVarInitFuncsPerPkg.add(pkg.name, copy)
    }

    public func GetConstVarInitFuncs(): ArrayList<String> {
        return constVarInitFuncs
    }

    public func ActivateCodegenFuncsForPackage(pkg: CHIRPackage): Unit {
        if (let Some(funcs) <- implicitFuncsPerPkg.get(pkg.name)) {
            implicitFuncs.clear()
            for ((key, value) in funcs) {
                implicitFuncs.add(key, value)
            }
        }
        if (let Some(funcs) <- constVarInitFuncsPerPkg.get(pkg.name)) {
            constVarInitFuncs.clear()
            for (funcName in funcs) {
                constVarInitFuncs.add(funcName)
            }
        }
    }

    public func FreeConstAnalysisWrapper(): Unit {
        ()
    }
}

public enum SrcCodeChangeState {
    | UNCHANGED
    | CHANGED
    | ADDED
    | DELETED
}

private func SrcCodeChangeStateIndex(state: SrcCodeChangeState): Int64 {
    return match (state) {
        case SrcCodeChangeState.UNCHANGED => 0
        case SrcCodeChangeState.CHANGED => 1
        case SrcCodeChangeState.ADDED => 2
        case SrcCodeChangeState.DELETED => 3
    }
}

extend SrcCodeChangeState <: Equatable<SrcCodeChangeState> {
    public operator func ==(rhs: SrcCodeChangeState): Bool {
        return SrcCodeChangeStateIndex(this) == SrcCodeChangeStateIndex(rhs)
    }

    public operator func !=(rhs: SrcCodeChangeState): Bool {
        return !(this == rhs)
    }
}

// ModuleFormat.fbs enum ExprKind (fbs:333-373): WildcardExpr=1, PrimitiveTypeExpr=2,
// ReturnExpr=3, JumpExpr=4, MemberAccess=5, RefExpr=6, CallExpr=7, UnaryExpr=8,
// IncOrDecExpr=9, LitConstExpr=10, BinaryExpr=11, SubscriptExpr=12, AssignExpr=13,
// ArrayExpr=14, PointerExpr=15, TypeConvExpr=16, ThrowExpr=17, SpawnExpr=18,
// ArrayLit=19, TupleLit=20, MatchExpr=21, LetPatternDestructor=22, IfExpr=23, TryExpr=24,
// WhileExpr=25, DoWhileExpr=26, LambdaExpr=27, Block=28, MatchCase=29,
// MatchCaseOther=30, ForInExpr=35, IfAvailableExpr=36, PerformExpr=37, ResumeExpr=38.
private const FLAT_EXPR_KIND_WILDCARD: UInt16 = 1u16
private const FLAT_EXPR_KIND_PRIMITIVE_TYPE: UInt16 = 2u16
private const FLAT_EXPR_KIND_RETURN: UInt16 = 3u16
private const FLAT_EXPR_KIND_JUMP: UInt16 = 4u16
private const FLAT_EXPR_KIND_MEMBER_ACCESS: UInt16 = 5u16
private const FLAT_EXPR_KIND_REF_EXPR: UInt16 = 6u16
private const FLAT_EXPR_KIND_CALL: UInt16 = 7u16
private const FLAT_EXPR_KIND_UNARY: UInt16 = 8u16
private const FLAT_EXPR_KIND_INC_OR_DEC: UInt16 = 9u16
private const FLAT_EXPR_KIND_LIT_CONST: UInt16 = 10u16
private const FLAT_EXPR_KIND_BINARY: UInt16 = 11u16
private const FLAT_EXPR_KIND_SUBSCRIPT: UInt16 = 12u16
private const FLAT_EXPR_KIND_ASSIGN: UInt16 = 13u16
private const FLAT_EXPR_KIND_ARRAY_EXPR: UInt16 = 14u16
private const FLAT_EXPR_KIND_POINTER_EXPR: UInt16 = 15u16
private const FLAT_EXPR_KIND_TYPE_CONV: UInt16 = 16u16
private const FLAT_EXPR_KIND_THROW: UInt16 = 17u16
private const FLAT_EXPR_KIND_SPAWN: UInt16 = 18u16
private const FLAT_EXPR_KIND_ARRAY_LIT: UInt16 = 19u16
private const FLAT_EXPR_KIND_TUPLE_LIT: UInt16 = 20u16
private const FLAT_EXPR_KIND_MATCH: UInt16 = 21u16
private const FLAT_EXPR_KIND_LET_PATTERN_DESTRUCTOR: UInt16 = 22u16
private const FLAT_EXPR_KIND_IF: UInt16 = 23u16
private const FLAT_EXPR_KIND_TRY: UInt16 = 24u16
private const FLAT_EXPR_KIND_WHILE: UInt16 = 25u16
private const FLAT_EXPR_KIND_DO_WHILE: UInt16 = 26u16
private const FLAT_EXPR_KIND_LAMBDA: UInt16 = 27u16
private const FLAT_EXPR_KIND_BLOCK: UInt16 = 28u16
private const FLAT_EXPR_KIND_MATCH_CASE: UInt16 = 29u16
private const FLAT_EXPR_KIND_MATCH_CASE_OTHER: UInt16 = 30u16
private const FLAT_EXPR_KIND_FOR_IN: UInt16 = 35u16
private const FLAT_EXPR_KIND_PERFORM: UInt16 = 37u16
private const FLAT_EXPR_KIND_RESUME: UInt16 = 38u16

// ModuleFormat.fbs enum PatternKind (fbs:515-524).
private const FLAT_PATTERN_KIND_CONST: UInt8 = 1u8
private const FLAT_PATTERN_KIND_WILDCARD: UInt8 = 2u8
private const FLAT_PATTERN_KIND_VAR: UInt8 = 3u8
private const FLAT_PATTERN_KIND_TUPLE: UInt8 = 4u8
private const FLAT_PATTERN_KIND_TYPE: UInt8 = 5u8
private const FLAT_PATTERN_KIND_ENUM: UInt8 = 6u8
private const FLAT_PATTERN_KIND_EXCEPT_TYPE: UInt8 = 7u8
private const FLAT_PATTERN_KIND_COMMAND_TYPE: UInt8 = 8u8

// ModuleFormat.fbs enum LitConstKind (fbs:388-397). Mirrors ASTLoader.cpp LIT_CONST_KIND_RMAP.
private func FlatToLitConstKind(value: UInt8): LitConstKind {
    return match (value) {
        case 0u8 => LitConstKind.INTEGER
        case 1u8 => LitConstKind.RUNE_BYTE
        case 2u8 => LitConstKind.FLOAT
        case 3u8 => LitConstKind.RUNE
        case 4u8 => LitConstKind.STRING
        case 5u8 => LitConstKind.JSTRING
        case 6u8 => LitConstKind.BOOL
        case 7u8 => LitConstKind.UNIT
        case _ => LitConstKind.NONE
    }
}

// ModuleFormat.fbs enum StringKind (fbs:398-403).
private func FlatToStringKind(value: UInt8): StringKind {
    return match (value) {
        case 1u8 => StringKind.JSTRING
        case 2u8 => StringKind.MULTILINE
        case 3u8 => StringKind.MULTILINE_RAW
        case _ => StringKind.NORMAL
    }
}

public class SrcCodeCacheInfo {
    public var state: SrcCodeChangeState = SrcCodeChangeState.ADDED
    public var code: String = ""

    public init() {}

    public init(code: String) {
        this.code = code
    }

    public init(state: SrcCodeChangeState, code: String) {
        this.state = state
        this.code = code
    }
}

public class TypeManager {
    public init() {}
    public func ReleasePostSemaCaches(): Unit {}
}

public class ImportedDeclGroup {
    public var name: String = ""
    public let decls: ArrayList<Decl> = ArrayList<Decl>()

    public init() {}

    public init(name: String, decls: ArrayList<Decl>) {
        this.name = name
        for (decl in decls) {
            this.decls.add(decl)
        }
    }
}

private class ParsedText {
    public var ok: Bool = false
    public var text: String = ""
    public var next: Int64 = 0

    public init() {}

    public init(ok: Bool, text: String, next: Int64) {
        this.ok = ok
        this.text = text
        this.next = next
    }
}

private class ParsedGenericArity {
    public var ok: Bool = false
    public var arity: Int64 = 0
    public var next: Int64 = 0

    public init(ok: Bool, arity: Int64, next: Int64) {
        this.ok = ok
        this.arity = arity
        this.next = next
    }
}

private class CjoFlatBuffer {
    private let data: Array<UInt8>

    public init(data: Array<UInt8>) {
        this.data = data
    }

    public func RootTable(): Int64 {
        if (data.size < 8 || data[4] != b'C' || data[5] != b'J' || data[6] != b'O' || data[7] != b'F') {
            return -1
        }
        let root = Int64(ReadU32(0))
        return if (IsInBounds(root, 4)) { root } else { -1 }
    }

    public func TableField(table: Int64, slot: Int64): Int64 {
        if (!IsInBounds(table, 4)) {
            return -1
        }
        let vtable = table - ReadI32(table)
        if (!IsInBounds(vtable, 4)) {
            return -1
        }
        let vtableSize = Int64(ReadU16(vtable))
        if (slot < 0 || slot + 2 > vtableSize) {
            return -1
        }
        let fieldOffset = Int64(ReadU16(vtable + slot))
        if (fieldOffset == 0) {
            return -1
        }
        let fieldPos = table + fieldOffset
        return if (IsInBounds(fieldPos, 1)) { fieldPos } else { -1 }
    }

    public func OffsetField(table: Int64, slot: Int64): Int64 {
        return Indirect(TableField(table, slot))
    }

    public func VectorField(table: Int64, slot: Int64): Int64 {
        let target = OffsetField(table, slot)
        return if (IsInBounds(target, 4)) { target } else { -1 }
    }

    public func StringField(table: Int64, slot: Int64): String {
        return StringAt(OffsetField(table, slot))
    }

    public func U8Field(table: Int64, slot: Int64, defaultValue: UInt8): UInt8 {
        let pos = TableField(table, slot)
        return if (pos >= 0 && IsInBounds(pos, 1)) { data[pos] } else { defaultValue }
    }

    public func U16Field(table: Int64, slot: Int64, defaultValue: UInt16): UInt16 {
        let pos = TableField(table, slot)
        return if (pos >= 0) { ReadU16(pos) } else { defaultValue }
    }

    public func U32Field(table: Int64, slot: Int64, defaultValue: UInt32): UInt32 {
        let pos = TableField(table, slot)
        return if (pos >= 0) { ReadU32(pos) } else { defaultValue }
    }

    public func I32Field(table: Int64, slot: Int64, defaultValue: Int64): Int64 {
        let pos = TableField(table, slot)
        return if (pos >= 0) { ReadI32(pos) } else { defaultValue }
    }

    public func I64Field(table: Int64, slot: Int64, defaultValue: Int64): Int64 {
        let pos = TableField(table, slot)
        return if (pos >= 0) { ReadI64(pos) } else { defaultValue }
    }

    public func VectorLength(vector: Int64): Int64 {
        if (!IsInBounds(vector, 4)) {
            return 0
        }
        return Int64(ReadU32(vector))
    }

    public func VectorU32(vector: Int64, index: Int64): UInt32 {
        let pos = vector + 4 + index * 4
        return ReadU32(pos)
    }

    public func VectorU64(vector: Int64, index: Int64): UInt64 {
        let pos = vector + 4 + index * 8
        return ReadU64(pos)
    }

    public func VectorBool(vector: Int64, index: Int64): Bool {
        let pos = vector + 4 + index
        return pos >= 0 && pos < data.size && data[pos] != 0u8
    }

    public func VectorOffsetElement(vector: Int64, index: Int64): Int64 {
        let pos = vector + 4 + index * 4
        return Indirect(pos)
    }

    public func U64At(pos: Int64): UInt64 {
        return ReadU64(pos)
    }

    public func U32At(pos: Int64): UInt32 {
        return ReadU32(pos)
    }

    public func StringAt(pos: Int64): String {
        if (!IsInBounds(pos, 4)) {
            return ""
        }
        let len = Int64(ReadU32(pos))
        let start = pos + 4
        if (len < 0 || !IsInBounds(start, len)) {
            return ""
        }
        return String.fromUtf8(data[start..start + len])
    }

    public func Indirect(pos: Int64): Int64 {
        if (!IsInBounds(pos, 4)) {
            return -1
        }
        let target = pos + Int64(ReadU32(pos))
        return if (IsInBounds(target, 1)) { target } else { -1 }
    }

    private func IsInBounds(pos: Int64, width: Int64): Bool {
        return pos >= 0 && width >= 0 && pos + width <= data.size
    }

    @OverflowWrapping
    private func ReadU16(pos: Int64): UInt16 {
        if (!IsInBounds(pos, 2)) {
            return 0u16
        }
        var out = UInt16(data[pos])
        out = out | (UInt16(data[pos + 1]) << 8)
        return out
    }

    @OverflowWrapping
    private func ReadU32(pos: Int64): UInt32 {
        if (!IsInBounds(pos, 4)) {
            return 0u32
        }
        var out = UInt32(data[pos])
        out = out | (UInt32(data[pos + 1]) << 8)
        out = out | (UInt32(data[pos + 2]) << 16)
        out = out | (UInt32(data[pos + 3]) << 24)
        return out
    }

    @OverflowWrapping
    private func ReadU64(pos: Int64): UInt64 {
        if (!IsInBounds(pos, 8)) {
            return 0u64
        }
        var out = UInt64(data[pos])
        out = out | (UInt64(data[pos + 1]) << 8)
        out = out | (UInt64(data[pos + 2]) << 16)
        out = out | (UInt64(data[pos + 3]) << 24)
        out = out | (UInt64(data[pos + 4]) << 32)
        out = out | (UInt64(data[pos + 5]) << 40)
        out = out | (UInt64(data[pos + 6]) << 48)
        out = out | (UInt64(data[pos + 7]) << 56)
        return out
    }

    @OverflowWrapping
    private func ReadI32(pos: Int64): Int64 {
        return Int64(Int32(ReadU32(pos)))
    }

    @OverflowWrapping
    private func ReadI64(pos: Int64): Int64 {
        return Int64(ReadU64(pos))
    }
}

private class CjoFlatDecl {
    public let index: UInt32
    public let table: Int64
    public let kind: UInt16
    public let isTopLevel: Bool
    public let identifier: String
    public let fullPackageName: String
    public let exportId: String
    public let mangledName: String
    public let mangledBeforeSema: String
    public let genericArity: Int64
    public let typeIndex: UInt32
    public let infoType: UInt8
    public var decl: Option<Decl> = None

    public init(index: UInt32, table: Int64, kind: UInt16, isTopLevel: Bool, identifier: String,
        fullPackageName: String, exportId: String, mangledName: String, mangledBeforeSema: String,
        genericArity: Int64, typeIndex: UInt32, infoType: UInt8) {
        this.index = index
        this.table = table
        this.kind = kind
        this.isTopLevel = isTopLevel
        this.identifier = identifier
        this.fullPackageName = fullPackageName
        this.exportId = exportId
        this.mangledName = mangledName
        this.mangledBeforeSema = mangledBeforeSema
        this.genericArity = genericArity
        this.typeIndex = typeIndex
        this.infoType = infoType
    }
}

private class CjoFullId {
    public let pkgId: Int64
    public let decl: String
    public let index: UInt32

    public init(pkgId: Int64, decl: String, index: UInt32) {
        this.pkgId = pkgId
        this.decl = decl
        this.index = index
    }
}

private class CjoSignatureMaterializer {
    private let packageName: String
    private let pkg: Package
    private let fallbackFile: File
    private let filesByIndex: HashMap<UInt32, File>
    private let importedPackages: ArrayList<Package>
    private var flat: Option<CjoFlatBuffer> = None
    private var flatAllDecls: Int64 = -1
    private var flatAllTypes: Int64 = -1
    private var flatAllExprs: Int64 = -1
    private var flatImports: Int64 = -1
    private let flatDecls: HashMap<UInt32, CjoFlatDecl> = HashMap<UInt32, CjoFlatDecl>()
    private let flatNominalKinds: HashMap<String, UInt8> = HashMap<String, UInt8>()
    private let flatTypeCache: HashMap<UInt32, Ty> = HashMap<UInt32, Ty>()
    private let flatGenericParamDecls: HashMap<UInt32, GenericParamDecl> = HashMap<UInt32, GenericParamDecl>()

    public init(packageName: String, pkg: Package, fallbackFile: File, filesByIndex: HashMap<UInt32, File>,
        importedPackages: ArrayList<Package>) {
        this.packageName = packageName
        this.pkg = pkg
        this.fallbackFile = fallbackFile
        this.filesByIndex = filesByIndex
        this.importedPackages = importedPackages
    }

    public func Materialize(data: Array<UInt8>): Unit {
        LoadSerializedDeclRecords(data)
        MaterializeSerializedImports()
        MaterializeSerializedDecls()
        MaterializeSerializedInheritedTypes()
    }

    private func LoadSerializedDeclRecords(data: Array<UInt8>): Unit {
        flat = Some(CjoFlatBuffer(data))
        flatAllDecls = -1
        flatAllTypes = -1
        flatAllExprs = -1
        flatImports = -1
        flatDecls.clear()
        flatNominalKinds.clear()
        flatTypeCache.clear()
        flatGenericParamDecls.clear()
        let reader = flat.getOrThrow()
        let root = reader.RootTable()
        if (root < 0 || reader.StringField(root, 8) != packageName) {
            return
        }
        flatAllTypes = reader.VectorField(root, 18)
        flatAllDecls = reader.VectorField(root, 20)
        flatAllExprs = reader.VectorField(root, 22)
        flatImports = reader.VectorField(root, 12)
        if (flatAllTypes < 0 || flatAllDecls < 0) {
            return
        }
        let declCount = reader.VectorLength(flatAllDecls)
        var idx: Int64 = 0
        while (idx < declCount) {
            let declTable = reader.VectorOffsetElement(flatAllDecls, idx)
            if (declTable >= 0) {
                let record = CreateFlatDeclRecord(reader, declTable, UInt32(idx + 1))
                flatDecls[record.index] = record
                if (let Some(nominalKind) <- FlatNominalKind(record.kind)) {
                    flatNominalKinds[record.identifier] = nominalKind
                }
            }
            idx++
        }
    }

    private func MaterializeSerializedInheritedTypes(): Unit {
        if ((let None <- flat) || flatAllTypes < 0 || flatAllDecls < 0) {
            return
        }
        let reader = flat.getOrThrow()
        let declCount = reader.VectorLength(flatAllDecls)
        var idx: Int64 = 0
        while (idx < declCount) {
            let formatIndex = UInt32(idx + 1)
            if (let Some(record) <- flatDecls.get(formatIndex)) {
                MaterializeFlatInheritedTypes(reader, record)
            }
            idx++
        }
    }

    private func MaterializeSerializedImports(): Unit {
        if (let None <- flat) {
            return
        }
        let reader = flat.getOrThrow()
        let root = reader.RootTable()
        if (root < 0) {
            return
        }
        let allFileImports = reader.VectorField(root, 16)
        if (allFileImports < 0) {
            return
        }
        var fileIdx: Int64 = 0
        while (fileIdx < reader.VectorLength(allFileImports)) {
            let importsTable = reader.VectorOffsetElement(allFileImports, fileIdx)
            if (importsTable >= 0) {
                MaterializeFlatImports(reader, importsTable, FileByFlatIndex(UInt32(fileIdx + 1)))
            }
            fileIdx++
        }
    }

    private func MaterializeFlatImports(reader: CjoFlatBuffer, importsTable: Int64, targetFile: File): Unit {
        let importSpecs = reader.VectorField(importsTable, 4)
        if (importSpecs < 0) {
            return
        }
        var idx: Int64 = 0
        while (idx < reader.VectorLength(importSpecs)) {
            let importTable = reader.VectorOffsetElement(importSpecs, idx)
            if (importTable >= 0) {
                targetFile.imports.add(CreateFlatImportSpec(reader, importTable, targetFile))
            }
            idx++
        }
    }

    private func CreateFlatImportSpec(reader: CjoFlatBuffer, importTable: Int64, targetFile: File): ImportSpec {
        let importSpec = ImportSpec()
        let identifier = reader.StringField(importTable, 10)
        let aliasName = reader.StringField(importTable, 12)
        if (!aliasName.isEmpty()) {
            importSpec.content.kind = ImportKind.IMPORT_ALIAS
        } else if (identifier == "*") {
            importSpec.content.kind = ImportKind.IMPORT_ALL
        } else {
            importSpec.content.kind = ImportKind.IMPORT_SINGLE
        }
        let prefixPaths = reader.VectorField(importTable, 8)
        if (prefixPaths >= 0) {
            var idx: Int64 = 0
            while (idx < reader.VectorLength(prefixPaths)) {
                importSpec.content.prefixPaths.add(reader.StringAt(reader.VectorOffsetElement(prefixPaths, idx)))
                idx++
            }
        }
        importSpec.content.identifier = Identifier(identifier, DEFAULT_POSITION, DEFAULT_POSITION)
        importSpec.content.aliasName = Identifier(aliasName, DEFAULT_POSITION, DEFAULT_POSITION)
        importSpec.content.isDecl = reader.U8Field(importTable, 16, 0u8) != 0u8
        importSpec.content.hasDoubleColon = reader.U8Field(importTable, 18, 0u8) != 0u8
        importSpec.withImplicitExport = reader.U8Field(importTable, 20, 1u8) != 0u8
        SetFlatImportAccessLevel(importSpec, FlatImportAccessLevel(reader.U8Field(importTable, 14, 0u8)))
        importSpec.EnableAttr(Attribute.IMPORTED)
        importSpec.curFile = Some(targetFile)
        importSpec.content.curFile = Some(targetFile)
        return importSpec
    }

    private func SetFlatImportAccessLevel(importSpec: ImportSpec, level: AccessLevel): Unit {
        let tokenKind = match (level) {
            case AccessLevel.PUBLIC => TokenKind.PUBLIC
            case AccessLevel.PROTECTED => TokenKind.PROTECTED
            case AccessLevel.INTERNAL => TokenKind.INTERNAL
            case AccessLevel.PRIVATE => TokenKind.PRIVATE
        }
        importSpec.modifier = Some(Modifier(tokenKind, DEFAULT_POSITION))
        importSpec.DisableAttr(Attribute.PUBLIC)
        importSpec.DisableAttr(Attribute.PRIVATE)
        importSpec.DisableAttr(Attribute.PROTECTED)
        importSpec.DisableAttr(Attribute.INTERNAL)
        match (level) {
            case AccessLevel.PUBLIC => importSpec.EnableAttr(Attribute.PUBLIC)
            case AccessLevel.PRIVATE => importSpec.EnableAttr(Attribute.PRIVATE)
            case AccessLevel.PROTECTED => importSpec.EnableAttr(Attribute.PROTECTED)
            case AccessLevel.INTERNAL => importSpec.EnableAttr(Attribute.INTERNAL)
        }
    }

    private func FlatImportAccessLevel(value: UInt8): AccessLevel {
        if (value == 3u8) {
            return AccessLevel.PUBLIC
        }
        if (value == 2u8) {
            return AccessLevel.PROTECTED
        }
        if (value == 1u8) {
            return AccessLevel.INTERNAL
        }
        return AccessLevel.PRIVATE
    }

    private func CreateFlatDeclRecord(reader: CjoFlatBuffer, declTable: Int64, index: UInt32): CjoFlatDecl {
        let genericTable = reader.OffsetField(declTable, 12)
        let genericArity = if (genericTable >= 0) { reader.VectorLength(reader.VectorField(genericTable, 4)) } else { 0 }
        return CjoFlatDecl(
            index,
            declTable,
            reader.U16Field(declTable, 4, 0u16),
            reader.U8Field(declTable, 6, 0u8) != 0u8,
            reader.StringField(declTable, 18),
            reader.StringField(declTable, 8),
            reader.StringField(declTable, 30),
            reader.StringField(declTable, 28),
            reader.StringField(declTable, 32),
            genericArity,
            reader.U32Field(declTable, 26, 0u32),
            reader.U8Field(declTable, 36, 0u8)
        )
    }

    private func MaterializeSerializedDecls(): Unit {
        if ((let None <- flat) || flatAllDecls < 0) {
            return
        }
        let reader = flat.getOrThrow()
        let declCount = reader.VectorLength(flatAllDecls)
        var idx: Int64 = 0
        while (idx < declCount) {
            let formatIndex = UInt32(idx + 1)
            if (let Some(record) <- flatDecls.get(formatIndex)) {
                if (record.isTopLevel) {
                    if (let Some(decl) <- EnsureFlatDecl(record)) {
                        AddFlatTopLevelDecl(decl)
                    }
                }
            }
            idx++
        }
    }

    private func AddFlatTopLevelDecl(decl: Decl): Unit {
        if (decl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            pkg.genericInstantiatedDecls.add(decl)
            return
        }
        let targetFile = decl.curFile ?? fallbackFile
        if (decl.IsExportedDecl() || decl.TestAttr(Attribute.FROM_COMMON_PART)) {
            targetFile.decls.add(decl)
            return
        }
        targetFile.exportedInternalDecls.add(decl)
    }

    private func CreateFlatDeclShell(reader: CjoFlatBuffer, record: CjoFlatDecl): Decl {
        if (record.kind == 0u16) {
            return InvalidDecl(INVALID_POSITION)
        }
        if (record.kind == 1u16) {
            let classDecl = ClassDecl()
            classDecl.body = Some(ClassBody())
            return classDecl
        }
        if (record.kind == 2u16) {
            let interfaceDecl = InterfaceDecl()
            interfaceDecl.body = Some(InterfaceBody())
            return interfaceDecl
        }
        if (record.kind == 3u16) {
            return FuncDecl()
        }
        if (record.kind == 4u16) {
            return PropDecl()
        }
        if (record.kind == 5u16) {
            return VarDecl()
        }
        if (record.kind == 6u16) {
            return VarWithPatternDecl()
        }
        if (record.kind == 7u16) {
            return FuncParam()
        }
        if (record.kind == 8u16) {
            let structDecl = StructDecl()
            structDecl.body = Some(StructBody())
            return structDecl
        }
        if (record.kind == 9u16) {
            let enumDecl = EnumDecl()
            enumDecl.bodyScope = Some(DummyBody())
            return enumDecl
        }
        if (record.kind == 10u16) {
            let extendDecl = ExtendDecl()
            extendDecl.bodyScope = Some(DummyBody())
            return extendDecl
        }
        if (record.kind == 11u16) {
            return TypeAliasDecl()
        }
        if (record.kind == 12u16) {
            return GenericParamDecl()
        }
        if (record.kind == 13u16) {
            return BuiltInDecl(FlatBuiltInType(reader, record))
        }
        throw IllegalArgumentException("unsupported FlatBuffer DeclKind ${record.kind}")
    }

    private func ApplyFlatDeclBasicInfo(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: Decl): Unit {
        decl.identifier = SrcIdentifier(record.identifier)
        decl.exportId = record.exportId
        decl.mangledName = record.mangledName
        decl.rawMangleName = record.mangledBeforeSema
        decl.fullPackageName = if (record.fullPackageName.isEmpty()) { packageName } else { record.fullPackageName }
        decl.moduleName = RootPackageName(decl.fullPackageName)
        decl.toBeCompiled = false
        ApplyFlatAttributes(reader, record, decl)
        ApplyFlatAnnotations(reader, record, decl)
        MarkFlatImportedDecl(reader, record, decl)
        ApplyFlatDeclHash(reader, record, decl)
    }

    // Loads the Decl.annotations vector (Decl field 10 -> vtable slot 24) onto the decl.
    // Mirrors ASTLoader::ASTLoaderImpl::LoadDeclBasicInfo annotation loop (ASTLoader.cpp:628-638)
    // and LoadAnnotation/LoadAnnotationArgs (ASTLoader.cpp:641-708). Bounded faithful slice:
    // built-in annotation kinds plus literal (LitConstExpr) args, matching the writer slice.
    private func ApplyFlatAnnotations(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: Decl): Unit {
        let annos = reader.VectorField(record.table, 24)
        if (annos < 0) {
            return
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(annos)
        while (idx < count) {
            let annoTable = reader.VectorOffsetElement(annos, idx)
            if (annoTable >= 0) {
                if (let Some(annotation) <- LoadFlatAnnotation(reader, annoTable)) {
                    decl.annotations.add(annotation)
                }
            }
            idx++
        }
    }

    // Mirrors ASTLoader::ASTLoaderImpl::LoadAnnotation (ASTLoader.cpp:641-692). Anno record
    // (schema/ModuleFormat.fbs:321-326): field 0 kind (slot 4), 1 identifier (slot 6),
    // 2 args (slot 8). The target FullId (slot 10) is not consumed in this bounded slice.
    private func LoadFlatAnnotation(reader: CjoFlatBuffer, annoTable: Int64): Option<Annotation> {
        let kindValue = reader.U16Field(annoTable, 4, 0u16)
        let annotation = Annotation()
        match (kindValue) {
            case 0u16 => annotation.kind = AstAnnotationKind.DEPRECATED
            case 1u16 =>
                // AnnoKind_TestRegistration -> @Attribute[TEST_REGISTER] (ASTLoader.cpp:649-652).
                annotation.kind = AstAnnotationKind.ATTRIBUTE
                annotation.attrs.add(Token(TokenKind.IDENTIFIER, "TEST_REGISTER"))
            case 2u16 => annotation.kind = AstAnnotationKind.FROZEN
            case 3u16 =>
                annotation.kind = AstAnnotationKind.CUSTOM
                annotation.isCompileTimeVisible = true
            case 4u16 => annotation.kind = AstAnnotationKind.JAVA_MIRROR
            case 5u16 => annotation.kind = AstAnnotationKind.JAVA_IMPL
            case 6u16 => annotation.kind = AstAnnotationKind.OBJ_C_MIRROR
            case 7u16 => annotation.kind = AstAnnotationKind.OBJ_C_IMPL
            case 8u16 => annotation.kind = AstAnnotationKind.FOREIGN_NAME
            case 9u16 => annotation.kind = AstAnnotationKind.JAVA_HAS_DEFAULT
            case 10u16 => annotation.kind = AstAnnotationKind.ANNOTATION
            case _ => return None
        }
        annotation.identifier = Identifier(reader.StringField(annoTable, 6))
        LoadFlatAnnotationArgs(reader, annoTable, annotation)
        return annotation
    }

    // Mirrors ASTLoader::ASTLoaderImpl::LoadAnnotationArgs (ASTLoader.cpp:694-708). AnnoArg
    // (schema/ModuleFormat.fbs:328-331): field 0 name (slot 4), 1 expr index (slot 6).
    // Reuses LoadFlatExpr (LitConstExpr-only) for the arg expr.
    private func LoadFlatAnnotationArgs(reader: CjoFlatBuffer, annoTable: Int64, annotation: Annotation): Unit {
        let args = reader.VectorField(annoTable, 8)
        if (args < 0) {
            return
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(args)
        while (idx < count) {
            let argTable = reader.VectorOffsetElement(args, idx)
            if (argTable >= 0) {
                let arg = FuncArg()
                arg.name = SrcIdentifier(reader.StringField(argTable, 4))
                let exprIndex = reader.U32Field(argTable, 6, 0u32)
                arg.expr = LoadFlatExpr(reader, exprIndex)
                annotation.args.add(arg)
            }
            idx++
        }
    }

    private func ApplyFlatDeclHash(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: Decl): Unit {
        let hashPos = reader.TableField(record.table, 34)
        if (hashPos < 0) {
            return
        }
        decl.hash.instVar = reader.U64At(hashPos)
        decl.hash.virt = reader.U64At(hashPos + 8)
        decl.hash.sig = reader.U64At(hashPos + 16)
        decl.hash.srcUse = reader.U64At(hashPos + 24)
        decl.hash.bodyHash = reader.U64At(hashPos + 32)
    }

    private func ApplyFlatAttributes(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: Decl): Unit {
        let attrs = reader.VectorField(record.table, 22)
        if (attrs < 0) {
            return
        }
        var wordIdx: Int64 = 0
        let wordCount = reader.VectorLength(attrs)
        while (wordIdx < wordCount) {
            let word = reader.VectorU64(attrs, wordIdx)
            var bit: Int64 = 0
            while (bit < 64) {
                if ((word & (1u64 << UInt64(bit))) != 0u64) {
                    EnableFlatAttribute(decl, wordIdx * 64 + bit)
                }
                bit++
            }
            wordIdx++
        }
    }

    private func EnableFlatAttribute(decl: Decl, idx: Int64): Unit {
        if (let Some(attr) <- FlatAttributeByIndex(idx)) {
            decl.EnableAttr(attr)
        }
    }

    private func FlatAttributeByIndex(idx: Int64): Option<Attribute> {
        return match (idx) {
            case 0 => Some(Attribute.IN_REFERENCE_CYCLE)
            case 1 => Some(Attribute.UNREACHABLE)
            case 2 => Some(Attribute.IMPLICIT_USED)
            case 3 => Some(Attribute.IMPORTED)
            case 4 => Some(Attribute.GLOBAL)
            case 5 => Some(Attribute.INITIALIZED)
            case 6 => Some(Attribute.COMPILER_ADD)
            case 7 => Some(Attribute.GENERIC)
            case 8 => Some(Attribute.DEFAULT)
            case 9 => Some(Attribute.STATIC)
            case 10 => Some(Attribute.PUBLIC)
            case 11 => Some(Attribute.PRIVATE)
            case 12 => Some(Attribute.PROTECTED)
            case 13 => Some(Attribute.EXTERNAL)
            case 14 => Some(Attribute.INTERNAL)
            case 15 => Some(Attribute.OVERRIDE)
            case 16 => Some(Attribute.REDEF)
            case 17 => Some(Attribute.ABSTRACT)
            case 18 => Some(Attribute.SEALED)
            case 19 => Some(Attribute.OPEN)
            case 20 => Some(Attribute.OPERATOR)
            case 21 => Some(Attribute.FOREIGN)
            case 22 => Some(Attribute.UNSAFE)
            case 23 => Some(Attribute.MUT)
            case 24 => Some(Attribute.HAS_BROKEN)
            case 25 => Some(Attribute.IN_STRUCT)
            case 26 => Some(Attribute.IN_EXTEND)
            case 27 => Some(Attribute.IN_ENUM)
            case 28 => Some(Attribute.IN_CLASSLIKE)
            case 29 => Some(Attribute.IN_MACRO)
            case 30 => Some(Attribute.PRIMARY_CONSTRUCTOR)
            case 31 => Some(Attribute.CONSTRUCTOR)
            case 32 => Some(Attribute.ENUM_CONSTRUCTOR)
            case 33 => Some(Attribute.FINALIZER)
            case 34 => Some(Attribute.IS_CLONED_SOURCE_CODE)
            case 35 => Some(Attribute.IS_CAPTURE)
            case 36 => Some(Attribute.IN_CORE)
            case 37 => Some(Attribute.NEED_AUTO_BOX)
            case 38 => Some(Attribute.MACRO_EXPANDED_NODE)
            case 39 => Some(Attribute.MACRO_FUNC)
            case 40 => Some(Attribute.MACRO_INVOKE_FUNC)
            case 41 => Some(Attribute.MACRO_INVOKE_BODY)
            case 42 => Some(Attribute.LEFT_VALUE)
            case 43 => Some(Attribute.C)
            case 44 => Some(Attribute.SRC_IMPORTED)
            case 45 => Some(Attribute.JAVA_APP)
            case 46 => Some(Attribute.JAVA_EXT)
            case 47 => Some(Attribute.STD_CALL)
            case 48 => Some(Attribute.NO_MANGLE)
            case 49 => Some(Attribute.INITIALIZATION_CHECKED)
            case 50 => Some(Attribute.IS_BROKEN)
            case 51 => Some(Attribute.GENERIC_INSTANTIATED)
            case 52 => Some(Attribute.HAS_INITIAL)
            case 53 => Some(Attribute.IS_VOLATILE)
            case 54 => Some(Attribute.NUMERIC_OVERFLOW)
            case 55 => Some(Attribute.INTRINSIC)
            case 56 => Some(Attribute.TOOL_ADD)
            case 57 => Some(Attribute.IS_CHECK_VISITED)
            case 58 => Some(Attribute.INCRE_COMPILE)
            case 59 => Some(Attribute.SIDE_EFFECT)
            case 60 => Some(Attribute.IMPLICIT_ADD)
            case 61 => Some(Attribute.MAIN_ENTRY)
            case 62 => Some(Attribute.GENERATED_TO_MOCK)
            case 63 => Some(Attribute.IS_OUTERMOST)
            case 64 => Some(Attribute.IS_ANNOTATION)
            case 65 => Some(Attribute.NO_REFLECT_INFO)
            case 66 => Some(Attribute.MOCK_SUPPORTED)
            case 67 => Some(Attribute.OPEN_TO_MOCK)
            case 68 => Some(Attribute.INTERFACE_IMPL)
            case 69 => Some(Attribute.FOR_TEST)
            case 70 => Some(Attribute.CONTAINS_MOCK_CREATION_CALL)
            case 71 => Some(Attribute.COMMON)
            case 72 => Some(Attribute.FROM_COMMON_PART)
            case 73 => Some(Attribute.COMMON_NON_EXHAUSTIVE)
            case 74 => Some(Attribute.SPECIFIC)
            case 75 => Some(Attribute.COMMON_WITH_DEFAULT)
            case 76 => Some(Attribute.JAVA_MIRROR)
            case 77 => Some(Attribute.JAVA_MIRROR_SUBTYPE)
            case 78 => Some(Attribute.JAVA_HAS_DEFAULT)
            case 79 => Some(Attribute.JAVA_MIRROR_SYNTHETIC_WRAPPER)
            case 80 => Some(Attribute.OBJ_C_MIRROR)
            case 81 => Some(Attribute.OBJ_C_MIRROR_SUBTYPE)
            case 82 => Some(Attribute.OBJ_C_INIT)
            case 83 => Some(Attribute.OBJ_C_OPTIONAL)
            case 84 => Some(Attribute.JAVA_CJ_MAPPING)
            case 85 => Some(Attribute.OBJ_C_CJ_MAPPING)
            case 86 => Some(Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD)
            case 87 => Some(Attribute.DESUGARED_MIRROR_FIELD)
            case 88 => Some(Attribute.HAS_INITED_FIELD)
            case 89 => Some(Attribute.OBJ_C_MIRROR_SYNTHETIC_WRAPPER)
            case 90 => Some(Attribute.CJ_MIRROR_JAVA_INTERFACE_DEFAULT)
            case 91 => Some(Attribute.CJ_MIRROR_OBJC_INTERFACE_FWD)
            case 92 => Some(Attribute.ALREADY_LOADED)
            case _ => None
        }
    }

    private func MarkFlatImportedDecl(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: Decl): Unit {
        decl.curFile = Some(FileByFlatIndex(FlatDeclFileIndex(reader, record)))
        decl.EnableAttr(Attribute.IMPORTED)
        decl.EnableAttr(Attribute.SRC_IMPORTED)
    }

    private func FileByFlatIndex(index: UInt32): File {
        return filesByIndex.get(index) ?? fallbackFile
    }

    private func FlatDeclFileIndex(reader: CjoFlatBuffer, record: CjoFlatDecl): UInt32 {
        let beginPos = reader.TableField(record.table, 14)
        return if (beginPos >= 0) { reader.U32At(beginPos) } else { 0u32 }
    }

    private func FlatBuiltInType(reader: CjoFlatBuffer, record: CjoFlatDecl): BuiltInType {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            throw IllegalStateException("FlatBuffer BuiltInDecl '${record.identifier}' has no BuiltInInfo")
        }
        let kind = reader.U8Field(infoTable, 4, 0u8)
        if (kind == 0u8) { return BuiltInType.ARRAY }
        if (kind == 1u8) { return BuiltInType.VARRAY }
        if (kind == 2u8) { return BuiltInType.POINTER }
        if (kind == 3u8) { return BuiltInType.CSTRING }
        if (kind == 4u8) { return BuiltInType.CFUNC }
        throw IllegalArgumentException("unsupported FlatBuffer BuiltInType ${kind}")
    }

    private func SetFlatGeneric(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: Decl): Unit {
        if (let Some(existing) <- ExistingFlatGeneric(decl)) {
            MapFlatGenericParameters(reader, record, existing)
            return
        }
        let genericTable = reader.OffsetField(record.table, 12)
        if (genericTable < 0) {
            return
        }
        let typeParams = reader.VectorField(genericTable, 4)
        if (typeParams < 0) {
            return
        }
        let generic = Generic()
        var idx: Int64 = 0
        let count = reader.VectorLength(typeParams)
        while (idx < count) {
            let paramIndex = reader.VectorU32(typeParams, idx)
            if (let Some(paramRecord) <- flatDecls.get(paramIndex)) {
                if (let Some(paramDecl) <- EnsureFlatDecl(paramRecord)) {
                    if (let Some(gpd) <- (paramDecl as GenericParamDecl)) {
                        gpd.outerDecl = Some(decl)
                        EnsureFlatGenericParamMangle(gpd, decl, idx)
                        flatGenericParamDecls[paramIndex] = gpd
                        generic.typeParameters.add(gpd)
                    }
                }
            }
            idx++
        }
        LoadFlatGenericConstraints(reader, genericTable, generic)
        if (!generic.typeParameters.isEmpty()) {
            decl.EnableAttr(Attribute.GENERIC)
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (let Some(body) <- funcDecl.funcBody) {
                    body.generic = Some(generic)
                    return
                }
            }
            decl.generic = Some(generic)
        }
    }

    private func LoadFlatGenericConstraints(reader: CjoFlatBuffer, genericTable: Int64, generic: Generic): Unit {
        let constraints = reader.VectorField(genericTable, 6)
        if (constraints < 0) {
            return
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(constraints)
        while (idx < count) {
            let constraintTable = reader.VectorOffsetElement(constraints, idx)
            if (constraintTable >= 0) {
                generic.genericConstraints.add(LoadFlatGenericConstraint(reader, constraintTable))
            }
            idx++
        }
    }

    private func LoadFlatGenericConstraint(reader: CjoFlatBuffer, constraintTable: Int64): GenericConstraint {
        let constraint = GenericConstraint()
        if (let Some(typeTy) <- LoadFlatType(reader.U32Field(constraintTable, 8, 0u32))) {
            constraint.SetTy(typeTy)
            let typeNode = TypeNodeForTy(typeTy)
            if (let Some(refType) <- (typeNode as RefType)) {
                constraint.refType = Some(refType)
            } else {
                throw IllegalStateException("FlatBuffer generic constraint type is not a reference type: ${typeTy.String()}")
            }
        }
        let uppers = reader.VectorField(constraintTable, 10)
        if (uppers >= 0) {
            var idx: Int64 = 0
            let count = reader.VectorLength(uppers)
            while (idx < count) {
                if (let Some(upperTy) <- LoadFlatType(reader.VectorU32(uppers, idx))) {
                    constraint.upperBounds.add(TypeNodeForTy(upperTy))
                }
                idx++
            }
        }
        constraint.isImplicitlyIntroduced = reader.U8Field(constraintTable, 12, 0u8) != 0u8
        return constraint
    }

    private func EnsureFlatGenericParamMangle(param: GenericParamDecl, owner: Decl, ordinal: Int64): Unit {
        if (!param.mangledName.isEmpty()) {
            return
        }
        let ownerMangle = if (!owner.mangledName.isEmpty()) {
            owner.mangledName
        } else if (!owner.exportId.isEmpty()) {
            owner.exportId
        } else if (!owner.rawMangleName.isEmpty()) {
            owner.rawMangleName
        } else {
            owner.fullPackageName + "." + owner.identifier.Val()
        }
        let paramMangle = ownerMangle + ".G${ordinal}." + param.identifier.Val()
        param.mangledName = paramMangle
        param.rawMangleName = paramMangle
    }

    private func ExistingFlatGeneric(decl: Decl): Option<Generic> {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                if (let Some(generic) <- body.generic) {
                    return Some(generic)
                }
            }
        }
        return decl.generic
    }

    private func MapFlatGenericParameters(reader: CjoFlatBuffer, record: CjoFlatDecl, generic: Generic): Unit {
        let genericTable = reader.OffsetField(record.table, 12)
        if (genericTable < 0) {
            return
        }
        let typeParams = reader.VectorField(genericTable, 4)
        if (typeParams < 0) {
            return
        }
        var idx: Int64 = 0
        let limit = if (reader.VectorLength(typeParams) < generic.typeParameters.size) {
            reader.VectorLength(typeParams)
        } else {
            generic.typeParameters.size
        }
        while (idx < limit) {
            flatGenericParamDecls[reader.VectorU32(typeParams, idx)] = generic.typeParameters[idx]
            idx++
        }
    }

    private func MaterializeFlatInheritedTypes(reader: CjoFlatBuffer, record: CjoFlatDecl): Unit {
        if (!IsFlatInheritableDeclKind(record.kind)) {
            return
        }
        let declOpt = EnsureFlatDecl(record)
        if (let None <- declOpt) {
            return
        }
        let decl = declOpt.getOrThrow()
        if (let Some(inheritable) <- (decl as InheritableDecl)) {
            MapFlatGenericParameters(reader, record, decl)
            let infoTable = reader.OffsetField(record.table, 38)
            if (infoTable < 0) {
                return
            }
            let inheritedTypes = reader.VectorField(infoTable, 4)
            if (inheritedTypes < 0) {
                return
            }
            var idx: Int64 = 0
            let inheritedCount = reader.VectorLength(inheritedTypes)
            while (idx < inheritedCount) {
                let tyIndex = reader.VectorU32(inheritedTypes, idx)
                if (let Some(inheritedTy) <- LoadFlatType(tyIndex)) {
                    AddFlatInheritedType(inheritable, inheritedTy)
                }
                idx++
            }
        }
    }

    private func IsFlatInheritableDeclKind(kind: UInt16): Bool {
        return kind == 1u16 || kind == 2u16 || kind == 8u16 || kind == 9u16 || kind == 10u16
    }

    private func FlatNominalKind(kind: UInt16): Option<UInt8> {
        if (kind == 1u16) { return Some(b'C') }
        if (kind == 2u16) { return Some(b'I') }
        if (kind == 8u16) { return Some(b'S') }
        if (kind == 9u16) { return Some(b'U') }
        return None
    }

    private func EnsureFlatDecl(record: CjoFlatDecl): Option<Decl> {
        if (let Some(existing) <- record.decl) {
            return Some(existing)
        }
        if (let None <- flat) {
            return None
        }
        let reader = flat.getOrThrow()
        let decl = CreateFlatDeclShell(reader, record)
        record.decl = Some(decl)
        ApplyFlatDeclBasicInfo(reader, record, decl)
        if (let Some(gpd) <- (decl as GenericParamDecl)) {
            gpd.SetTy(GenericsTy(gpd.identifier.Val(), gpd))
            flatGenericParamDecls[record.index] = gpd
            return Some(gpd)
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            LoadFlatFuncDeclAdvancedInfo(reader, record, funcDecl)
            LoadFlatDeclType(record, funcDecl)
            return Some(funcDecl)
        }
        SetFlatGeneric(reader, record, decl)
        LoadFlatDeclType(record, decl)
        if (record.kind == 5u16) {
            if (let Some(varDecl) <- (decl as VarDecl)) {
                LoadFlatVarInfo(reader, record, varDecl)
            }
        }
        if (record.kind == 6u16) {
            if (let Some(varWithPattern) <- (decl as VarWithPatternDecl)) {
                LoadFlatVarWithPatternInfo(reader, record, varWithPattern)
            }
        }
        if (let Some(param) <- (decl as FuncParam)) {
            LoadFlatParamInfo(reader, record, param)
        }
        if (let Some(propDecl) <- (decl as PropDecl)) {
            LoadFlatPropInfo(reader, record, propDecl)
        }
        if (let Some(aliasDecl) <- (decl as TypeAliasDecl)) {
            LoadFlatTypeAliasInfo(reader, record, aliasDecl)
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            LoadFlatEnumInfo(reader, record, enumDecl)
        }
        if (let Some(inheritable) <- (decl as InheritableDecl)) {
            LoadFlatBodyMembers(reader, record, inheritable)
        }
        return Some(decl)
    }

    private func LoadFlatDeclType(record: CjoFlatDecl, decl: Decl): Unit {
        if (record.typeIndex == 0u32) {
            if (let Some(nominalKind) <- FlatNominalKind(record.kind)) {
                SetNominalTy(decl, record.identifier)
            }
            return
        }
        if (let Some(ty) <- LoadFlatType(record.typeIndex)) {
            decl.SetTy(ty)
            if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
                varDecl.typeNode = Some(TypeNodeForTy(ty))
            }
            if (let Some(aliasDecl) <- (decl as TypeAliasDecl)) {
                aliasDecl.typeNode = Some(TypeNodeForTy(ty))
            }
            if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                extendDecl.extendedType = Some(TypeNodeForTy(ty))
            }
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (let Some(body) <- funcDecl.funcBody) {
                    body.SetTy(ty)
                    if (let Some(funcTy) <- (ty as FuncTy)) {
                        body.retType = Some(TypeNodeForTy(funcTy.retTy))
                    }
                }
            }
        } else if (let Some(_) <- FlatNominalKind(record.kind)) {
            SetNominalTy(decl, record.identifier)
        }
    }

    private func LoadFlatFuncDeclAdvancedInfo(reader: CjoFlatBuffer, record: CjoFlatDecl, funcDecl: FuncDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            throw IllegalStateException("FlatBuffer FuncDecl '${record.identifier}' has no FuncInfo")
        }
        funcDecl.overflowStrategy = FlatOverflowStrategy(reader.U8Field(infoTable, 6, 0u8))
        funcDecl.op = FlatOperatorKind(reader.U8Field(infoTable, 8, 0u8))
        funcDecl.isConst = reader.U8Field(infoTable, 12, 0u8) != 0u8
        funcDecl.isInline = reader.U8Field(infoTable, 14, 0u8) != 0u8
        funcDecl.isFastNative = reader.U8Field(infoTable, 16, 0u8) != 0u8
        // Mirror ASTLoader.cpp:810-811: derive isFrozen from the loaded @Frozen annotation
        // (annotations are loaded in ApplyFlatDeclBasicInfo, which runs before this).
        funcDecl.isFrozen = funcDecl.HasAnno(AstAnnotationKind.FROZEN)
        let bodyTable = reader.OffsetField(infoTable, 4)
        if (bodyTable < 0) {
            throw IllegalStateException("FlatBuffer FuncDecl '${record.identifier}' has no FuncBody")
        }
        let body = LoadFlatFuncBody(reader, bodyTable, Some(funcDecl), funcDecl.isInline, funcDecl.isConst)
        body.funcDecl = Some(funcDecl)
        funcDecl.funcBody = Some(body)
        // Update param functions' references: set ownerFunc on each param's desugar (default-param)
        // function, for top-level AND member funcs. Mirrors C++ ASTLoader.cpp:829-833 — without this
        // a top-level imported generic func's default-param desugar (e.g. y.1 <T$0,P$1>) has no
        // ownerFunc, so MangleFunctionDecl skips MangleDeclName and never declares <T$0> on the
        // generics stack, throwing "Using undeclared generic type" at mangle time.
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                if (let Some(desugar) <- param.desugarDecl) {
                    desugar.ownerFunc = Some(funcDecl)
                }
            }
        }
        SetFlatGeneric(reader, record, funcDecl)
        if (let Some(funcTy) <- FlatFuncTypeFromBody(reader, bodyTable, body)) {
            body.SetTy(funcTy)
            funcDecl.SetTy(funcTy)
        }
        SetOuterFunctionDecl(funcDecl)
    }

    // Loads FuncBody.body (fbs FuncBody field 2 / slot 8 = body expr index), gated by the current
    // selfhost shouldImportBody path. On import, the loaded Block is the un-wrapped funcBody.body
    // (LoadExpr<Block>, no dummy-RefExpr wrap), and every nested ReturnExpr's refFuncBody is set to
    // this funcBody (ExprLoader.cpp:500-509).
    private func LoadFlatFuncBody(reader: CjoFlatBuffer, bodyTable: Int64, funcDecl: Option<FuncDecl>,
        isInline: Bool, isConst: Bool): FuncBody {
        let body = FuncBody()
        LoadFlatFuncParamLists(reader, bodyTable, body)
        if (let Some(retTy) <- LoadFlatType(reader.U32Field(bodyTable, 6, 0u32))) {
            body.retType = Some(TypeNodeForTy(retTy))
        }
        body.captureKind = FlatCaptureKind(reader.U8Field(bodyTable, 12, 0u8))
        if (let Some(fd) <- funcDecl) {
            body.funcDecl = Some(fd)
        }
        LoadFlatFuncBodyContent(reader, bodyTable, isInline, isConst, body)
        body.EnableAttr(Attribute.IMPORTED)
        return body
    }

    private func LoadFlatFuncBodyContent(reader: CjoFlatBuffer, bodyTable: Int64, isInline: Bool, isConst: Bool,
        body: FuncBody): Unit {
        let always = reader.U8Field(bodyTable, 10, 0u8) != 0u8
        let shouldImportBody = always || isInline || isConst
        if (!shouldImportBody) {
            return
        }
        // FuncBody field 2 (slot 8) = body expr index.
        let bodyIndex = reader.U32Field(bodyTable, 8, 0u32)
        if (let Some(loaded) <- LoadFlatExprRaw(reader, bodyIndex)) {
            if (let Some(block) <- (loaded as Block)) {
                body.body = Some(block)
                let setRefFuncBody = { node: Node =>
                    if (node.astKind == ASTKind.FUNC_BODY) {
                        return VisitAction.SKIP_CHILDREN
                    }
                    if (let Some(re) <- (node as ReturnExpr)) {
                        re.refFuncBody = Some(body)
                    }
                    return VisitAction.WALK_CHILDREN
                }
                Walker(block, visitPre: setRefFuncBody).Walk()
            }
        }
    }

    private func LoadFlatFuncParamLists(reader: CjoFlatBuffer, bodyTable: Int64, body: FuncBody): Unit {
        let lists = reader.VectorField(bodyTable, 4)
        if (lists < 0) {
            return
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(lists)
        while (idx < count) {
            body.paramLists.add(LoadFlatFuncParamList(reader, reader.VectorOffsetElement(lists, idx)))
            idx++
        }
    }

    private func LoadFlatFuncParamList(reader: CjoFlatBuffer, listTable: Int64): FuncParamList {
        let list = FuncParamList()
        let params = reader.VectorField(listTable, 4)
        let desugars = reader.VectorField(listTable, 6)
        if (params < 0) {
            return list
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(params)
        while (idx < count) {
            let paramIndex = reader.VectorU32(params, idx)
            if (let Some(paramRecord) <- flatDecls.get(paramIndex)) {
                if (let Some(paramDecl) <- EnsureFlatDecl(paramRecord)) {
                    if (let Some(param) <- (paramDecl as FuncParam)) {
                        if (desugars >= 0 && idx < reader.VectorLength(desugars)) {
                            let desugarIndex = reader.VectorU32(desugars, idx)
                            if (desugarIndex != 0u32) {
                                if (let Some(desugarRecord) <- flatDecls.get(desugarIndex)) {
                                    if (let Some(desugarDecl) <- EnsureFlatDecl(desugarRecord)) {
                                        if (let Some(desugarFunc) <- (desugarDecl as FuncDecl)) {
                                            param.desugarDecl = Some(desugarFunc)
                                        }
                                    }
                                }
                            }
                        }
                        list.params.add(param)
                    }
                }
            }
            idx++
        }
        return list
    }

    private func FlatFuncTypeFromBody(reader: CjoFlatBuffer, bodyTable: Int64, body: FuncBody): Option<FuncTy> {
        let params = ArrayList<Ty>()
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                params.add(param.GetTy() ?? InvalidTy())
            }
        }
        let retTy = LoadFlatType(reader.U32Field(bodyTable, 6, 0u32)) ?? PrimitiveTy(TypeKind.TYPE_UNIT)
        return Some(FuncTy(params.toArray(), retTy))
    }

    private func LoadFlatVarInfo(reader: CjoFlatBuffer, record: CjoFlatDecl, varDecl: VarDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            return
        }
        varDecl.isVar = reader.U8Field(infoTable, 4, 0u8) != 0u8
        varDecl.isConst = reader.U8Field(infoTable, 6, 0u8) != 0u8
        varDecl.isMemberParam = reader.U8Field(infoTable, 8, 0u8) != 0u8
        // VarInfo field 3 (vtable slot 10) = initializer expr index. Mirrors ASTLoader.cpp:719-720.
        let initIndex = reader.U32Field(infoTable, 10, 0u32)
        if (let Some(initializer) <- LoadFlatExpr(reader, initIndex)) {
            varDecl.initializer = Some(initializer)
        }
    }

    // Generic LoadExpr<Expr> entry: loads the raw expr then applies the C++ dummy-RefExpr wrap when
    // the loaded node is a Block (ExprLoader.cpp:417-443 — the `if constexpr (!is_same<ExprT,Block>)`
    // branch creates a COMPILER_ADD RefExpr whose desugarExpr is the Block, so CHIR can generate the
    // 'goto'). Used for sub-expr operands (default ExprT). For funcBody.body, the un-wrapped Block is
    // needed, so that call site uses LoadFlatExprRaw + a direct Block cast instead.
    private func LoadFlatExpr(reader: CjoFlatBuffer, exprIndex: UInt32): Option<Expr> {
        let loaded = LoadFlatExprRaw(reader, exprIndex)
        if (let Some(expr) <- loaded) {
            if (let Some(block) <- (expr as Block)) {
                let dummy = RefExpr()
                dummy.EnableAttr(Attribute.COMPILER_ADD)
                if (let Some(ty) <- block.GetTy()) {
                    dummy.SetTy(ty)
                }
                dummy.desugarExpr = block
                return dummy
            }
        }
        return loaded
    }

    // Recursive EXPR-load dispatcher. Loads an Expr by its 1-based index from the package allExprs
    // vector (root field 9, slot 22). Mirrors ExprLoader.cpp LoadExpr (:417-443) + per-kind loaders.
    // Bounded faithful slice: all expression kinds materialized by C++ ExprLoader.cpp.
    // Returns None for INVALID_FORMAT_INDEX (0) and malformed FuncArg/subnode wrapper records only.
    private func LoadFlatExprRaw(reader: CjoFlatBuffer, exprIndex: UInt32): Option<Expr> {
        if (exprIndex == 0u32 || flatAllExprs < 0) {
            return None
        }
        let count = reader.VectorLength(flatAllExprs)
        let idx = Int64(exprIndex) - 1
        if (idx < 0 || idx >= count) {
            return None
        }
        let exprTable = reader.VectorOffsetElement(flatAllExprs, idx)
        if (exprTable < 0) {
            return None
        }
        // Expr field 0 (slot 4) = kind.
        let kind = reader.U16Field(exprTable, 4, 0u16)
        if (kind == FLAT_EXPR_KIND_WILDCARD) {
            return Some(LoadFlatWildcardExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_PRIMITIVE_TYPE) {
            return Some(LoadFlatPrimitiveTypeExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_LIT_CONST) {
            return Some(LoadFlatLitConstExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_MEMBER_ACCESS) {
            return Some(LoadFlatMemberAccess(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_REF_EXPR) {
            return Some(LoadFlatRefExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_UNARY) {
            return Some(LoadFlatUnaryExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_INC_OR_DEC) {
            return Some(LoadFlatIncOrDecExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_BINARY) {
            return Some(LoadFlatBinaryExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_SUBSCRIPT) {
            return Some(LoadFlatSubscriptExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_ASSIGN) {
            return Some(LoadFlatAssignExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_ARRAY_EXPR) {
            return Some(LoadFlatArrayExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_POINTER_EXPR) {
            return Some(LoadFlatPointerExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_JUMP) {
            return Some(LoadFlatJumpExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_TYPE_CONV) {
            return Some(LoadFlatTypeConvExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_THROW) {
            return Some(LoadFlatThrowExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_PERFORM) {
            return Some(LoadFlatPerformExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_RESUME) {
            return Some(LoadFlatResumeExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_SPAWN) {
            return Some(LoadFlatSpawnExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_TRY) {
            return Some(LoadFlatTryExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_IF) {
            return Some(LoadFlatIfExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_WHILE) {
            return Some(LoadFlatWhileExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_DO_WHILE) {
            return Some(LoadFlatDoWhileExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_ARRAY_LIT) {
            return Some(LoadFlatArrayLit(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_TUPLE_LIT) {
            return Some(LoadFlatTupleLit(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_MATCH) {
            return Some(LoadFlatMatchExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_LET_PATTERN_DESTRUCTOR) {
            return Some(LoadFlatLetPatternDestructor(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_FOR_IN) {
            return Some(LoadFlatForInExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_LAMBDA) {
            return Some(LoadFlatLambdaExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_CALL) {
            // Mirrors ExprLoader.cpp:92-115 LoadCallExpr and ExprLoader.cpp:516-531 LoadFuncArg.
            let ce = CallExpr()
            LoadFlatExprBasicInfo(reader, exprTable, ce)
            let operands = reader.VectorField(exprTable, 12)
            if (operands < 0 || reader.VectorLength(operands) < 1) {
                return None
            }
            if (let Some(base) <- LoadFlatExpr(reader, reader.VectorU32(operands, 0))) {
                ce.baseFunc = Some(base)
            } else {
                return None
            }
            var argIdx: Int64 = 1
            let argCount = reader.VectorLength(operands)
            while (argIdx < argCount) {
                if (let Some(arg) <- LoadFlatFuncArg(reader, reader.VectorU32(operands, argIdx))) {
                    ce.args.add(arg)
                } else {
                    return None
                }
                argIdx++
            }
            let desugarArgs = ArrayList<FuncArg>()
            for (arg in ce.args) {
                desugarArgs.add(arg)
            }
            ce.desugarArgs = Some(desugarArgs)
            let infoTable = reader.OffsetField(exprTable, 20)
            if (infoTable >= 0) {
                let flatCallKind = reader.U8Field(infoTable, 6, 0u8)
                if (flatCallKind == 1u8) {
                    ce.callKind = CallKind.CALL_DECLARED_FUNCTION
                } else if (flatCallKind == 2u8) {
                    ce.callKind = CallKind.CALL_OBJECT_CREATION
                } else if (flatCallKind == 3u8) {
                    ce.callKind = CallKind.CALL_FUNCTION_PTR
                } else if (flatCallKind == 4u8) {
                    ce.callKind = CallKind.CALL_STRUCT_CREATION
                } else if (flatCallKind == 5u8) {
                    ce.callKind = CallKind.CALL_SUPER_FUNCTION
                } else if (flatCallKind == 6u8) {
                    ce.callKind = CallKind.CALL_VARIADIC_FUNCTION
                } else if (flatCallKind == 7u8) {
                    ce.callKind = CallKind.CALL_ANNOTATION
                } else if (flatCallKind == 8u8) {
                    ce.callKind = CallKind.CALL_BUILTIN_FUNCTION
                } else if (flatCallKind == 9u8) {
                    ce.callKind = CallKind.CALL_INTRINSIC_FUNCTION
                }
                if (reader.U8Field(infoTable, 4, 0u8) != 0u8) {
                    ce.EnableAttr(Attribute.SIDE_EFFECT)
                }
            }
            if (let Some(base) <- ce.baseFunc) {
                if (let Some(nameRef) <- (base as NameReferenceExpr)) {
                    nameRef.isAlone = false
                }
            }
            ce.EnableAttr(Attribute.IMPORTED)
            return Some(ce)
        }
        if (kind == FLAT_EXPR_KIND_RETURN) {
            return Some(LoadFlatReturnExpr(reader, exprTable))
        }
        if (kind == FLAT_EXPR_KIND_BLOCK) {
            return Some(LoadFlatBlock(reader, exprTable))
        }
        return None
    }

    // Mirrors ExprLoader.cpp:348-358 LoadLambdaExpr: LambdaInfo owns a nested FuncBody and
    // supportMock restores Attribute.MOCK_SUPPORTED. LoadFuncBody is called with C++ defaults
    // (isInline=false, isConst=true), so the lambda body is imported when source is present.
    private func LoadFlatLambdaExpr(reader: CjoFlatBuffer, exprTable: Int64): LambdaExpr {
        let le = LambdaExpr()
        LoadFlatExprBasicInfo(reader, exprTable, le)
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            let bodyTable = reader.OffsetField(infoTable, 4)
            if (bodyTable >= 0) {
                le.funcBody = Some(LoadFlatFuncBody(reader, bodyTable, None, false, true))
            }
            if (reader.U8Field(infoTable, 6, 0u8) != 0u8) {
                le.EnableAttr(Attribute.MOCK_SUPPORTED)
            }
        }
        le.EnableAttr(Attribute.IMPORTED)
        return le
    }

    // Mirrors ExprLoader.cpp:33-37 LoadWildcardExpr. WildcardExpr has no extra ExprInfo table.
    private func LoadFlatWildcardExpr(reader: CjoFlatBuffer, exprTable: Int64): WildcardExpr {
        let we = WildcardExpr()
        LoadFlatExprBasicInfo(reader, exprTable, we)
        we.EnableAttr(Attribute.IMPORTED)
        return we
    }

    // Mirrors ExprLoader.cpp:39-48 LoadPrimitiveTypeExpr. The serialized Expr.type field points to
    // the PackageFormat::Type; the type kind is recovered through the same primitive type map used by
    // LoadFlatType.
    private func LoadFlatPrimitiveTypeExpr(reader: CjoFlatBuffer, exprTable: Int64): PrimitiveTypeExpr {
        let ty = LoadFlatType(reader.U32Field(exprTable, 14, 0u32))
        let kind = if (let Some(value) <- ty) { value.kind } else { TypeKind.TYPE_INVALID }
        let pte = PrimitiveTypeExpr(kind)
        LoadFlatExprBasicInfo(reader, exprTable, pte)
        pte.EnableAttr(Attribute.IMPORTED)
        return pte
    }

    // Mirrors ExprLoader.cpp:58-66 LoadJumpExpr. JumpInfo carries only isBreak.
    private func LoadFlatJumpExpr(reader: CjoFlatBuffer, exprTable: Int64): JumpExpr {
        let je = JumpExpr()
        LoadFlatExprBasicInfo(reader, exprTable, je)
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            je.isBreak = reader.U8Field(infoTable, 4, 0u8) != 0u8
        }
        je.EnableAttr(Attribute.IMPORTED)
        return je
    }

    // Mirrors ExprLoader.cpp:130-138 LoadIncOrDecExpr. Operand 0 is expr; IncOrDecInfo field 0
    // (slot 4) is the OperatorKind encoded through OP_KIND_RMAP.
    private func LoadFlatIncOrDecExpr(reader: CjoFlatBuffer, exprTable: Int64): IncOrDecExpr {
        let ide = IncOrDecExpr()
        LoadFlatExprBasicInfo(reader, exprTable, ide)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            ide.expr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            ide.op = FlatOperatorKind(reader.U8Field(infoTable, 4, 0u8))
        }
        ide.EnableAttr(Attribute.IMPORTED)
        return ide
    }

    // Mirrors ExprLoader.cpp:220-227 LoadTypeConvExpr. Operand 0 is the converted expr.
    private func LoadFlatTypeConvExpr(reader: CjoFlatBuffer, exprTable: Int64): TypeConvExpr {
        let tce = TypeConvExpr()
        LoadFlatExprBasicInfo(reader, exprTable, tce)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            tce.expr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        tce.EnableAttr(Attribute.IMPORTED)
        return tce
    }

    // Mirrors ExprLoader.cpp:228-233 LoadThrowExpr. Operand 0 is the thrown expr.
    private func LoadFlatThrowExpr(reader: CjoFlatBuffer, exprTable: Int64): ThrowExpr {
        let te = ThrowExpr()
        LoadFlatExprBasicInfo(reader, exprTable, te)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            te.expr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        te.EnableAttr(Attribute.IMPORTED)
        return te
    }

    // Mirrors ExprLoader.cpp:236-241 LoadPerformExpr. Operand 0 is the performed expr.
    private func LoadFlatPerformExpr(reader: CjoFlatBuffer, exprTable: Int64): PerformExpr {
        let pe = PerformExpr()
        LoadFlatExprBasicInfo(reader, exprTable, pe)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            pe.expr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        pe.EnableAttr(Attribute.IMPORTED)
        return pe
    }

    // Mirrors ExprLoader.cpp:244-247 LoadResumeExpr. The serialized package format carries no
    // additional ResumeExpr fields in this loader path.
    private func LoadFlatResumeExpr(reader: CjoFlatBuffer, exprTable: Int64): ResumeExpr {
        let re = ResumeExpr()
        LoadFlatExprBasicInfo(reader, exprTable, re)
        re.EnableAttr(Attribute.IMPORTED)
        return re
    }

    // Mirrors ExprLoader.cpp:250-262 LoadSpawnExpr. Operand 0 is the optional thread-context arg;
    // SpawnInfo.future is a local VarDecl FullId.
    private func LoadFlatSpawnExpr(reader: CjoFlatBuffer, exprTable: Int64): SpawnExpr {
        let se = SpawnExpr()
        LoadFlatExprBasicInfo(reader, exprTable, se)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) > 0) {
            se.arg = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            if (let Some(decl) <- ResolveFlatFullId(reader, reader.OffsetField(infoTable, 4))) {
                se.futureObj = decl as VarDecl
            }
        }
        se.EnableAttr(Attribute.IMPORTED)
        return se
    }

    // Mirrors ExprLoader.cpp:198-208 LoadArrayExpr and ReferenceLoader.cpp:622-630 for optional
    // ArrayInfo.initFunc on non-VArray array constructor expressions.
    private func LoadFlatArrayExpr(reader: CjoFlatBuffer, exprTable: Int64): ArrayExpr {
        let ae = ArrayExpr()
        LoadFlatExprBasicInfo(reader, exprTable, ae)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0) {
            var idx: Int64 = 0
            let count = reader.VectorLength(operands)
            while (idx < count) {
                if (let Some(arg) <- LoadFlatFuncArg(reader, reader.VectorU32(operands, idx))) {
                    ae.args.add(arg)
                }
                idx++
            }
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            ae.isValueArray = reader.U8Field(infoTable, 6, 0u8) != 0u8
            if (ae.TyKind() != TypeKind.TYPE_VARRAY) {
                if (let Some(initDecl) <- ResolveFlatFullId(reader, reader.OffsetField(infoTable, 4))) {
                    ae.initFunc = initDecl as FuncDecl
                }
            }
        }
        ae.EnableAttr(Attribute.IMPORTED)
        return ae
    }

    // Mirrors ExprLoader.cpp:211-217 LoadPointerExpr. Optional operand 0 is a FuncArg wrapper.
    private func LoadFlatPointerExpr(reader: CjoFlatBuffer, exprTable: Int64): PointerExpr {
        let pe = PointerExpr()
        LoadFlatExprBasicInfo(reader, exprTable, pe)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) == 1) {
            pe.arg = LoadFlatFuncArg(reader, reader.VectorU32(operands, 0))
        }
        pe.EnableAttr(Attribute.IMPORTED)
        return pe
    }

    // Mirrors ExprLoader.cpp:303-327 LoadTryExpr and ReferenceLoader.cpp:676-682. Operands are
    // tryBlock, zero or more catch blocks, then finallyBlock-or-0; TryInfo owns catch patterns and
    // resource VarDecl FullIds (ModuleFormat.fbs:486-489).
    private func LoadFlatTryExpr(reader: CjoFlatBuffer, exprTable: Int64): TryExpr {
        let te = TryExpr()
        LoadFlatExprBasicInfo(reader, exprTable, te)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            if (let Some(tryExpr) <- LoadFlatExprRaw(reader, reader.VectorU32(operands, 0))) {
                te.tryBlock = tryExpr as Block
            }
            var operandIdx: Int64 = 1
            let operandCount = reader.VectorLength(operands)
            while (operandIdx < operandCount - 1) {
                if (let Some(catchExpr) <- LoadFlatExprRaw(reader, reader.VectorU32(operands, operandIdx))) {
                    if (let Some(catchBlock) <- (catchExpr as Block)) {
                        te.catchBlocks.add(catchBlock)
                    }
                }
                operandIdx++
            }
            let finallyIndex = reader.VectorU32(operands, operandCount - 1)
            if (let Some(finallyExpr) <- LoadFlatExprRaw(reader, finallyIndex)) {
                te.finallyBlock = finallyExpr as Block
            }
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            let resources = reader.VectorField(infoTable, 4)
            if (resources >= 0) {
                var resourceIdx: Int64 = 0
                let resourceCount = reader.VectorLength(resources)
                while (resourceIdx < resourceCount) {
                    if (let Some(resourceDecl) <- ResolveFlatFullId(reader,
                        reader.VectorOffsetElement(resources, resourceIdx))) {
                        if (let Some(varDecl) <- (resourceDecl as VarDecl)) {
                            te.resourceSpec.add(varDecl)
                        }
                    }
                    resourceIdx++
                }
            }
            let patterns = reader.VectorField(infoTable, 6)
            if (patterns >= 0) {
                var patternIdx: Int64 = 0
                let patternCount = reader.VectorLength(patterns)
                while (patternIdx < patternCount) {
                    if (let Some(pattern) <- LoadFlatPattern(reader, reader.VectorOffsetElement(patterns, patternIdx))) {
                        te.catchPatterns.add(pattern)
                    }
                    patternIdx++
                }
            }
        }
        te.EnableAttr(Attribute.IMPORTED)
        return te
    }

    // Mirrors ExprLoader.cpp:285-300 LoadIfExpr. Operands are condExpr, thenBody, elseBody; hasElse
    // and isElseIf are recovered from the loaded else node rather than serialized as fields.
    private func LoadFlatIfExpr(reader: CjoFlatBuffer, exprTable: Int64): IfExpr {
        let ie = IfExpr()
        LoadFlatExprBasicInfo(reader, exprTable, ie)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 2) {
            ie.condExpr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
            if (let Some(thenExpr) <- LoadFlatExprRaw(reader, reader.VectorU32(operands, 1))) {
                ie.thenBody = thenExpr as Block
            }
            if (reader.VectorLength(operands) > 2) {
                ie.elseBody = LoadFlatExpr(reader, reader.VectorU32(operands, 2))
            }
        }
        ie.hasElse = ie.elseBody.isSome()
        if (let Some(elseExpr) <- ie.elseBody) {
            ie.isElseIf = elseExpr.astKind == ASTKind.IF_EXPR
            if (let Some(desugar) <- elseExpr.desugarExpr) {
                ie.elseBody = Some(desugar)
            }
        }
        ie.EnableAttr(Attribute.IMPORTED)
        return ie
    }

    // Mirrors ExprLoader.cpp:330-337 LoadWhileExpr. Operands are condExpr then body; the body is
    // loaded raw as Block, matching C++ LoadExpr<Block>.
    private func LoadFlatWhileExpr(reader: CjoFlatBuffer, exprTable: Int64): WhileExpr {
        let we = WhileExpr()
        LoadFlatExprBasicInfo(reader, exprTable, we)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) == 2) {
            we.condExpr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
            if (let Some(bodyExpr) <- LoadFlatExprRaw(reader, reader.VectorU32(operands, 1))) {
                we.body = bodyExpr as Block
            }
        }
        we.EnableAttr(Attribute.IMPORTED)
        return we
    }

    // Mirrors ExprLoader.cpp:339-346 LoadDoWhileExpr. Operands are body then condExpr; the body is
    // loaded raw as Block, matching C++ LoadExpr<Block>.
    private func LoadFlatDoWhileExpr(reader: CjoFlatBuffer, exprTable: Int64): DoWhileExpr {
        let dwe = DoWhileExpr()
        LoadFlatExprBasicInfo(reader, exprTable, dwe)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) == 2) {
            if (let Some(bodyExpr) <- LoadFlatExprRaw(reader, reader.VectorU32(operands, 0))) {
                dwe.body = bodyExpr as Block
            }
            dwe.condExpr = LoadFlatExpr(reader, reader.VectorU32(operands, 1))
        }
        dwe.EnableAttr(Attribute.IMPORTED)
        return dwe
    }

    // Mirrors ExprLoader.cpp:383-402 LoadMatchExpr. MatchInfo.matchMode decides whether operands are
    // selector + MatchCase indexes or MatchCaseOther indexes.
    private func LoadFlatMatchExpr(reader: CjoFlatBuffer, exprTable: Int64): MatchExpr {
        let me = MatchExpr()
        LoadFlatExprBasicInfo(reader, exprTable, me)
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            me.matchMode = reader.U8Field(infoTable, 4, 0u8) != 0u8
        }
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0) {
            if (me.matchMode) {
                if (reader.VectorLength(operands) >= 1) {
                    me.selector = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
                    var idx: Int64 = 1
                    let count = reader.VectorLength(operands)
                    while (idx < count) {
                        if (let Some(matchCase) <- LoadFlatMatchCase(reader, reader.VectorU32(operands, idx))) {
                            if (let Some(selector) <- me.selector) {
                                matchCase.SetCtxExprForPatterns(selector)
                            }
                            me.matchCases.add(matchCase)
                        }
                        idx++
                    }
                }
            } else {
                var idx: Int64 = 0
                let count = reader.VectorLength(operands)
                while (idx < count) {
                    if (let Some(matchCase) <- LoadFlatMatchCaseOther(reader, reader.VectorU32(operands, idx))) {
                        me.matchCaseOthers.add(matchCase)
                    }
                    idx++
                }
            }
        }
        me.EnableAttr(Attribute.IMPORTED)
        return me
    }

    // Mirrors ExprLoader.cpp:445-458 LoadMatchCase plus ReferenceLoader.cpp:732-743: this loader
    // restores the wrapper ty and pattern tys immediately so imported Frozen bodies can CHIR-lower.
    private func LoadFlatMatchCase(reader: CjoFlatBuffer, exprIndex: UInt32): Option<MatchCase> {
        let exprTable = FlatExprTable(reader, exprIndex)
        if (exprTable < 0 || reader.U16Field(exprTable, 4, 0u16) != FLAT_EXPR_KIND_MATCH_CASE) {
            return None
        }
        let mc = MatchCase()
        LoadFlatNodeBasicInfo(reader, exprTable, mc)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 2) {
            mc.patternGuard = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
            if (let Some(bodyExpr) <- LoadFlatExprRaw(reader, reader.VectorU32(operands, 1))) {
                mc.exprOrDecls = bodyExpr as Block
            }
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            let patterns = reader.VectorField(infoTable, 4)
            if (patterns >= 0) {
                var idx: Int64 = 0
                let count = reader.VectorLength(patterns)
                while (idx < count) {
                    if (let Some(pattern) <- LoadFlatPattern(reader, reader.VectorOffsetElement(patterns, idx))) {
                        mc.patterns.add(pattern)
                    }
                    idx++
                }
            }
        }
        mc.EnableAttr(Attribute.IMPORTED)
        return Some(mc)
    }

    // Mirrors ExprLoader.cpp:478-486 LoadMatchCaseOther; this wrapper has no ExprInfo table.
    private func LoadFlatMatchCaseOther(reader: CjoFlatBuffer, exprIndex: UInt32): Option<MatchCaseOther> {
        let exprTable = FlatExprTable(reader, exprIndex)
        if (exprTable < 0 || reader.U16Field(exprTable, 4, 0u16) != FLAT_EXPR_KIND_MATCH_CASE_OTHER) {
            return None
        }
        let mco = MatchCaseOther()
        LoadFlatNodeBasicInfo(reader, exprTable, mco)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 2) {
            mco.matchExpr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
            if (let Some(bodyExpr) <- LoadFlatExprRaw(reader, reader.VectorU32(operands, 1))) {
                mco.exprOrDecls = bodyExpr as Block
            }
        }
        mco.EnableAttr(Attribute.IMPORTED)
        return Some(mco)
    }

    // Mirrors ExprLoader.cpp:404-414 LoadLetPatternDestructor plus ReferenceLoader.cpp:717-724:
    // the selfhost loader restores expr and pattern tys eagerly instead of in a later refs pass.
    private func LoadFlatLetPatternDestructor(reader: CjoFlatBuffer, exprTable: Int64): LetPatternDestructor {
        let lpd = LetPatternDestructor()
        LoadFlatExprBasicInfo(reader, exprTable, lpd)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            lpd.initializer = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            let patterns = reader.VectorField(infoTable, 4)
            if (patterns >= 0) {
                var idx: Int64 = 0
                let count = reader.VectorLength(patterns)
                while (idx < count) {
                    if (let Some(pattern) <- LoadFlatPattern(reader, reader.VectorOffsetElement(patterns, idx))) {
                        lpd.patterns.add(pattern)
                    }
                    idx++
                }
            }
        }
        lpd.EnableAttr(Attribute.IMPORTED)
        return lpd
    }

    // Mirrors ExprLoader.cpp:460-475 LoadForInExpr. Desugared for-in variants have non-invalid
    // ForInKind and load operand 0 as a raw Block, matching C++ LoadExpr<Block>.
    private func LoadFlatForInExpr(reader: CjoFlatBuffer, exprTable: Int64): ForInExpr {
        let fie = ForInExpr()
        LoadFlatExprBasicInfo(reader, exprTable, fie)
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            fie.forInKind = FlatToForInKind(reader.U8Field(infoTable, 6, 0u8))
            fie.pattern = LoadFlatPattern(reader, reader.OffsetField(infoTable, 4))
        }
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) == 3) {
            if (IsInvalidForInKind(fie.forInKind)) {
                fie.inExpression = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
            } else if (let Some(inExpr) <- LoadFlatExprRaw(reader, reader.VectorU32(operands, 0))) {
                if (let Some(block) <- (inExpr as Block)) {
                    fie.inExpression = Some(block)
                }
            }
            fie.patternGuard = LoadFlatExpr(reader, reader.VectorU32(operands, 1))
            if (let Some(bodyExpr) <- LoadFlatExprRaw(reader, reader.VectorU32(operands, 2))) {
                fie.body = bodyExpr as Block
            }
        }
        fie.EnableAttr(Attribute.IMPORTED)
        return fie
    }

    private func FlatToForInKind(kind: UInt8): ForInKind {
        if (kind == 1u8) {
            return ForInKind.FORIN_RANGE
        }
        if (kind == 2u8) {
            return ForInKind.FORIN_STRING
        }
        if (kind == 3u8) {
            return ForInKind.FORIN_ITER
        }
        return ForInKind.FORIN_INVALID
    }

    private func IsInvalidForInKind(kind: ForInKind): Bool {
        match (kind) {
            case ForInKind.FORIN_INVALID => true
            case _ => false
        }
    }

    // Mirrors ExprLoader.cpp:118-127 LoadUnaryExpr. Operand 0 is expr; UnaryInfo field 0 (slot 4)
    // is the OperatorKind encoded through OP_KIND_RMAP.
    private func LoadFlatUnaryExpr(reader: CjoFlatBuffer, exprTable: Int64): UnaryExpr {
        let ue = UnaryExpr()
        LoadFlatExprBasicInfo(reader, exprTable, ue)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            ue.expr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            ue.op = FlatOperatorKind(reader.U8Field(infoTable, 4, 0u8))
        }
        ue.EnableAttr(Attribute.IMPORTED)
        return ue
    }

    // Mirrors ExprLoader.cpp:154-163 LoadBinaryExpr. Operands are left then right; BinaryInfo field
    // 0 (slot 4) is the OperatorKind encoded through OP_KIND_RMAP.
    private func LoadFlatBinaryExpr(reader: CjoFlatBuffer, exprTable: Int64): BinaryExpr {
        let be = BinaryExpr()
        LoadFlatExprBasicInfo(reader, exprTable, be)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 2) {
            be.leftExpr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
            be.rightExpr = LoadFlatExpr(reader, reader.VectorU32(operands, 1))
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            be.op = FlatOperatorKind(reader.U8Field(infoTable, 4, 0u8))
        }
        be.EnableAttr(Attribute.IMPORTED)
        return be
    }

    // Mirrors ExprLoader.cpp:166-183 LoadSubscriptExpr. Operand 0 is baseExpr; remaining operands are
    // indexExprs. SubscriptInfo.isTupleAccess is restored from ModuleFormat.fbs:477-479.
    private func LoadFlatSubscriptExpr(reader: CjoFlatBuffer, exprTable: Int64): SubscriptExpr {
        let se = SubscriptExpr()
        LoadFlatExprBasicInfo(reader, exprTable, se)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) > 1) {
            se.baseExpr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
            var idx: Int64 = 1
            let count = reader.VectorLength(operands)
            while (idx < count) {
                if (let Some(indexExpr) <- LoadFlatExpr(reader, reader.VectorU32(operands, idx))) {
                    se.indexExprs.add(indexExpr)
                }
                idx++
            }
            if (let Some(base) <- se.baseExpr) {
                if (let Some(nameRef) <- (base as NameReferenceExpr)) {
                    nameRef.isAlone = false
                }
            }
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            se.isTupleAccess = reader.U8Field(infoTable, 4, 0u8) != 0u8
        }
        se.EnableAttr(Attribute.IMPORTED)
        return se
    }

    // Mirrors ExprLoader.cpp:186-195 LoadAssignExpr. Operands are leftValue then rightExpr; AssignInfo
    // restores op and isCompound through OP_KIND_RMAP.
    private func LoadFlatAssignExpr(reader: CjoFlatBuffer, exprTable: Int64): AssignExpr {
        let ae = AssignExpr()
        LoadFlatExprBasicInfo(reader, exprTable, ae)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 2) {
            ae.leftValue = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
            ae.rightExpr = LoadFlatExpr(reader, reader.VectorU32(operands, 1))
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            ae.op = FlatOperatorKind(reader.U8Field(infoTable, 6, 0u8))
            ae.isCompound = reader.U8Field(infoTable, 4, 0u8) != 0u8
        }
        ae.EnableAttr(Attribute.IMPORTED)
        return ae
    }

    // Mirrors ExprLoader.cpp:265-272 LoadArrayLit for children and ReferenceLoader.cpp:612-620 for
    // ArrayInfo.initFunc on non-VArray literals.
    private func LoadFlatArrayLit(reader: CjoFlatBuffer, exprTable: Int64): ArrayLit {
        let al = ArrayLit()
        LoadFlatExprBasicInfo(reader, exprTable, al)
        LoadFlatExprOperands(reader, exprTable, al.children)
        if (al.TyKind() != TypeKind.TYPE_VARRAY) {
            let infoTable = reader.OffsetField(exprTable, 20)
            if (infoTable >= 0) {
                if (let Some(initDecl) <- ResolveFlatFullId(reader, reader.OffsetField(infoTable, 4))) {
                    al.initFunc = initDecl as FuncDecl
                }
            }
        }
        al.EnableAttr(Attribute.IMPORTED)
        return al
    }

    // Mirrors ExprLoader.cpp:275-282 LoadTupleLit. Operands are tuple element expressions.
    private func LoadFlatTupleLit(reader: CjoFlatBuffer, exprTable: Int64): TupleLit {
        let tl = TupleLit()
        LoadFlatExprBasicInfo(reader, exprTable, tl)
        LoadFlatExprOperands(reader, exprTable, tl.children)
        tl.EnableAttr(Attribute.IMPORTED)
        return tl
    }

    private func LoadFlatExprOperands(reader: CjoFlatBuffer, exprTable: Int64, out: ArrayList<Expr>): Unit {
        let operands = reader.VectorField(exprTable, 12)
        if (operands < 0) {
            return
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(operands)
        while (idx < count) {
            if (let Some(child) <- LoadFlatExpr(reader, reader.VectorU32(operands, idx))) {
                out.add(child)
            }
            idx++
        }
    }

    // Mirrors ExprLoader.cpp:67-79 LoadMemberAccess, plus ReferenceLoader.cpp:586-600 deferred
    // reference restoration for target, instTys, and matchedParentTy.
    private func LoadFlatMemberAccess(reader: CjoFlatBuffer, exprTable: Int64): MemberAccess {
        let ma = MemberAccess()
        LoadFlatExprBasicInfo(reader, exprTable, ma)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            ma.baseExpr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
            if (let Some(base) <- ma.baseExpr) {
                if (let Some(nameRef) <- (base as NameReferenceExpr)) {
                    nameRef.isAlone = false
                }
            }
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            ma.field = SrcIdentifier(reader.StringField(infoTable, 4))
            LoadFlatReferenceInfo(reader, infoTable, ma)
            ma.target = LoadFlatReferenceTarget(reader, infoTable)
        }
        ma.EnableAttr(Attribute.IMPORTED)
        return ma
    }

    // Mirrors ExprLoader.cpp:81-90 LoadRefExpr, plus ReferenceLoader.cpp:586-610 deferred
    // reference restoration for target, instTys, and matchedParentTy.
    private func LoadFlatRefExpr(reader: CjoFlatBuffer, exprTable: Int64): RefExpr {
        let re = RefExpr()
        LoadFlatExprBasicInfo(reader, exprTable, re)
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            let name = reader.StringField(infoTable, 4)
            re.ref.identifier = SrcIdentifier(name)
            re.isThis = name == "this"
            re.isSuper = name == "super"
            LoadFlatReferenceInfo(reader, infoTable, re)
            re.ref.target = LoadFlatReferenceTarget(reader, infoTable)
        }
        re.EnableAttr(Attribute.IMPORTED)
        return re
    }

    private func LoadFlatExprBasicInfo(reader: CjoFlatBuffer, exprTable: Int64, expr: Expr): Unit {
        LoadFlatNodeBasicInfo(reader, exprTable, expr)
    }

    private func LoadFlatNodeBasicInfo(reader: CjoFlatBuffer, exprTable: Int64, node: Node): Unit {
        if (let Some(ty) <- LoadFlatType(reader.U32Field(exprTable, 14, 0u32))) {
            node.SetTy(ty)
        }
    }

    private func FlatExprTable(reader: CjoFlatBuffer, exprIndex: UInt32): Int64 {
        if (exprIndex == 0u32 || flatAllExprs < 0) {
            return -1
        }
        let idx = Int64(exprIndex) - 1
        if (idx < 0 || idx >= reader.VectorLength(flatAllExprs)) {
            return -1
        }
        return reader.VectorOffsetElement(flatAllExprs, idx)
    }

    // Mirrors ExprLoader.cpp:516-531 LoadFuncArg. FuncArg is encoded as an Expr table with no
    // Expr.kind, operand 0 for the value expression, and ExprInfo_FuncArgInfo at slot 20.
    private func LoadFlatFuncArg(reader: CjoFlatBuffer, argExprIndex: UInt32): Option<FuncArg> {
        let argTable = FlatExprTable(reader, argExprIndex)
        if (argTable < 0) {
            return None
        }
        let arg = FuncArg()
        LoadFlatNodeBasicInfo(reader, argTable, arg)
        let argInfo = reader.OffsetField(argTable, 20)
        let isDefaultVal = if (argInfo >= 0) {
            reader.U8Field(argInfo, 6, 0u8) != 0u8
        } else {
            false
        }
        if (argInfo >= 0) {
            arg.withInout = reader.U8Field(argInfo, 4, 0u8) != 0u8
        }
        if (isDefaultVal) {
            arg.expr = Some(InvalidExpr())
            arg.EnableAttr(Attribute.HAS_INITIAL)
            return Some(arg)
        }
        let argOperands = reader.VectorField(argTable, 12)
        if (argOperands < 0 || reader.VectorLength(argOperands) != 1) {
            return None
        }
        if (let Some(argExpr) <- LoadFlatExpr(reader, reader.VectorU32(argOperands, 0))) {
            arg.expr = Some(argExpr)
            return Some(arg)
        }
        return None
    }

    private func LoadFlatReferenceInfo(reader: CjoFlatBuffer, infoTable: Int64, expr: NameReferenceExpr): Unit {
        let instTys = reader.VectorField(infoTable, 8)
        if (instTys >= 0) {
            var idx: Int64 = 0
            let count = reader.VectorLength(instTys)
            while (idx < count) {
                if (let Some(ty) <- LoadFlatType(reader.VectorU32(instTys, idx))) {
                    expr.instTys.add(ty)
                }
                idx++
            }
        }
        expr.matchedParentTy = LoadFlatType(reader.U32Field(infoTable, 10, 0u32))
    }

    private func LoadFlatReferenceTarget(reader: CjoFlatBuffer, infoTable: Int64): Option<Decl> {
        return ResolveFlatFullId(reader, reader.OffsetField(infoTable, 6))
    }

    // Mirrors ExprLoader.cpp:50-56 LoadReturnExpr. Operand 0 = return value sub-expr.
    private func LoadFlatReturnExpr(reader: CjoFlatBuffer, exprTable: Int64): ReturnExpr {
        let re = ReturnExpr()
        // Expr field 5 (slot 14) = type index.
        if (let Some(ty) <- LoadFlatType(reader.U32Field(exprTable, 14, 0u32))) {
            re.SetTy(ty)
        }
        // Expr field 4 (slot 12) = operands (uint32 vector of sub-expr indices).
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            re.expr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        re.EnableAttr(Attribute.IMPORTED)
        return re
    }

    // Mirrors ExprLoader.cpp:361-381 LoadBlock + BlockInfo (fbs:483-485). operands[i] is an Expr when
    // BlockInfo.isExpr[i] is true, else a Decl; the trailing isExpr entry is the 'unsafe' flag.
    private func LoadFlatBlock(reader: CjoFlatBuffer, exprTable: Int64): Block {
        let block = Block()
        if (let Some(ty) <- LoadFlatType(reader.U32Field(exprTable, 14, 0u32))) {
            block.SetTy(ty)
        }
        // Expr field 8 (slot 20) = info (BlockInfo); BlockInfo field 0 (slot 4) = isExpr bool vector.
        let infoTable = reader.OffsetField(exprTable, 20)
        let isExprVec = if (infoTable >= 0) { reader.VectorField(infoTable, 4) } else { -1 }
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0) {
            let size = reader.VectorLength(operands)
            var i = 0
            while (i < size) {
                let childIndex = reader.VectorU32(operands, i)
                let isExpr = isExprVec >= 0 && i < reader.VectorLength(isExprVec) && reader.VectorBool(isExprVec, i)
                if (isExpr) {
                    if (let Some(childExpr) <- LoadFlatExpr(reader, childIndex)) {
                        block.body.add(childExpr)
                    }
                } else {
                    if (let Some(childRecord) <- flatDecls.get(childIndex)) {
                        if (let Some(childDecl) <- EnsureFlatDecl(childRecord)) {
                            block.body.add(childDecl)
                        }
                    }
                }
                i++
            }
            // Trailing isExpr entry encodes the block's 'unsafe' attribute (ExprWriter.cpp:538).
            if (isExprVec >= 0 && reader.VectorLength(isExprVec) > size && reader.VectorBool(isExprVec, size)) {
                block.EnableAttr(Attribute.UNSAFE)
            }
        }
        block.EnableAttr(Attribute.IMPORTED)
        return block
    }

    // Mirrors ExprLoader.cpp:141-152 LoadLitConstExpr + LitConstInfo (fbs:446-450).
    private func LoadFlatLitConstExpr(reader: CjoFlatBuffer, exprTable: Int64): LitConstExpr {
        // Expr field 7 (slot 18) = info_type, field 8 (slot 20) = info (LitConstInfo table).
        let infoTable = reader.OffsetField(exprTable, 20)
        let lce = LitConstExpr()
        if (infoTable >= 0) {
            // LitConstInfo field 0 (slot 4) strValue, 1 (slot 6) constKind, 2 (slot 8) strKind.
            lce.stringValue = reader.StringField(infoTable, 4)
            lce.kind = FlatToLitConstKind(reader.U8Field(infoTable, 6, 0u8))
            lce.stringKind = FlatToStringKind(reader.U8Field(infoTable, 8, 0u8))
        }
        lce.rawString = lce.stringValue
        // Expr field 5 (slot 14) = type index.
        let typeIndex = reader.U32Field(exprTable, 14, 0u32)
        if (let Some(ty) <- LoadFlatType(typeIndex)) {
            lce.SetTy(ty)
        }
        // ExprLoader.cpp:148-150: compute codepoints for RUNE/STRING literals.
        if (lce.kind == LitConstKind.RUNE || lce.kind == LitConstKind.STRING) {
            for (point in StringConvertor.UTF8ToCodepoint(lce.stringValue)) {
                lce.codepoint.add(point)
            }
        }
        lce.EnableAttr(Attribute.IMPORTED)
        return lce
    }

    private func LoadFlatVarWithPatternInfo(reader: CjoFlatBuffer, record: CjoFlatDecl,
        varDecl: VarWithPatternDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            return
        }
        varDecl.isVar = reader.U8Field(infoTable, 4, 0u8) != 0u8
        varDecl.isConst = reader.U8Field(infoTable, 6, 0u8) != 0u8
        // Mirrors ASTLoader.cpp:742-743: initializer is field 3, irrefutablePattern is field 2.
        if (let Some(initializer) <- LoadFlatExpr(reader, reader.U32Field(infoTable, 10, 0u32))) {
            varDecl.initializer = Some(initializer)
        }
        varDecl.irrefutablePattern = LoadFlatPattern(reader, reader.OffsetField(infoTable, 8))
    }

    // Mirrors ExprLoader.cpp:534-634 and ReferenceLoader.cpp:745-785 for cjo Pattern records.
    private func LoadFlatPattern(reader: CjoFlatBuffer, patternTable: Int64): Option<Pattern> {
        if (patternTable < 0) {
            return None
        }
        let kind = reader.U8Field(patternTable, 4, 0u8)
        let pattern = if (kind == FLAT_PATTERN_KIND_CONST) {
            LoadFlatConstPattern(reader, patternTable)
        } else if (kind == FLAT_PATTERN_KIND_WILDCARD) {
            WildcardPattern()
        } else if (kind == FLAT_PATTERN_KIND_VAR) {
            LoadFlatVarPattern(reader, patternTable)
        } else if (kind == FLAT_PATTERN_KIND_TUPLE) {
            LoadFlatTuplePattern(reader, patternTable)
        } else if (kind == FLAT_PATTERN_KIND_TYPE) {
            LoadFlatTypePattern(reader, patternTable)
        } else if (kind == FLAT_PATTERN_KIND_ENUM) {
            LoadFlatEnumPattern(reader, patternTable)
        } else if (kind == FLAT_PATTERN_KIND_EXCEPT_TYPE) {
            LoadFlatExceptTypePattern(reader, patternTable)
        } else if (kind == FLAT_PATTERN_KIND_COMMAND_TYPE) {
            LoadFlatCommandTypePattern(reader, patternTable)
        } else {
            return None
        }
        LoadFlatPatternTy(reader, patternTable, pattern)
        SyncFlatVarPatternDeclTy(pattern)
        if (let Some(typePattern) <- (pattern as TypePattern)) {
            if (let Some(ty) <- typePattern.GetTy()) {
                typePattern.typeNode = Some(TypeNodeForTy(ty))
            }
        }
        return Some(pattern)
    }

    private func LoadFlatPatternTy(reader: CjoFlatBuffer, patternTable: Int64, pattern: Pattern): Unit {
        let types = reader.VectorField(patternTable, 12)
        if (types >= 0 && reader.VectorLength(types) >= 1) {
            if (let Some(ty) <- LoadFlatType(reader.VectorU32(types, 0))) {
                pattern.SetTy(ty)
            }
        }
    }

    private func SyncFlatVarPatternDeclTy(pattern: Pattern): Unit {
        if (let Some(varPattern) <- (pattern as VarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                if (!Ty.IsTyCorrect(varDecl.GetTy())) {
                    if (let Some(ty) <- varPattern.GetTy()) {
                        varDecl.SetTy(ty)
                        varDecl.typeNode = Some(TypeNodeForTy(ty))
                    }
                }
            }
        }
    }

    private func LoadFlatConstPattern(reader: CjoFlatBuffer, patternTable: Int64): ConstPattern {
        let pattern = ConstPattern()
        let exprs = reader.VectorField(patternTable, 14)
        if (exprs >= 0 && reader.VectorLength(exprs) >= 1) {
            pattern.literal = LoadFlatExpr(reader, reader.VectorU32(exprs, 0))
        }
        return pattern
    }

    private func LoadFlatVarPattern(reader: CjoFlatBuffer, patternTable: Int64): VarPattern {
        let pattern = VarPattern()
        let exprs = reader.VectorField(patternTable, 14)
        if (exprs >= 0 && reader.VectorLength(exprs) >= 1) {
            let declIndex = reader.VectorU32(exprs, 0)
            if (let Some(record) <- flatDecls.get(declIndex)) {
                if (let Some(decl) <- EnsureFlatDecl(record)) {
                    if (let Some(varDecl) <- (decl as VarDecl)) {
                        pattern.varDecl = Some(varDecl)
                        varDecl.parentPattern = pattern
                    }
                }
            }
        }
        return pattern
    }

    private func LoadFlatTuplePattern(reader: CjoFlatBuffer, patternTable: Int64): TuplePattern {
        let pattern = TuplePattern()
        LoadFlatChildPatterns(reader, patternTable, pattern.patterns)
        return pattern
    }

    private func LoadFlatTypePattern(reader: CjoFlatBuffer, patternTable: Int64): TypePattern {
        let pattern = TypePattern()
        let children = reader.VectorField(patternTable, 10)
        if (children >= 0 && reader.VectorLength(children) >= 1) {
            pattern.pattern = LoadFlatPattern(reader, reader.VectorOffsetElement(children, 0))
        }
        pattern.matchBeforeRuntime = reader.U8Field(patternTable, 18, 0u8) != 0u8
        pattern.needRuntimeTypeCheck = reader.U8Field(patternTable, 20, 0u8) != 0u8
        return pattern
    }

    private func LoadFlatEnumPattern(reader: CjoFlatBuffer, patternTable: Int64): EnumPattern {
        let pattern = EnumPattern()
        LoadFlatChildPatterns(reader, patternTable, pattern.patterns)
        let exprs = reader.VectorField(patternTable, 14)
        if (exprs >= 0 && reader.VectorLength(exprs) >= 1) {
            pattern.constructor = LoadFlatExpr(reader, reader.VectorU32(exprs, 0))
        }
        return pattern
    }

    private func LoadFlatExceptTypePattern(reader: CjoFlatBuffer, patternTable: Int64): ExceptTypePattern {
        let pattern = ExceptTypePattern()
        LoadFlatTypeListPattern(reader, patternTable, pattern)
        return pattern
    }

    private func LoadFlatCommandTypePattern(reader: CjoFlatBuffer, patternTable: Int64): CommandTypePattern {
        let pattern = CommandTypePattern()
        LoadFlatTypeListPattern(reader, patternTable, pattern)
        return pattern
    }

    private func LoadFlatTypeListPattern(reader: CjoFlatBuffer, patternTable: Int64, pattern: TypeListPattern): Unit {
        let children = reader.VectorField(patternTable, 10)
        if (children >= 0 && reader.VectorLength(children) >= 1) {
            pattern.pattern = LoadFlatPattern(reader, reader.VectorOffsetElement(children, 0))
        }
        let types = reader.VectorField(patternTable, 12)
        if (types >= 0) {
            var idx: Int64 = 1
            let count = reader.VectorLength(types)
            while (idx < count) {
                if (let Some(ty) <- LoadFlatType(reader.VectorU32(types, idx))) {
                    pattern.types.add(TypeNodeForTy(ty))
                }
                idx++
            }
        }
    }

    private func LoadFlatChildPatterns(reader: CjoFlatBuffer, patternTable: Int64, out: ArrayList<Pattern>): Unit {
        let children = reader.VectorField(patternTable, 10)
        if (children < 0) {
            return
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(children)
        while (idx < count) {
            if (let Some(child) <- LoadFlatPattern(reader, reader.VectorOffsetElement(children, idx))) {
                out.add(child)
            }
            idx++
        }
    }

    private func LoadFlatParamInfo(reader: CjoFlatBuffer, record: CjoFlatDecl, param: FuncParam): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            return
        }
        param.isNamedParam = reader.U8Field(infoTable, 4, 0u8) != 0u8
        param.isMemberParam = reader.U8Field(infoTable, 6, 0u8) != 0u8
    }

    private func LoadFlatPropInfo(reader: CjoFlatBuffer, record: CjoFlatDecl, propDecl: PropDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            return
        }
        propDecl.isConst = reader.U8Field(infoTable, 4, 0u8) != 0u8
        propDecl.isVar = reader.U8Field(infoTable, 6, 0u8) != 0u8
        LoadFlatPropAccessors(reader, propDecl, reader.VectorField(infoTable, 8), true)
        LoadFlatPropAccessors(reader, propDecl, reader.VectorField(infoTable, 10), false)
    }

    private func LoadFlatPropAccessors(reader: CjoFlatBuffer, propDecl: PropDecl, accessors: Int64,
        isSetter: Bool): Unit {
        if (accessors < 0) {
            return
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(accessors)
        while (idx < count) {
            let accessorIndex = reader.VectorU32(accessors, idx)
            if (let Some(accessorRecord) <- flatDecls.get(accessorIndex)) {
                if (let Some(accessorDecl) <- EnsureFlatDecl(accessorRecord)) {
                    if (let Some(funcDecl) <- (accessorDecl as FuncDecl)) {
                        funcDecl.propDecl = Some(propDecl)
                        funcDecl.outerDecl = propDecl.outerDecl
                        if (isSetter) {
                            funcDecl.isSetter = true
                            propDecl.setters.add(funcDecl)
                        } else {
                            funcDecl.isGetter = true
                            propDecl.getters.add(funcDecl)
                        }
                    }
                }
            }
            idx++
        }
    }

    private func LoadFlatTypeAliasInfo(reader: CjoFlatBuffer, record: CjoFlatDecl, aliasDecl: TypeAliasDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            return
        }
        if (let Some(aliasedTy) <- LoadFlatType(reader.U32Field(infoTable, 4, 0u32))) {
            aliasDecl.typeNode = Some(TypeNodeForTy(aliasedTy))
        }
    }

    private func LoadFlatEnumInfo(reader: CjoFlatBuffer, record: CjoFlatDecl, enumDecl: EnumDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            return
        }
        enumDecl.hasArguments = reader.U8Field(infoTable, 10, 0u8) != 0u8
        enumDecl.hasEllipsis = reader.U8Field(infoTable, 12, 0u8) != 0u8
    }

    private func LoadFlatBodyMembers(reader: CjoFlatBuffer, record: CjoFlatDecl, parent: InheritableDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            return
        }
        let body = reader.VectorField(infoTable, 6)
        if (body < 0) {
            return
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(body)
        while (idx < count) {
            let memberIndex = reader.VectorU32(body, idx)
            if (let Some(memberRecord) <- flatDecls.get(memberIndex)) {
                if (let Some(member) <- EnsureFlatDecl(memberRecord)) {
                    AddFlatMember(parent, member)
                }
            }
            idx++
        }
    }

    private func AddFlatMember(parent: InheritableDecl, member: Decl): Unit {
        SetFlatOuterDeclForMember(member, parent)
        if (let Some(enumDecl) <- (parent as EnumDecl)) {
            if (member.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                enumDecl.constructors.add(member)
            } else {
                enumDecl.members.add(member)
            }
            return
        }
        AddMember(parent, member)
    }

    private func SetFlatOuterDeclForMember(member: Decl, parent: Decl): Unit {
        member.outerDecl = Some(parent)
        member.scopeLevel = 2u32
        if (let Some(propDecl) <- (member as PropDecl)) {
            for (getter in propDecl.getters) {
                getter.propDecl = Some(propDecl)
                getter.outerDecl = Some(parent)
                getter.scopeLevel = member.scopeLevel
                getter.isGetter = true
                SetFlatFuncParentReference(getter, parent)
            }
            for (setter in propDecl.setters) {
                setter.propDecl = Some(propDecl)
                setter.outerDecl = Some(parent)
                setter.scopeLevel = member.scopeLevel
                setter.isSetter = true
                SetFlatFuncParentReference(setter, parent)
            }
        } else if (let Some(funcDecl) <- (member as FuncDecl)) {
            SetFlatFuncParentReference(funcDecl, parent)
            if (let Some(body) <- funcDecl.funcBody) {
                if (!body.paramLists.isEmpty()) {
                    for (param in body.paramLists[0].params) {
                        if (let Some(desugar) <- param.desugarDecl) {
                            desugar.ownerFunc = Some(funcDecl)
                            SetFlatFuncParentReference(desugar, parent)
                        }
                    }
                }
            }
        }
    }

    private func SetFlatFuncParentReference(funcDecl: FuncDecl, parent: Decl): Unit {
        if (let None <- funcDecl.funcBody) {
            return
        }
        let body = funcDecl.funcBody.getOrThrow()
        var parentDecl = parent
        if (let Some(extendDecl) <- (parent as ExtendDecl)) {
            if (let Some(extendedDecl) <- Ty.GetDeclPtrOfTy(extendDecl.GetTy())) {
                parentDecl = extendedDecl
            }
        }
        if (parentDecl.IsClassLikeDecl()) {
            if (let Some(classLike) <- (parentDecl as ClassLikeDecl)) {
                body.parentClassLike = Some(classLike)
            }
        } else if (let Some(structDecl) <- (parentDecl as StructDecl)) {
            body.parentStruct = Some(structDecl)
        } else if (let Some(enumDecl) <- (parentDecl as EnumDecl)) {
            body.parentEnum = Some(enumDecl)
        }
    }

    private func FlatOverflowStrategy(kind: UInt8): OverflowStrategy {
        if (kind == 0u8) { return OverflowStrategy.NA }
        if (kind == 1u8) { return OverflowStrategy.CHECKED }
        if (kind == 2u8) { return OverflowStrategy.WRAPPING }
        if (kind == 3u8) { return OverflowStrategy.THROWING }
        if (kind == 4u8) { return OverflowStrategy.SATURATING }
        throw IllegalArgumentException("unsupported FlatBuffer OverflowPolicy ${kind}")
    }

    private func FlatOperatorKind(kind: UInt8): TokenKind {
        if (kind == 0u8) { return TokenKind.ILLEGAL }
        if (kind == 1u8) { return TokenKind.LSQUARE }
        if (kind == 2u8) { return TokenKind.LPAREN }
        if (kind == 3u8) { return TokenKind.NOT }
        if (kind == 4u8) { return TokenKind.EXP }
        if (kind == 5u8) { return TokenKind.MUL }
        if (kind == 6u8) { return TokenKind.DIV }
        if (kind == 7u8) { return TokenKind.MOD }
        if (kind == 8u8) { return TokenKind.ADD }
        if (kind == 9u8) { return TokenKind.SUB }
        if (kind == 10u8) { return TokenKind.LSHIFT }
        if (kind == 11u8) { return TokenKind.RSHIFT }
        if (kind == 12u8) { return TokenKind.LT }
        if (kind == 13u8) { return TokenKind.LE }
        if (kind == 14u8) { return TokenKind.GT }
        if (kind == 15u8) { return TokenKind.GE }
        if (kind == 16u8) { return TokenKind.EQUAL }
        if (kind == 17u8) { return TokenKind.NOTEQ }
        if (kind == 18u8) { return TokenKind.BITAND }
        if (kind == 19u8) { return TokenKind.BITXOR }
        if (kind == 20u8) { return TokenKind.BITOR }
        if (kind == 21u8) { return TokenKind.INCR }
        if (kind == 22u8) { return TokenKind.DECR }
        if (kind == 23u8) { return TokenKind.IS }
        if (kind == 24u8) { return TokenKind.AS }
        if (kind == 25u8) { return TokenKind.AND }
        if (kind == 26u8) { return TokenKind.OR }
        if (kind == 27u8) { return TokenKind.COALESCING }
        if (kind == 28u8) { return TokenKind.PIPELINE }
        if (kind == 29u8) { return TokenKind.COMPOSITION }
        if (kind == 30u8) { return TokenKind.ASSIGN }
        if (kind == 31u8) { return TokenKind.EXP_ASSIGN }
        if (kind == 32u8) { return TokenKind.MUL_ASSIGN }
        if (kind == 33u8) { return TokenKind.DIV_ASSIGN }
        if (kind == 34u8) { return TokenKind.MOD_ASSIGN }
        if (kind == 35u8) { return TokenKind.ADD_ASSIGN }
        if (kind == 36u8) { return TokenKind.SUB_ASSIGN }
        if (kind == 37u8) { return TokenKind.LSHIFT_ASSIGN }
        if (kind == 38u8) { return TokenKind.RSHIFT_ASSIGN }
        if (kind == 39u8) { return TokenKind.BITAND_ASSIGN }
        if (kind == 40u8) { return TokenKind.BITXOR_ASSIGN }
        if (kind == 41u8) { return TokenKind.BITOR_ASSIGN }
        if (kind == 42u8) { return TokenKind.AND_ASSIGN }
        if (kind == 43u8) { return TokenKind.OR_ASSIGN }
        throw IllegalArgumentException("unsupported FlatBuffer OperatorKind ${kind}")
    }

    private func FlatCaptureKind(kind: UInt8): CaptureKind {
        if (kind == 0u8) { return CaptureKind.NO_CAPTURE }
        if (kind == 1u8) { return CaptureKind.CAPTURE_VAR }
        if (kind == 2u8) { return CaptureKind.TRANSITIVE_CAPTURE }
        throw IllegalArgumentException("unsupported FlatBuffer CaptureKind ${kind}")
    }

    private func MapFlatGenericParameters(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: Decl): Unit {
        let genericTable = reader.OffsetField(record.table, 12)
        if (genericTable < 0) {
            return
        }
        let typeParams = reader.VectorField(genericTable, 4)
        if (typeParams < 0) {
            return
        }
        if (let Some(generic) <- decl.generic) {
            var idx: Int64 = 0
            let limit = if (reader.VectorLength(typeParams) < generic.typeParameters.size) {
                reader.VectorLength(typeParams)
            } else {
                generic.typeParameters.size
            }
            while (idx < limit) {
                flatGenericParamDecls[reader.VectorU32(typeParams, idx)] = generic.typeParameters[idx]
                idx++
            }
        }
    }

    private func AddFlatInheritedType(inheritable: InheritableDecl, inheritedTy: Ty): Unit {
        if (HasFlatInheritedType(inheritable, inheritedTy)) {
            return
        }
        inheritable.inheritedTypes.add(TypeNodeForTy(inheritedTy))
        if (let Some(classLikeTy) <- (inheritedTy as ClassLikeTy)) {
            if (let Some(selfTy) <- inheritable.GetTy()) {
                if (!HasDirectSubtype(classLikeTy, selfTy)) {
                    classLikeTy.directSubtypes.add(selfTy)
                }
            }
        }
    }

    private func HasFlatInheritedType(inheritable: InheritableDecl, inheritedTy: Ty): Bool {
        let inheritedDecl = Ty.GetDeclPtrOfTy(Some(inheritedTy))
        for (typeNode in inheritable.inheritedTypes) {
            if (let Some(existingTy) <- typeNode.GetTy()) {
                if (let Some(existingDecl) <- Ty.GetDeclPtrOfTy(Some(existingTy))) {
                    if (let Some(targetDecl) <- inheritedDecl) {
                        if (SameDecl(existingDecl, targetDecl)) {
                            return true
                        }
                    }
                }
                if (existingTy.String() == inheritedTy.String()) {
                    return true
                }
            }
        }
        return false
    }

    private func HasDirectSubtype(classLikeTy: ClassLikeTy, selfTy: Ty): Bool {
        for (subtype in classLikeTy.directSubtypes) {
            if (subtype.String() == selfTy.String()) {
                return true
            }
        }
        return false
    }

    private func LoadFlatType(index: UInt32): Option<Ty> {
        if (index == 0u32) {
            return None
        }
        if (let Some(cached) <- flatTypeCache.get(index)) {
            return Some(cached)
        }
        if (let None <- flat) {
            return None
        }
        let reader = flat.getOrThrow()
        if (flatAllTypes < 0) {
            return None
        }
        let typeIdx = Int64(index) - 1
        if (typeIdx < 0 || typeIdx >= reader.VectorLength(flatAllTypes)) {
            return None
        }
        let typeTable = reader.VectorOffsetElement(flatAllTypes, typeIdx)
        if (typeTable < 0) {
            return None
        }
        if (reader.U16Field(typeTable, 4, 1u16) == 29u16) {
            if (let Some(genericTy) <- LoadFlatGenericTy(reader, typeTable)) {
                flatTypeCache[index] = genericTy
                if (let Some(value) <- (genericTy as GenericsTy)) {
                    LoadFlatGenericUpperBounds(reader, typeTable, value)
                }
                return Some(genericTy)
            }
            return Some(InvalidTy())
        }
        let loaded = CreateFlatType(reader, typeTable)
        if (let Some(ty) <- loaded) {
            flatTypeCache[index] = ty
        }
        return loaded
    }

    private func CreateFlatType(reader: CjoFlatBuffer, typeTable: Int64): Option<Ty> {
        let kind = reader.U16Field(typeTable, 4, 1u16)
        let typeArgs = LoadFlatTypeArgs(reader, typeTable)
        if (let Some(primitiveKind) <- FlatPrimitiveTypeKind(kind)) {
            return Some(PrimitiveTy(primitiveKind))
        }
        if (kind == 18u16) {
            return Some(TupleTy(typeArgs.toArray()))
        }
        if (kind == 20u16) {
            let infoTable = reader.OffsetField(typeTable, 10)
            let retTy = if (infoTable >= 0) {
                LoadFlatType(reader.U32Field(infoTable, 4, 0u32)) ?? PrimitiveTy(TypeKind.TYPE_UNIT)
            } else {
                PrimitiveTy(TypeKind.TYPE_UNIT)
            }
            let cfg = FuncTyConfig()
            if (infoTable >= 0) {
                cfg.isC = reader.U8Field(infoTable, 6, 0u8) != 0u8
                cfg.hasVariableLenArg = reader.U8Field(infoTable, 8, 0u8) != 0u8
            }
            return Some(FuncTy(typeArgs.toArray(), retTy, cfg: cfg))
        }
        if (kind == 22u16) {
            let elemTy = if (typeArgs.isEmpty()) { AnyTy() } else { typeArgs[0] }
            let infoTable2 = reader.OffsetField(typeTable, 10)
            let dims = if (infoTable2 >= 0) { UInt64(reader.I64Field(infoTable2, 4, 1)) } else { 1u64 }
            return Some(ArrayTy(elemTy, dims))
        }
        if (kind == 23u16) {
            let elemTy2 = if (typeArgs.isEmpty()) { AnyTy() } else { typeArgs[0] }
            let infoTable3 = reader.OffsetField(typeTable, 10)
            let size = if (infoTable3 >= 0) { reader.I64Field(infoTable3, 4, 0) } else { 0 }
            return Some(VArrayTy(elemTy2, size))
        }
        if (kind == 24u16) {
            let elemTy3 = if (typeArgs.isEmpty()) { AnyTy() } else { typeArgs[0] }
            return Some(PointerTy(elemTy3))
        }
        if (kind == 25u16) {
            return Some(CStringTy())
        }
        if (kind == 29u16) {
            return LoadFlatGenericTy(reader, typeTable)
        }
        if (kind == 19u16 || kind == 21u16 || kind == 26u16 || kind == 27u16 || kind == 28u16) {
            return LoadFlatCompositeTy(reader, typeTable, kind, typeArgs)
        }
        return Some(InvalidTy())
    }

    private func LoadFlatTypeArgs(reader: CjoFlatBuffer, typeTable: Int64): ArrayList<Ty> {
        let args = ArrayList<Ty>()
        let argVec = reader.VectorField(typeTable, 6)
        if (argVec < 0) {
            return args
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(argVec)
        while (idx < count) {
            if (let Some(argTy) <- LoadFlatType(reader.VectorU32(argVec, idx))) {
                args.add(argTy)
            }
            idx++
        }
        return args
    }

    private func LoadFlatCompositeTy(reader: CjoFlatBuffer, typeTable: Int64, kind: UInt16,
        typeArgs: ArrayList<Ty>): Option<Ty> {
        let declOpt = LoadFlatTypeDecl(reader, typeTable)
        if (let None <- declOpt) {
            return Some(InvalidTy())
        }
        let decl = declOpt.getOrThrow()
        if (kind == 19u16) {
            if (let Some(enumDecl) <- (decl as EnumDecl)) {
                return Some(EnumTy(enumDecl.identifier.Val(), enumDecl, typeArgs.toArray()))
            }
        } else if (kind == 21u16) {
            if (let Some(structDecl) <- (decl as StructDecl)) {
                return Some(StructTy(structDecl.identifier.Val(), structDecl, typeArgs.toArray()))
            }
        } else if (kind == 26u16) {
            if (let Some(classDecl) <- (decl as ClassDecl)) {
                return Some(ClassTy(classDecl.identifier.Val(), classDecl, typeArgs.toArray()))
            }
        } else if (kind == 27u16) {
            if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
                return Some(InterfaceTy(interfaceDecl.identifier.Val(), interfaceDecl, typeArgs.toArray()))
            }
        } else if (kind == 28u16) {
            if (let Some(aliasDecl) <- (decl as TypeAliasDecl)) {
                return Some(TypeAliasTy(aliasDecl.identifier.Val(), aliasDecl, typeArgs.toArray()))
            }
        }
        return Some(InvalidTy())
    }

    private func LoadFlatTypeDecl(reader: CjoFlatBuffer, typeTable: Int64): Option<Decl> {
        let infoTable = reader.OffsetField(typeTable, 10)
        if (infoTable < 0) {
            return None
        }
        let fullIdTable = reader.OffsetField(infoTable, 4)
        return ResolveFlatFullId(reader, fullIdTable)
    }

    private func LoadFlatGenericTy(reader: CjoFlatBuffer, typeTable: Int64): Option<Ty> {
        let declOpt = LoadFlatTypeDecl(reader, typeTable)
        if (let Some(decl) <- declOpt) {
            if (let Some(paramDecl) <- (decl as GenericParamDecl)) {
                let ty = paramDecl.GetTy() ?? GenericsTy(paramDecl.identifier.Val(), paramDecl)
                if (let None <- paramDecl.GetTy()) {
                    paramDecl.SetTy(ty)
                }
                return Some(ty)
            }
        }
        return Some(InvalidTy())
    }

    private func LoadFlatGenericUpperBounds(reader: CjoFlatBuffer, typeTable: Int64, genericTy: GenericsTy): Unit {
        let infoTable = reader.OffsetField(typeTable, 10)
        if (infoTable < 0) {
            return
        }
        let uppers = reader.VectorField(infoTable, 6)
        if (uppers < 0) {
            return
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(uppers)
        while (idx < count) {
            if (let Some(upperTy) <- LoadFlatType(reader.VectorU32(uppers, idx))) {
                if (!HasFlatGenericUpperBound(genericTy, upperTy)) {
                    genericTy.upperBounds.add(upperTy)
                }
            }
            idx++
        }
    }

    private func HasFlatGenericUpperBound(genericTy: GenericsTy, upperTy: Ty): Bool {
        for (existing in genericTy.upperBounds) {
            if (existing.String() == upperTy.String()) {
                return true
            }
        }
        return false
    }

    private func ResolveFlatFullId(reader: CjoFlatBuffer, fullIdTable: Int64): Option<Decl> {
        if (fullIdTable < 0) {
            return None
        }
        let id = ReadFlatFullId(reader, fullIdTable)
        if (id.pkgId == -1) {
            return None
        }
        if (id.pkgId == -2) {
            if (let Some(record) <- flatDecls.get(id.index)) {
                if (!record.fullPackageName.isEmpty() && record.fullPackageName != packageName) {
                    if (let Some(found) <- FindImportedDeclByExportId(record.fullPackageName, record.exportId)) {
                        return Some(found)
                    }
                }
                return EnsureFlatDecl(record)
            }
            return None
        }
        if (id.pkgId == -3) {
            return None
        }
        return ResolveImportedFullId(id)
    }

    private func ReadFlatFullId(reader: CjoFlatBuffer, fullIdTable: Int64): CjoFullId {
        return CjoFullId(
            reader.I32Field(fullIdTable, 4, 0),
            reader.StringField(fullIdTable, 6),
            reader.U32Field(fullIdTable, 8, 0u32)
        )
    }

    private func ResolveImportedFullId(id: CjoFullId): Option<Decl> {
        let importIdx = id.pkgId
        if (flatImports < 0 || importIdx < 0 || (let None <- flat)) {
            return None
        }
        let reader = flat.getOrThrow()
        if (importIdx >= reader.VectorLength(flatImports)) {
            return None
        }
        let packageName = reader.StringAt(reader.VectorOffsetElement(flatImports, importIdx))
        if (packageName.isEmpty()) {
            return None
        }
        if (!id.decl.isEmpty()) {
            if (let Some(found) <- FindImportedDeclByExportId(packageName, id.decl)) {
                return Some(found)
            }
        }
        return None
    }

    private func FindImportedDeclByExportId(fullPackageName: String, exportId: String): Option<Decl> {
        for (importedPackage in importedPackages) {
            if (importedPackage.fullPackageName != fullPackageName) {
                continue
            }
            for (importedFile in importedPackage.files) {
                for (decl in importedFile.decls) {
                    if (decl.exportId == exportId || decl.rawMangleName == exportId || decl.mangledName == exportId) {
                        return Some(decl)
                    }
                }
            }
        }
        let parsedPackage = ParseLengthText(exportId, 0)
        if (!parsedPackage.ok || parsedPackage.text != fullPackageName) {
            return None
        }
        let parsedName = ParseLengthText(exportId, parsedPackage.next)
        if (!parsedName.ok || parsedName.text.isEmpty()) {
            return None
        }
        var pos = parsedName.next
        let genericArity = ParseGenericArity(exportId, pos)
        if (genericArity.ok) {
            pos = genericArity.next
        }
        let arity = genericArity.arity
        for (importedPackage in importedPackages) {
            if (importedPackage.fullPackageName != fullPackageName) {
                continue
            }
            for (importedFile in importedPackage.files) {
                for (decl in importedFile.decls) {
                    if (decl.identifier.Val() == parsedName.text && decl.IsNominalDecl() &&
                        ImportedGenericArityMatches(decl, arity)) {
                        return Some(decl)
                    }
                }
            }
        }
        return None
    }

    private func ImportedGenericArityMatches(decl: Decl, genericArity: Int64): Bool {
        if (genericArity <= 0) {
            return true
        }
        if (let Some(generic) <- decl.generic) {
            return generic.typeParameters.size == genericArity
        }
        return false
    }

    private func FlatPrimitiveTypeKind(kind: UInt16): Option<TypeKind> {
        if (kind == 1u16) { return Some(TypeKind.TYPE_UNIT) }
        if (kind == 2u16) { return Some(TypeKind.TYPE_INT8) }
        if (kind == 3u16) { return Some(TypeKind.TYPE_INT16) }
        if (kind == 4u16) { return Some(TypeKind.TYPE_INT32) }
        if (kind == 5u16) { return Some(TypeKind.TYPE_INT64) }
        if (kind == 6u16) { return Some(TypeKind.TYPE_INT_NATIVE) }
        if (kind == 7u16) { return Some(TypeKind.TYPE_UINT8) }
        if (kind == 8u16) { return Some(TypeKind.TYPE_UINT16) }
        if (kind == 9u16) { return Some(TypeKind.TYPE_UINT32) }
        if (kind == 10u16) { return Some(TypeKind.TYPE_UINT64) }
        if (kind == 11u16) { return Some(TypeKind.TYPE_UINT_NATIVE) }
        if (kind == 12u16) { return Some(TypeKind.TYPE_FLOAT16) }
        if (kind == 13u16) { return Some(TypeKind.TYPE_FLOAT32) }
        if (kind == 14u16) { return Some(TypeKind.TYPE_FLOAT64) }
        if (kind == 15u16) { return Some(TypeKind.TYPE_RUNE) }
        if (kind == 16u16) { return Some(TypeKind.TYPE_NOTHING) }
        if (kind == 17u16) { return Some(TypeKind.TYPE_BOOLEAN) }
        return None
    }

    private func SetNominalTy(decl: Decl, name: String): Unit {
        let typeArgs = ArrayList<Ty>()
        if (let Some(generic) <- decl.generic) {
            for (param in generic.typeParameters) {
                if (let Some(paramTy) <- param.GetTy()) {
                    typeArgs.add(paramTy)
                }
            }
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            structDecl.SetTy(StructTy(name, structDecl, typeArgs.toArray()))
        } else if (let Some(classDecl) <- (decl as ClassDecl)) {
            classDecl.SetTy(ClassTy(name, classDecl, typeArgs.toArray()))
        } else if (let Some(enumDecl) <- (decl as EnumDecl)) {
            enumDecl.SetTy(EnumTy(name, enumDecl, typeArgs.toArray()))
        } else if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            interfaceDecl.SetTy(InterfaceTy(name, interfaceDecl, typeArgs.toArray()))
        }
    }

    private func AddMember(parent: Decl, member: Decl, prepend!: Bool = false): Unit {
        if (let Some(structDecl) <- (parent as StructDecl)) {
            if (let Some(body) <- structDecl.body) { AddDeclToMembers(body.decls, member, prepend: prepend) }
        } else if (let Some(classDecl) <- (parent as ClassDecl)) {
            if (let Some(body2) <- classDecl.body) { AddDeclToMembers(body2.decls, member, prepend: prepend) }
        } else if (let Some(interfaceDecl) <- (parent as InterfaceDecl)) {
            if (let Some(body3) <- interfaceDecl.body) { AddDeclToMembers(body3.decls, member, prepend: prepend) }
        } else if (let Some(enumDecl) <- (parent as EnumDecl)) {
            enumDecl.members.add(member)
        } else if (let Some(extendDecl) <- (parent as ExtendDecl)) {
            extendDecl.members.add(member)
        }
    }

    private func AddDeclToMembers(members: ArrayList<Decl>, member: Decl, prepend!: Bool): Unit {
        if (!prepend) {
            members.add(member)
            return
        }
        let existing = ArrayList<Decl>()
        for (decl in members) {
            existing.add(decl)
        }
        members.clear()
        members.add(member)
        for (decl in existing) {
            members.add(decl)
        }
    }

    private func TypeNodeForTy(ty: Ty): Type {
        if (let Some(primitiveTy) <- (ty as PrimitiveTy)) {
            let primitive = PrimitiveType(primitiveTy.kind)
            primitive.SetTy(ty)
            return primitive
        }
        let refType = RefType(ty.name)
        refType.SetTy(ty)
        if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
            refType.ref.target = decl
        }
        return refType
    }

    private func ParseGenericArity(signature: String, start: Int64): ParsedGenericArity {
        if (start >= signature.size || signature[start] != b'<') {
            return ParsedGenericArity(false, 0, start)
        }
        var pos = start + 1
        var value: Int64 = 0
        var hasDigit = false
        while (pos < signature.size && signature[pos] >= b'0' && signature[pos] <= b'9') {
            value = value * 10 + Int64(signature[pos] - b'0')
            hasDigit = true
            pos++
        }
        if (!hasDigit || pos >= signature.size || signature[pos] != b'>') {
            return ParsedGenericArity(false, 0, start)
        }
        return ParsedGenericArity(true, value, pos + 1)
    }

    private func ParseLengthText(signature: String, start: Int64): ParsedText {
        var pos = start
        var len: Int64 = 0
        var hasDigit = false
        while (pos < signature.size && signature[pos] >= b'0' && signature[pos] <= b'9') {
            if (len > signature.size) {
                return ParsedText(false, "", start)
            }
            len = len * 10 + Int64(signature[pos] - b'0')
            if (len > signature.size) {
                return ParsedText(false, "", start)
            }
            hasDigit = true
            pos++
        }
        if (!hasDigit || len < 0 || pos + len > signature.size) {
            return ParsedText(false, "", start)
        }
        return ParsedText(true, signature[pos..pos + len], pos + len)
    }

    private func RootPackageName(fullPackageName: String): String {
        var idx: Int64 = 0
        while (idx < fullPackageName.size) {
            if (fullPackageName[idx] == UInt8(46)) {
                return fullPackageName[0..idx]
            }
            idx++
        }
        return fullPackageName
    }
}

private enum FrontendPackageRelation {
    | NONE
    | CHILD
    | SAME_MODULE
    | SAME_PACKAGE
}

private func FrontendPackageRelationIndex(relation: FrontendPackageRelation): Int64 {
    return match (relation) {
        case FrontendPackageRelation.NONE => 0
        case FrontendPackageRelation.CHILD => 1
        case FrontendPackageRelation.SAME_MODULE => 2
        case FrontendPackageRelation.SAME_PACKAGE => 3
    }
}

extend FrontendPackageRelation <: Equatable<FrontendPackageRelation> {
    public operator func ==(right: FrontendPackageRelation): Bool {
        return FrontendPackageRelationIndex(this) == FrontendPackageRelationIndex(right)
    }

    public operator func !=(right: FrontendPackageRelation): Bool {
        return !(this == right)
    }
}

public class ImportManager {
    private let diag: DiagnosticEngine
    private let searchPath: ArrayList<String> = ArrayList<String>()
    private let importedPackages: ArrayList<Package> = ArrayList<Package>()
    private let depPkgCjdPaths: HashMap<String, String> = HashMap<String, String>()
    private let directDependencies: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    private let directDependencyOrder: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    private let loadingPackages: HashSet<String> = HashSet<String>()
    private let sourcePackagesForMembers: ArrayList<Package> = ArrayList<Package>()
    private let packageMembers: HashMap<String, HashMap<String, ArrayList<Decl>>> =
        HashMap<String, HashMap<String, ArrayList<Decl>>>()
    private let packageMembersVisited: HashSet<String> = HashSet<String>()

    public init(diag: DiagnosticEngine) {
        this.diag = diag
    }

    public func UpdateSearchPath(cangjieModules: String): Unit {
        searchPath.clear()
        if (!cangjieModules.isEmpty()) {
            searchPath.add(cangjieModules)
        }
    }

    private func AppendSearchPath(path: String): Unit {
        let normalized = NormalizePath(path)
        if (normalized.isEmpty()) {
            return
        }
        for (entry in searchPath) {
            if (entry == normalized) {
                return
            }
        }
        searchPath.add(normalized)
    }

    public func GetSearchPath(): ArrayList<String> {
        return searchPath
    }

    public func GeneratePkgDepInfo(pkgs: ArrayList<Package>): ArrayList<String> {
        let out = ArrayList<String>()
        let sourcePackages = HashSet<String>()
        for (pkg in pkgs) {
            sourcePackages.add(pkg.fullPackageName)
        }
        for (pkg in pkgs) {
            let deps = CollectDirectDependencyNames(pkg, sourcePackages)
            out.add("{\"package\":\"" + EscapeJson(pkg.fullPackageName) + "\",\"deps\":" +
                StringSetToJsonArray(deps) + "}")
        }
        return out
    }

    public func GeneratePkgDepInfoByCjo(path: String): ArrayList<String> {
        let out = ArrayList<String>()
        out.add("{\"inputCjo\":\"" + EscapeJson(path) + "\",\"deps\":[]}")
        return out
    }

    public func BuildIndex(cangjieModules: String, opts: GlobalOptions, pkgs: ArrayList<Package>): Bool {
        UpdateSearchPath(cangjieModules)
        for (path in opts.importPaths) {
            AppendSearchPath(path)
        }
        importedPackages.clear()
        depPkgCjdPaths.clear()
        directDependencies.clear()
        directDependencyOrder.clear()
        loadingPackages.clear()
        sourcePackagesForMembers.clear()
        packageMembers.clear()
        packageMembersVisited.clear()
        let sourcePackages = HashSet<String>()
        for (pkg in pkgs) {
            if (pkg.fullPackageName.isEmpty()) {
                diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "empty package name")
                return false
            }
            AddImplicitImports(pkg, opts)
            sourcePackages.add(pkg.fullPackageName)
            sourcePackagesForMembers.add(pkg)
        }
        for (pkg in pkgs) {
            let deps = CollectDirectDependencyNamesInOrder(pkg, sourcePackages)
            let filteredDeps = HashSet<String>()
            for (dep in deps) {
                if (dep.isEmpty() || dep == pkg.fullPackageName) {
                    continue
                }
                filteredDeps.add(dep)
                if (!sourcePackages.contains(dep) && !depPkgCjdPaths.contains(dep)) {
                    let cjdPath = FileUtil.FindSerializationFile(dep, ".cjo", searchPath.toArray())
                    if (!cjdPath.isEmpty()) {
                        depPkgCjdPaths.add(dep, cjdPath)
                    }
                }
            }
            directDependencies.add(pkg.fullPackageName, filteredDeps)
            directDependencyOrder.add(pkg.fullPackageName, deps)
        }
        if (!LoadResolvedImportedPackages()) {
            return false
        }
        for (pkg in pkgs) {
            RebuildPackageMembers(pkg.fullPackageName)
        }
        CheckImports(pkgs)
        return diag.GetErrorCount() == 0
    }

    public func ReindexSourcePackagesAfterMacroExpand(pkgs: ArrayList<Package>): Unit {
        let _ = pkgs
    }

    public func DeleteASTLoaders(): Unit {}
    public func ClearPackageBCHIRCache(): Unit {}
    public func IsSourceCodeImported(): Bool { return true }

    public func GetAllImportedPackages(): ArrayList<Package> {
        return importedPackages
    }

    public func GetCurImportedPackages(fullPackageName: String): ArrayList<Package> {
        let out = ArrayList<Package>()
        let deps = directDependencyOrder.get(fullPackageName) ?? return out
        for (dep in deps) {
            if (let Some(pkg) <- GetPackage(dep)) {
                out.add(pkg)
            }
        }
        return out
    }

    public func AddImportedPackage(pkg: Package): Unit {
        AddImportedPackageIfMissing(pkg)
    }

    public func GetDepPkgCjdPaths(): HashMap<String, String> {
        return depPkgCjdPaths
    }

    public func GetImportedDecls(file: File): ArrayList<ImportedDeclGroup> {
        let out = ArrayList<ImportedDeclGroup>()
        if (let Some(pkg) <- file.curPackage) {
            for (importSpec in file.imports) {
                CollectDeclsFromImport(pkg.fullPackageName, importSpec, out)
            }
        }
        return out
    }

    public func GetPackageMembers(srcFullPackageName: String, targetFullPackageName: String): HashMap<String, ArrayList<Decl>> {
        let out = HashMap<String, ArrayList<Decl>>()
        BuildPackageMembers(targetFullPackageName)
        let relation = GetFrontendPackageRelation(srcFullPackageName, targetFullPackageName)
        if (let Some(members) <- packageMembers.get(targetFullPackageName)) {
            for (name in members.keys()) {
                if (let Some(decls) <- members.get(name)) {
                    let visibleDecls = ArrayList<Decl>()
                    for (decl in decls) {
                        if (IsFrontendVisible(decl, relation)) {
                            AddDeclIfMissing(visibleDecls, decl)
                        }
                    }
                    if (!visibleDecls.isEmpty()) {
                        out[name] = visibleDecls
                    }
                }
            }
        }
        return out
    }

    public func GetCoreDecl(name: String): Option<Decl> {
        return GetImportedDecl("std.core", name)
    }

    public func GetAstDecl(name: String): Option<Decl> {
        return GetImportedDecl("std.ast", name)
    }

    private func GetImportedDecl(packageName: String, name: String): Option<Decl> {
        if (let Some(pkg) <- GetPackage(packageName)) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    if (decl.identifier.Val() == name) {
                        return Some(decl)
                    }
                }
            }
        }
        return None
    }

    private func CollectDeclsFromImport(srcFullPackageName: String, importSpec: ImportSpec,
        out: ArrayList<ImportedDeclGroup>): Unit {
        if (importSpec.IsImportMulti()) {
            return
        }
        let targetPackageName = importSpec.content.GetImportedPackageNameWithIsDecl()
        if (targetPackageName.isEmpty()) {
            return
        }
        if (let Some(pkg) <- GetPackage(targetPackageName)) {
            BuildPackageMembers(targetPackageName)
            if (importSpec.IsImportAll()) {
                if (let Some(members) <- packageMembers.get(targetPackageName)) {
                    for (name in members.keys()) {
                        if (let Some(decls) <- members.get(name)) {
                            for (decl in decls) {
                                if (IsDeclVisibleFrom(srcFullPackageName, decl)) {
                                    AddImportedDeclGroupValue(out, name, decl)
                                }
                            }
                        }
                    }
                }
            } else if (IsPackageImport(importSpec, targetPackageName)) {
                let importedName = if (importSpec.IsImportAlias()) {
                    importSpec.content.aliasName.Val()
                } else {
                    LastPackageName(targetPackageName)
                }
                AddImportedDeclGroupValue(out, importedName, PackageDecl(pkg))
            } else {
                let importedName = if (importSpec.IsImportAlias()) {
                    importSpec.content.aliasName.Val()
                } else {
                    importSpec.content.identifier.Val()
                }
                if (let Some(members) <- packageMembers.get(targetPackageName)) {
                    if (let Some(decls) <- members.get(importSpec.content.identifier.Val())) {
                        for (decl in decls) {
                            if (IsDeclVisibleFrom(srcFullPackageName, decl)) {
                                AddImportedDeclGroupValue(out, importedName, decl)
                            }
                        }
                    }
                }
            }
        }
    }

    private func IsPackageImport(importSpec: ImportSpec, targetPackageName: String): Bool {
        if (importSpec.IsImportAll() || importSpec.content.isDecl) {
            return false
        }
        for (pkg in importedPackages) {
            if (pkg.fullPackageName == targetPackageName) {
                return true
            }
        }
        return false
    }

    private func IsDeclVisibleFrom(srcFullPackageName: String, decl: Decl): Bool {
        if (decl.TestAttr(Attribute.PUBLIC)) {
            return true
        }
        if (decl.fullPackageName == srcFullPackageName) {
            return true
        }
        if (decl.TestAttr(Attribute.INTERNAL)) {
            return RootPackageName(decl.fullPackageName) == RootPackageName(srcFullPackageName)
        }
        if (decl.TestAttr(Attribute.PROTECTED)) {
            return RootPackageName(decl.fullPackageName) == RootPackageName(srcFullPackageName)
        }
        return false
    }

    private func IsFrontendVisible(node: Node, relation: FrontendPackageRelation): Bool {
        return node.TestAttr(Attribute.PUBLIC) || relation == FrontendPackageRelation.SAME_PACKAGE ||
            (node.TestAttr(Attribute.PROTECTED) && relation != FrontendPackageRelation.NONE) ||
            (node.TestAttr(Attribute.INTERNAL) &&
                (relation == FrontendPackageRelation.CHILD || relation == FrontendPackageRelation.SAME_PACKAGE))
    }

    private func IsFrontendCompatibleAccessLevel(srcLevel: AccessLevel, refLevel: AccessLevel): Bool {
        return FrontendAccessLevelIndex(srcLevel) >= FrontendAccessLevelIndex(refLevel)
    }

    private func FrontendAccessLevelIndex(level: AccessLevel): Int64 {
        return match (level) {
            case AccessLevel.PRIVATE => 0
            case AccessLevel.INTERNAL => 1
            case AccessLevel.PROTECTED => 2
            case AccessLevel.PUBLIC => 3
        }
    }

    private func GetFrontendPackageRelation(srcFullPkgName: String, targetFullPkgName: String): FrontendPackageRelation {
        if (srcFullPkgName == targetFullPkgName) {
            return FrontendPackageRelation.SAME_PACKAGE
        }
        if (srcFullPkgName.isEmpty() || targetFullPkgName.isEmpty()) {
            return FrontendPackageRelation.NONE
        }
        let srcPath = SplitQualifiedName(srcFullPkgName)
        let targetPath = SplitQualifiedName(targetFullPkgName)
        if (targetPath.size < srcPath.size && StartsWithPath(srcPath, targetPath)) {
            return FrontendPackageRelation.CHILD
        }
        if (!srcPath.isEmpty() && !targetPath.isEmpty() && srcPath[0] == targetPath[0]) {
            return FrontendPackageRelation.SAME_MODULE
        }
        return FrontendPackageRelation.NONE
    }

    private func StartsWithPath(source: ArrayList<String>, prefix: ArrayList<String>): Bool {
        if (prefix.size > source.size) {
            return false
        }
        var idx: Int64 = 0
        while (idx < prefix.size) {
            if (source[idx] != prefix[idx]) {
                return false
            }
            idx++
        }
        return true
    }

    private func PutImportedDecl(map: HashMap<String, ArrayList<Decl>>, name: String, decl: Decl): Unit {
        if (!map.contains(name)) {
            map[name] = ArrayList<Decl>()
        }
        if (let Some(values) <- map.get(name)) {
            AddDeclIfMissing(values, decl)
        }
    }

    private func AddImportedDeclGroupValue(groups: ArrayList<ImportedDeclGroup>, name: String, decl: Decl): Unit {
        for (group in groups) {
            if (group.name == name) {
                AddDeclIfMissing(group.decls, decl)
                return
            }
        }
        let decls = ArrayList<Decl>()
        decls.add(decl)
        groups.add(ImportedDeclGroup(name, decls))
    }

    private func AddDeclIfMissing(values: ArrayList<Decl>, decl: Decl): Unit {
        for (value in values) {
            if (SameImportedAwareDecl(value, decl)) {
                return
            }
        }
        values.add(decl)
    }

    private func SameImportedAwareDecl(left: Decl, right: Decl): Bool {
        if (left.TestAttr(Attribute.IMPORTED) && right.TestAttr(Attribute.IMPORTED)) {
            if (!left.rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
                return left.rawMangleName == right.rawMangleName
            }
            if (!left.mangledName.isEmpty() || !right.mangledName.isEmpty()) {
                return left.mangledName == right.mangledName
            }
        }
        return SameDecl(left, right)
    }

    private func LastPackageName(fullPackageName: String): String {
        let parts = SplitQualifiedName(fullPackageName)
        if (parts.isEmpty()) {
            return fullPackageName
        }
        return parts[parts.size - 1]
    }

    private func RootPackageName(fullPackageName: String): String {
        let parts = SplitQualifiedName(fullPackageName)
        if (parts.isEmpty()) {
            return fullPackageName
        }
        return parts[0]
    }

    private func SplitQualifiedName(fullPackageName: String): ArrayList<String> {
        let out = ArrayList<String>()
        var start: Int64 = 0
        var idx: Int64 = 0
        while (idx <= fullPackageName.size) {
            if (idx == fullPackageName.size || fullPackageName[idx] == UInt8(46)) {
                if (idx > start) {
                    out.add(fullPackageName[start..idx])
                }
                start = idx + 1
            }
            idx++
        }
        return out
    }

    public func GetPackage(name: String): Option<Package> {
        for (pkg in importedPackages) {
            if (pkg.fullPackageName == name) {
                return Some(pkg)
            }
        }
        return None
    }

    private func GetPackageForImportCheck(name: String, sourcePackages: ArrayList<Package>): Option<Package> {
        if (let Some(pkg) <- GetPackage(name)) {
            return Some(pkg)
        }
        for (pkg in sourcePackages) {
            if (pkg.fullPackageName == name) {
                return Some(pkg)
            }
        }
        return None
    }

    private func CheckImports(sourcePackages: ArrayList<Package>): Unit {
        for (pkg in sourcePackages) {
            for (file in pkg.files) {
                for (importSpec in file.imports) {
                    if (importSpec.IsImportMulti()) {
                        continue
                    }
                    let fullPackageName = importSpec.content.GetImportedPackageNameWithIsDecl()
                    if (fullPackageName.isEmpty()) {
                        continue
                    }
                    let packageOpt = GetPackageForImportCheck(fullPackageName, sourcePackages)
                    if (let None <- packageOpt) {
                        continue
                    }
                    if (importSpec.TestAttr(Attribute.IMPLICIT_ADD) || importSpec.IsImportAll() ||
                        IsPackageImportForCheck(importSpec, fullPackageName, sourcePackages)) {
                        continue
                    }
                    let packageValue = packageOpt.getOrThrow()
                    if (!HasVisibleImportedDecl(pkg.fullPackageName, packageValue, importSpec.content.identifier.Val())) {
                        let im = importSpec.content
                        let nameRange = MakeRange(im.prefixPoses[0], im.identifier.End())
                        diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
                            DiagKindRefactor.package_decl_not_find_in_package,
                            nameRange,
                            arguments: [im.identifier.Val(), fullPackageName]).Emit()
                    }
                }
            }
        }
    }

    private func IsPackageImportForCheck(
        importSpec: ImportSpec,
        targetPackageName: String,
        sourcePackages: ArrayList<Package>
    ): Bool {
        if (importSpec.IsImportAll() || importSpec.content.isDecl) {
            return false
        }
        for (pkg in importedPackages) {
            if (pkg.fullPackageName == targetPackageName) {
                return true
            }
        }
        for (pkg in sourcePackages) {
            if (pkg.fullPackageName == targetPackageName) {
                return true
            }
        }
        return false
    }

    private func HasVisibleImportedDecl(srcFullPackageName: String, pkg: Package, name: String): Bool {
        BuildPackageMembers(pkg.fullPackageName)
        let relation = GetFrontendPackageRelation(srcFullPackageName, pkg.fullPackageName)
        if (let Some(members) <- packageMembers.get(pkg.fullPackageName)) {
            if (let Some(decls) <- members.get(name)) {
                for (decl in decls) {
                    if (IsFrontendVisible(decl, relation)) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func RebuildPackageMembers(fullPackageName: String): Unit {
        packageMembers.remove(fullPackageName)
        packageMembersVisited.remove(fullPackageName)
        BuildPackageMembers(fullPackageName)
    }

    private func BuildPackageMembers(fullPackageName: String, importedPackage!: String = ""): Unit {
        if (packageMembersVisited.contains(fullPackageName)) {
            return
        }
        packageMembersVisited.add(fullPackageName)
        let pkgOpt = GetPackageForMemberBuild(fullPackageName)
        if (let None <- pkgOpt) {
            return
        }
        let pkg = pkgOpt.getOrThrow()
        if (!packageMembers.contains(fullPackageName)) {
            packageMembers[fullPackageName] = HashMap<String, ArrayList<Decl>>()
        }
        let members = packageMembers.get(fullPackageName).getOrThrow()
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (!decl.TestAttr(Attribute.MACRO_EXPANDED_NODE)) {
                    PutImportedDecl(members, decl.identifier.Val(), decl)
                }
            }
        }
        let relation = if (importedPackage.isEmpty()) {
            GetFrontendPackageRelation(fullPackageName, fullPackageName)
        } else {
            GetFrontendPackageRelation(importedPackage, fullPackageName)
        }
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsImportMulti()) {
                    continue
                }
                let importedName = importSpec.content.GetImportedPackageNameWithIsDecl()
                if (importedName.isEmpty()) {
                    continue
                }
                BuildPackageMembers(importedName, importedPackage: fullPackageName)
                if (importSpec.IsReExport() && IsFrontendVisible(importSpec, relation)) {
                    AddReExportedMembers(importSpec, importedName, members)
                }
            }
        }
    }

    private func GetPackageForMemberBuild(fullPackageName: String): Option<Package> {
        if (let Some(pkg) <- GetPackage(fullPackageName)) {
            return Some(pkg)
        }
        for (pkg in sourcePackagesForMembers) {
            if (pkg.fullPackageName == fullPackageName) {
                return Some(pkg)
            }
        }
        return None
    }

    private func AddReExportedMembers(
        importSpec: ImportSpec,
        importedPackage: String,
        targetMembers: HashMap<String, ArrayList<Decl>>
    ): Unit {
        if (let None <- packageMembers.get(importedPackage)) {
            return
        }
        let importedMembers = packageMembers.get(importedPackage).getOrThrow()
        if (importSpec.IsImportAll()) {
            for (name in importedMembers.keys()) {
                if (let Some(decls) <- importedMembers.get(name)) {
                    AddImportedDeclsWithAccess(decls, targetMembers, name, GetAccessLevel(importSpec))
                }
            }
            return
        }
        let sourceName = importSpec.content.identifier.Val()
        if (let Some(decls) <- importedMembers.get(sourceName)) {
            let targetName = if (importSpec.IsImportAlias()) {
                importSpec.content.aliasName.Val()
            } else {
                sourceName
            }
            AddImportedDeclsWithAccess(decls, targetMembers, targetName, GetAccessLevel(importSpec))
        }
    }

    private func AddImportedDeclsWithAccess(
        decls: ArrayList<Decl>,
        targetMembers: HashMap<String, ArrayList<Decl>>,
        targetName: String,
        importLevel: AccessLevel
    ): Unit {
        for (decl in decls) {
            if (IsFrontendCompatibleAccessLevel(importLevel, GetAccessLevel(decl))) {
                PutImportedDecl(targetMembers, targetName, decl)
            }
        }
    }

    private func AddImportedPackageIfMissing(pkg: Package): Unit {
        for (existing in importedPackages) {
            if (existing.fullPackageName == pkg.fullPackageName) {
                return
            }
        }
        importedPackages.add(pkg)
    }

    private func LoadResolvedImportedPackages(): Bool {
        if (let Some(corePath) <- depPkgCjdPaths.get("std.core")) {
            if ((let None <- GetPackage("std.core")) && !LoadImportedPackageFromCjo("std.core", corePath)) {
                return false
            }
        }
        for (dep in depPkgCjdPaths.keys()) {
            if (dep == "std.core" || (let Some(_) <- GetPackage(dep))) {
                continue
            }
            if (let Some(path) <- depPkgCjdPaths.get(dep)) {
                if (!LoadImportedPackageFromCjo(dep, path)) {
                    return false
                }
            }
        }
        return true
    }

    private func LoadImportedPackageFromCjo(fullPackageName: String, cjoPath: String): Bool {
        if ((let Some(_) <- GetPackage(fullPackageName)) || loadingPackages.contains(fullPackageName)) {
            return true
        }
        loadingPackages.add(fullPackageName)
        let (ok, data, reason) = FileUtil.ReadBinaryFileToBuffer(cjoPath)
        if (!ok) {
            loadingPackages.remove(fullPackageName)
            diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                "failed to load imported package '${fullPackageName}' from '${cjoPath}': ${reason}")
            return false
        }
        if (!LoadSerializedImportDependencies(data, fullPackageName)) {
            loadingPackages.remove(fullPackageName)
            return false
        }
        let pkg = CreatePackage(fullPackageName)
        pkg.EnableAttr(Attribute.IMPORTED)
        pkg.hasSourceImportedDecl = true
        let (fallbackFile, filesByIndex) = MaterializeCjoFiles(data, pkg, cjoPath)
        let materializer = CjoSignatureMaterializer(fullPackageName, pkg, fallbackFile, filesByIndex, importedPackages)
        materializer.Materialize(data)
        AddImportedPackageIfMissing(pkg)
        loadingPackages.remove(fullPackageName)
        return true
    }

    private func MaterializeCjoFiles(data: Array<UInt8>, pkg: Package, cjoPath: String): (File, HashMap<UInt32, File>) {
        let filesByIndex = HashMap<UInt32, File>()
        let reader = CjoFlatBuffer(data)
        let root = reader.RootTable()
        let filesVec = if (root >= 0) { reader.VectorField(root, 14) } else { -1 }
        if (filesVec >= 0) {
            var idx: Int64 = 0
            while (idx < reader.VectorLength(filesVec)) {
                let storedPath = reader.StringAt(reader.VectorOffsetElement(filesVec, idx))
                let file = CreateImportedCjoFile(pkg, if (storedPath.isEmpty()) { cjoPath } else { storedPath },
                    UInt64(idx + 1))
                filesByIndex[UInt32(idx + 1)] = file
                idx++
            }
        }
        if (pkg.files.isEmpty()) {
            let file = CreateImportedCjoFile(pkg, cjoPath, 1u64)
            filesByIndex[1u32] = file
        }
        return (pkg.files[0], filesByIndex)
    }

    private func CreateImportedCjoFile(pkg: Package, path: String, fileID: UInt64): File {
        let file = CreateFile(path)
        file.fileName = FileUtil.GetFileName(path)
        file.begin = Position(fileID, 1, 1)
        file.end = Position(fileID, 1, 1)
        file.curPackage = Some(pkg)
        pkg.files.add(file)
        return file
    }

    private func LoadSerializedImportDependencies(data: Array<UInt8>, ownerPackageName: String): Bool {
        let reader = CjoFlatBuffer(data)
        let root = reader.RootTable()
        if (root < 0) {
            return true
        }
        let flatImports = reader.VectorField(root, 12)
        if (flatImports < 0) {
            return true
        }
        var idx: Int64 = 0
        while (idx < reader.VectorLength(flatImports)) {
            let depName = reader.StringAt(reader.VectorOffsetElement(flatImports, idx))
            if (!depName.isEmpty() && depName != ownerPackageName && (let None <- GetPackage(depName)) &&
                !loadingPackages.contains(depName)) {
                let depPath = FileUtil.FindSerializationFile(depName, ".cjo", searchPath.toArray())
                if (!depPath.isEmpty() && !LoadImportedPackageFromCjo(depName, depPath)) {
                    return false
                }
            }
            idx++
        }
        return true
    }

    private func CollectDirectDependencyNames(pkg: Package, sourcePackages: HashSet<String>): HashSet<String> {
        let deps = HashSet<String>()
        for (dep in CollectDirectDependencyNamesInOrder(pkg, sourcePackages)) {
            deps.add(dep)
        }
        return deps
    }

    private func CollectDirectDependencyNamesInOrder(pkg: Package, sourcePackages: HashSet<String>): ArrayList<String> {
        let deps = ArrayList<String>()
        let seen = HashSet<String>()
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                let depName = NormalizeImportedPackageName(importSpec.content, sourcePackages)
                if (!depName.isEmpty() && depName != pkg.fullPackageName && !seen.contains(depName)) {
                    seen.add(depName)
                    deps.add(depName)
                }
            }
        }
        return deps
    }

    private func AddImplicitImports(pkg: Package, opts: GlobalOptions): Unit {
        if (!opts.implicitPrelude) {
            return
        }
        for (file in pkg.files) {
            AddImplicitImportAll(file, "std.core")
        }
    }

    private func AddImplicitImportAll(file: File, fullPackageName: String): Unit {
        for (importSpec in file.imports) {
            if (importSpec.TestAttr(Attribute.IMPLICIT_ADD) && importSpec.IsImportAll() &&
                importSpec.content.GetPrefixPath() == fullPackageName) {
                return
            }
        }
        let importSpec = CreateImportSpec(fullPackageName, "*", "")
        importSpec.curFile = Some(file)
        importSpec.content.curFile = Some(file)
        file.imports.add(importSpec)
    }

    private func NormalizeImportedPackageName(content: ImportContent, sourcePackages: HashSet<String>): String {
        if (content.kind == ImportKind.IMPORT_ALL || content.isDecl) {
            return content.GetPrefixPath()
        }
        let importedPackageName = content.GetImportedPackageName()
        for (possibleName in content.GetPossiblePackageNames()) {
            if (sourcePackages.contains(possibleName) ||
                !FileUtil.FindSerializationFile(possibleName, ".cjo", searchPath.toArray()).isEmpty()) {
                if (possibleName != importedPackageName) {
                    content.isDecl = true
                }
                return possibleName
            }
        }
        return content.GetImportedPackageName()
    }
}

private func StringSetToJsonArray(values: HashSet<String>): String {
    let orderedValues = ArrayList<String>()
    for (value in values) {
        orderedValues.add(value)
    }
    sort(orderedValues, by: { left: String, right: String =>
        if (left < right) {
            Ordering.LT
        } else if (left > right) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    })
    let parts = ArrayList<String>()
    for (value in orderedValues) {
        parts.add("\"" + EscapeJson(value) + "\"")
    }
    return "[" + JoinStringList(parts, ",") + "]"
}

private func JoinStringList(values: ArrayList<String>, delimiter: String): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(delimiter)
        }
        builder.append(values[idx])
        idx++
    }
    return builder.toString()
}

public class PackageManager {
    private let importManager: ImportManager
    public init(importManager: ImportManager) {
        this.importManager = importManager
    }

    public func ResolveDependence(pkgs: ArrayList<Package>): Bool {
        let _ = importManager
        sort(pkgs, by: { left: Package, right: Package =>
            if (left.fullPackageName < right.fullPackageName) {
                Ordering.LT
            } else if (left.fullPackageName > right.fullPackageName) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        return true
    }

    public func GetBuildOrders(pkgs: ArrayList<Package>): ArrayList<ArrayList<Package>> {
        let out = ArrayList<ArrayList<Package>>()
        for (pkg in pkgs) {
            let group = ArrayList<Package>()
            group.add(pkg)
            out.add(group)
        }
        return out
    }
}

public class TestManager {
    public init() {}
    public func MarkDeclsForTestIfNeeded(pkgs: ArrayList<Package>): Unit {
        let _ = pkgs
    }
}

public class GenericInstantiationManager {
    public init(instance: CompilerInstance) {
        let _ = instance
    }
}

public class BaseMangler {
    public var lambdaCounter: Int64 = 0
    public init() {}

    public func Mangle(decl: Decl, prefix!: String = ""): String {
        let pkgPrefix = if (decl.fullPackageName.isEmpty()) { "" } else { decl.fullPackageName + "." }
        return "_C" + (pkgPrefix + prefix + decl.identifier.Val()).replace(".", "_").replace("::", "_")
    }
}

public func EscapeJson(text: String): String {
    return text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")
}

public let DIR_SEPARATOR: String = "/"
