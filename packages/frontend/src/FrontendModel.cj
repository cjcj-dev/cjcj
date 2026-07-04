package cangjie_compiler::frontend

public import cangjie_compiler::basic.{
    BEGIN_POSITION, CANGJIE_VERSION, DEFAULT_POSITION, INVALID_POSITION, DiagCategory, DiagColor, DiagKindRefactor,
    DiagHelp, DiagSeverity, IntegratedString, MakeRange, Position, PositionStatus, Range, Source, SourceManager
}
public import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::basic.StringConvertor
import cangjie_compiler::basic.Diagnostic as BasicDiagnostic
import cangjie_compiler::basic.DiagFormat as BasicDiagFormat
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.FaithfulUnorderedMap
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::chir.CHIRContext as RealCHIRContext
import cangjie_compiler::chir.Package as RealCHIRPackage
import cangjie_compiler::modules.SemaImportManager
import cangjie_compiler::option.OptimizationLevel
import cangjie_compiler::option.enumIndex
public import cangjie_compiler::mangle.BaseMangler
import cangjie_compiler::sema.GenericInstantiation.GenericInstantiationManagerImpl as RealGenericInstantiationManagerImpl
import cangjie_compiler::sema.TypeManager as FaithfulSemaTypeManager
import cangjie_compiler::utils.{AST_PACKAGE_NAME, EraseIf, JoinStrings, MAIN_INVOKE}
import cangjie_compiler::utils.FileUtil
import cangjie_compiler::utils.ProfileRecorder
import cangjie_compiler::utils.STANDARD_LIBS
import std.collection.*
import std.sort.*

foreign {
    func CJOFVerifyPackageBuffer(data: CPointer<UInt8>, size: UIntNative): Int32
}

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
    private let impl: FaithfulSemaTypeManager = FaithfulSemaTypeManager()

    public init() {}

    public func AsFaithfulSemaTypeManager(): FaithfulSemaTypeManager {
        return impl
    }

    public func ReleasePostSemaCaches(): Unit {
        impl.ReleasePostSemaCaches()
    }
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

    public func I32At(pos: Int64): Int64 {
        return ReadI32(pos)
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

    public func VerifyPackageBuffer(): Bool {
        if (data.isEmpty()) {
            return false
        }
        var result = false
        try (buffer = LibC.malloc<UInt8>(count: data.size).asResource()) {
            if (!buffer.value.isNull()) {
                var idx: Int64 = 0
                unsafe {
                    while (idx < data.size) {
                        (buffer.value + idx).write(data[idx])
                        idx++
                    }
                    result = CJOFVerifyPackageBuffer(buffer.value, UIntNative(data.size)) != 0
                }
            }
        } catch (e: Exception) {
            result = false
        }
        return result
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
    private var pkg: Package
    private var filesByIndex: HashMap<UInt32, File>
    private var idToFileMap: HashMap<UInt64, File>
    private let importedPackages: ArrayList<Package>
    private let packageDecls: HashMap<String, PackageDecl>
    private let exportIdDeclMaps: HashMap<String, HashMap<String, Decl>>
    private let diag: DiagnosticEngine
    private var flat: Option<CjoFlatBuffer> = None
    private var flatAllDecls: Int64 = -1
    private var flatAllTypes: Int64 = -1
    private var flatAllExprs: Int64 = -1
    private var flatImports: Int64 = -1
    private var data: Option<Array<UInt8>> = None
    private let typeManager: FaithfulSemaTypeManager
    private let flatDecls: HashMap<UInt32, CjoFlatDecl> = HashMap<UInt32, CjoFlatDecl>()
    private let flatNominalKinds: HashMap<String, UInt8> = HashMap<String, UInt8>()
    private let flatTypeCache: HashMap<UInt32, Ty> = HashMap<UInt32, Ty>()
    private let flatGenericParamDecls: HashMap<UInt32, GenericParamDecl> = HashMap<UInt32, GenericParamDecl>()
    private let allLoadedDecls: HashMap<UInt32, Decl> = HashMap<UInt32, Decl>()
    private let allLoadedExprs: HashMap<UInt32, Expr> = HashMap<UInt32, Expr>()
    private let allDummyExprs: HashSet<Node> = HashSet<Node>()
    private let importNonGenericSrcFuncDecls: ArrayList<Decl> = ArrayList<Decl>()
    private let importSrcCode: Bool
    private let deserializingCommon: Bool
    private let canInline: Bool
    private let isLoadCache: Bool

    public init(packageName: String, pkg: Package, filesByIndex: HashMap<UInt32, File>,
        idToFileMap: HashMap<UInt64, File>, importedPackages: ArrayList<Package>,
        packageDecls: HashMap<String, PackageDecl>, exportIdDeclMaps: HashMap<String, HashMap<String, Decl>>,
        diag: DiagnosticEngine, typeManager: FaithfulSemaTypeManager,
        importSrcCode!: Bool = true, deserializingCommon!: Bool = false, canInline!: Bool = false,
        isLoadCache!: Bool = false, data!: Option<Array<UInt8>> = None) {
        this.packageName = packageName
        this.pkg = pkg
        this.filesByIndex = filesByIndex
        this.idToFileMap = idToFileMap
        this.importedPackages = importedPackages
        this.packageDecls = packageDecls
        this.exportIdDeclMaps = exportIdDeclMaps
        this.diag = diag
        this.typeManager = typeManager
        this.importSrcCode = importSrcCode
        this.deserializingCommon = deserializingCommon
        this.canInline = canInline
        this.isLoadCache = isLoadCache
        this.data = data
        if (!this.exportIdDeclMaps.contains(packageName)) {
            this.exportIdDeclMaps[packageName] = HashMap<String, Decl>()
        }
    }

    public func Materialize(data: Array<UInt8>): Unit {
        let _ = LoadPackageDependencies(data)
        LoadPackageDecls()
        LoadRefs()
    }

    public func LoadPackageDependencies(newData: Array<UInt8>): Bool {
        data = Some(newData)
        PreLoadImportedPackageNode(newData)
        return flatAllTypes >= 0 && flatAllDecls >= 0
    }

    public func LoadPackageDecls(): Unit {
        LoadSerializedDeclRecords()
        MaterializeSerializedDecls()
    }

    public func LoadRefs(): Unit {
        if ((let None <- flat) || flatAllDecls < 0) {
            return
        }
        let reader = flat.getOrThrow()
        for ((index, decl) in allLoadedDecls) {
            if (let Some(record) <- flatDecls.get(index)) {
                LoadFlatDeclRefs(reader, record, decl)
                LoadFlatDeclDependencies(reader, record, decl)
            }
        }
        for ((index2, expr) in allLoadedExprs) {
            let exprTable = FlatExprTable(reader, index2)
            if (exprTable >= 0) {
                LoadFlatExprRefs(reader, exprTable, expr)
            }
        }
        for (dummy in allDummyExprs) {
            let dummyExpr = (dummy as Expr).getOrThrow()
            let desugar = dummyExpr.desugarExpr.getOrThrow()
            if (let Some(ty) <- desugar.GetTy()) {
                dummyExpr.SetTy(ty)
            }
        }
        for ((_, expr2) in allLoadedExprs) {
            PostLoadFlatReference(expr2)
        }
    }

    public func GetImportedPackageName(): String {
        return packageName
    }

    public func GetDependentPackageNames(): ArrayList<String> {
        let dep = ArrayList<String>()
        if ((let None <- flat) || flatImports < 0) {
            return dep
        }
        let reader = flat.getOrThrow()
        var idx: Int64 = 0
        while (idx < reader.VectorLength(flatImports)) {
            let importItem = reader.StringAt(reader.VectorOffsetElement(flatImports, idx))
            if (importItem != packageName) {
                dep.add(importItem)
            }
            idx++
        }
        return dep
    }

    public func PreloadCommonPartOfPackage(targetPkg: Package, opts: GlobalOptions): Bool {
        let rawData = data.getOrThrow()
        flat = Some(CjoFlatBuffer(rawData))
        flatAllDecls = -1
        flatAllTypes = -1
        flatAllExprs = -1
        flatImports = -1
        flatDecls.clear()
        flatNominalKinds.clear()
        flatTypeCache.clear()
        flatGenericParamDecls.clear()
        allLoadedDecls.clear()
        allLoadedExprs.clear()
        allDummyExprs.clear()
        importNonGenericSrcFuncDecls.clear()
        let reader = flat.getOrThrow()
        if (!reader.VerifyPackageBuffer()) {
            diag.DiagnoseRefactor(DiagKindRefactor.module_loaded_ast_failed, DEFAULT_POSITION,
                arguments: ["ast", targetPkg.fullPackageName, CANGJIE_VERSION])
            return false
        }
        let root = reader.RootTable()
        if (root < 0) {
            return false
        }
        let deserializedPackageName = reader.StringField(root, 8)
        if (targetPkg.fullPackageName != deserializedPackageName) {
            ReportPackageMismatch(targetPkg, targetPkg.fullPackageName, deserializedPackageName)
            return false
        }
        pkg = targetPkg
        filesByIndex = HashMap<UInt32, File>()
        idToFileMap = HashMap<UInt64, File>()
        flatAllTypes = reader.VectorField(root, 18)
        flatAllDecls = reader.VectorField(root, 20)
        flatAllExprs = reader.VectorField(root, 22)
        flatImports = reader.VectorField(root, 12)
        let specificFeatures = CollectFeaturesFromPackage(targetPkg)
        let filesVec = reader.VectorField(root, 14)
        var idx: Int64 = 0
        while (idx < reader.VectorLength(filesVec)) {
            let commonFile = PreloadCommonFile(reader, UInt32(idx))
            ValidateCommonSpecificFeatureSetsRelations(commonFile, specificFeatures, targetPkg)
            targetPkg.files.add(commonFile)
            idx++
        }
        if (!ValidateOptions(reader, opts)) {
            return false
        }
        AddCurFile(targetPkg)
        return true
    }

    private func PreloadCommonFile(reader: CjoFlatBuffer, indexOfFile: UInt32): File {
        let root = reader.RootTable()
        let fileIndex = Int64(indexOfFile)
        let allFiles = reader.VectorField(root, 14)
        let allFileImports = reader.VectorField(root, 16)
        let allFileInfo = reader.VectorField(root, 28)
        let fileInfo = reader.VectorOffsetElement(allFileInfo, fileIndex)
        let tmpFilePath = reader.StringAt(reader.VectorOffsetElement(allFiles, fileIndex))
        let fileID = diag.GetSourceManager().AddSource(tmpFilePath, "", packageName: Some(pkg.fullPackageName),
            isCjmpFile: true)
        if (UInt32(fileID) != reader.U32Field(fileInfo, 4, 0u32)) {
            throw IllegalStateException("FlatBuffer common part file ID mismatch")
        }
        let source = diag.GetSourceManager().GetSource(fileID)
        let file = CreateFile(source.path)
        file.fileName = FileUtil.GetFileName(source.path)
        file.filePath = source.path
        file.fileHash = source.fileHash
        file.begin.fileID = fileID
        file.curFile = Some(file)
        file.curPackage = Some(pkg)
        let importsTable = reader.VectorOffsetElement(allFileImports, fileIndex)
        if (importsTable >= 0) {
            MaterializeFlatImports(reader, importsTable, file)
            for (importSpec in file.imports) {
                importSpec.EnableAttr(Attribute.FROM_COMMON_PART)
            }
        }
        let featureTable = reader.OffsetField(fileInfo, 10)
        if (featureTable >= 0) {
            file.feature = LoadFeaturesDirective(reader, featureTable)
        }
        file.EnableAttr(Attribute.FROM_COMMON_PART)
        file.EnableAttr(Attribute.COMMON)
        file.isCommon = true
        file.begin = LoadFlatPosition(reader, reader.TableField(fileInfo, 6))
        file.end = LoadFlatPosition(reader, reader.TableField(fileInfo, 8))
        filesByIndex[UInt32(fileIndex + 1)] = file
        if (!idToFileMap.contains(fileID)) {
            idToFileMap[fileID] = file
        }
        return file
    }

    private func LoadFeaturesDirective(reader: CjoFlatBuffer, raw: Int64): Option<FeaturesDirective> {
        let ftrDirective = FeaturesDirective()
        let featuresSet = FeaturesSet()
        let rawFeaturesSet = reader.OffsetField(raw, 4)
        let rawFeatures = reader.VectorField(rawFeaturesSet, 4)
        var idx: Int64 = 0
        while (idx < reader.VectorLength(rawFeatures)) {
            let rawFeature = reader.VectorOffsetElement(rawFeatures, idx)
            let feature = FeatureId()
            let identifiers = reader.VectorField(rawFeature, 4)
            var identifierIdx: Int64 = 0
            while (identifierIdx < reader.VectorLength(identifiers)) {
                feature.identifiers.add(Identifier(reader.StringAt(reader.VectorOffsetElement(identifiers, identifierIdx))))
                identifierIdx++
            }
            featuresSet.content.add(feature)
            idx++
        }
        ftrDirective.featuresSet = Some(featuresSet)
        return Some(ftrDirective)
    }

    private func ReportPackageMismatch(node: Package, expectedPackageName: String, actualPackageName: String): Unit {
        var range = MakeRange(node.begin, node.end)
        if (range.HasZero()) {
            if (node.files.isEmpty()) {
                throw IllegalStateException("There are no files in the current package")
            }
            let file = node.files[0]
            range = MakeRange(file.begin, file.end)
        }
        diag.AsBasicDiagnosticEngine().DiagnoseRefactor(DiagKindRefactor.module_common_cjo_wrong_package, range,
            arguments: [actualPackageName, expectedPackageName]).Emit()
    }

    private func CollectFeaturesFromPackage(sourcePkg: Package): TreeSet<String> {
        let features = TreeSet<String>()
        for (feature in sourcePkg.files[0].GetFeatures()) {
            features.add(feature)
        }
        return features
    }

    private func ValidateCommonSpecificFeatureSetsRelations(
        commonFile: File,
        specificFeatures: TreeSet<String>,
        sourcePkg: Package
    ): Unit {
        let parentFeatures = TreeSet<String>()
        for (feature in commonFile.GetFeatures()) {
            parentFeatures.add(feature)
        }
        let difference = ArrayList<String>()
        for (feature in parentFeatures) {
            if (!specificFeatures.contains(feature)) {
                difference.add("'" + feature + "'")
            }
        }
        if (!difference.isEmpty()) {
            let diagBuilder = diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
                DiagKindRefactor.feature_is_not_subset_of_child_set,
                commonFile.begin,
                arguments: [commonFile.GetFullPackageName(), commonFile.filePath])
            diagBuilder.AddNote("Extra feature from common part file: " + JoinStrings(difference.toArray(), " "))
            let childFile = sourcePkg.files[0]
            if (let Some(featureDirective) <- childFile.feature) {
                diagBuilder.AddNote(MakeRange(featureDirective.begin, featureDirective.end),
                    "Conflicting specific feature set:")
            }
            diagBuilder.Emit()
        }
    }

    private func ValidateOptions(reader: CjoFlatBuffer, opts: GlobalOptions): Bool {
        let root = reader.RootTable()
        let optionsTable = reader.OffsetField(root, 32)
        if (optionsTable < 0) {
            diag.DiagnoseRefactor(DiagKindRefactor.module_common_cjo_no_options, DEFAULT_POSITION)
            return true
        }
        var failed = false
        let loadedDebugOption = reader.U8Field(optionsTable, 6, 0u8) != 0u8
        if (loadedDebugOption != opts.enableCompileDebug) {
            let before = if (loadedDebugOption) { "enabled" } else { "disabled" }
            let after = if (opts.enableCompileDebug) { "enabled" } else { "disabled" }
            diag.DiagnoseRefactor(DiagKindRefactor.module_common_cjo_debug_mismatch, DEFAULT_POSITION,
                arguments: [before, after])
            failed = true
        }
        let cjoOptLevel = match (reader.U8Field(optionsTable, 4, 0u8)) {
            case 0u8 => OptimizationLevel.O0
            case 1u8 => OptimizationLevel.O1
            case 2u8 => OptimizationLevel.O2
            case 3u8 => OptimizationLevel.O3
            case 4u8 => OptimizationLevel.Os
            case 5u8 => OptimizationLevel.Oz
            case _ => throw IllegalStateException("Unexpected optimization level")
        }
        if (cjoOptLevel != opts.optimizationLevel) {
            diag.DiagnoseRefactor(DiagKindRefactor.module_common_cjo_opt_mismatch, DEFAULT_POSITION,
                arguments: [OptimizationLevelToString(cjoOptLevel), OptimizationLevelToString(opts.optimizationLevel)])
            failed = true
        }
        return !failed
    }

    private func OptimizationLevelToString(level: OptimizationLevel): String {
        return match (level) {
            case OptimizationLevel.O0 => "O0"
            case OptimizationLevel.O1 => "O1"
            case OptimizationLevel.O2 => "O2"
            case OptimizationLevel.O3 => "O3"
            case OptimizationLevel.Os => "Os"
            case OptimizationLevel.Oz => "Oz"
        }
    }

    private func PreLoadImportedPackageNode(data: Array<UInt8>): Unit {
        flat = Some(CjoFlatBuffer(data))
        flatAllDecls = -1
        flatAllTypes = -1
        flatAllExprs = -1
        flatImports = -1
        flatDecls.clear()
        flatNominalKinds.clear()
        flatTypeCache.clear()
        flatGenericParamDecls.clear()
        allLoadedDecls.clear()
        allLoadedExprs.clear()
        allDummyExprs.clear()
        importNonGenericSrcFuncDecls.clear()
        let reader = flat.getOrThrow()
        let root = reader.RootTable()
        if (root < 0 || reader.StringField(root, 8) != packageName) {
            return
        }
        pkg.isMacroPackage = reader.U8Field(root, 26, 0u8) != 0u8
        let packageAccess = reader.U8Field(root, 28, 0u8)
        pkg.accessible = if (packageAccess == 0u8) {
            AccessLevel.PUBLIC
        } else if (packageAccess == 1u8) {
            AccessLevel.PROTECTED
        } else {
            AccessLevel.INTERNAL
        }
        flatAllTypes = reader.VectorField(root, 18)
        flatAllDecls = reader.VectorField(root, 20)
        flatAllExprs = reader.VectorField(root, 22)
        flatImports = reader.VectorField(root, 12)
        MaterializeSerializedImports()
        let dependentStdPkgs = reader.VectorField(root, 34)
        if (dependentStdPkgs >= 0) {
            var depIdx: Int64 = 0
            while (depIdx < reader.VectorLength(dependentStdPkgs)) {
                let depStdPkg = reader.StringAt(reader.VectorOffsetElement(dependentStdPkgs, depIdx))
                if (!depStdPkg.isEmpty()) {
                    pkg.AddDependentStdPkg(depStdPkg)
                }
                depIdx++
            }
        }
    }

    private func LoadFlatDeclRefs(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: Decl): Unit {
        decl.SetTy(LoadFlatTypeOrInvalid(record.typeIndex))
        if (!Ty.IsTyCorrect(decl.GetTy()) && isLoadCache) {
            return
        }
        LoadFlatGenericConstraintsRef(reader, record, decl.GetGeneric())
        LoadFlatAnnotationBaseExprs(reader, record, decl)
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            LoadFlatFuncDeclRefs(reader, record, funcDecl)
        } else if (let Some(structDecl) <- (decl as StructDecl)) {
            LoadFlatInheritableDeclRefs(reader, record, structDecl)
        } else if (let Some(enumDecl) <- (decl as EnumDecl)) {
            LoadFlatInheritableDeclRefs(reader, record, enumDecl)
        } else if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            LoadFlatInheritableDeclRefs(reader, record, interfaceDecl)
        } else if (let Some(classDecl) <- (decl as ClassDecl)) {
            LoadFlatInheritableDeclRefs(reader, record, classDecl)
        } else if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            LoadFlatInheritableDeclRefs(reader, record, extendDecl)
            if (let Some(ty2) <- extendDecl.GetTy()) {
                extendDecl.extendedType = Some(UpdateFlatTypeNode(extendDecl.extendedType, TypeNodeForTy(ty2)))
            }
        } else if (let Some(aliasDecl) <- (decl as TypeAliasDecl)) {
            LoadFlatTypeAliasDeclRef(reader, record, aliasDecl)
        } else if (let Some(varWithPattern) <- (decl as VarWithPatternDecl)) {
            let infoTable = reader.OffsetField(record.table, 38)
            if (infoTable < 0) {
                throw IllegalStateException("FlatBuffer VarWithPatternDecl has no VarWithPatternInfo")
            }
            if (let Some(pattern) <- varWithPattern.irrefutablePattern) {
                LoadFlatPatternRefs(reader, reader.OffsetField(infoTable, 8), pattern)
            } else {
                throw IllegalStateException("FlatBuffer VarWithPatternDecl irrefutablePattern is missing")
            }
        } else if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
            if (varDecl.typeNode.isNone()) {
                if (let Some(varTy) <- decl.GetTy()) {
                    if (varTy.HasAliasTy() || varTy.IsFunc()) {
                        varDecl.typeNode = Some(TypeNodeForTy(varTy))
                    }
                }
            }
        }
        if (decl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            decl.genericDecl = ResolveFlatFullId(reader, reader.OffsetField(record.table, 10))
        }
    }

    private func LoadFlatFuncDeclRefs(reader: CjoFlatBuffer, record: CjoFlatDecl, funcDecl: FuncDecl): Unit {
        if (let None <- funcDecl.funcBody) {
            throw IllegalStateException("FlatBuffer FuncDecl has no loaded FuncBody")
        }
        let body = funcDecl.funcBody.getOrThrow()
        let nonGenericCtor = funcDecl.TestAttr(Attribute.CONSTRUCTOR) && body.body.isNone()
        if (!nonGenericCtor) {
            let infoTable = reader.OffsetField(record.table, 38)
            if (infoTable < 0) {
                throw IllegalStateException("FlatBuffer FuncDecl has no FuncInfo")
            }
            let bodyTable = reader.OffsetField(infoTable, 4)
            if (bodyTable < 0) {
                throw IllegalStateException("FlatBuffer FuncDecl has no FuncBody")
            }
            let retTypeIndex = reader.U32Field(bodyTable, 6, 0u32)
            if (retTypeIndex != 0u32) {
                body.retType = Some(UpdateFlatTypeNode(body.retType, TypeNodeForTy(LoadFlatTypeOrInvalid(retTypeIndex))))
            }
        }
        body.SetTy(funcDecl.GetTy() ?? FaithfulSemaTypeManager.GetInvalidTy())
    }

    private func LoadFlatInheritableDeclRefs(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: InheritableDecl): Unit {
        for (member in decl.GetMemberDeclPtrs()) {
            SetFlatMemberDeclReference(member, decl)
        }
        if (!decl.toBeCompiled) {
            MaterializeFlatInheritedTypes(reader, record)
        }
    }

    private func SetFlatMemberDeclReference(member: Decl, parentDecl: Decl): Unit {
        var parentTypeDecl = parentDecl
        if (let Some(extendDecl) <- (parentDecl as ExtendDecl)) {
            if (let Some(extendedDecl) <- Ty.GetDeclPtrOfTy(extendDecl.GetTy())) {
                parentTypeDecl = extendedDecl
            }
        }
        if (let Some(propDecl) <- (member as PropDecl)) {
            for (getter in propDecl.getters) {
                SetFlatFuncParentReference(getter, parentTypeDecl)
            }
            for (setter in propDecl.setters) {
                SetFlatFuncParentReference(setter, parentTypeDecl)
            }
        } else if (let Some(funcDecl) <- (member as FuncDecl)) {
            SetFlatFuncParentReference(funcDecl, parentTypeDecl)
            if (let None <- funcDecl.funcBody) {
                throw IllegalStateException("FlatBuffer member FuncDecl has no loaded FuncBody")
            }
            let body = funcDecl.funcBody.getOrThrow()
            if (!body.paramLists.isEmpty()) {
                for (param in body.paramLists[0].params) {
                    if (let Some(desugar) <- param.desugarDecl) {
                        SetFlatFuncParentReference(desugar, parentTypeDecl)
                    }
                }
            }
        }
    }

    private func LoadFlatTypeAliasDeclRef(reader: CjoFlatBuffer, record: CjoFlatDecl, aliasDecl: TypeAliasDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            throw IllegalStateException("FlatBuffer TypeAliasDecl has no AliasInfo")
        }
        aliasDecl.typeNode = Some(UpdateFlatTypeNode(aliasDecl.typeNode,
            TypeNodeForTy(LoadFlatTypeOrInvalid(reader.U32Field(infoTable, 4, 0u32)))))
    }

    private func LoadFlatDeclDependencies(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: Decl): Unit {
        let rawDeps = reader.VectorField(record.table, 40)
        if (deserializingCommon && rawDeps >= 0) {
            var idx: Int64 = 0
            let count = reader.VectorLength(rawDeps)
            while (idx < count) {
                decl.dependencies.add(ResolveFlatFullId(reader, reader.VectorOffsetElement(rawDeps, idx)))
                idx++
            }
        }
    }

    private func LoadFlatGenericConstraintsRef(reader: CjoFlatBuffer, record: CjoFlatDecl,
        generic: Option<Generic>): Unit {
        if (let None <- generic) {
            return
        }
        let genericValue = generic.getOrThrow()
        if (genericValue.TestAttr(Attribute.INCRE_COMPILE)) {
            return
        }
        let genericTable = reader.OffsetField(record.table, 12)
        if (genericTable < 0) {
            return
        }
        LoadFlatGenericConstraints(reader, genericTable, genericValue)
    }

    private func LoadFlatAnnotationBaseExprs(reader: CjoFlatBuffer, record: CjoFlatDecl, decl: Decl): Unit {
        let annos = reader.VectorField(record.table, 24)
        if (annos < 0) {
            return
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(annos)
        if (count != decl.annotations.size) {
            throw IllegalStateException("FlatBuffer annotations do not match loaded annotations")
        }
        while (idx < count) {
            LoadFlatAnnotationBaseExpr(reader, reader.VectorOffsetElement(annos, idx), decl.annotations[idx])
            idx++
        }
    }

    private func LoadFlatAnnotationBaseExpr(reader: CjoFlatBuffer, annoTable: Int64, annotation: Annotation): Unit {
        if (annotation.kind != AstAnnotationKind.CUSTOM) {
            return
        }
        if (let Some(targetCtr) <- ResolveFlatFullId(reader, reader.OffsetField(annoTable, 10))) {
            let refExpr = RefExpr()
            refExpr.ref.target = Some(targetCtr)
            refExpr.ref.identifier = targetCtr.identifier
            if (let Some(ty) <- targetCtr.GetTy()) {
                refExpr.SetTy(ty)
            }
            annotation.baseExpr = Some(refExpr)
        }
    }

    private func LoadFlatExprRefs(reader: CjoFlatBuffer, exprTable: Int64, expr: Expr): Unit {
        expr.SetTy(LoadFlatTypeOrInvalid(reader.U32Field(exprTable, 14, 0u32)))
        expr.overflowStrategy = FlatOverflowStrategy(reader.U8Field(exprTable, 16, 0u8))
        expr.mapExpr = allLoadedExprs.get(reader.U32Field(exprTable, 10, 0u32))
        if (let Some(member) <- (expr as MemberAccess)) {
            let infoTable = reader.OffsetField(exprTable, 20)
            if (infoTable < 0) {
                throw IllegalStateException("FlatBuffer MemberAccess has no ReferenceInfo")
            }
            member.target = LoadFlatReferenceTarget(reader, infoTable)
            LoadFlatReferenceInfo(reader, infoTable, member)
        } else if (let Some(refExpr) <- (expr as RefExpr)) {
            let infoTable2 = reader.OffsetField(exprTable, 20)
            if (infoTable2 < 0) {
                throw IllegalStateException("FlatBuffer RefExpr has no ReferenceInfo")
            }
            refExpr.ref.target = LoadFlatReferenceTarget(reader, infoTable2)
            LoadFlatReferenceInfo(reader, infoTable2, refExpr)
        } else if (let Some(arrayLit) <- (expr as ArrayLit)) {
            if (expr.TyKind() != TypeKind.TYPE_VARRAY) {
                let infoTable3 = reader.OffsetField(exprTable, 20)
                if (infoTable3 < 0) {
                    throw IllegalStateException("FlatBuffer ArrayLit has no ArrayInfo")
                }
                if (let Some(initDecl) <- ResolveFlatFullId(reader, reader.OffsetField(infoTable3, 4))) {
                    arrayLit.initFunc = initDecl as FuncDecl
                }
                if (let None <- arrayLit.initFunc) {
                    throw IllegalStateException("FlatBuffer ArrayLit initFunc is missing")
                }
            }
        } else if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
            if (expr.TyKind() != TypeKind.TYPE_VARRAY) {
                let infoTable4 = reader.OffsetField(exprTable, 20)
                if (infoTable4 < 0) {
                    throw IllegalStateException("FlatBuffer ArrayExpr has no ArrayInfo")
                }
                if (let Some(initDecl2) <- ResolveFlatFullId(reader, reader.OffsetField(infoTable4, 4))) {
                    arrayExpr.initFunc = initDecl2 as FuncDecl
                }
            }
        } else if (let Some(lambda) <- (expr as LambdaExpr)) {
            if (let Some(body) <- lambda.funcBody) {
                body.SetTy(expr.GetTy() ?? FaithfulSemaTypeManager.GetInvalidTy())
            }
        } else if (let Some(litConst) <- (expr as LitConstExpr)) {
            let litTy = expr.GetTy() ?? FaithfulSemaTypeManager.GetInvalidTy()
            if (litTy.IsString()) {
                litConst.ref = TypeNodeForTy(litTy) as RefType
            }
            InitializeLitConstValue(litConst)
        } else if (let Some(jump) <- (expr as JumpExpr)) {
            jump.refLoop = jump.mapExpr
        }
        LoadFlatSubNodeRefs(reader, exprTable, expr)
    }

    private func LoadFlatSubNodeRefs(reader: CjoFlatBuffer, exprTable: Int64, expr: Expr): Unit {
        if (let Some(call) <- (expr as CallExpr)) {
            let operands = reader.VectorField(exprTable, 12)
            if (operands < 0 || reader.VectorLength(operands) - 1 != call.args.size) {
                throw IllegalStateException("FlatBuffer CallExpr operands do not match loaded args")
            }
            var idx: Int64 = 1
            let count = reader.VectorLength(operands)
            while (idx < count) {
                let index = reader.VectorU32(operands, idx)
                if (index == 0u32) {
                    throw IllegalStateException("FlatBuffer CallExpr arg operand is invalid")
                }
                let argTable = FlatExprTable(reader, index)
                if (argTable < 0) {
                    throw IllegalStateException("FlatBuffer CallExpr arg table is missing")
                }
                let argTy = LoadFlatTypeOrInvalid(reader.U32Field(argTable, 14, 0u32))
                let arg = call.args[idx - 1]
                arg.SetTy(argTy)
                if (arg.TestAttr(Attribute.HAS_INITIAL)) {
                    if (let Some(argExpr) <- arg.expr) {
                        argExpr.SetTy(arg.GetTy() ?? FaithfulSemaTypeManager.GetInvalidTy())
                    }
                }
                idx++
            }
        } else if (let Some(tryExpr) <- (expr as TryExpr)) {
            let infoTable = reader.OffsetField(exprTable, 20)
            if (infoTable < 0) {
                throw IllegalStateException("FlatBuffer TryExpr has no TryInfo")
            }
            let patterns = reader.VectorField(infoTable, 6)
            if (patterns < 0 || reader.VectorLength(patterns) != tryExpr.catchPatterns.size) {
                throw IllegalStateException("FlatBuffer TryExpr patterns do not match loaded catch patterns")
            }
            var patternIdx: Int64 = 0
            let patternCount = reader.VectorLength(patterns)
            while (patternIdx < patternCount) {
                LoadFlatPatternRefs(reader, reader.VectorOffsetElement(patterns, patternIdx),
                    tryExpr.catchPatterns[patternIdx])
                patternIdx++
            }
        } else if (let Some(matchExpr) <- (expr as MatchExpr)) {
            let operands = reader.VectorField(exprTable, 12)
            if (operands < 0) {
                throw IllegalStateException("FlatBuffer MatchExpr has no operands")
            }
            if (matchExpr.matchMode) {
                if (reader.VectorLength(operands) - 1 != matchExpr.matchCases.size) {
                    throw IllegalStateException("FlatBuffer MatchExpr cases do not match loaded match cases")
                }
                let selector = matchExpr.selector.getOrThrow()
                var idx2: Int64 = 1
                let count2 = reader.VectorLength(operands)
                while (idx2 < count2) {
                    LoadFlatMatchCaseRef(reader, reader.VectorU32(operands, idx2),
                        matchExpr.matchCases[idx2 - 1], selector)
                    idx2++
                }
            } else {
                if (reader.VectorLength(operands) != matchExpr.matchCaseOthers.size) {
                    throw IllegalStateException("FlatBuffer MatchExpr other cases do not match loaded match cases")
                }
                var idx3: Int64 = 0
                let count3 = reader.VectorLength(operands)
                while (idx3 < count3) {
                    let mcTable = FlatExprTable(reader, reader.VectorU32(operands, idx3))
                    if (mcTable < 0) {
                        throw IllegalStateException("FlatBuffer MatchCaseOther table is missing")
                    }
                    matchExpr.matchCaseOthers[idx3].SetTy(
                        LoadFlatTypeOrInvalid(reader.U32Field(mcTable, 14, 0u32)))
                    idx3++
                }
            }
        } else if (let Some(forIn) <- (expr as ForInExpr)) {
            let infoTable2 = reader.OffsetField(exprTable, 20)
            if (infoTable2 < 0) {
                throw IllegalStateException("FlatBuffer ForInExpr has no ForInInfo")
            }
            if (let Some(pattern) <- forIn.pattern) {
                LoadFlatPatternRefs(reader, reader.OffsetField(infoTable2, 4), pattern)
            } else {
                throw IllegalStateException("FlatBuffer ForInExpr pattern is missing")
            }
        }
        LoadFlatSubNodeRefs2(reader, exprTable, expr)
    }

    private func LoadFlatSubNodeRefs2(reader: CjoFlatBuffer, exprTable: Int64, expr: Expr): Unit {
        if (let Some(letPattern) <- (expr as LetPatternDestructor)) {
            let infoTable = reader.OffsetField(exprTable, 20)
            if (infoTable < 0) {
                throw IllegalStateException("FlatBuffer LetPatternDestructor has no info")
            }
            let patterns = reader.VectorField(infoTable, 4)
            if (patterns < 0 || reader.VectorLength(patterns) != letPattern.patterns.size) {
                throw IllegalStateException("FlatBuffer LetPatternDestructor patterns do not match loaded patterns")
            }
            var idx: Int64 = 0
            let count = reader.VectorLength(patterns)
            while (idx < count) {
                LoadFlatPatternRefs(reader, reader.VectorOffsetElement(patterns, idx), letPattern.patterns[idx])
                idx++
            }
            let operands = reader.VectorField(exprTable, 12)
            if (operands < 0 || reader.VectorLength(operands) < 1) {
                throw IllegalStateException("FlatBuffer LetPatternDestructor initializer operand is missing")
            }
            let initTable = FlatExprTable(reader, reader.VectorU32(operands, 0))
            if (initTable < 0) {
                throw IllegalStateException("FlatBuffer LetPatternDestructor initializer table is missing")
            }
            if (let Some(initializer) <- letPattern.initializer) {
                initializer.SetTy(LoadFlatTypeOrInvalid(reader.U32Field(initTable, 14, 0u32)))
            } else {
                throw IllegalStateException("FlatBuffer LetPatternDestructor initializer is missing")
            }
        }
    }

    private func LoadFlatMatchCaseRef(reader: CjoFlatBuffer, index: UInt32, matchCase: MatchCase,
        selector: Expr): Unit {
        let mcTable = FlatExprTable(reader, index)
        if (mcTable < 0) {
            throw IllegalStateException("FlatBuffer MatchCase table is missing")
        }
        matchCase.SetTy(LoadFlatTypeOrInvalid(reader.U32Field(mcTable, 14, 0u32)))
        let infoTable = reader.OffsetField(mcTable, 20)
        if (infoTable < 0) {
            throw IllegalStateException("FlatBuffer MatchCase has no info")
        }
        let patterns = reader.VectorField(infoTable, 4)
        if (patterns < 0 || reader.VectorLength(patterns) != matchCase.patterns.size) {
            throw IllegalStateException("FlatBuffer MatchCase patterns do not match loaded patterns")
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(patterns)
        while (idx < count) {
            LoadFlatPatternRefs(reader, reader.VectorOffsetElement(patterns, idx), matchCase.patterns[idx])
            matchCase.patterns[idx].ctxExpr = Some(selector)
            idx++
        }
    }

    private func LoadFlatPatternRefs(reader: CjoFlatBuffer, patternTable: Int64, pattern: Pattern): Unit {
        if (patternTable < 0) {
            throw IllegalStateException("FlatBuffer Pattern table is missing")
        }
        let types = reader.VectorField(patternTable, 12)
        if (types < 0 || reader.VectorLength(types) < 1) {
            throw IllegalStateException("FlatBuffer Pattern has no type")
        }
        pattern.SetTy(LoadFlatTypeOrInvalid(reader.VectorU32(types, 0)))
        let kind = reader.U8Field(patternTable, 4, 0u8)
        if (kind == FLAT_PATTERN_KIND_TUPLE) {
            let tuplePattern = (pattern as TuplePattern).getOrThrow()
            let children = reader.VectorField(patternTable, 10)
            if (children < 0 || reader.VectorLength(children) != tuplePattern.patterns.size) {
                throw IllegalStateException("FlatBuffer TuplePattern children do not match loaded patterns")
            }
            var idx: Int64 = 0
            let count = reader.VectorLength(children)
            while (idx < count) {
                LoadFlatPatternRefs(reader, reader.VectorOffsetElement(children, idx), tuplePattern.patterns[idx])
                idx++
            }
        } else if (kind == FLAT_PATTERN_KIND_TYPE) {
            let typePattern = (pattern as TypePattern).getOrThrow()
            let children2 = reader.VectorField(patternTable, 10)
            if (children2 < 0 || reader.VectorLength(children2) < 1) {
                throw IllegalStateException("FlatBuffer TypePattern child is missing")
            }
            LoadFlatPatternRefs(reader, reader.VectorOffsetElement(children2, 0),
                typePattern.pattern.getOrThrow())
            typePattern.typeNode = Some(UpdateFlatTypeNode(typePattern.typeNode,
                TypeNodeForTy(pattern.GetTy() ?? FaithfulSemaTypeManager.GetInvalidTy())))
        } else if (kind == FLAT_PATTERN_KIND_ENUM) {
            let enumPattern = (pattern as EnumPattern).getOrThrow()
            let children3 = reader.VectorField(patternTable, 10)
            if (children3 < 0 || reader.VectorLength(children3) != enumPattern.patterns.size) {
                throw IllegalStateException("FlatBuffer EnumPattern children do not match loaded patterns")
            }
            var idx2: Int64 = 0
            let count2 = reader.VectorLength(children3)
            while (idx2 < count2) {
                LoadFlatPatternRefs(reader, reader.VectorOffsetElement(children3, idx2), enumPattern.patterns[idx2])
                idx2++
            }
        } else if (kind == FLAT_PATTERN_KIND_EXCEPT_TYPE) {
            let exceptPattern = (pattern as ExceptTypePattern).getOrThrow()
            let children4 = reader.VectorField(patternTable, 10)
            if (children4 < 0 || reader.VectorLength(children4) < 1) {
                throw IllegalStateException("FlatBuffer ExceptTypePattern child is missing")
            }
            LoadFlatPatternRefs(reader, reader.VectorOffsetElement(children4, 0),
                exceptPattern.pattern.getOrThrow())
            exceptPattern.types.clear()
            var idx3: Int64 = 1
            let count3 = reader.VectorLength(types)
            while (idx3 < count3) {
                exceptPattern.types.add(TypeNodeForTy(LoadFlatTypeOrInvalid(reader.VectorU32(types, idx3))))
                idx3++
            }
        } else if (kind == FLAT_PATTERN_KIND_COMMAND_TYPE) {
            let commandPattern = (pattern as CommandTypePattern).getOrThrow()
            let children5 = reader.VectorField(patternTable, 10)
            if (children5 < 0 || reader.VectorLength(children5) < 1) {
                throw IllegalStateException("FlatBuffer CommandTypePattern child is missing")
            }
            LoadFlatPatternRefs(reader, reader.VectorOffsetElement(children5, 0),
                commandPattern.pattern.getOrThrow())
            commandPattern.types.clear()
            var idx4: Int64 = 1
            let count4 = reader.VectorLength(types)
            while (idx4 < count4) {
                commandPattern.types.add(TypeNodeForTy(LoadFlatTypeOrInvalid(reader.VectorU32(types, idx4))))
                idx4++
            }
        }
    }

    private func PostLoadFlatReference(expr: Expr): Unit {
        if (let Some(call) <- (expr as CallExpr)) {
            let base = call.baseFunc.getOrThrow()
            if (let Some(target) <- base.GetTarget()) {
                call.resolvedFunction = target as FuncDecl
            }
        } else if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
            for (arg in arrayExpr.args) {
                let argExpr = arg.expr.getOrThrow()
                arg.SetTy(argExpr.GetTy() ?? FaithfulSemaTypeManager.GetInvalidTy())
            }
        } else if (let Some(pointerExpr) <- (expr as PointerExpr)) {
            if (let Some(arg) <- pointerExpr.arg) {
                let argExpr = arg.expr.getOrThrow()
                arg.SetTy(argExpr.GetTy() ?? FaithfulSemaTypeManager.GetInvalidTy())
            }
        }
    }

    private func LoadSerializedDeclRecords(): Unit {
        flatDecls.clear()
        flatNominalKinds.clear()
        flatTypeCache.clear()
        flatGenericParamDecls.clear()
        allLoadedDecls.clear()
        allLoadedExprs.clear()
        allDummyExprs.clear()
        importNonGenericSrcFuncDecls.clear()
        let reader = flat.getOrThrow()
        let root = reader.RootTable()
        if (root < 0 || reader.StringField(root, 8) != packageName) {
            return
        }
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
        importSpec.begin = LoadFlatPosition(reader, reader.TableField(importTable, 4))
        importSpec.end = LoadFlatPosition(reader, reader.TableField(importTable, 6))
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
                    if (IgnoreDecl(reader, record)) {
                        idx++
                        continue
                    }
                    if (let Some(decl) <- EnsureFlatDecl(record)) {
                        if (decl.TestAttr(Attribute.ALREADY_LOADED)) {
                            decl.doNotExport = true
                        }
                        AddFlatTopLevelDecl(decl)
                    }
                }
            }
            idx++
        }
        FinalizeSourceImportedDecls()
    }

    private func IgnoreDecl(reader: CjoFlatBuffer, record: CjoFlatDecl): Bool {
        // 1. Ignore main entry function during loading (it is only needed for incremental compilation).
        // 2. Ignore instantiated decl and non-external, non-implicit used decl when 'importSrcCode' is disabled.
        // 3. When current is macro package:
        //    a) ignore instantiated decl. NOTE: macro package's instantiated decls will not be used in CodeGen.
        //    b) ignore non-macro decl when interpretation is off.
        //    c) ignore decl which is not macro and not type when interpretation is on.
        return TestAttr(reader, record, Attribute.MAIN_ENTRY) ||
            (!importSrcCode &&
                (TestAttr(reader, record, Attribute.GENERIC_INSTANTIATED) ||
                    (TestAttr(reader, record, Attribute.PRIVATE) &&
                        !TestAttr(reader, record, Attribute.IMPLICIT_USED)))) ||
            (pkg.isMacroPackage &&
                (TestAttr(reader, record, Attribute.GENERIC_INSTANTIATED) ||
                    !TestAttr(reader, record, Attribute.MACRO_FUNC)))
    }

    private func AddFlatTopLevelDecl(decl: Decl): Unit {
        let targetFile = decl.curFile ??
            throw IllegalStateException("imported decl '${decl.identifier.Val()}' has no current file")
        AddCurFile(decl, file: Some(targetFile))
        if (decl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            pkg.genericInstantiatedDecls.add(decl)
            return
        }
        if (decl.IsExportedDecl() || decl.TestAttr(Attribute.FROM_COMMON_PART)) {
            targetFile.decls.add(decl)
            return
        }
        targetFile.exportedInternalDecls.add(decl)
    }

    private func FinalizeSourceImportedDecls(): Unit {
        pkg.srcImportedNonGenericDecls.clear()
        for (decl in importNonGenericSrcFuncDecls) {
            if (!IsInDeclWithAttribute(decl, Attribute.GENERIC)) {
                pkg.srcImportedNonGenericDecls.add(decl)
            }
        }
        if (!deserializingCommon) {
            pkg.hasSourceImportedDecl = !allLoadedExprs.isEmpty() || pkg.TestAttr(Attribute.TOOL_ADD)
        }
        AddCurFile(pkg)
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
        decl.begin = LoadFlatPosition(reader, reader.TableField(record.table, 14))
        decl.end = LoadFlatPosition(reader, reader.TableField(record.table, 16))
        let identifierPos = LoadFlatPosition(reader, reader.TableField(record.table, 20))
        let identifierEnd = if (identifierPos == INVALID_POSITION || identifierPos == DEFAULT_POSITION) {
            identifierPos
        } else {
            identifierPos + record.identifier.size
        }
        decl.identifier = SrcIdentifier(record.identifier, identifierPos, identifierEnd, false)
        decl.exportId = record.exportId
        decl.mangledName = record.mangledName
        decl.rawMangleName = record.mangledBeforeSema
        decl.fullPackageName = if (record.fullPackageName.isEmpty()) { packageName } else { record.fullPackageName }
        decl.moduleName = RootPackageName(decl.fullPackageName)
        decl.toBeCompiled = false
        ApplyFlatAttributes(reader, record, decl)
        ApplyFlatAnnotations(reader, record, decl)
        MarkFlatImportedDecl(decl)
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

    private func TestAttr(reader: CjoFlatBuffer, record: CjoFlatDecl, attr: Attribute): Bool {
        let attrs = reader.VectorField(record.table, 22)
        if (attrs < 0) {
            return false
        }
        let attrIdx = AttributeIndex(attr)
        let wordIdx = attrIdx / 64
        if (wordIdx >= reader.VectorLength(attrs)) {
            return false
        }
        let bit = attrIdx % 64
        return (reader.VectorU64(attrs, wordIdx) & (1u64 << UInt64(bit))) != 0u64
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

    private func MarkFlatImportedDecl(decl: Decl): Unit {
        if (let Some(file) <- idToFileMap.get(decl.begin.fileID)) {
            decl.curFile = Some(file)
        } else if (decl.begin.fileID == 0u64 && !pkg.files.isEmpty()) {
            decl.curFile = Some(pkg.files[0])
        }
        decl.EnableAttr(Attribute.IMPORTED)
    }

    private func FileByFlatIndex(index: UInt32): File {
        return filesByIndex.get(index) ??
            throw IllegalStateException("FlatBuffer file index ${index} is not registered for package '${packageName}'")
    }

    private func LoadFlatPosition(reader: CjoFlatBuffer, posTable: Int64): Position {
        if (posTable < 0) {
            throw IllegalStateException("FlatBuffer Position is null")
        }
        let fileIndex = reader.U32At(posTable)
        let pkgIndex = reader.U32At(posTable + 4)
        let line = reader.I32At(posTable + 8)
        let column = reader.I32At(posTable + 12)
        let fileID = if (pkgIndex == 0u32) {
            if (fileIndex == 0u32) { 0u64 } else { FileByFlatIndex(fileIndex).begin.fileID }
        } else {
            if (let Some(importedFile) <- ImportedFileByFlatPosition(reader, pkgIndex, fileIndex)) {
                let importedFileID = importedFile.begin.fileID
                if (!idToFileMap.contains(importedFileID)) {
                    idToFileMap[importedFileID] = importedFile
                }
                importedFileID
            } else {
                0u64
            }
        }
        return Position(fileID, line, column)
    }

    private func ImportedFileByFlatPosition(reader: CjoFlatBuffer, pkgIndex: UInt32, fileIndex: UInt32): Option<File> {
        let importOffset = Int64(pkgIndex) - 1
        if (flatImports < 0 || importOffset < 0 || importOffset >= reader.VectorLength(flatImports)) {
            throw IllegalStateException("FlatBuffer package index ${pkgIndex} is not registered for package '${packageName}'")
        }
        let fullPackageName = reader.StringAt(reader.VectorOffsetElement(flatImports, importOffset))
        let importedPackage = FindImportedPackage(fullPackageName)
        if (let None <- importedPackage) {
            return None
        }
        let imported = importedPackage.getOrThrow()
        if (Int64(fileIndex) >= imported.files.size) {
            throw IllegalStateException("FlatBuffer file index ${fileIndex} is out of range for package '${fullPackageName}'")
        }
        return Some(imported.files[Int64(fileIndex)])
    }

    private func FindImportedPackage(fullPackageName: String): Option<Package> {
        for (importedPackage in importedPackages) {
            if (importedPackage.fullPackageName == fullPackageName) {
                return Some(importedPackage)
            }
        }
        return None
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
        if (record.kind != 0u16 && !allLoadedDecls.contains(record.index)) {
            allLoadedDecls.add(record.index, decl)
        }
        ApplyFlatDeclBasicInfo(reader, record, decl)
        if (let Some(gpd) <- (decl as GenericParamDecl)) {
            gpd.SetTy(typeManager.GetGenericsTy(gpd))
            flatGenericParamDecls[record.index] = gpd
            if (!gpd.exportId.isEmpty()) {
                AddFlatDeclToImportedPackage(gpd)
            }
            return Some(gpd)
        }
        if (ShouldAddFlatDeclToImportedPackage(record.kind)) {
            AddFlatDeclToImportedPackage(decl)
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            LoadFlatFuncDeclAdvancedInfo(reader, record, funcDecl)
            return Some(funcDecl)
        }
        SetFlatGeneric(reader, record, decl)
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
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            LoadFlatEnumInfo(reader, record, enumDecl)
        }
        if (let Some(inheritable) <- (decl as InheritableDecl)) {
            LoadFlatBodyMembers(reader, record, inheritable)
        }
        return Some(decl)
    }

    private func LoadFlatFuncDeclAdvancedInfo(reader: CjoFlatBuffer, record: CjoFlatDecl, funcDecl: FuncDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            throw IllegalStateException("FlatBuffer FuncDecl '${record.identifier}' has no FuncInfo")
        }
        funcDecl.overflowStrategy = FlatOverflowStrategy(reader.U8Field(infoTable, 6, 0u8))
        funcDecl.op = FlatOperatorKind(reader.U8Field(infoTable, 8, 0u8))
        funcDecl.isConst = reader.U8Field(infoTable, 12, 0u8) != 0u8
        funcDecl.isInline = (reader.U8Field(infoTable, 14, 0u8) != 0u8) && canInline
        funcDecl.isFastNative = reader.U8Field(infoTable, 16, 0u8) != 0u8
        // Mirror ASTLoader.cpp:810-811: derive isFrozen from the loaded @Frozen annotation
        // (annotations are loaded in ApplyFlatDeclBasicInfo, which runs before this).
        funcDecl.isFrozen = funcDecl.HasAnno(AstAnnotationKind.FROZEN)
        let bodyTable = reader.OffsetField(infoTable, 4)
        if (bodyTable < 0) {
            throw IllegalStateException("FlatBuffer FuncDecl '${record.identifier}' has no FuncBody")
        }
        let body = LoadFlatFuncBody(reader, bodyTable, Some(funcDecl), funcDecl.isInline, true)
        body.funcDecl = Some(funcDecl)
        funcDecl.funcBody = Some(body)
        SetFlatGeneric(reader, record, funcDecl)
        if (importSrcCode && body.body.isSome()) {
            if (body.generic.isNone() && IsGlobalOrMember(funcDecl)) {
                importNonGenericSrcFuncDecls.add(funcDecl)
            }
            funcDecl.EnableAttr(Attribute.SRC_IMPORTED)
        }
        SetOuterFunctionDecl(funcDecl)
        // Update param functions' references: set ownerFunc on each param's desugar (default-param)
        // function, for top-level AND member funcs. Mirrors C++ ASTLoader.cpp:829-833 — without this
        // a top-level imported generic func's default-param desugar (e.g. y.1 <T$0,P$1>) has no
        // ownerFunc, so MangleFunctionDecl skips MangleDeclName and never declares <T$0> on the
        // generics stack, throwing "Using undeclared generic type" at mangle time.
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                if (let Some(desugar) <- param.desugarDecl) {
                    desugar.ownerFunc = Some(funcDecl)
                    desugar.isFrozen = funcDecl.isFrozen
                    if (importSrcCode && !funcDecl.TestAttr(Attribute.GENERIC) && IsGlobalOrMember(funcDecl)) {
                        if (let Some(desugarBody) <- desugar.funcBody) {
                            if (desugarBody.body.isSome()) {
                                importNonGenericSrcFuncDecls.add(desugar)
                            }
                        }
                    }
                }
            }
        }
    }

    // Loads FuncBody.body (fbs FuncBody field 2 / slot 8 = body expr index), gated by the current
    // selfhost shouldImportBody path. On import, the loaded Block is the un-wrapped funcBody.body
    // (LoadExpr<Block>, no dummy-RefExpr wrap), and every nested ReturnExpr's refFuncBody is set to
    // this funcBody (ExprLoader.cpp:500-509).
    private func LoadFlatFuncBody(reader: CjoFlatBuffer, bodyTable: Int64, funcDecl: Option<FuncDecl>,
        isInline: Bool, isConst: Bool): FuncBody {
        let body = FuncBody()
        LoadFlatFuncParamLists(reader, bodyTable, body)
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
        if (!importSrcCode || !shouldImportBody) {
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
        if ((importSrcCode && !varDecl.TestAttr(Attribute.COMMON)) || deserializingCommon) {
            if (let Some(initializer) <- LoadFlatExpr(reader, initIndex)) {
                varDecl.initializer = Some(initializer)
            }
        }
        if (varDecl.initializer.isSome() && IsGlobalOrMember(varDecl)) {
            importNonGenericSrcFuncDecls.add(varDecl)
            varDecl.EnableAttr(Attribute.SRC_IMPORTED)
        }
        if (IsGlobalOrMember(varDecl)) {
            AddFlatDeclToImportedPackage(varDecl)
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
                allDummyExprs.add(dummy)
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
            return Some(LoadFlatWildcardExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_PRIMITIVE_TYPE) {
            return Some(LoadFlatPrimitiveTypeExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_LIT_CONST) {
            return Some(LoadFlatLitConstExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_MEMBER_ACCESS) {
            return Some(LoadFlatMemberAccess(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_REF_EXPR) {
            return Some(LoadFlatRefExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_UNARY) {
            return Some(LoadFlatUnaryExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_INC_OR_DEC) {
            return Some(LoadFlatIncOrDecExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_BINARY) {
            return Some(LoadFlatBinaryExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_SUBSCRIPT) {
            return Some(LoadFlatSubscriptExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_ASSIGN) {
            return Some(LoadFlatAssignExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_ARRAY_EXPR) {
            return Some(LoadFlatArrayExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_POINTER_EXPR) {
            return Some(LoadFlatPointerExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_JUMP) {
            return Some(LoadFlatJumpExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_TYPE_CONV) {
            return Some(LoadFlatTypeConvExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_THROW) {
            return Some(LoadFlatThrowExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_PERFORM) {
            return Some(LoadFlatPerformExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_RESUME) {
            return Some(LoadFlatResumeExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_SPAWN) {
            return Some(LoadFlatSpawnExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_TRY) {
            return Some(LoadFlatTryExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_IF) {
            return Some(LoadFlatIfExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_WHILE) {
            return Some(LoadFlatWhileExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_DO_WHILE) {
            return Some(LoadFlatDoWhileExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_ARRAY_LIT) {
            return Some(LoadFlatArrayLit(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_TUPLE_LIT) {
            return Some(LoadFlatTupleLit(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_MATCH) {
            return Some(LoadFlatMatchExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_LET_PATTERN_DESTRUCTOR) {
            return Some(LoadFlatLetPatternDestructor(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_FOR_IN) {
            return Some(LoadFlatForInExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_LAMBDA) {
            return Some(LoadFlatLambdaExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_CALL) {
            // Mirrors ExprLoader.cpp:92-115 LoadCallExpr and ExprLoader.cpp:516-531 LoadFuncArg.
            let ce = CallExpr()
            if (!allLoadedExprs.contains(exprIndex)) {
                allLoadedExprs.add(exprIndex, ce)
            }
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
            return Some(LoadFlatReturnExpr(reader, exprTable, exprIndex))
        }
        if (kind == FLAT_EXPR_KIND_BLOCK) {
            return Some(LoadFlatBlock(reader, exprTable, exprIndex))
        }
        return Some(LoadFlatInvalidExpr(reader, exprTable, exprIndex))
    }

    // Mirrors ExprLoader.cpp:25-31 LoadInvalidExpr, used when Expr.kind has no registered loader.
    private func LoadFlatInvalidExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): InvalidExpr {
        diag.DiagnoseRefactor(DiagKindRefactor.package_unsupported_load, DEFAULT_POSITION,
            arguments: ["expression"])
        let invalidExpr = InvalidExpr(INVALID_POSITION)
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, invalidExpr)
        }
        LoadFlatExprBasicInfo(reader, exprTable, invalidExpr)
        return invalidExpr
    }

    // Mirrors ExprLoader.cpp:348-358 LoadLambdaExpr: LambdaInfo owns a nested FuncBody and
    // supportMock restores Attribute.MOCK_SUPPORTED. LoadFuncBody is called with C++ defaults
    // (isInline=false, isConst=true), so the lambda body is imported when source is present.
    private func LoadFlatLambdaExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): LambdaExpr {
        let le = LambdaExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, le)
        }
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
    private func LoadFlatWildcardExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): WildcardExpr {
        let we = WildcardExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, we)
        }
        LoadFlatExprBasicInfo(reader, exprTable, we)
        we.EnableAttr(Attribute.IMPORTED)
        return we
    }

    // Mirrors ExprLoader.cpp:39-48 LoadPrimitiveTypeExpr. The serialized Expr.type field points to
    // the PackageFormat::Type; the type kind is recovered through the same primitive type map used by
    // LoadFlatType.
    private func LoadFlatPrimitiveTypeExpr(reader: CjoFlatBuffer, exprTable: Int64,
        exprIndex: UInt32): PrimitiveTypeExpr {
        let pte = PrimitiveTypeExpr(FlatPrimitiveExprKind(reader, reader.U32Field(exprTable, 14, 0u32)))
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, pte)
        }
        LoadFlatExprBasicInfo(reader, exprTable, pte)
        pte.EnableAttr(Attribute.IMPORTED)
        return pte
    }

    private func FlatPrimitiveExprKind(reader: CjoFlatBuffer, typeIndex: UInt32): TypeKind {
        if (typeIndex == 0u32 || flatAllTypes < 0) {
            return TypeKind.TYPE_INVALID
        }
        let idx = Int64(typeIndex) - 1
        if (idx < 0 || idx >= reader.VectorLength(flatAllTypes)) {
            return TypeKind.TYPE_INVALID
        }
        let typeTable = reader.VectorOffsetElement(flatAllTypes, idx)
        if (typeTable < 0) {
            return TypeKind.TYPE_INVALID
        }
        return FlatPrimitiveTypeKind(reader.U16Field(typeTable, 4, 1u16)) ?? TypeKind.TYPE_INVALID
    }

    // Mirrors ExprLoader.cpp:58-66 LoadJumpExpr. JumpInfo carries only isBreak.
    private func LoadFlatJumpExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): JumpExpr {
        let je = JumpExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, je)
        }
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
    private func LoadFlatIncOrDecExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): IncOrDecExpr {
        let ide = IncOrDecExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, ide)
        }
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
    private func LoadFlatTypeConvExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): TypeConvExpr {
        let tce = TypeConvExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, tce)
        }
        LoadFlatExprBasicInfo(reader, exprTable, tce)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            tce.expr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        tce.EnableAttr(Attribute.IMPORTED)
        return tce
    }

    // Mirrors ExprLoader.cpp:228-233 LoadThrowExpr. Operand 0 is the thrown expr.
    private func LoadFlatThrowExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): ThrowExpr {
        let te = ThrowExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, te)
        }
        LoadFlatExprBasicInfo(reader, exprTable, te)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) >= 1) {
            te.expr = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        te.EnableAttr(Attribute.IMPORTED)
        return te
    }

    // Mirrors ExprLoader.cpp:236-241 LoadPerformExpr. Operand 0 is the performed expr.
    private func LoadFlatPerformExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): PerformExpr {
        let pe = PerformExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, pe)
        }
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
    private func LoadFlatResumeExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): ResumeExpr {
        let re = ResumeExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, re)
        }
        LoadFlatExprBasicInfo(reader, exprTable, re)
        re.EnableAttr(Attribute.IMPORTED)
        return re
    }

    // Mirrors ExprLoader.cpp:250-262 LoadSpawnExpr. Operand 0 is the optional thread-context arg;
    // SpawnInfo.future is a local VarDecl FullId.
    private func LoadFlatSpawnExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): SpawnExpr {
        let se = SpawnExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, se)
        }
        LoadFlatExprBasicInfo(reader, exprTable, se)
        let operands = reader.VectorField(exprTable, 12)
        if (operands >= 0 && reader.VectorLength(operands) > 0) {
            se.arg = LoadFlatExpr(reader, reader.VectorU32(operands, 0))
        }
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            if (let Some(decl) <- LoadFlatLocalDeclFromFullId(reader, reader.OffsetField(infoTable, 4))) {
                se.futureObj = decl as VarDecl
            }
        }
        se.EnableAttr(Attribute.IMPORTED)
        return se
    }

    // Mirrors ExprLoader.cpp:198-208 LoadArrayExpr and ReferenceLoader.cpp:622-630 for optional
    // ArrayInfo.initFunc on non-VArray array constructor expressions.
    private func LoadFlatArrayExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): ArrayExpr {
        let ae = ArrayExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, ae)
        }
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
        }
        ae.EnableAttr(Attribute.IMPORTED)
        return ae
    }

    // Mirrors ExprLoader.cpp:211-217 LoadPointerExpr. Optional operand 0 is a FuncArg wrapper.
    private func LoadFlatPointerExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): PointerExpr {
        let pe = PointerExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, pe)
        }
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
    private func LoadFlatTryExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): TryExpr {
        let te = TryExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, te)
        }
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
                    if (let Some(resourceDecl) <- LoadFlatLocalDeclFromFullId(reader,
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
    private func LoadFlatIfExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): IfExpr {
        let ie = IfExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, ie)
        }
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
                allDummyExprs.remove(elseExpr)
                ie.elseBody = Some(desugar)
            }
        }
        ie.EnableAttr(Attribute.IMPORTED)
        return ie
    }

    // Mirrors ExprLoader.cpp:330-337 LoadWhileExpr. Operands are condExpr then body; the body is
    // loaded raw as Block, matching C++ LoadExpr<Block>.
    private func LoadFlatWhileExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): WhileExpr {
        let we = WhileExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, we)
        }
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
    private func LoadFlatDoWhileExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): DoWhileExpr {
        let dwe = DoWhileExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, dwe)
        }
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
    private func LoadFlatMatchExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): MatchExpr {
        let me = MatchExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, me)
        }
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
    private func LoadFlatLetPatternDestructor(reader: CjoFlatBuffer, exprTable: Int64,
        exprIndex: UInt32): LetPatternDestructor {
        let lpd = LetPatternDestructor()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, lpd)
        }
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
    private func LoadFlatForInExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): ForInExpr {
        let fie = ForInExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, fie)
        }
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
    private func LoadFlatUnaryExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): UnaryExpr {
        let ue = UnaryExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, ue)
        }
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
    private func LoadFlatBinaryExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): BinaryExpr {
        let be = BinaryExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, be)
        }
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
    private func LoadFlatSubscriptExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): SubscriptExpr {
        let se = SubscriptExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, se)
        }
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
    private func LoadFlatAssignExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): AssignExpr {
        let ae = AssignExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, ae)
        }
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
    private func LoadFlatArrayLit(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): ArrayLit {
        let al = ArrayLit()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, al)
        }
        LoadFlatExprBasicInfo(reader, exprTable, al)
        LoadFlatExprOperands(reader, exprTable, al.children)
        al.EnableAttr(Attribute.IMPORTED)
        return al
    }

    // Mirrors ExprLoader.cpp:275-282 LoadTupleLit. Operands are tuple element expressions.
    private func LoadFlatTupleLit(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): TupleLit {
        let tl = TupleLit()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, tl)
        }
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
    private func LoadFlatMemberAccess(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): MemberAccess {
        let ma = MemberAccess()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, ma)
        }
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
        }
        ma.EnableAttr(Attribute.IMPORTED)
        return ma
    }

    // Mirrors ExprLoader.cpp:81-90 LoadRefExpr, plus ReferenceLoader.cpp:586-610 deferred
    // reference restoration for target, instTys, and matchedParentTy.
    private func LoadFlatRefExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): RefExpr {
        let re = RefExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, re)
        }
        LoadFlatExprBasicInfo(reader, exprTable, re)
        let infoTable = reader.OffsetField(exprTable, 20)
        if (infoTable >= 0) {
            let name = reader.StringField(infoTable, 4)
            re.ref.identifier = SrcIdentifier(name)
            re.isThis = name == "this"
            re.isSuper = name == "super"
        }
        re.EnableAttr(Attribute.IMPORTED)
        return re
    }

    private func LoadFlatExprBasicInfo(reader: CjoFlatBuffer, exprTable: Int64, expr: Expr): Unit {
        LoadFlatNodeBasicInfo(reader, exprTable, expr)
    }

    private func LoadFlatNodeBasicInfo(reader: CjoFlatBuffer, exprTable: Int64, node: Node): Unit {
        node.begin = LoadFlatPosition(reader, reader.TableField(exprTable, 6))
        node.end = LoadFlatPosition(reader, reader.TableField(exprTable, 8))
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
        if (instTys < 0) {
            throw IllegalStateException("FlatBuffer ReferenceInfo has no instTys")
        }
        var idx: Int64 = 0
        let count = reader.VectorLength(instTys)
        while (idx < count) {
            expr.instTys.add(LoadFlatTypeOrInvalid(reader.VectorU32(instTys, idx)))
            idx++
        }
        expr.matchedParentTy = LoadFlatType(reader.U32Field(infoTable, 10, 0u32))
    }

    private func LoadFlatReferenceTarget(reader: CjoFlatBuffer, infoTable: Int64): Option<Decl> {
        return ResolveFlatFullId(reader, reader.OffsetField(infoTable, 6))
    }

    // Mirrors ExprLoader.cpp:50-56 LoadReturnExpr. Operand 0 = return value sub-expr.
    private func LoadFlatReturnExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): ReturnExpr {
        let re = ReturnExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, re)
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
    private func LoadFlatBlock(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): Block {
        let block = Block()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, block)
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
    private func LoadFlatLitConstExpr(reader: CjoFlatBuffer, exprTable: Int64, exprIndex: UInt32): LitConstExpr {
        // Expr field 7 (slot 18) = info_type, field 8 (slot 20) = info (LitConstInfo table).
        let infoTable = reader.OffsetField(exprTable, 20)
        let lce = LitConstExpr()
        if (!allLoadedExprs.contains(exprIndex)) {
            allLoadedExprs.add(exprIndex, lce)
        }
        LoadFlatExprBasicInfo(reader, exprTable, lce)
        if (infoTable >= 0) {
            // LitConstInfo field 0 (slot 4) strValue, 1 (slot 6) constKind, 2 (slot 8) strKind.
            lce.stringValue = reader.StringField(infoTable, 4)
            lce.kind = FlatToLitConstKind(reader.U8Field(infoTable, 6, 0u8))
            lce.stringKind = FlatToStringKind(reader.U8Field(infoTable, 8, 0u8))
        }
        lce.rawString = lce.stringValue
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
        pattern.begin = LoadFlatPosition(reader, reader.TableField(patternTable, 6))
        pattern.end = LoadFlatPosition(reader, reader.TableField(patternTable, 8))
        return Some(pattern)
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
        let children = reader.VectorField(patternTable, 10)
        if (children >= 0 && reader.VectorLength(children) >= 1) {
            pattern.pattern = LoadFlatPattern(reader, reader.VectorOffsetElement(children, 0))
        }
        return pattern
    }

    private func LoadFlatCommandTypePattern(reader: CjoFlatBuffer, patternTable: Int64): CommandTypePattern {
        let pattern = CommandTypePattern()
        let children = reader.VectorField(patternTable, 10)
        if (children >= 0 && reader.VectorLength(children) >= 1) {
            pattern.pattern = LoadFlatPattern(reader, reader.VectorOffsetElement(children, 0))
        }
        return pattern
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
                            desugar.outerDecl = Some(parent)
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
            return Some(FaithfulSemaTypeManager.GetInvalidTy())
        }
        let loaded = CreateFlatType(reader, typeTable)
        if (let Some(ty) <- loaded) {
            flatTypeCache[index] = ty
        }
        return loaded
    }

    private func LoadFlatTypeOrInvalid(index: UInt32): Ty {
        return LoadFlatType(index) ?? FaithfulSemaTypeManager.GetInvalidTy()
    }

    private func CreateFlatType(reader: CjoFlatBuffer, typeTable: Int64): Option<Ty> {
        let kind = reader.U16Field(typeTable, 4, 1u16)
        let typeArgs = LoadFlatTypeArgs(reader, typeTable)
        if (let Some(primitiveKind) <- FlatPrimitiveTypeKind(kind)) {
            return Some(FaithfulSemaTypeManager.GetPrimitiveTy(primitiveKind))
        }
        if (kind == 18u16) {
            return Some(typeManager.GetTupleTy(typeArgs.toArray()))
        }
        if (kind == 20u16) {
            let infoTable = reader.OffsetField(typeTable, 10)
            let retTy = if (infoTable >= 0) {
                LoadFlatType(reader.U32Field(infoTable, 4, 0u32)) ??
                    FaithfulSemaTypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            } else {
                FaithfulSemaTypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            }
            let cfg = FuncTyConfig()
            if (infoTable >= 0) {
                cfg.isC = reader.U8Field(infoTable, 6, 0u8) != 0u8
                cfg.hasVariableLenArg = reader.U8Field(infoTable, 8, 0u8) != 0u8
            }
            return Some(typeManager.GetFunctionTy(typeArgs.toArray(), retTy, cfg: cfg))
        }
        if (kind == 22u16) {
            let elemTy = if (typeArgs.isEmpty()) { typeManager.GetAnyTy() } else { typeArgs[0] }
            let infoTable2 = reader.OffsetField(typeTable, 10)
            let dims = if (infoTable2 >= 0) { UInt64(reader.I64Field(infoTable2, 4, 1)) } else { 1u64 }
            return Some(typeManager.GetArrayTy(elemTy, dims))
        }
        if (kind == 23u16) {
            let elemTy2 = if (typeArgs.isEmpty()) { typeManager.GetAnyTy() } else { typeArgs[0] }
            let infoTable3 = reader.OffsetField(typeTable, 10)
            let size = if (infoTable3 >= 0) { reader.I64Field(infoTable3, 4, 0) } else { 0 }
            return Some(typeManager.GetVArrayTy(elemTy2, size))
        }
        if (kind == 24u16) {
            let elemTy3 = if (typeArgs.isEmpty()) { typeManager.GetAnyTy() } else { typeArgs[0] }
            return Some(typeManager.GetPointerTy(elemTy3))
        }
        if (kind == 25u16) {
            return Some(FaithfulSemaTypeManager.GetCStringTy())
        }
        if (kind == 29u16) {
            return LoadFlatGenericTy(reader, typeTable)
        }
        if (kind == 19u16 || kind == 21u16 || kind == 26u16 || kind == 27u16 || kind == 28u16) {
            return LoadFlatCompositeTy(reader, typeTable, kind, typeArgs)
        }
        return Some(FaithfulSemaTypeManager.GetInvalidTy())
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
            return Some(FaithfulSemaTypeManager.GetInvalidTy())
        }
        let decl = declOpt.getOrThrow()
        if (kind == 19u16) {
            if (let Some(enumDecl) <- (decl as EnumDecl)) {
                return Some(typeManager.GetEnumTy(enumDecl, typeArgs: typeArgs.toArray()))
            }
        } else if (kind == 21u16) {
            if (let Some(structDecl) <- (decl as StructDecl)) {
                return Some(typeManager.GetStructTy(structDecl, typeArgs.toArray()))
            }
        } else if (kind == 26u16) {
            if (let Some(classDecl) <- (decl as ClassDecl)) {
                let infoTable = reader.OffsetField(typeTable, 10)
                let isThisTy = infoTable >= 0 && reader.U8Field(infoTable, 6, 0u8) != 0u8
                if (isThisTy) {
                    return Some(typeManager.GetClassThisTy(classDecl, typeArgs.toArray()))
                }
                return Some(typeManager.GetClassTy(classDecl, typeArgs.toArray()))
            }
        } else if (kind == 27u16) {
            if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
                return Some(typeManager.GetInterfaceTy(interfaceDecl, typeArgs.toArray()))
            }
        } else if (kind == 28u16) {
            if (let Some(aliasDecl) <- (decl as TypeAliasDecl)) {
                return Some(typeManager.GetTypeAliasTy(aliasDecl, typeArgs.toArray()))
            }
        }
        return Some(FaithfulSemaTypeManager.GetInvalidTy())
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
                let ty = paramDecl.GetTy() ?? typeManager.GetGenericsTy(paramDecl)
                if (let None <- paramDecl.GetTy()) {
                    paramDecl.SetTy(ty)
                }
                return Some(ty)
            }
        }
        return Some(FaithfulSemaTypeManager.GetInvalidTy())
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
            return allLoadedDecls.get(id.index)
        }
        if (id.pkgId == -3) {
            return FindImportedPackageDecl(id.decl)
        }
        return ResolveImportedFullId(id)
    }

    private func LoadFlatLocalDeclFromFullId(reader: CjoFlatBuffer, fullIdTable: Int64): Option<Decl> {
        if (fullIdTable < 0) {
            return None
        }
        let id = ReadFlatFullId(reader, fullIdTable)
        if (id.pkgId != -2 || id.index == 0u32) {
            return None
        }
        if (let Some(loaded) <- allLoadedDecls.get(id.index)) {
            return Some(loaded)
        }
        if (let Some(record) <- flatDecls.get(id.index)) {
            return EnsureFlatDecl(record)
        }
        return None
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
            if (let Some(exportIdDeclMap) <- exportIdDeclMaps.get(packageName)) {
                if (let Some(found) <- exportIdDeclMap.get(id.decl)) {
                    return Some(found)
                }
            }
        }
        if (!HasPackageDecl(packageName) && !isLoadCache) {
            diag.DiagnoseRefactor(DiagKindRefactor.package_invalid_cjo_dependency, DEFAULT_POSITION,
                arguments: [this.packageName, packageName])
        }
        return None
    }

    private func FindImportedPackageDecl(fullPackageName: String): Option<Decl> {
        if (let Some(existing) <- packageDecls.get(fullPackageName)) {
            return Some(existing)
        }
        var packageValue: Option<Package> = None
        if (fullPackageName == packageName) {
            packageValue = Some(pkg)
        }
        if (let None <- packageValue) {
            for (importedPackage in importedPackages) {
                if (importedPackage.fullPackageName == fullPackageName) {
                    packageValue = Some(importedPackage)
                    break
                }
            }
        }
        let targetPackage = packageValue ?? return None
        let packageDecl = PackageDecl(targetPackage)
        packageDecls[fullPackageName] = packageDecl
        return Some(packageDecl)
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

    private func ShouldAddFlatDeclToImportedPackage(kind: UInt16): Bool {
        return kind == 1u16 || kind == 2u16 || kind == 3u16 || kind == 8u16 || kind == 9u16 ||
            kind == 10u16 || kind == 11u16 || kind == 13u16
    }

    private func AddFlatDeclToImportedPackage(decl: Decl): Unit {
        if (decl.astKind == ASTKind.EXTEND_DECL) {
            return
        }
        let exportIdDeclMap = GetCurrentExportIdDeclMap()
        if (decl.exportId.isEmpty()) {
            let identifier = decl.identifier.Val()
            if (!exportIdDeclMap.contains(identifier)) {
                exportIdDeclMap[identifier] = decl
            }
            return
        }
        if (let None <- exportIdDeclMap.get(decl.exportId)) {
            exportIdDeclMap[decl.exportId] = decl
            return
        }
        let existingDecl = exportIdDeclMap.get(decl.exportId).getOrThrow()
        var reportError = existingDecl != decl && importSrcCode
        if (decl.TestAttr(Attribute.FROM_COMMON_PART)) {
            reportError = false
            if (FlatDeclaredInDifferentFiles(decl, existingDecl)) {
                return
            }
            decl.EnableAttr(Attribute.ALREADY_LOADED)
        }
        if (reportError) {
            throw IllegalStateException("Found same exportID when import a package.")
        }
    }

    private func GetCurrentExportIdDeclMap(): HashMap<String, Decl> {
        if (let Some(existingMap) <- exportIdDeclMaps.get(packageName)) {
            return existingMap
        }
        let createdMap = HashMap<String, Decl>()
        exportIdDeclMaps[packageName] = createdMap
        return createdMap
    }

    private func FlatDeclaredInDifferentFiles(left: Decl, right: Decl): Bool {
        if (let Some(leftFile) <- left.curFile) {
            if (let Some(rightFile) <- right.curFile) {
                return leftFile.objectId != rightFile.objectId
            }
        }
        return false
    }

    private func HasPackageDecl(fullPackageName: String): Bool {
        if (packageDecls.contains(fullPackageName) || fullPackageName == packageName) {
            return true
        }
        return FindImportedPackage(fullPackageName).isSome()
    }

    private func SetNominalTy(decl: Decl): Unit {
        let typeArgs = ArrayList<Ty>()
        if (let Some(generic) <- decl.generic) {
            for (param in generic.typeParameters) {
                if (let Some(paramTy) <- param.GetTy()) {
                    typeArgs.add(paramTy)
                }
            }
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            structDecl.SetTy(typeManager.GetStructTy(structDecl, typeArgs.toArray()))
        } else if (let Some(classDecl) <- (decl as ClassDecl)) {
            classDecl.SetTy(typeManager.GetClassTy(classDecl, typeArgs.toArray()))
        } else if (let Some(enumDecl) <- (decl as EnumDecl)) {
            enumDecl.SetTy(typeManager.GetEnumTy(enumDecl, typeArgs: typeArgs.toArray()))
        } else if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            interfaceDecl.SetTy(typeManager.GetInterfaceTy(interfaceDecl, typeArgs.toArray()))
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
        var hasTypeAlias = false
        if (TypeKindIndex(ty.kind) <= TypeKindIndex(TypeKind.TYPE_BOOLEAN) && ty.kind != TypeKind.TYPE_NOTHING) {
            let primitive = PrimitiveType()
            primitive.str = ty.String()
            primitive.kind = ty.kind
            primitive.SetTy(ty)
            MarkFlatWrappedType(primitive)
            return primitive
        } else if (let Some(funcTy) <- (ty as FuncTy)) {
            let funcType = FuncType()
            for (paramTy in funcTy.paramTys) {
                let paramType = TypeNodeForTy(paramTy)
                funcType.paramTypes.add(paramType)
                hasTypeAlias = hasTypeAlias || !Ty.IsInitialTy(paramType.aliasTy)
            }
            funcType.SetTy(ty)
            let retType = TypeNodeForTy(funcTy.retTy)
            funcType.retType = Some(retType)
            hasTypeAlias = hasTypeAlias || !Ty.IsInitialTy(retType.aliasTy)
            MarkFlatWrappedType(funcType)
            if (hasTypeAlias) {
                funcType.aliasTy = ty
            }
            return funcType
        } else if (let Some(tupleTy) <- (ty as TupleTy)) {
            let tupleType = TupleType()
            for (argTy in tupleTy.typeArgs) {
                let fieldType = TypeNodeForTy(argTy)
                tupleType.fieldTypes.add(fieldType)
                hasTypeAlias = hasTypeAlias || !Ty.IsInitialTy(fieldType.aliasTy)
            }
            tupleType.SetTy(ty)
            MarkFlatWrappedType(tupleType)
            if (hasTypeAlias) {
                tupleType.aliasTy = ty
            }
            return tupleType
        }
        return RefTypeForTy(ty)
    }

    private func RefTypeForTy(ty: Ty): RefType {
        if (!CanWrapFlatRefType(ty.kind)) {
            throw IllegalStateException("FlatBuffer cannot wrap semantic type as RefType: ${ty.String()}")
        }
        var hasTypeAlias = ty.kind == TypeKind.TYPE
        let refType = RefType(ty.name)
        for (argTy in ty.typeArgs) {
            let typeArg = TypeNodeForTy(argTy)
            refType.typeArguments.add(typeArg)
            hasTypeAlias = hasTypeAlias || !Ty.IsInitialTy(typeArg.aliasTy)
        }
        refType.SetTy(ty)
        if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
            refType.ref.target = decl
            if ((ty as ClassThisTy).isSome()) {
                refType.ref.identifier = SrcIdentifier("This")
            } else {
                refType.ref.identifier = decl.identifier
            }
        }
        if (hasTypeAlias) {
            refType.aliasTy = ty
        }
        MarkFlatWrappedType(refType)
        return refType
    }

    private func CanWrapFlatRefType(kind: TypeKind): Bool {
        return kind == TypeKind.TYPE_ENUM || kind == TypeKind.TYPE_STRUCT || kind == TypeKind.TYPE_ARRAY ||
            kind == TypeKind.TYPE_VARRAY || kind == TypeKind.TYPE_POINTER || kind == TypeKind.TYPE_CSTRING ||
            kind == TypeKind.TYPE_CLASS || kind == TypeKind.TYPE_INTERFACE || kind == TypeKind.TYPE ||
            kind == TypeKind.TYPE_GENERICS || kind == TypeKind.TYPE_NOTHING || kind == TypeKind.TYPE_INVALID
    }

    private func MarkFlatWrappedType(typeNode: Type): Unit {
        typeNode.EnableAttr(Attribute.IMPORTED)
        typeNode.EnableAttr(Attribute.COMPILER_ADD)
        typeNode.EnableAttr(Attribute.IS_CHECK_VISITED)
    }

    private func UpdateFlatTypeNode(astType: Option<Type>, loadedType: Type): Type {
        if (let None <- astType) {
            return loadedType
        }
        let existing = astType.getOrThrow()
        if (Ty.IsTyCorrect(loadedType.GetTy())) {
            existing.SetTy(loadedType.GetTy().getOrThrow())
            existing.EnableAttr(Attribute.IS_CHECK_VISITED)
            if (let Some(refType) <- (existing as RefType)) {
                refType.ref.target = loadedType.GetTarget()
            } else if (let Some(qualifiedType) <- (existing as QualifiedType)) {
                qualifiedType.target = loadedType.GetTarget()
            }
        }
        return existing
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

enum FrontendPackageRelation {
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

public enum DepType {
    | DIRECT
    | INDIRECT
    | BOTH
}

private func DepTypeIndex(depType: DepType): Int64 {
    return match (depType) {
        case DepType.DIRECT => 0
        case DepType.INDIRECT => 1
        case DepType.BOTH => 2
    }
}

extend DepType <: Equatable<DepType> {
    public operator func ==(right: DepType): Bool {
        return DepTypeIndex(this) == DepTypeIndex(right)
    }

    public operator func !=(right: DepType): Bool {
        return !(this == right)
    }
}

private class StdDepEntry {
    public var depType: DepType
    public var fullPackageName: String

    public init(depType: DepType, fullPackageName: String) {
        this.depType = depType
        this.fullPackageName = fullPackageName
    }
}

private class CjoPackageInfo {
    public var loader: Option<CjoSignatureMaterializer> = None
    public var pkg: Package
    public var pkgDecl: PackageDecl
    public let declMap: HashMap<String, ArrayList<Decl>> = HashMap<String, ArrayList<Decl>>()
    public let implicitDeclMap: HashMap<String, Decl> = HashMap<String, Decl>()
    public var onlyUsedByMacro: Bool = false

    public init(pkg: Package) {
        this.pkg = pkg
        this.pkgDecl = PackageDecl(pkg)
    }

    public init(pkg: Package, loader: CjoSignatureMaterializer) {
        this.pkg = pkg
        this.pkgDecl = PackageDecl(pkg)
        this.loader = Some(loader)
    }
}

private class DependencyGraph {
    private let importManager: ImportManager
    private let dependencyMap: HashMap<String, HashMap<String, ArrayList<ImportSpec>>> =
        HashMap<String, HashMap<String, ArrayList<ImportSpec>>>()
    private let pkgReExportMap: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    private let cacheDirectDependencyPackageDecls: HashMap<String, ArrayList<PackageDecl>> =
        HashMap<String, ArrayList<PackageDecl>>()
    private let cacheDependencyPackageDecls: HashMap<String, ArrayList<PackageDecl>> =
        HashMap<String, ArrayList<PackageDecl>>()
    private let cacheDependencyPackageNames: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()

    public init(importManager: ImportManager) {
        this.importManager = importManager
    }

    public func GetDirectDependencyPackageDecls(fullPackageName: String): ArrayList<PackageDecl> {
        if (let Some(cached) <- cacheDirectDependencyPackageDecls.get(fullPackageName)) {
            return cached
        }
        let packageDecls = ArrayList<PackageDecl>()
        let collected = HashSet<Node>()
        let tmpQueue = ArrayList<PackageDecl>()
        let edgeNames = ArrayList<String>()
        for (edgeName in GetEdges(fullPackageName).keys()) {
            edgeNames.add(edgeName)
        }
        sort(edgeNames, by: { left: String, right: String =>
            if (left < right) {
                Ordering.LT
            } else if (left > right) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        for (edgeName in edgeNames) {
            if (let Some(pkgDecl) <- importManager.GetPackageDecl(edgeName)) {
                tmpQueue.add(pkgDecl)
            }
        }
        var head: Int64 = 0
        while (head < tmpQueue.size) {
            let pkgDecl = tmpQueue[head]
            head++
            if (!collected.contains(pkgDecl)) {
                collected.add(pkgDecl)
                packageDecls.add(pkgDecl)
            }
            if (!pkgDecl.srcPackage.isMacroPackage) {
                continue
            }
            if (let Some(reExports) <- pkgReExportMap.get(pkgDecl.srcPackage.fullPackageName)) {
                for (reExportPackageName in reExports) {
                    if (let Some(reExportPkgDecl) <- importManager.GetPackageDecl(reExportPackageName)) {
                        if (!reExportPkgDecl.srcPackage.isMacroPackage && !collected.contains(reExportPkgDecl)) {
                            packageDecls.add(reExportPkgDecl)
                            collected.add(reExportPkgDecl)
                        } else if (reExportPkgDecl.srcPackage.isMacroPackage) {
                            tmpQueue.add(reExportPkgDecl)
                            collected.add(reExportPkgDecl)
                        }
                    }
                }
            }
        }
        cacheDirectDependencyPackageDecls[fullPackageName] = packageDecls
        return packageDecls
    }

    public func GetAllDependencyPackageDecls(fullPackageName: String, includeMacroPkg: Bool): ArrayList<PackageDecl> {
        let keyPair = fullPackageName + "|" + if (includeMacroPkg) { "true" } else { "false" }
        if (let Some(cached) <- cacheDependencyPackageDecls.get(keyPair)) {
            return cached
        }
        let packageDecls = ArrayList<PackageDecl>()
        for (pkgName in GetAllDependencyPackageNames(fullPackageName, includeMacroPkg)) {
            if (let Some(pkgDecl) <- importManager.GetPackageDecl(pkgName)) {
                packageDecls.add(pkgDecl)
            }
        }
        cacheDependencyPackageDecls[keyPair] = packageDecls
        return packageDecls
    }

    public func GetAllDependencyPackageNames(fullPackageName: String, includeMacroPkg: Bool): ArrayList<String> {
        if (let Some(cached) <- cacheDependencyPackageNames.get(fullPackageName)) {
            return cached
        }
        let packageNames = HashSet<String>()
        let stack = ArrayList<String>()
        let edgeNames = ArrayList<String>()
        for (edgeName in GetEdges(fullPackageName).keys()) {
            edgeNames.add(edgeName)
        }
        sort(edgeNames, by: { left: String, right: String =>
            if (left < right) {
                Ordering.LT
            } else if (left > right) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        for (edgeName in edgeNames) {
            stack.add(edgeName)
        }
        while (!stack.isEmpty()) {
            let pkgName = stack[stack.size - 1]
            stack.remove(at: stack.size - 1)
            if (packageNames.contains(pkgName)) {
                continue
            }
            let nestedEdgeNames = ArrayList<String>()
            for (edgeName in GetEdges(pkgName).keys()) {
                nestedEdgeNames.add(edgeName)
            }
            sort(nestedEdgeNames, by: { left: String, right: String =>
                if (left < right) {
                    Ordering.LT
                } else if (left > right) {
                    Ordering.GT
                } else {
                    Ordering.EQ
                }
            })
            for (edgeName in nestedEdgeNames) {
                stack.add(edgeName)
            }
            packageNames.add(pkgName)
        }
        let out = ArrayList<String>()
        for (pkgName in packageNames) {
            if (includeMacroPkg || !importManager.IsMacroRelatedPackageName(pkgName)) {
                out.add(pkgName)
            }
        }
        sort(out, by: { left: String, right: String =>
            if (left < right) {
                Ordering.LT
            } else if (left > right) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        cacheDependencyPackageNames[fullPackageName] = out
        return out
    }

    public func AddDependenciesForPackage(pkg: Package): Unit {
        if (dependencyMap.contains(pkg.fullPackageName)) {
            return
        }
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                AddDependenciesForImport(pkg, importSpec)
            }
        }
    }

    public func Clear(): Unit {
        dependencyMap.clear()
        pkgReExportMap.clear()
        cacheDirectDependencyPackageDecls.clear()
        cacheDependencyPackageDecls.clear()
        cacheDependencyPackageNames.clear()
    }

    private func GetEdges(fullPackageName: String): HashMap<String, ArrayList<ImportSpec>> {
        if (let Some(edges) <- dependencyMap.get(fullPackageName)) {
            return edges
        }
        return HashMap<String, ArrayList<ImportSpec>>()
    }

    private func AddDependenciesForImport(pkg: Package, importSpec: ImportSpec): Unit {
        let fullPackageName = importManager.GetPackageNameByImport(importSpec)
        if (let None <- importManager.GetPackage(fullPackageName)) {
            return
        }
        let packageValue = importManager.GetPackage(fullPackageName).getOrThrow()
        if (packageValue.fullPackageName == pkg.fullPackageName) {
            return
        }
        AddDependency(pkg.fullPackageName, packageValue.fullPackageName, importSpec)
        AddDependenciesForPackage(packageValue)
        let relation = importManager.GetFrontendPackageRelation(pkg.fullPackageName, fullPackageName)
        if (importSpec.IsReExport() && importManager.IsFrontendVisible(importSpec, relation)) {
            if (!pkgReExportMap.contains(pkg.fullPackageName)) {
                pkgReExportMap[pkg.fullPackageName] = HashSet<String>()
            }
            if (let Some(reExports) <- pkgReExportMap.get(pkg.fullPackageName)) {
                reExports.add(fullPackageName)
            }
        }
    }

    private func AddDependency(u: String, v: String, importSpec: ImportSpec): Unit {
        if (!dependencyMap.contains(u)) {
            dependencyMap[u] = HashMap<String, ArrayList<ImportSpec>>()
        }
        if (let Some(edges) <- dependencyMap.get(u)) {
            if (!edges.contains(v)) {
                edges[v] = ArrayList<ImportSpec>()
            }
            if (let Some(imports) <- edges.get(v)) {
                imports.add(importSpec)
            }
        }
    }
}

private const NO_CJO_HELP_INFO: String =
    "check if the .cjo file of the package exists in CANGJIE_PATH or CANGJIE_HOME, or use " +
    "'--import-path' to specify the .cjo file path"

public class ImportManager <: SemaImportManager {
    private let diag: DiagnosticEngine
    private let typeManager: FaithfulSemaTypeManager
    private let globalOptions: GlobalOptions
    private let searchPath: ArrayList<String> = ArrayList<String>()
    private let importedPackages: ArrayList<Package> = ArrayList<Package>()
    private let packageDecls: HashMap<String, PackageDecl> = HashMap<String, PackageDecl>()
    private let exportIdDeclMaps: HashMap<String, HashMap<String, Decl>> =
        HashMap<String, HashMap<String, Decl>>()
    private let depPkgCjdPaths: HashMap<String, String> = HashMap<String, String>()
    private let stdDepsMap: HashMap<String, StdDepEntry> = HashMap<String, StdDepEntry>()
    private let packageNameMap: FaithfulUnorderedMap<CjoPackageInfo> = FaithfulUnorderedMap<CjoPackageInfo>()
    private var dependencyGraph: Option<DependencyGraph> = None
    private let loadingPackages: HashSet<String> = HashSet<String>()
    private let loadedPackages: HashSet<String> = HashSet<String>()
    private let sourcePackagesForMembers: ArrayList<Package> = ArrayList<Package>()
    private let packageMembers: HashMap<String, HashMap<String, ArrayList<Decl>>> =
        HashMap<String, HashMap<String, ArrayList<Decl>>>()
    private let packageMembersVisited: HashSet<String> = HashSet<String>()
    private let importedPackageNameMap: HashMap<Node, (String, Bool)> =
        HashMap<Node, (String, Bool)>()
    private let visitedPkgs: HashSet<String> = HashSet<String>()
    private let typeAliasCache: HashMap<Int64, Ty> = HashMap<Int64, Ty>()
    private let commonPartLoaders: ArrayList<CjoSignatureMaterializer> = ArrayList<CjoSignatureMaterializer>()
    private let importedDeclsMap: HashMap<String, ArrayList<Decl>> = HashMap<String, ArrayList<Decl>>()
    private let fileImportedDeclsMap: HashMap<UInt64, HashMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, HashMap<String, ArrayList<Decl>>>()
    private let fileUsedMacroDeclsMap: HashMap<UInt64, HashMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, HashMap<String, ArrayList<Decl>>>()
    private var canInlineImportedSource: Bool = false
    private var importSrcCode: Bool = true
    private var hasBuildIndex: Bool = false
    private var curPackage: Option<Package> = None

    public init(diag: DiagnosticEngine, typeManager: FaithfulSemaTypeManager, globalOptions: GlobalOptions) {
        this.diag = diag
        this.typeManager = typeManager
        this.globalOptions = globalOptions
        this.dependencyGraph = Some(DependencyGraph(this))
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
        let (ok, data, reason) = FileUtil.ReadBinaryFileToBuffer(path)
        if (!ok) {
            diag.DiagnoseRefactor(DiagKindRefactor.module_read_file_to_buffer_failed, DEFAULT_POSITION,
                arguments: [path, reason])
            return out
        }
        if (!VerifySerializedPackageData(data, "")) {
            return out
        }
        let depInfo = ReadSerializedPackageDepInfo(data)
        if (!depInfo.isEmpty()) {
            out.add(depInfo)
        }
        return out
    }

    public func BuildIndex(cangjieModules: String, opts: GlobalOptions, pkgs: ArrayList<Package>): Bool {
        let incrBuildIndex = HasBuildIndex()
        if (!incrBuildIndex) {
            UpdateSearchPath(cangjieModules)
        } else {
            ClearCachesForRebuild()
        }
        canInlineImportedSource = CanInlineImportedSource(opts)
        if (!incrBuildIndex) {
            for (path in opts.importPaths) {
                AppendSearchPath(path)
            }
        }
        importedPackages.clear()
        packageDecls.clear()
        exportIdDeclMaps.clear()
        depPkgCjdPaths.clear()
        stdDepsMap.clear()
        packageNameMap.clear()
        dependencyGraph.getOrThrow().Clear()
        loadingPackages.clear()
        loadedPackages.clear()
        sourcePackagesForMembers.clear()
        packageMembers.clear()
        packageMembersVisited.clear()
        importedPackageNameMap.clear()
        visitedPkgs.clear()
        commonPartLoaders.clear()
        importedDeclsMap.clear()
        fileImportedDeclsMap.clear()
        fileUsedMacroDeclsMap.clear()
        for (pkg in pkgs) {
            if (pkg.fullPackageName.isEmpty()) {
                diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "empty package name")
                return false
            }
            AddImplicitImports(pkg, opts)
            sourcePackagesForMembers.add(pkg)
            AddSourcePackage(pkg)
        }
        if (!ResolveImportedPackages(pkgs)) {
            return false
        }
        for (pkg in pkgs) {
            dependencyGraph.getOrThrow().AddDependenciesForPackage(pkg)
        }
        for (pkg in pkgs) {
            RebuildPackageMembers(pkg.fullPackageName)
        }
        for (pkg in pkgs) {
            AddImportedDeclsForSourcePackage(pkg)
        }
        CheckImports(pkgs)
        for (pd in GetAllPackageDecls()) {
            if (pd.srcPackage.hasSourceImportedDecl) {
                pkgs.add(pd.srcPackage)
            }
        }
        if (!pkgs.isEmpty()) {
            curPackage = Some(pkgs[0])
        }
        SetHasBuildIndex(true)
        return diag.GetErrorCount() == 0
    }

    public func ReindexSourcePackagesAfterMacroExpand(pkgs: ArrayList<Package>): Unit {
        if (pkgs.size <= 1) {
            return
        }
        for (pkg in pkgs) {
            RebuildSourcePackageDeclMap(pkg.fullPackageName)
        }
        importedDeclsMap.clear()
        fileImportedDeclsMap.clear()
        for (pkg in pkgs) {
            AddImportedDeclsForSourcePackage(pkg)
        }
    }

    public func DeleteASTLoaders(): Unit {
        for (packageName in packageNameMap.keys()) {
            if (let Some(info) <- packageNameMap.get(packageName)) {
                info.loader = None
            }
        }
    }
    public func ClearPackageBCHIRCache(): Unit {}
    public func ClearForReBuildIndex(): Unit {
        for (packageName in packageNameMap.keys()) {
            if (let Some(info) <- packageNameMap.get(packageName)) {
                info.loader = None
            }
        }
        packageNameMap.clear()
        importedPackageNameMap.clear()
        visitedPkgs.clear()
        loadingPackages.clear()
        loadedPackages.clear()
        importedPackages.clear()
        hasBuildIndex = false
    }
    public func HasBuildIndex(): Bool {
        return hasBuildIndex
    }
    public func SetHasBuildIndex(value: Bool): Unit {
        hasBuildIndex = value
    }
    private func ClearCachesForRebuild(): Unit {
        ClearForReBuildIndex()
        typeManager.Clear()
        typeManager.ClearMapCache()
        depPkgCjdPaths.clear()
        stdDepsMap.clear()
        dependencyGraph.getOrThrow().Clear()
        importedDeclsMap.clear()
        fileImportedDeclsMap.clear()
        fileUsedMacroDeclsMap.clear()
    }
    public func SetSourceCodeImportStatus(shouldImport: Bool): Unit {
        importSrcCode = shouldImport
    }
    public func IsSourceCodeImported(): Bool { return importSrcCode }

    public func GetAllImportedPackages(): ArrayList<Package> {
        let out = ArrayList<Package>()
        for (pkgDecl in GetAllPackageDecls()) {
            out.add(pkgDecl.srcPackage)
        }
        return out
    }

    private func GetAllPackageDecls(includeMacroPkg!: Bool = false): ArrayList<PackageDecl> {
        let out = ArrayList<PackageDecl>()
        for (packageName in packageNameMap.keys()) {
            if (let Some(info) <- packageNameMap.get(packageName)) {
                if (!info.pkg.TestAttr(Attribute.IMPORTED) || includeMacroPkg ||
                    (!info.onlyUsedByMacro && !info.pkg.isMacroPackage)) {
                    out.add(info.pkgDecl)
                }
            }
        }
        return out
    }

    private func GetPackageInfo(fullPackageName: String): Option<CjoPackageInfo> {
        return packageNameMap.get(fullPackageName)
    }

    private func AddSourcePackage(pkg: Package): Unit {
        let info = CjoPackageInfo(pkg)
        packageNameMap.add(pkg.fullPackageName, info)
        packageDecls[pkg.fullPackageName] = info.pkgDecl
    }

    public func IsOnlyUsedByMacro(fullPackageName: String): Bool {
        if (let Some(info) <- GetPackageInfo(fullPackageName)) {
            return info.onlyUsedByMacro
        }
        return false
    }

    public func SetOnlyUsedByMacro(fullPackageName: String, onlyUsedByMacro: Bool): Unit {
        if (let Some(info) <- GetPackageInfo(fullPackageName)) {
            info.onlyUsedByMacro = onlyUsedByMacro
        }
    }

    public func IsMacroRelatedPackageName(fullPackageName: String): Bool {
        if (let Some(info) <- GetPackageInfo(fullPackageName)) {
            return info.onlyUsedByMacro
        }
        return false
    }

    public func GetPackageDecl(fullPackageName: String): Option<PackageDecl> {
        if (let Some(info) <- GetPackageInfo(fullPackageName)) {
            return Some(info.pkgDecl)
        }
        return None
    }

    public func GetCurImportedPackages(fullPackageName: String): ArrayList<Package> {
        let out = ArrayList<Package>()
        for (pkgDecl in dependencyGraph.getOrThrow().GetDirectDependencyPackageDecls(fullPackageName)) {
            out.add(pkgDecl.srcPackage)
        }
        return out
    }

    public func GetAllDependentPackageDecls(fullPackageName: String, includeMacroPkg: Bool): ArrayList<PackageDecl> {
        return dependencyGraph.getOrThrow().GetAllDependencyPackageDecls(fullPackageName, includeMacroPkg)
    }

    public func GetAllDependentPackageNames(fullPackageName: String): ArrayList<String> {
        return dependencyGraph.getOrThrow().GetAllDependencyPackageNames(fullPackageName, false)
    }

    public func AddImportedPackage(pkg: Package): Unit {
        AddImportedPackageIfMissing(pkg)
    }

    public func GetDepPkgCjdPaths(): HashMap<String, String> {
        return depPkgCjdPaths
    }

    public func GetUsedSTDLibFiles(depType: DepType): HashSet<String> {
        let result = HashSet<String>()
        for (cjoPath in stdDepsMap.keys()) {
            if (let Some(entry) <- stdDepsMap.get(cjoPath)) {
                if (entry.depType == depType || entry.depType == DepType.BOTH) {
                    result.add(cjoPath)
                }
            }
        }
        return result
    }

    public func AnalyzeDepStdPkgsOfBC(fullPackageName: String): Bool {
        if ((let Some(_) <- GetPackage(fullPackageName)) || depPkgCjdPaths.contains(fullPackageName)) {
            return true
        }
        let cjoPath = FileUtil.FindSerializationFile(fullPackageName, ".cjo", searchPath.toArray())
        if (cjoPath.isEmpty()) {
            diag.DiagnoseRefactor(DiagKindRefactor.bc_cjo_error, DEFAULT_POSITION, arguments: [fullPackageName])
            return false
        }
        let (ok, data, _) = FileUtil.ReadBinaryFileToBuffer(cjoPath)
        if (!ok) {
            diag.DiagnoseRefactor(DiagKindRefactor.bc_cjo_error, DEFAULT_POSITION, arguments: [fullPackageName])
            return false
        }
        if (!VerifySerializedPackageData(data, fullPackageName)) {
            return false
        }
        depPkgCjdPaths[fullPackageName] = cjoPath
        for (depStdPkg in ReadAllDependentStdPkgs(data)) {
            let depCjoPath = FindAndSaveDepStdCjoPath(depStdPkg)
            HandleStdPackage(depStdPkg, depCjoPath, isRecursive: true)
        }
        return true
    }

    public func GetImportedDecls(file: File): ArrayList<ImportedDeclGroup> {
        let out = ArrayList<ImportedDeclGroup>()
        for (name in importedDeclsMap.keys()) {
            if (let Some(decls) <- importedDeclsMap.get(name)) {
                out.add(ImportedDeclGroup(name, decls))
            }
        }
        if (let Some(fileMap) <- fileImportedDeclsMap.get(file.fileHash)) {
            for (name in fileMap.keys()) {
                if (let Some(decls) <- fileMap.get(name)) {
                    out.add(ImportedDeclGroup(name, decls))
                }
            }
        }
        return out
    }

    public func AddUsedMacroDecls(file: File, decl: Decl): Unit {
        if (!fileUsedMacroDeclsMap.contains(file.indexOfPackage)) {
            fileUsedMacroDeclsMap[file.indexOfPackage] = HashMap<String, ArrayList<Decl>>()
        }
        if (let Some(usedDeclMap) <- fileUsedMacroDeclsMap.get(file.indexOfPackage)) {
            PutImportedDecl(usedDeclMap, decl.fullPackageName, decl)
        }
    }

    public func GetUsedMacroDecls(file: File): HashMap<String, ArrayList<Decl>> {
        let out = HashMap<String, ArrayList<Decl>>()
        if (let Some(usedDeclMap) <- fileUsedMacroDeclsMap.get(file.indexOfPackage)) {
            for (packageName in usedDeclMap.keys()) {
                if (let Some(decls) <- usedDeclMap.get(packageName)) {
                    let copiedDecls = ArrayList<Decl>()
                    for (decl in decls) {
                        AddDeclIfMissing(copiedDecls, decl)
                    }
                    out[packageName] = copiedDecls
                }
            }
        }
        return out
    }

    public func GetPackageMembers(fullPackageName: String): HashMap<String, ArrayList<Decl>> {
        let out = HashMap<String, ArrayList<Decl>>()
        if (let Some(info) <- GetPackageInfo(fullPackageName)) {
            for (name in info.declMap.keys()) {
                if (let Some(decls) <- info.declMap.get(name)) {
                    let copiedDecls = ArrayList<Decl>()
                    for (decl in decls) {
                        AddDeclIfMissing(copiedDecls, decl)
                    }
                    out[name] = copiedDecls
                }
            }
        }
        return out
    }

    public func GetPackageNameByImport(importSpec: ImportSpec): String {
        if (let Some(packageNamePair) <- importedPackageNameMap.get(importSpec)) {
            return packageNamePair[0]
        }
        return ""
    }

    public func IsImportPackage(importSpec: ImportSpec): Bool {
        if (let Some(packageNamePair) <- importedPackageNameMap.get(importSpec)) {
            return packageNamePair[1]
        }
        return false
    }

    public func GetPackageMembers(srcFullPackageName: String, targetFullPackageName: String): HashMap<String, ArrayList<Decl>> {
        let out = HashMap<String, ArrayList<Decl>>()
        if (srcFullPackageName == targetFullPackageName) {
            return out
        }
        let relation = GetFrontendPackageRelation(srcFullPackageName, targetFullPackageName)
        if (let Some(info) <- GetPackageInfo(targetFullPackageName)) {
            for (name in info.declMap.keys()) {
                if (let Some(decls) <- info.declMap.get(name)) {
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
        let decls = GetPackageMembersByName(packageName, name)
        if (decls.isEmpty()) {
            return GetImplicitPackageMembersByName(packageName, name)
        }
        return Some(decls[0])
    }

    private func CollectDeclsFromImportToMap(srcFullPackageName: String, importSpec: ImportSpec,
        targetMap: HashMap<String, ArrayList<Decl>>): Unit {
        if (importSpec.IsImportMulti()) {
            return
        }
        let targetPackageName = GetPackageNameByImport(importSpec)
        if (targetPackageName.isEmpty()) {
            return
        }
        let packageDeclOpt = GetPackageDecl(targetPackageName)
        if (let None <- packageDeclOpt) {
            return
        }
        let relation = GetFrontendPackageRelation(srcFullPackageName, targetPackageName)
        let importLevel = GetAccessLevel(importSpec)
        if (importSpec.IsImportAll()) {
            let members = GetPackageMembers(targetPackageName)
            for (name in members.keys()) {
                if (let Some(decls) <- members.get(name)) {
                    for (decl in decls) {
                        if (IsVisibleImportedDecl(importLevel, relation, decl)) {
                            PutImportedDecl(targetMap, name, decl)
                        }
                    }
                }
            }
            return
        }
        if (IsImportPackage(importSpec)) {
            let importedName = if (importSpec.IsImportAlias()) {
                importSpec.content.aliasName.Val()
            } else {
                LastPackageName(targetPackageName)
            }
            PutImportedDecl(targetMap, importedName, packageDeclOpt.getOrThrow())
        } else {
            let importedName = if (importSpec.IsImportAlias()) {
                importSpec.content.aliasName.Val()
            } else {
                importSpec.content.identifier.Val()
            }
            for (decl in GetPackageMembersByName(targetPackageName, importSpec.content.identifier.Val())) {
                if (IsVisibleImportedDecl(importLevel, relation, decl)) {
                    PutImportedDecl(targetMap, importedName, decl)
                }
            }
            importSpec.content.isDecl = true
        }
    }

    private func AddImportedDeclsForSourcePackage(pkg: Package): Unit {
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                let declMap = if (importSpec.IsReExport()) {
                    importedDeclsMap
                } else {
                    GetFileImportedDeclMap(file.fileHash)
                }
                CollectDeclsFromImportToMap(pkg.fullPackageName, importSpec, declMap)
            }
        }
    }

    private func GetPackageMembersByName(fullPackageName: String, name: String): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        if (let Some(info) <- GetPackageInfo(fullPackageName)) {
            if (let Some(decls) <- info.declMap.get(name)) {
                for (decl in decls) {
                    AddDeclIfMissing(out, decl)
                }
            }
        }
        return out
    }

    private func GetImplicitPackageMembersByName(fullPackageName: String, name: String): Option<Decl> {
        if (let Some(info) <- GetPackageInfo(fullPackageName)) {
            return info.implicitDeclMap.get(name)
        }
        return None
    }

    public func ClearVisitedPkgs(): Unit {
        visitedPkgs.clear()
    }

    private func AddPackageDeclMap(fullPackageName: String, importedPackage!: String = ""): Unit {
        let infoOpt = GetPackageInfo(fullPackageName)
        if (let None <- infoOpt) {
            return
        }
        if (visitedPkgs.contains(fullPackageName)) {
            return
        }
        let info = infoOpt.getOrThrow()
        visitedPkgs.add(fullPackageName)
        let relation = if (importedPackage.isEmpty()) {
            FrontendPackageRelation.CHILD
        } else {
            GetFrontendPackageRelation(importedPackage, fullPackageName)
        }
        for (file in info.pkg.files) {
            for (decl in file.decls) {
                if (decl.astKind == ASTKind.MACRO_EXPAND_DECL) {
                    continue
                }
                AddDeclToMap(decl, info.declMap)
            }
            for (decl2 in file.exportedInternalDecls) {
                if (decl2.TestAttr(Attribute.IMPLICIT_USED)) {
                    info.implicitDeclMap[decl2.identifier.Val()] = decl2
                }
            }
        }
        for (file2 in info.pkg.files) {
            for (importSpec in file2.imports) {
                if (importSpec.IsImportMulti()) {
                    continue
                }
                let pkgName = GetPackageNameByImport(importSpec)
                if (pkgName.isEmpty()) {
                    continue
                }
                AddPackageDeclMap(pkgName, importedPackage: fullPackageName)
                if (importSpec.IsReExport() && IsFrontendVisible(importSpec, relation)) {
                    AddImportsToMap(importSpec, pkgName, info.declMap)
                }
            }
        }
    }

    private func RebuildSourcePackageDeclMap(fullPackageName: String): Unit {
        if (let Some(info) <- GetPackageInfo(fullPackageName)) {
            info.declMap.clear()
            info.implicitDeclMap.clear()
            visitedPkgs.remove(fullPackageName)
            AddPackageDeclMap(fullPackageName)
        }
    }

    private func AddImportsToMap(
        importSpec: ImportSpec,
        importedPackage: String,
        declMap: HashMap<String, ArrayList<Decl>>
    ): Unit {
        if (let None <- GetPackageInfo(importedPackage)) {
            return
        }
        let importLevel = GetAccessLevel(importSpec)
        if (importSpec.IsImportAll()) {
            let members = GetPackageMembers(importedPackage)
            for (name in members.keys()) {
                if (let Some(decls) <- members.get(name)) {
                    if (!declMap.contains(name)) {
                        declMap[name] = ArrayList<Decl>()
                    }
                    if (let Some(targetMap) <- declMap.get(name)) {
                        AddImportedDeclToMap(decls, targetMap, importLevel)
                    }
                }
            }
            return
        }
        let sourceName = importSpec.content.identifier.Val()
        let decls = GetPackageMembersByName(importedPackage, sourceName)
        if (decls.isEmpty()) {
            return
        }
        let targetName = if (importSpec.IsImportAlias()) {
            importSpec.content.aliasName.Val()
        } else {
            sourceName
        }
        if (!declMap.contains(targetName)) {
            declMap[targetName] = ArrayList<Decl>()
        }
        if (let Some(targetMap) <- declMap.get(targetName)) {
            AddImportedDeclToMap(decls, targetMap, importLevel)
        }
    }

    private func AddDeclToMap(decl: Decl, declMap: HashMap<String, ArrayList<Decl>>): Unit {
        if (decl.astKind == ASTKind.EXTEND_DECL) {
            return
        }
        if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
            if (let Some(pattern) <- vpd.irrefutablePattern) {
                let walker = Walker(pattern, visitPre: { node: Node =>
                    if (let Some(varDecl) <- (node as VarDecl)) {
                        PutImportedDecl(declMap, varDecl.identifier.Val(), varDecl)
                    }
                    VisitAction.WALK_CHILDREN
                })
                let _ = walker.Walk()
            }
            return
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (!funcDecl.TestAttr(Attribute.MAIN_ENTRY) && funcDecl.identifier.Val() != MAIN_INVOKE) {
                PutImportedDecl(declMap, decl.identifier.Val(), decl)
            }
            return
        }
        PutImportedDecl(declMap, decl.identifier.Val(), decl)
    }

    private func GetFileImportedDeclMap(fileHash: UInt64): HashMap<String, ArrayList<Decl>> {
        if (!fileImportedDeclsMap.contains(fileHash)) {
            fileImportedDeclsMap[fileHash] = HashMap<String, ArrayList<Decl>>()
        }
        return fileImportedDeclsMap.get(fileHash).getOrThrow()
    }

    private func IsVisibleImportedDecl(importLevel: AccessLevel, relation: FrontendPackageRelation, decl: Decl): Bool {
        return IsFrontendCompatibleAccessLevel(importLevel, GetAccessLevel(decl)) && IsFrontendVisible(decl, relation)
    }

    func IsFrontendVisible(node: Node, relation: FrontendPackageRelation): Bool {
        return node.TestAttr(Attribute.PUBLIC) || relation == FrontendPackageRelation.SAME_PACKAGE ||
            (node.TestAttr(Attribute.PROTECTED) && relation != FrontendPackageRelation.NONE) ||
            (node.TestAttr(Attribute.INTERNAL) &&
                (relation == FrontendPackageRelation.CHILD || relation == FrontendPackageRelation.SAME_PACKAGE))
    }

    private func IsFrontendCompatibleAccessLevel(srcLevel: AccessLevel, refLevel: AccessLevel): Bool {
        return FrontendAccessLevelIndex(srcLevel) <= FrontendAccessLevelIndex(refLevel)
    }

    private func FrontendAccessLevelIndex(level: AccessLevel): Int64 {
        return match (level) {
            case AccessLevel.PRIVATE => 0
            case AccessLevel.INTERNAL => 1
            case AccessLevel.PROTECTED => 2
            case AccessLevel.PUBLIC => 3
        }
    }

    func GetFrontendPackageRelation(srcFullPkgName: String, targetFullPkgName: String): FrontendPackageRelation {
        let pureSrcFullPackageName = if (IsTestPackage(srcFullPkgName)) {
            GetMainPartPkgNameForTestPkg(srcFullPkgName)
        } else {
            srcFullPkgName
        }
        let pureTargetFullPackageName = if (IsTestPackage(targetFullPkgName)) {
            GetMainPartPkgNameForTestPkg(targetFullPkgName)
        } else {
            targetFullPkgName
        }
        if (pureSrcFullPackageName == pureTargetFullPackageName) {
            return FrontendPackageRelation.SAME_PACKAGE
        }
        if (pureSrcFullPackageName.isEmpty() || pureTargetFullPackageName.isEmpty()) {
            return FrontendPackageRelation.NONE
        }
        let srcPath = SplitQualifiedName(pureSrcFullPackageName)
        let targetPath = SplitQualifiedName(pureTargetFullPackageName)
        if (targetPath.size < srcPath.size && StartsWithPath(srcPath, targetPath)) {
            return FrontendPackageRelation.CHILD
        }
        if (!srcPath.isEmpty() && !targetPath.isEmpty() && srcPath[0] == targetPath[0]) {
            return FrontendPackageRelation.SAME_MODULE
        }
        return FrontendPackageRelation.NONE
    }

    private func IsSuperPackage(srcFullPackageName: String, targetFullPackageName: String): Bool {
        let pureSrcFullPackageName = if (IsTestPackage(srcFullPackageName)) {
            GetMainPartPkgNameForTestPkg(srcFullPackageName)
        } else {
            srcFullPackageName
        }
        let pureTargetFullPackageName = if (IsTestPackage(targetFullPackageName)) {
            GetMainPartPkgNameForTestPkg(targetFullPackageName)
        } else {
            targetFullPackageName
        }
        if (!pureTargetFullPackageName.startsWith(pureSrcFullPackageName)) {
            return false
        }
        let srcNames = SplitQualifiedName(pureSrcFullPackageName)
        let targetNames = SplitQualifiedName(pureTargetFullPackageName)
        return srcNames.size + 1 == targetNames.size
    }

    private func RelationToString(relation: FrontendPackageRelation): String {
        return match (relation) {
            case FrontendPackageRelation.NONE => "irrelevant"
            case FrontendPackageRelation.CHILD => "child"
            case FrontendPackageRelation.SAME_MODULE => "same module"
            case FrontendPackageRelation.SAME_PACKAGE => "same package"
        }
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

    private func ReplaceTypeAliasInNode(node: Node): Unit {
        let walker = Walker(node, visitPre: { current: Node =>
            if (current.astKind == ASTKind.TYPE_ALIAS_DECL) {
                return VisitAction.WALK_CHILDREN
            }
            if (!Ty.IsTyCorrect(current.GetTy())) {
                return VisitAction.WALK_CHILDREN
            }
            let key = current.GetTy().getOrThrow()
            if (!key.HasAliasTy()) {
                return VisitAction.WALK_CHILDREN
            }
            if (let Some(cached) <- typeAliasCache.get(key.objectId)) {
                current.SetTy(cached)
            } else {
                current.SetTy(typeManager.SubstituteTypeAliasInTy(key))
                typeAliasCache[key.objectId] = current.GetTy().getOrThrow()
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    private func SubstituteImportedTypeAliasTy(srcPackages: ArrayList<Package>, opts: GlobalOptions): Unit {
        try (recorder = ProfileRecorder("LoadPackageDeclsOnDemand", "SubstituteImportedTypeAliasTy")) {
            for (pkg in importedPackages) {
                SubstituteImportedTypeAliasTyInPackage(pkg, srcPackages, opts)
            }
            for (pkg2 in sourcePackagesForMembers) {
                SubstituteImportedTypeAliasTyInPackage(pkg2, srcPackages, opts)
            }
            typeAliasCache.clear()
        }
    }

    private func SubstituteImportedTypeAliasTyInPackage(
        pkg: Package,
        srcPackages: ArrayList<Package>,
        opts: GlobalOptions
    ): Unit {
        var isSrcPackage = false
        for (srcPackage in srcPackages) {
            if (srcPackage.fullPackageName == pkg.fullPackageName) {
                isSrcPackage = true
                break
            }
        }
        if (isSrcPackage && opts.commonPartCjos.isEmpty()) {
            return
        }
        for (file in pkg.files) {
            if (isSrcPackage && !file.TestAttr(Attribute.FROM_COMMON_PART)) {
                continue
            }
            ReplaceTypeAliasInNode(file)
        }
    }

    private func LastPackageName(fullPackageName: String): String {
        let parts = SplitQualifiedName(fullPackageName)
        if (parts.isEmpty()) {
            return fullPackageName
        }
        return parts[parts.size - 1]
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
        if (let Some(info) <- GetPackageInfo(name)) {
            return Some(info.pkg)
        }
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
                    let fullPackageName = GetPackageNameByImport(importSpec)
                    if (fullPackageName.isEmpty()) {
                        continue
                    }
                    let packageOpt = GetPackageForImportCheck(fullPackageName, sourcePackages)
                    if (let None <- packageOpt) {
                        continue
                    }
                    let packageValue = packageOpt.getOrThrow()
                    let packageRange = GetPackageNameRange(importSpec)
                    if (fullPackageName != packageValue.fullPackageName) {
                        diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
                            DiagKindRefactor.package_import_inconsistent,
                            packageRange,
                            arguments: [packageValue.fullPackageName, fullPackageName]).Emit()
                        continue
                    } else if (fullPackageName == pkg.fullPackageName) {
                        diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
                            DiagKindRefactor.package_import_itself_illegal,
                            packageRange,
                            arguments: [fullPackageName]).Emit()
                        continue
                    }
                    if (importSpec.TestAttr(Attribute.IMPLICIT_ADD)) {
                        continue
                    }
                    let relation = GetFrontendPackageRelation(pkg.fullPackageName, fullPackageName)
                    if ((FrontendAccessLevelIndex(packageValue.accessible) ==
                            FrontendAccessLevelIndex(AccessLevel.PROTECTED) &&
                            relation == FrontendPackageRelation.NONE) ||
                        (FrontendAccessLevelIndex(packageValue.accessible) ==
                            FrontendAccessLevelIndex(AccessLevel.INTERNAL) &&
                            relation != FrontendPackageRelation.CHILD &&
                            !IsSuperPackage(pkg.fullPackageName, fullPackageName))) {
                        diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
                            DiagKindRefactor.package_accessibility,
                            packageRange,
                            arguments: [fullPackageName, GetAccessLevelStr(packageValue), RelationToString(relation),
                                pkg.fullPackageName]).Emit()
                    } else if (importSpec.IsReExport() && !pkg.isMacroPackage && packageValue.isMacroPackage) {
                        diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
                            DiagKindRefactor.package_cannot_export_macro_package,
                            packageRange).Emit()
                        continue
                    } else if (importSpec.IsImportAll()) {
                        continue
                    } else if (IsImportPackage(importSpec)) {
                        if (importSpec.IsReExport()) {
                            diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
                                DiagKindRefactor.package_re_export_package_name,
                                packageRange,
                                arguments: [fullPackageName, GetAccessLevelStr(importSpec)]).Emit()
                        }
                        continue
                    } else if (!HasVisibleImportedDecl(pkg.fullPackageName, packageValue, importSpec.content.identifier.Val())) {
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
        let relation = GetFrontendPackageRelation(srcFullPackageName, pkg.fullPackageName)
        for (decl in GetPackageMembersByName(pkg.fullPackageName, name)) {
            if (IsFrontendVisible(decl, relation)) {
                return true
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

    private func AddImportedDeclToMap(
        decls: ArrayList<Decl>,
        targetSet: ArrayList<Decl>,
        importLevel: AccessLevel
    ): Unit {
        for (decl in decls) {
            if (IsFrontendCompatibleAccessLevel(importLevel, GetAccessLevel(decl))) {
                AddDeclIfMissing(targetSet, decl)
            }
        }
    }

    private func AddImportedPackageIfMissing(pkg: Package): Unit {
        let info = CjoPackageInfo(pkg)
        packageNameMap.add(pkg.fullPackageName, info)
        packageDecls[pkg.fullPackageName] = info.pkgDecl
        for (existing in importedPackages) {
            if (existing.fullPackageName == pkg.fullPackageName) {
                return
            }
        }
        importedPackages.add(pkg)
    }

    private func SaveDepPkgCjoPath(fullPackageName: String, cjoPath: String): Unit {
        depPkgCjdPaths[fullPackageName] = cjoPath
    }

    private func GetPackageCjo(importSpec: ImportSpec): (String, String) {
        let mapped = GetPackageNameByImport(importSpec)
        if (!mapped.isEmpty()) {
            return (mapped, FileUtil.FindSerializationFile(mapped, ".cjo", searchPath.toArray()))
        }
        var cjoPath = ""
        var cjoPackageName = ""
        var inGroupPackageName = ""
        for (candidate in importSpec.content.GetPossiblePackageNames()) {
            cjoPackageName = candidate
            if (inGroupPackageName.isEmpty() && GetPackageInfo(cjoPackageName).isSome()) {
                inGroupPackageName = cjoPackageName
            }
            cjoPath = FileUtil.FindSerializationFile(cjoPackageName, ".cjo", searchPath.toArray())
            if (!cjoPath.isEmpty()) {
                break
            }
        }
        if (!inGroupPackageName.isEmpty() && inGroupPackageName != cjoPackageName) {
            cjoPackageName = inGroupPackageName
            cjoPath = ""
        }
        if (cjoPackageName.isEmpty()) {
            cjoPackageName = importSpec.content.GetImportedPackageName()
        }
        AddImportedPackageName(importSpec, cjoPackageName)
        return (cjoPackageName, cjoPath)
    }

    private func ResolveImportedPackages(packages: ArrayList<Package>): Bool {
        var success = true
        for (pkg in packages) {
            curPackage = Some(pkg)
            if (!LoadFilesOfCommonPart(pkg)) {
                return false
            }
            success = ResolveImportedPackageHeaders(pkg, isRecursive: false) && success
            pkg.ClearAllDependentStdPkgs()
            for (cjoPath in stdDepsMap.keys()) {
                if (let Some(entry) <- stdDepsMap.get(cjoPath)) {
                    pkg.AddDependentStdPkg(entry.fullPackageName)
                }
            }
        }
        LoadPackageDeclsOnDemand(packages)
        for (pkg2 in packages) {
            AddPackageDeclMap(pkg2.fullPackageName)
        }
        return success
    }

    private func AddLoadedPackages(pkgName: String): Bool {
        if (loadedPackages.contains(pkgName)) {
            return false
        }
        loadedPackages.add(pkgName)
        return true
    }

    private func AlreadyLoaded(pkgName: String): Bool {
        return loadedPackages.contains(pkgName)
    }

    private func IsReExportBy(srcPackage: String, reExportPackage: String): Bool {
        if (let Some(info) <- GetPackageInfo(srcPackage)) {
            for (file in info.pkg.files) {
                for (importSpec in file.imports) {
                    if (!importSpec.IsReExport()) {
                        continue
                    }
                    if (GetPackageNameByImport(importSpec) == reExportPackage) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func NeedCollectDependency(curName: String, isCurMacro: Bool, depName: String): Bool {
        if (depName == curName || AlreadyLoaded(depName)) {
            return false
        }
        if (let Some(depPd) <- GetPackageDecl(depName)) {
            let isDepMacro = depPd.srcPackage.isMacroPackage
            if (!isCurMacro || isDepMacro || depName == AST_PACKAGE_NAME || IsReExportBy(curName, depName)) {
                return true
            }
        }
        return false
    }

    private func LoadFilesOfCommonPart(pkg: Package): Bool {
        if (!globalOptions.IsCompilingCJMPSpecific() && globalOptions.commonPartCjos.isEmpty()) {
            return true
        }
        EraseIf<File>(pkg.files, { file: File => file.TestAttr(Attribute.FROM_COMMON_PART) })
        for (commonLoader in GetCommonPartCjos(pkg.fullPackageName)) {
            if (!commonLoader.PreloadCommonPartOfPackage(pkg, globalOptions)) {
                return false
            }
        }
        return true
    }

    private func LoadPackageDeclsOnDemand(packages: ArrayList<Package>, fromLsp!: Bool = false): Unit {
        let queue = ArrayList<CjoPackageInfo>()
        let loaders = ArrayList<CjoSignatureMaterializer>()
        for (pkg in packages) {
            if (fromLsp) {
                if (let Some(info) <- GetPackageInfo(pkg.fullPackageName)) {
                    queue.add(info)
                }
            }
            for (file in pkg.files) {
                for (importSpec in file.imports) {
                    let pkgName = GetPackageNameByImport(importSpec)
                    if (!pkgName.isEmpty()) {
                        if (let Some(info) <- GetPackageInfo(pkgName)) {
                            queue.add(info)
                        }
                    }
                }
            }
        }
        for (pkg in packages) {
            if (globalOptions.IsCompilingCJMPSpecific() || !globalOptions.commonPartCjos.isEmpty()) {
                for (commonLoader in GetCommonPartCjos(pkg.fullPackageName)) {
                    commonLoader.LoadPackageDecls()
                    loaders.add(commonLoader)
                }
            }
        }
        var head: Int64 = 0
        while (head < queue.size) {
            let cur = queue[head]
            head++
            if (let None <- cur.loader) {
                continue
            }
            let loader = cur.loader.getOrThrow()
            let pkgName = loader.GetImportedPackageName()
            if (!AddLoadedPackages(pkgName)) {
                continue
            }
            loaders.add(loader)
            loader.LoadPackageDecls()
            let isCurMacro = cur.pkg.isMacroPackage
            for (depPkg in loader.GetDependentPackageNames()) {
                if (NeedCollectDependency(pkgName, isCurMacro, depPkg)) {
                    if (let Some(depInfo) <- GetPackageInfo(depPkg)) {
                        queue.add(depInfo)
                    }
                }
            }
        }
        for (loader2 in loaders) {
            loader2.LoadRefs()
        }
        if (!fromLsp) {
            SubstituteImportedTypeAliasTy(packages, globalOptions)
        }
    }

    private func GetCommonPartCjos(expectedName: String): ArrayList<CjoSignatureMaterializer> {
        if (!commonPartLoaders.isEmpty()) {
            return commonPartLoaders
        }
        if (globalOptions.commonPartCjos.isEmpty()) {
            diag.DiagnoseRefactor(DiagKindRefactor.module_common_part_path_is_required, DEFAULT_POSITION)
        }
        for (commonPartCjo in globalOptions.commonPartCjos) {
            if (let Some(loader) <- ReadCjo(expectedName, commonPartCjo)) {
                commonPartLoaders.add(loader)
            }
        }
        return commonPartLoaders
    }

    private func ReadCjo(fullPackageName: String, cjoPath: String): Option<CjoSignatureMaterializer> {
        let (ok, data, reason) = FileUtil.ReadBinaryFileToBuffer(cjoPath)
        if (!ok) {
            diag.DiagnoseRefactor(DiagKindRefactor.module_read_file_to_buffer_failed, DEFAULT_POSITION,
                arguments: [cjoPath, reason])
            return None
        }
        let pkg = CreatePackage(fullPackageName)
        let filesByIndex = HashMap<UInt32, File>()
        let idToFileMap = HashMap<UInt64, File>()
        let materializer = CjoSignatureMaterializer(fullPackageName, pkg, filesByIndex, idToFileMap, importedPackages,
            packageDecls, exportIdDeclMaps, diag, typeManager, importSrcCode: importSrcCode,
            deserializingCommon: true, canInline: canInlineImportedSource, data: Some(data))
        return Some(materializer)
    }

    private func ResolveImportedPackageHeaders(pkg: Package, isRecursive!: Bool = false): Bool {
        var success = true
        for (file in pkg.files) {
            if (!ResolveImportedPackageForFile(file, isRecursive: isRecursive)) {
                success = false
            }
        }
        return success
    }

    private func ResolveImportedPackageForFile(file: File, isRecursive!: Bool = false): Bool {
        var success = true
        if (let None <- file.curPackage) {
            throw IllegalStateException("ResolveImportedPackageForFile requires file.curPackage")
        }
        let curPkg = file.curPackage.getOrThrow()
        let isMacroRelated = curPkg.isMacroPackage || IsMacroRelatedPackageName(curPkg.fullPackageName)
        if (let None <- curPackage) {
            throw IllegalStateException("ResolveImportedPackageForFile requires curPackage")
        }
        let rootPkg = curPackage.getOrThrow()
        let relation = GetFrontendPackageRelation(rootPkg.fullPackageName, curPkg.fullPackageName)
        for (importSpec in file.imports) {
            if (importSpec.IsImportMulti() || !importSpec.withImplicitExport) {
                continue
            }
            let isVisibleImport = importSpec.IsReExport() && IsFrontendVisible(importSpec, relation)
            let packageAndPath = GetPackageCjo(importSpec)
            let fullPackageName = packageAndPath[0]
            let cjoPath = packageAndPath[1]
            SaveDepPkgCjoPath(fullPackageName, cjoPath)
            if (let Some(importPkg) <- GetPackage(fullPackageName)) {
                if (importPkg.TestAttr(Attribute.IMPORTED) && !importPkg.TestAttr(Attribute.TOOL_ADD) &&
                    cjoPath.isEmpty()) {
                    throw IllegalStateException("already-parsed imported package has empty cjo path")
                }
                if (!importPkg.TestAttr(Attribute.IMPORTED) && curPkg.TestAttr(Attribute.IMPORTED)) {
                    success = false
                    diag.DiagnoseRefactor(DiagKindRefactor.module_same_name_with_indirect_dependent_pkg,
                        DEFAULT_POSITION, arguments: [fullPackageName, curPkg.fullPackageName])
                } else {
                    success = HandleParsedPackage(importPkg, cjoPath, !isMacroRelated || isVisibleImport,
                        isRecursive) && success
                }
                continue
            }
            let isMainPartPkgForTestPkg = globalOptions.compileTestsOnly && IsTestPackage(curPkg.fullPackageName) &&
                GetMainPartPkgNameForTestPkg(curPkg.fullPackageName) == fullPackageName
            if (!CheckCjoPathLegality(importSpec, cjoPath, fullPackageName, isRecursive, isMainPartPkgForTestPkg) ||
                !LoadImportedPackageFromCjo(fullPackageName, cjoPath)) {
                success = false
                continue
            }
            if (let Some(importPkg) <- GetPackage(fullPackageName)) {
                if (importPkg.isMacroPackage && isRecursive && !isVisibleImport && isMacroRelated) {
                    RemovePackage(fullPackageName, importPkg)
                    continue
                }
                let macroReExportCommonPackage = isVisibleImport && isMacroRelated && !importPkg.isMacroPackage
                if ((!IsMacroRelatedPackageName(curPkg.fullPackageName) && !importPkg.isMacroPackage) ||
                    rootPkg.isMacroPackage || macroReExportCommonPackage) {
                    HandleStdPackage(fullPackageName, cjoPath, isRecursive: isRecursive)
                    for (depStdPkg in importPkg.GetAllDependentStdPkgs()) {
                        HandleStdPackage(depStdPkg, FindAndSaveDepStdCjoPath(depStdPkg), isRecursive: true)
                    }
                } else {
                    SetOnlyUsedByMacro(fullPackageName, true)
                }
                success = ResolveImportedPackageHeaders(importPkg, isRecursive: true) && success
            }
        }
        return success
    }

    private func HandleParsedPackage(pkg: Package, filePath: String, isUsedAsCommon: Bool, isRecursive: Bool): Bool {
        var shouldPromoteMacroUse = false
        if (let Some(root) <- curPackage) {
            shouldPromoteMacroUse = root.isMacroPackage || (isUsedAsCommon && !pkg.isMacroPackage)
        }
        if (IsOnlyUsedByMacro(pkg.fullPackageName) && shouldPromoteMacroUse) {
            SetOnlyUsedByMacro(pkg.fullPackageName, false)
            HandleStdPackage(pkg.fullPackageName, filePath, isRecursive: isRecursive)
            for (depStdPkg in pkg.GetAllDependentStdPkgs()) {
                HandleStdPackage(depStdPkg, FindAndSaveDepStdCjoPath(depStdPkg), isRecursive: true)
            }
            return ResolveImportedPackageHeaders(pkg, isRecursive: true)
        }
        return true
    }

    private func RemovePackage(fullPkgName: String, pkg: Package): Unit {
        packageNameMap.remove(fullPkgName)
        packageDecls.remove(fullPkgName)
        var idx: Int64 = 0
        while (idx < importedPackages.size) {
            if (importedPackages[idx].fullPackageName == pkg.fullPackageName) {
                importedPackages.remove(at: idx)
                return
            }
            idx++
        }
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
        if (!VerifySerializedPackageData(data, fullPackageName)) {
            loadingPackages.remove(fullPackageName)
            return false
        }
        let pkg = CreatePackage(fullPackageName)
        pkg.EnableAttr(Attribute.IMPORTED)
        let (filesByIndex, idToFileMap) = MaterializeCjoFiles(data, pkg)
        let materializer = CjoSignatureMaterializer(fullPackageName, pkg, filesByIndex, idToFileMap, importedPackages,
            packageDecls, exportIdDeclMaps, diag, typeManager, importSrcCode: importSrcCode,
            canInline: canInlineImportedSource)
        if (!materializer.LoadPackageDependencies(data)) {
            loadingPackages.remove(fullPackageName)
            return false
        }
        let info = CjoPackageInfo(pkg, materializer)
        packageNameMap.add(fullPackageName, info)
        packageDecls[fullPackageName] = info.pkgDecl
        importedPackages.add(pkg)
        loadingPackages.remove(fullPackageName)
        return true
    }

    private func MaterializeCjoFiles(data: Array<UInt8>, pkg: Package): (HashMap<UInt32, File>, HashMap<UInt64, File>) {
        let filesByIndex = HashMap<UInt32, File>()
        let idToFileMap = HashMap<UInt64, File>()
        let reader = CjoFlatBuffer(data)
        let root = reader.RootTable()
        let filesVec = if (root >= 0) { reader.VectorField(root, 14) } else { -1 }
        if (filesVec >= 0) {
            var idx: Int64 = 0
            while (idx < reader.VectorLength(filesVec)) {
                let storedPath = reader.StringAt(reader.VectorOffsetElement(filesVec, idx))
                let fileID = diag.GetSourceManager().AddSource(storedPath, "", packageName: Some(pkg.fullPackageName))
                let file = CreateImportedCjoFile(pkg, fileID)
                filesByIndex[UInt32(idx + 1)] = file
                if (!idToFileMap.contains(fileID)) {
                    idToFileMap[fileID] = file
                }
                idx++
            }
        }
        return (filesByIndex, idToFileMap)
    }

    private func VerifySerializedPackageData(data: Array<UInt8>, importedPackageName: String): Bool {
        let reader = CjoFlatBuffer(data)
        if (!reader.VerifyPackageBuffer()) {
            diag.DiagnoseRefactor(DiagKindRefactor.module_loaded_ast_failed, DEFAULT_POSITION,
                arguments: ["ast", importedPackageName, CANGJIE_VERSION])
            return false
        }
        return true
    }

    private func CanInlineImportedSource(opts: GlobalOptions): Bool {
        return opts.chirLLVM && enumIndex(opts.optimizationLevel) > enumIndex(OptimizationLevel.O1) &&
            !opts.enableCompileTest && !opts.enableHotReload
    }

    private func ReadSerializedPackageDepInfo(data: Array<UInt8>): String {
        let reader = CjoFlatBuffer(data)
        let root = reader.RootTable()
        if (root < 0) {
            return ""
        }
        return reader.StringField(root, 10)
    }

    private func CreateImportedCjoFile(pkg: Package, fileID: UInt64): File {
        let source = diag.GetSourceManager().GetSource(fileID)
        let file = CreateFile(source.path)
        file.fileName = FileUtil.GetFileName(source.path)
        file.filePath = source.path
        file.fileHash = source.fileHash
        file.begin.fileID = fileID
        file.curFile = Some(file)
        file.curPackage = Some(pkg)
        pkg.files.add(file)
        return file
    }

    private func ReadAllDependentStdPkgs(data: Array<UInt8>): ArrayList<String> {
        let out = ArrayList<String>()
        let reader = CjoFlatBuffer(data)
        let root = reader.RootTable()
        if (root < 0) {
            return out
        }
        let dependentStdPkgs = reader.VectorField(root, 34)
        if (dependentStdPkgs < 0) {
            return out
        }
        var idx: Int64 = 0
        while (idx < reader.VectorLength(dependentStdPkgs)) {
            let depName = reader.StringAt(reader.VectorOffsetElement(dependentStdPkgs, idx))
            if (!depName.isEmpty()) {
                out.add(depName)
            }
            idx++
        }
        return out
    }

    private func FindAndSaveDepStdCjoPath(fullPackageName: String): String {
        if (let Some(cachedPath) <- depPkgCjdPaths.get(fullPackageName)) {
            return cachedPath
        }
        let cjoPath = FileUtil.FindSerializationFile(fullPackageName, ".cjo", searchPath.toArray())
        if (!cjoPath.isEmpty()) {
            depPkgCjdPaths[fullPackageName] = cjoPath
        }
        return cjoPath
    }

    private func HandleStdPackage(fullPackageName: String, cjoPath: String, isRecursive!: Bool = false): Unit {
        let depType = if (isRecursive) { DepType.INDIRECT } else { DepType.DIRECT }
        if (let Some(entry) <- stdDepsMap.get(cjoPath)) {
            if (entry.depType != depType) {
                entry.depType = DepType.BOTH
            }
            return
        }
        if (STANDARD_LIBS.contains(fullPackageName) && !cjoPath.isEmpty() && FileUtil.FileExist(cjoPath)) {
            stdDepsMap[cjoPath] = StdDepEntry(depType, fullPackageName)
        }
    }

    private func CheckCjoPathLegality(
        importSpec: ImportSpec,
        cjoPath: String,
        fullPackageName: String,
        isRecursive: Bool,
        isMainPartPkgForTestPkg: Bool
    ): Bool {
        if (!cjoPath.isEmpty()) {
            return true
        }
        let kind = if (isMainPartPkgForTestPkg) {
            DiagKindRefactor.package_missed_cjo_main_pkg_part_for_test_pkg
        } else {
            DiagKindRefactor.package_search_error
        }
        let range = if (isRecursive) {
            MakeRange(importSpec.begin, importSpec.begin + 1)
        } else {
            GetPackageNameRange(importSpec)
        }
        let builder = diag.AsBasicDiagnosticEngine().DiagnoseRefactor(kind, range, arguments: [fullPackageName])
        builder.AddHelp(DiagHelp(NO_CJO_HELP_INFO))
        builder.Emit()
        return false
    }

    private func GetPackageNameRange(importSpec: ImportSpec): BasicRange {
        let im = importSpec.content
        if (importSpec.TestAttr(Attribute.IMPLICIT_ADD)) {
            return MakeRange(DEFAULT_POSITION, im.identifier.Val())
        }
        if (IsPackageImportForCheck(importSpec, im.GetImportedPackageNameWithIsDecl(), sourcePackagesForMembers)) {
            if (im.prefixPoses.isEmpty()) {
                return MakeRange(im.identifier.Begin(), im.identifier.End())
            }
            return MakeRange(im.prefixPoses[0], im.identifier.End())
        }
        if (im.prefixPoses.isEmpty() || im.prefixPaths.isEmpty()) {
            return MakeRange(im.identifier.Begin(), im.identifier.End())
        }
        return MakeRange(im.prefixPoses[0],
            im.prefixPoses[im.prefixPoses.size - 1] + im.prefixPaths[im.prefixPaths.size - 1].size)
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
                if (importSpec.IsImportMulti() || !importSpec.withImplicitExport) {
                    continue
                }
                let depName = NormalizeImportedPackageName(importSpec, sourcePackages)
                if (!depName.isEmpty() && depName != pkg.fullPackageName && !seen.contains(depName)) {
                    seen.add(depName)
                    deps.add(depName)
                }
                if (!depName.isEmpty() && !sourcePackages.contains(depName) && (let None <- GetPackage(depName))) {
                    let cjoPath = FileUtil.FindSerializationFile(depName, ".cjo", searchPath.toArray())
                    let isMainPartPkgForTestPkg = globalOptions.compileTestsOnly && IsTestPackage(pkg.fullPackageName) &&
                        GetMainPartPkgNameForTestPkg(pkg.fullPackageName) == depName
                    let _ = CheckCjoPathLegality(importSpec, cjoPath, depName, false, isMainPartPkgForTestPkg)
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

    private func AddImportedPackageName(importSpec: ImportSpec, packageName: String): Unit {
        let possibleName = importSpec.content.GetImportedPackageName()
        importedPackageNameMap[importSpec] =
            (packageName, packageName == possibleName && importSpec.content.kind != ImportKind.IMPORT_ALL)
    }

    private func NormalizeImportedPackageName(importSpec: ImportSpec, sourcePackages: HashSet<String>): String {
        let content = importSpec.content
        if (content.kind == ImportKind.IMPORT_ALL || content.isDecl) {
            let packageName = content.GetPrefixPath()
            AddImportedPackageName(importSpec, packageName)
            return packageName
        }
        let importedPackageName = content.GetImportedPackageName()
        for (possibleName in content.GetPossiblePackageNames()) {
            if (sourcePackages.contains(possibleName) ||
                !FileUtil.FindSerializationFile(possibleName, ".cjo", searchPath.toArray()).isEmpty()) {
                if (possibleName != importedPackageName) {
                    content.isDecl = true
                }
                AddImportedPackageName(importSpec, possibleName)
                return possibleName
            }
        }
        AddImportedPackageName(importSpec, importedPackageName)
        return importedPackageName
    }

    private func IsTestPackage(pkgName: String): Bool {
        return pkgName.size >= 5 && pkgName[pkgName.size - 5..pkgName.size] == "$test"
    }

    private func GetMainPartPkgNameForTestPkg(testPkgName: String): String {
        return testPkgName[0..testPkgName.size - 5]
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

public class PackageInfo {
    public var fullPackageName: String
    public let deps: ArrayList<PackageInfo> = ArrayList<PackageInfo>()

    public init(fullPackageName: String) {
        this.fullPackageName = fullPackageName
    }
}

private class TarjanContext {
    public let indices: HashMap<String, Int64> = HashMap<String, Int64>()
    public let lowlinks: HashMap<String, Int64> = HashMap<String, Int64>()
    public let onStack: HashSet<String> = HashSet<String>()
    public var nextIndex: Int64 = 0

    public init() {}
}

public class PackageManager {
    private let importManager: ImportManager
    private let orderedPackageInfos: ArrayList<ArrayList<PackageInfo>> = ArrayList<ArrayList<PackageInfo>>()
    public let packageToOtherSccMap: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    public let packageInfoMap: HashMap<String, PackageInfo> = HashMap<String, PackageInfo>()

    public init(importManager: ImportManager) {
        this.importManager = importManager
    }

    public func ResolveDependence(pkgs: ArrayList<Package>): Bool {
        packageInfoMap.clear()
        orderedPackageInfos.clear()
        packageToOtherSccMap.clear()
        CollectDeps(pkgs)
        let ctx = TarjanContext()
        let stack = ArrayList<PackageInfo>()
        while (ctx.indices.size < packageInfoMap.size) {
            var progressed = false
            for (name in packageInfoMap.keys()) {
                if (!ctx.indices.contains(name)) {
                    if (let Some(info) <- packageInfoMap.get(name)) {
                        TarjanForSCC(ctx, stack, info)
                        progressed = true
                    }
                }
            }
            if (!progressed) {
                break
            }
        }
        let sortPackageMap = HashMap<String, Package>()
        for (pkg in pkgs) {
            sortPackageMap[pkg.fullPackageName] = pkg
        }
        var ret = true
        var pkgIndex: Int64 = 0
        for (component in orderedPackageInfos) {
            ret = ret && component.size == 1
            for (pkgInfo in component) {
                if (let Some(pkg) <- sortPackageMap.get(pkgInfo.fullPackageName)) {
                    pkgs[pkgIndex] = pkg
                    pkgIndex++
                }
            }
        }
        return ret
    }

    public func GetBuildOrders(pkgs: ArrayList<Package>): ArrayList<ArrayList<Package>> {
        let out = ArrayList<ArrayList<Package>>()
        let sortPackageMap = HashMap<String, Package>()
        for (pkg in pkgs) {
            sortPackageMap[pkg.fullPackageName] = pkg
        }
        for (component in orderedPackageInfos) {
            let group = ArrayList<Package>()
            for (pkgInfo in component) {
                if (let Some(pkg) <- sortPackageMap.get(pkgInfo.fullPackageName)) {
                    group.add(pkg)
                }
            }
            out.add(group)
        }
        return out
    }

    private func CollectDeps(pkgs: ArrayList<Package>): Unit {
        for (pkg in pkgs) {
            packageInfoMap[pkg.fullPackageName] = PackageInfo(pkg.fullPackageName)
        }
        for (pkg in pkgs) {
            if (let Some(pkgInfo) <- packageInfoMap.get(pkg.fullPackageName)) {
                for (file in pkg.files) {
                    CollectDepsInFile(file, pkgInfo, pkg)
                }
            }
        }
    }

    private func CollectDepsInFile(file: File, pkgInfo: PackageInfo, pkg: Package): Unit {
        for (importSpec in file.imports) {
            var fullPkgName = importManager.GetPackageNameByImport(importSpec)
            let pdOpt = importManager.GetPackageDecl(fullPkgName)
            if (let None <- pdOpt) {
                continue
            }
            let importPkg = pdOpt.getOrThrow().srcPackage
            if (importPkg.TestAttr(Attribute.TOOL_ADD)) {
                continue
            }
            fullPkgName = importPkg.fullPackageName
            if (let Some(found) <- packageInfoMap.get(fullPkgName)) {
                AddUniqueInfo(pkgInfo.deps, found)
            } else {
                if (!packageToOtherSccMap.contains(pkg.fullPackageName)) {
                    packageToOtherSccMap[pkg.fullPackageName] = HashSet<String>()
                }
                if (let Some(values) <- packageToOtherSccMap.get(pkg.fullPackageName)) {
                    values.add(importPkg.fullPackageName)
                }
            }
        }
    }

    private func TarjanForSCC(ctx: TarjanContext, stack: ArrayList<PackageInfo>, u: PackageInfo): Unit {
        ctx.nextIndex++
        ctx.indices[u.fullPackageName] = ctx.nextIndex
        ctx.lowlinks[u.fullPackageName] = ctx.nextIndex
        stack.add(u)
        ctx.onStack.add(u.fullPackageName)

        for (w in u.deps) {
            if (!ctx.indices.contains(w.fullPackageName)) {
                TarjanForSCC(ctx, stack, w)
                let currentLow = ctx.lowlinks.get(u.fullPackageName).getOrThrow()
                let childLow = ctx.lowlinks.get(w.fullPackageName).getOrThrow()
                ctx.lowlinks[u.fullPackageName] = if (currentLow < childLow) { currentLow } else { childLow }
            } else if (ctx.onStack.contains(w.fullPackageName)) {
                let currentLow = ctx.lowlinks.get(u.fullPackageName).getOrThrow()
                let childIndex = ctx.indices.get(w.fullPackageName).getOrThrow()
                ctx.lowlinks[u.fullPackageName] = if (currentLow < childIndex) { currentLow } else { childIndex }
            }
        }
        if (ctx.lowlinks.get(u.fullPackageName).getOrThrow() == ctx.indices.get(u.fullPackageName).getOrThrow()) {
            let infos = ArrayList<PackageInfo>()
            while (!stack.isEmpty()) {
                let v = stack[stack.size - 1]
                stack.remove(at: stack.size - 1)
                ctx.onStack.remove(v.fullPackageName)
                infos.add(v)
                if (v.fullPackageName == u.fullPackageName) {
                    break
                }
            }
            orderedPackageInfos.add(infos)
        }
    }

    private func AddUniqueInfo(values: ArrayList<PackageInfo>, value: PackageInfo): Unit {
        for (item in values) {
            if (item.fullPackageName == value.fullPackageName) {
                return
            }
        }
        values.add(value)
    }
}

public class TestManager {
    public init() {}
    public func MarkDeclsForTestIfNeeded(pkgs: ArrayList<Package>): Unit {
        let _ = pkgs
    }
}

public class GenericInstantiationManager {
    private let impl: RealGenericInstantiationManagerImpl

    public init(instance: CompilerInstance) {
        impl = RealGenericInstantiationManagerImpl(instance.faithfulSemaInstance.getOrThrow())
    }

    public func GenericInstantiatePackage(pkg: Package, resetGlobalState!: Bool = true): Unit {
        impl.GenericInstantiatePackage(pkg, resetGlobalState: resetGlobalState)
    }

    public func ResetGenericInstantiationStage(): Unit {
        impl.ResetGenericInstantiationStage()
    }
}

public func EscapeJson(text: String): String {
    return text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")
}

public let DIR_SEPARATOR: String = "/"
