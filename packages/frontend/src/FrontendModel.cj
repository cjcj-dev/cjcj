package cangjie_compiler::frontend

public import cangjie_compiler::basic.{
    BEGIN_POSITION, DEFAULT_POSITION, INVALID_POSITION, DiagCategory, DiagColor, DiagKindRefactor, DiagSeverity,
    IntegratedString, MakeRange, Position, PositionStatus, Range, Source, SourceManager
}
public import cangjie_compiler::ast.*
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

    public func VectorOffsetElement(vector: Int64, index: Int64): Int64 {
        let pos = vector + 4 + index * 4
        return Indirect(pos)
    }

    public func U64At(pos: Int64): UInt64 {
        return ReadU64(pos)
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
    private let file: File
    private let importedPackages: ArrayList<Package>
    private var flat: Option<CjoFlatBuffer> = None
    private var flatAllDecls: Int64 = -1
    private var flatAllTypes: Int64 = -1
    private var flatImports: Int64 = -1
    private let flatDecls: HashMap<UInt32, CjoFlatDecl> = HashMap<UInt32, CjoFlatDecl>()
    private let flatNominalKinds: HashMap<String, UInt8> = HashMap<String, UInt8>()
    private let flatTypeCache: HashMap<UInt32, Ty> = HashMap<UInt32, Ty>()
    private let flatGenericParamDecls: HashMap<UInt32, GenericParamDecl> = HashMap<UInt32, GenericParamDecl>()

    public init(packageName: String, pkg: Package, file: File, importedPackages: ArrayList<Package>) {
        this.packageName = packageName
        this.pkg = pkg
        this.file = file
        this.importedPackages = importedPackages
    }

    public func Materialize(data: Array<UInt8>): Unit {
        LoadSerializedDeclRecords(data)
        MaterializeSerializedDecls()
        MaterializeSerializedInheritedTypes()
    }

    private func LoadSerializedDeclRecords(data: Array<UInt8>): Unit {
        flat = Some(CjoFlatBuffer(data))
        flatAllDecls = -1
        flatAllTypes = -1
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
        if (decl.IsExportedDecl() || decl.TestAttr(Attribute.FROM_COMMON_PART)) {
            file.decls.add(decl)
            return
        }
        file.exportedInternalDecls.add(decl)
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
        let codegenMangle = FlatCodegenMangle(record)
        decl.mangledName = if (codegenMangle.isEmpty()) { record.mangledName } else { codegenMangle }
        decl.rawMangleName = if (codegenMangle.isEmpty()) { record.mangledBeforeSema } else { codegenMangle }
        decl.fullPackageName = if (record.fullPackageName.isEmpty()) { packageName } else { record.fullPackageName }
        decl.moduleName = RootPackageName(decl.fullPackageName)
        decl.toBeCompiled = false
        ApplyFlatAttributes(reader, record, decl)
        MarkFlatImportedDecl(decl)
        ApplyFlatDeclHash(reader, record, decl)
    }

    private func FlatCodegenMangle(record: CjoFlatDecl): String {
        if (!record.mangledName.isEmpty()) {
            return record.mangledName
        }
        if (record.exportId.startsWith("_C")) {
            return record.exportId
        }
        if (record.mangledBeforeSema.startsWith("_C")) {
            return record.mangledBeforeSema
        }
        return ""
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

    private func MarkFlatImportedDecl(decl: Decl): Unit {
        decl.curFile = Some(file)
        decl.EnableAttr(Attribute.IMPORTED)
        decl.EnableAttr(Attribute.SRC_IMPORTED)
        if (packageName == "std.core") {
            decl.EnableAttr(Attribute.IN_CORE)
        } else if (packageName == "std.ast") {
            decl.EnableAttr(Attribute.IN_MACRO)
        }
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
        let bodyTable = reader.OffsetField(infoTable, 4)
        if (bodyTable < 0) {
            throw IllegalStateException("FlatBuffer FuncDecl '${record.identifier}' has no FuncBody")
        }
        let body = FuncBody()
        LoadFlatFuncParamLists(reader, bodyTable, body)
        if (let Some(retTy) <- LoadFlatType(reader.U32Field(bodyTable, 6, 0u32))) {
            body.retType = Some(TypeNodeForTy(retTy))
        }
        body.captureKind = FlatCaptureKind(reader.U8Field(bodyTable, 12, 0u8))
        body.funcDecl = Some(funcDecl)
        funcDecl.funcBody = Some(body)
        SetFlatGeneric(reader, record, funcDecl)
        if (let Some(funcTy) <- FlatFuncTypeFromBody(reader, bodyTable, body)) {
            body.SetTy(funcTy)
            funcDecl.SetTy(funcTy)
        }
        SetOuterFunctionDecl(funcDecl)
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
    }

    private func LoadFlatVarWithPatternInfo(reader: CjoFlatBuffer, record: CjoFlatDecl,
        varDecl: VarWithPatternDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        if (infoTable < 0) {
            return
        }
        varDecl.isVar = reader.U8Field(infoTable, 4, 0u8) != 0u8
        varDecl.isConst = reader.U8Field(infoTable, 6, 0u8) != 0u8
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

public class ImportManager {
    private let diag: DiagnosticEngine
    private let searchPath: ArrayList<String> = ArrayList<String>()
    private let importedPackages: ArrayList<Package> = ArrayList<Package>()
    private let depPkgCjdPaths: HashMap<String, String> = HashMap<String, String>()
    private let directDependencies: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()

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
        for (pkg in pkgs) {
            let deps = CollectDirectDependencyNames(pkg)
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
        let sourcePackages = HashSet<String>()
        for (pkg in pkgs) {
            if (pkg.fullPackageName.isEmpty()) {
                diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "empty package name")
                return false
            }
            AddImplicitImports(pkg, opts)
            sourcePackages.add(pkg.fullPackageName)
        }
        for (pkg in pkgs) {
            let deps = CollectDirectDependencyNames(pkg)
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
        }
        return LoadResolvedImportedPackages()
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
        if (let Some(pkg) <- GetPackage(targetFullPackageName)) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    if (IsDeclVisibleFrom(srcFullPackageName, decl)) {
                        PutImportedDecl(out, decl.identifier.Val(), decl)
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
        let targetPackageName = if (importSpec.IsImportAll()) {
            importSpec.content.GetPrefixPath()
        } else {
            importSpec.content.GetImportedPackageName()
        }
        if (targetPackageName.isEmpty()) {
            return
        }
        if (let Some(pkg) <- GetPackage(targetPackageName)) {
            if (importSpec.IsImportAll()) {
                for (file in pkg.files) {
                    for (decl in file.decls) {
                        if (IsDeclVisibleFrom(srcFullPackageName, decl)) {
                            AddImportedDeclGroupValue(out, decl.identifier.Val(), decl)
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
                for (file in pkg.files) {
                    for (decl in file.decls) {
                        if (decl.identifier.Val() == importSpec.content.identifier.Val() &&
                            IsDeclVisibleFrom(srcFullPackageName, decl)) {
                            AddImportedDeclGroupValue(out, importedName, decl)
                        }
                    }
                }
            }
        }
    }

    private func IsPackageImport(importSpec: ImportSpec, targetPackageName: String): Bool {
        if (importSpec.IsImportAll()) {
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
        let (ok, data, reason) = FileUtil.ReadBinaryFileToBuffer(cjoPath)
        if (!ok) {
            diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                "failed to load imported package '${fullPackageName}' from '${cjoPath}': ${reason}")
            return false
        }
        let pkg = CreatePackage(fullPackageName)
        pkg.EnableAttr(Attribute.IMPORTED)
        pkg.hasSourceImportedDecl = true
        let file = CreateFile(cjoPath)
        file.curPackage = Some(pkg)
        pkg.files.add(file)
        let materializer = CjoSignatureMaterializer(fullPackageName, pkg, file, importedPackages)
        materializer.Materialize(data)
        AddImportedPackageIfMissing(pkg)
        return true
    }

    private func CollectDirectDependencyNames(pkg: Package): HashSet<String> {
        let deps = HashSet<String>()
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                let depName = NormalizeImportedPackageName(importSpec.content)
                if (!depName.isEmpty() && depName != pkg.fullPackageName) {
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

    private func NormalizeImportedPackageName(content: ImportContent): String {
        if (content.kind == ImportKind.IMPORT_ALL) {
            return content.GetPrefixPath()
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
