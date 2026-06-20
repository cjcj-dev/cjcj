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

private class ParsedType {
    public var ok: Bool = false
    public var ty: Ty = InvalidTy()
    public var next: Int64 = 0

    public init(ok: Bool, ty: Ty, next: Int64) {
        this.ok = ok
        this.ty = ty
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

    public func VectorOffsetElement(vector: Int64, index: Int64): Int64 {
        let pos = vector + 4 + index * 4
        return Indirect(pos)
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
    public let identifier: String
    public let fullPackageName: String
    public let exportId: String
    public let mangledName: String
    public let mangledBeforeSema: String
    public let genericArity: Int64
    public var decl: Option<Decl> = None

    public init(index: UInt32, table: Int64, kind: UInt16, identifier: String, fullPackageName: String,
        exportId: String, mangledName: String, mangledBeforeSema: String, genericArity: Int64) {
        this.index = index
        this.table = table
        this.kind = kind
        this.identifier = identifier
        this.fullPackageName = fullPackageName
        this.exportId = exportId
        this.mangledName = mangledName
        this.mangledBeforeSema = mangledBeforeSema
        this.genericArity = genericArity
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
    private let exportedSymbols: HashSet<String>
    private let nominalDecls: HashMap<String, Decl> = HashMap<String, Decl>()
    private let extendDecls: HashMap<String, ExtendDecl> = HashMap<String, ExtendDecl>()
    private let inferredNominalKinds: HashMap<String, UInt8> = HashMap<String, UInt8>()
    private let inferredGenericNames: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    private let activeGenericParams: ArrayList<GenericParamDecl> = ArrayList<GenericParamDecl>()
    private var flat: Option<CjoFlatBuffer> = None
    private var flatAllDecls: Int64 = -1
    private var flatAllTypes: Int64 = -1
    private var flatImports: Int64 = -1
    private let flatDecls: HashMap<UInt32, CjoFlatDecl> = HashMap<UInt32, CjoFlatDecl>()
    private let flatTypeCache: HashMap<UInt32, Ty> = HashMap<UInt32, Ty>()
    private let flatGenericParamDecls: HashMap<UInt32, GenericParamDecl> = HashMap<UInt32, GenericParamDecl>()

    public init(packageName: String, pkg: Package, file: File, importedPackages: ArrayList<Package>,
        exportedSymbols: HashSet<String>) {
        this.packageName = packageName
        this.pkg = pkg
        this.file = file
        this.importedPackages = importedPackages
        this.exportedSymbols = exportedSymbols
    }

    public func Materialize(strings: ArrayList<String>, data: Array<UInt8>): Unit {
        InferSignatureMetadata(strings)
        var idx: Int64 = 0
        while (idx < strings.size) {
            let signature = strings[idx]
            if (LooksLikePackageSignature(signature)) {
                MaterializeSignature(signature, FindFollowingMangle(strings, idx))
            }
            idx++
        }
        MaterializeSerializedInheritedTypes(data)
    }

    private func InferSignatureMetadata(strings: ArrayList<String>): Unit {
        var idx: Int64 = 0
        while (idx < strings.size) {
            let signature = strings[idx]
            if (LooksLikePackageSignature(signature)) {
                InferSignatureMetadata(signature)
            }
            idx++
        }
    }

    private func InferSignatureMetadata(signature: String): Unit {
        let parsedPackage = ParseLengthText(signature, 0)
        if (!parsedPackage.ok || parsedPackage.text != packageName) {
            return
        }
        let parsedName = ParseLengthText(signature, parsedPackage.next)
        if (!parsedName.ok || parsedName.text.isEmpty()) {
            return
        }
        var pos = parsedName.next
        let genericArity = ParseGenericArity(signature, pos)
        if (genericArity.ok) {
            pos = genericArity.next
        }
        if (pos >= signature.size || !IsNominalKind(signature[pos])) {
            return
        }
        inferredNominalKinds[parsedName.text] = signature[pos]
        if (genericArity.arity <= 0 || inferredGenericNames.contains(parsedName.text)) {
            return
        }
        let names = CollectParentGenericNamesFromMember(signature, pos + 1, genericArity.arity)
        if (names.size == genericArity.arity) {
            inferredGenericNames[parsedName.text] = names
        }
    }

    private func CollectParentGenericNamesFromMember(signature: String, memberStart: Int64,
        genericArity: Int64): ArrayList<String> {
        let empty = ArrayList<String>()
        if (memberStart >= signature.size) {
            return empty
        }
        let parsedMember = ParseLengthText(signature, memberStart)
        if (!parsedMember.ok || parsedMember.text.isEmpty()) {
            return empty
        }
        var pos = parsedMember.next
        let memberGenericArity = ParseGenericArity(signature, pos)
        if (memberGenericArity.ok) {
            pos = memberGenericArity.next
        }
        if (pos < signature.size && signature[pos] == b'<') {
            return empty
        }
        if (memberGenericArity.arity != 0) {
            return empty
        }
        let names = CollectGenericNames(signature, pos, signature.size)
        let out = ArrayList<String>()
        for (name in names) {
            if (!out.contains(name)) {
                out.add(name)
            }
            if (out.size == genericArity) {
                return out
            }
        }
        return empty
    }

    private func LooksLikePackageSignature(signature: String): Bool {
        let parsedPackage = ParseLengthText(signature, 0)
        return parsedPackage.ok && parsedPackage.text == packageName
    }

    private func MaterializeSignature(signature: String, mangle: String): Unit {
        let parsedPackage = ParseLengthText(signature, 0)
        if (!parsedPackage.ok || parsedPackage.text != packageName) {
            return
        }
        let parsedName = ParseLengthText(signature, parsedPackage.next)
        if (!parsedName.ok || parsedName.text.isEmpty()) {
            return
        }
        var pos = parsedName.next
        let genericArity = ParseGenericArity(signature, pos)
        if (genericArity.ok) {
            pos = genericArity.next
        }
        if (pos >= signature.size) {
            return
        }
        if (parsedName.text == "Extend!") {
            MaterializeExtendSignature(signature, pos, mangle)
            return
        }
        let marker = signature[pos]
        if (IsNominalKind(marker)) {
            let nominal = EnsureNominal(parsedName.text, marker, genericArity.arity)
            if (pos + 1 >= signature.size) {
                SetImportedMangle(nominal, mangle)
                return
            }
            let genericMark = PushGenericParams(nominal)
            MaterializeMemberSignature(signature, pos + 1, nominal, mangle)
            RestoreGenericParams(genericMark)
            return
        }
        if (marker == b'F' && genericArity.arity == 0) {
            MaterializeFunction(parsedName.text, signature, pos, mangle, None)
            return
        }
        if (marker == b'P') {
            MaterializePropertyAccessorSignature(parsedName.text, signature, pos, mangle)
        }
    }

    private func MaterializeExtendSignature(signature: String, extendStart: Int64, mangle: String): Unit {
        let memberStart = FindExtendMemberStart(signature, extendStart)
        if (memberStart <= extendStart || memberStart >= signature.size) {
            return
        }
        let headerKey = signature[extendStart..memberStart]
        let extendDecl = EnsureExtendDecl(signature, extendStart, memberStart, headerKey)
        let genericMark = PushGenericParams(extendDecl)
        MaterializeMemberSignature(signature, memberStart, extendDecl, mangle)
        RestoreGenericParams(genericMark)
    }

    private func FindExtendMemberStart(signature: String, extendStart: Int64): Int64 {
        let extended = ParseType(signature, extendStart)
        if (!extended.ok) {
            return -1
        }
        var pos = extended.next
        if (pos + 1 < signature.size && signature[pos] == b'<' && signature[pos + 1] == b':') {
            pos += 2
            while (pos < signature.size && signature[pos] != b'X' && signature[pos] != b'W') {
                if (signature[pos] == b'&') {
                    pos++
                    continue
                }
                let inherited = ParseType(signature, pos)
                if (!inherited.ok || inherited.next <= pos) {
                    break
                }
                pos = inherited.next
            }
        }
        while (pos < signature.size && signature[pos] != b'X') {
            pos++
        }
        if (pos >= signature.size || signature[pos] != b'X') {
            return -1
        }
        return pos + 1
    }

    private func EnsureExtendDecl(signature: String, extendStart: Int64, memberStart: Int64,
        headerKey: String): ExtendDecl {
        if (let Some(existing) <- extendDecls.get(headerKey)) {
            return existing
        }
        let extendDecl = ExtendDecl()
        extendDecl.identifier = SrcIdentifier("Extend!")
        extendDecl.fullPackageName = packageName
        extendDecl.moduleName = RootPackageName(packageName)
        extendDecl.toBeCompiled = false
        extendDecl.rawMangleName = "Extend!" + headerKey
        extendDecl.mangledName = extendDecl.rawMangleName
        MarkImportedDecl(extendDecl)

        AttachGenericNames(extendDecl, CollectGenericNames(signature, extendStart, memberStart))
        let genericMark = PushGenericParams(extendDecl)
        let extended = ParseType(signature, extendStart)
        if (extended.ok) {
            extendDecl.extendedType = Some(TypeNodeForTy(extended.ty))
            extendDecl.SetTy(extended.ty)
            var pos = extended.next
            if (pos + 1 < memberStart && signature[pos] == b'<' && signature[pos + 1] == b':') {
                pos += 2
                while (pos < memberStart && signature[pos] != b'X' && signature[pos] != b'W') {
                    if (signature[pos] == b'&') {
                        pos++
                        continue
                    }
                    let inherited = ParseType(signature, pos)
                    if (!inherited.ok || inherited.next <= pos) {
                        break
                    }
                    extendDecl.inheritedTypes.add(TypeNodeForTy(inherited.ty))
                    pos = inherited.next
                }
            }
        }
        RestoreGenericParams(genericMark)
        extendDecls[headerKey] = extendDecl
        file.decls.add(extendDecl)
        return extendDecl
    }

    private func MaterializeMemberSignature(signature: String, memberStart: Int64, nominal: Decl, mangle: String): Unit {
        if (memberStart >= signature.size) {
            return
        }
        let parsedMember = ParseLengthText(signature, memberStart)
        if (!parsedMember.ok || parsedMember.text.isEmpty()) {
            return
        }
        var pos = parsedMember.next
        let genericArity = ParseGenericArity(signature, pos)
        if (genericArity.ok) {
            pos = genericArity.next
        }
        if (pos >= signature.size || genericArity.arity != 0) {
            return
        }
        if (signature[pos] == b'F') {
            MaterializeFunction(parsedMember.text, signature, pos, mangle, Some(nominal))
            return
        }
        if (signature[pos] == b'V') {
            MaterializeMemberVar(parsedMember.text, signature, pos, mangle, nominal)
            return
        }
        if (signature[pos] == b'P') {
            let _ = EnsureProperty(parsedMember.text, nominal, None, mangle: mangle)
        }
    }

    private func MaterializePropertyAccessorSignature(propName: String, signature: String, propStart: Int64,
        mangle: String): Unit {
        if (MaterializeDirectPropertyAccessorSignature(propName, signature, propStart, mangle)) {
            return
        }
        let ownerStart = propStart + 1
        let memberStart = FindExtendMemberStart(signature, ownerStart)
        if (memberStart <= ownerStart || memberStart >= signature.size) {
            return
        }
        let headerKey = signature[ownerStart..memberStart]
        let extendDecl = EnsureExtendDecl(signature, ownerStart, memberStart, headerKey)
        let genericMark = PushGenericParams(extendDecl)
        MaterializePropertyAccessor(propName, signature, memberStart, mangle, extendDecl)
        RestoreGenericParams(genericMark)
    }

    private func MaterializeDirectPropertyAccessorSignature(propName: String, signature: String, propStart: Int64,
        mangle: String): Bool {
        let ownerStart = propStart + 1
        let parsedOwner = ParseLengthText(signature, ownerStart)
        if (!parsedOwner.ok || parsedOwner.text.isEmpty()) {
            return false
        }
        var pos = parsedOwner.next
        let genericArity = ParseGenericArity(signature, pos)
        if (genericArity.ok) {
            pos = genericArity.next
        }
        if (pos >= signature.size || !IsNominalKind(signature[pos])) {
            return false
        }
        let owner = EnsureNominal(parsedOwner.text, signature[pos], genericArity.arity)
        let genericMark = PushGenericParams(owner)
        MaterializePropertyAccessor(propName, signature, pos + 1, mangle, owner)
        RestoreGenericParams(genericMark)
        return true
    }

    private func MaterializePropertyAccessor(propName: String, signature: String, accessorStart: Int64,
        mangle: String, outer: Decl): Unit {
        let parsedAccessor = ParseLengthText(signature, accessorStart)
        if (!parsedAccessor.ok || parsedAccessor.text != "get") {
            return
        }
        var pos = parsedAccessor.next
        let genericArity = ParseGenericArity(signature, pos)
        if (genericArity.ok) {
            pos = genericArity.next
        }
        if (pos >= signature.size || genericArity.arity != 0 || signature[pos] != b'F') {
            return
        }
        let parsedFunc = ParseFunctionType(signature, pos)
        if (!parsedFunc[0] || !parsedFunc[1].isEmpty()) {
            return
        }
        let propDecl = EnsureProperty(propName, outer, Some(parsedFunc[2]))
        let getter = CreatePropertyGetter(propDecl, parsedFunc[2], mangle)
        if (propDecl.getters.isEmpty()) {
            propDecl.getters.add(getter)
        }
    }

    private func EnsureProperty(name: String, outer: Decl, ty: Option<Ty>, mangle!: String = ""): PropDecl {
        for (member in outer.GetMemberDecls()) {
            if (member.identifier.Val() == name) {
                if (let Some(propDecl) <- (member as PropDecl)) {
                    if (let Some(propTy) <- ty) {
                        propDecl.SetTy(propTy)
                        propDecl.typeNode = Some(TypeNodeForTy(propTy))
                    }
                    if (!mangle.isEmpty() && propDecl.rawMangleName.isEmpty()) {
                        propDecl.rawMangleName = mangle
                        propDecl.mangledName = mangle
                    }
                    return propDecl
                }
            }
        }
        let propDecl = PropDecl()
        propDecl.identifier = SrcIdentifier(name)
        propDecl.toBeCompiled = false
        propDecl.fullPackageName = packageName
        propDecl.moduleName = RootPackageName(packageName)
        propDecl.rawMangleName = mangle
        propDecl.mangledName = mangle
        propDecl.outerDecl = Some(outer)
        if (let Some(propTy2) <- ty) {
            propDecl.SetTy(propTy2)
            propDecl.typeNode = Some(TypeNodeForTy(propTy2))
        }
        MarkImportedDecl(propDecl)
        AddMember(outer, propDecl)
        return propDecl
    }

    private func CreatePropertyGetter(propDecl: PropDecl, retTy: Ty, mangle: String): FuncDecl {
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(CreateFuncParamList(ArrayList<FuncParam>(), None))
        let funcTy = FuncTy(Array<Ty>(), retTy)
        let body = CreateFuncBody(paramLists, Some(TypeNodeForTy(retTy)), None, Some(funcTy))
        let getter = CreateFuncDecl("get", Some(body), Some(funcTy))
        body.funcDecl = Some(getter)
        getter.toBeCompiled = false
        getter.fullPackageName = packageName
        getter.moduleName = RootPackageName(packageName)
        getter.rawMangleName = mangle
        getter.mangledName = mangle
        getter.outerDecl = propDecl.outerDecl
        getter.propDecl = Some(propDecl)
        getter.isGetter = true
        MarkImportedDecl(getter)
        return getter
    }

    private func MaterializeMemberVar(name: String, signature: String, vPos: Int64, mangle: String, outer: Decl): Unit {
        let parsed = ParseVariableType(signature, vPos)
        let isEnumCtor = IsEnumConstructor(outer, name)
        if (!parsed.ok && !isEnumCtor) {
            return
        }
        let varTy = if (parsed.ok) {
            parsed.ty
        } else {
            outer.GetTy() ?? InvalidTy()
        }
        let varDecl = CreateVarDecl(name, None, Some(TypeNodeForTy(varTy)))
        varDecl.SetTy(varTy)
        varDecl.toBeCompiled = false
        varDecl.fullPackageName = packageName
        varDecl.moduleName = RootPackageName(packageName)
        varDecl.rawMangleName = mangle
        varDecl.mangledName = mangle
        varDecl.outerDecl = Some(outer)
        MarkImportedDecl(varDecl)
        if (IsStaticMemberVarMangle(mangle)) {
            varDecl.EnableAttr(Attribute.STATIC)
        }
        if (isEnumCtor) {
            varDecl.EnableAttr(Attribute.ENUM_CONSTRUCTOR)
            if (let Some(enumDecl) <- (outer as EnumDecl)) {
                AddEnumConstructor(enumDecl, varDecl)
            }
            return
        }
        AddMember(outer, varDecl, prepend: true)
    }

    private func IsStaticMemberVarMangle(mangle: String): Bool {
        return !mangle.isEmpty() && !mangle.contains("K_")
    }

    private func IsEnumConstructor(outer: Decl, name: String): Bool {
        if (let None <- (outer as EnumDecl)) {
            return false
        }
        return !name.isEmpty() && name[0] >= b'A' && name[0] <= b'Z'
    }

    private func AddEnumConstructorIfNeeded(outer: Decl, originalName: String, decl: Decl): Bool {
        if (!IsEnumConstructor(outer, originalName)) {
            return false
        }
        decl.EnableAttr(Attribute.ENUM_CONSTRUCTOR)
        if (let Some(enumDecl) <- (outer as EnumDecl)) {
            AddEnumConstructor(enumDecl, decl)
            return true
        }
        return false
    }

    private func AddEnumConstructor(enumDecl: EnumDecl, decl: Decl): Unit {
        if (IsStdCoreOption(enumDecl) && decl.identifier.Val() == "Some") {
            enumDecl.constructors.add(decl, at: 0)
            return
        }
        enumDecl.constructors.add(decl)
    }

    private func IsStdCoreOption(enumDecl: EnumDecl): Bool {
        return enumDecl.fullPackageName == "std.core" && enumDecl.identifier.Val() == "Option"
    }

    private func MaterializeFunction(name: String, signature: String, fPos: Int64, mangle: String,
        outer: Option<Decl>): Unit {
        let parsed = ParseFunctionType(signature, fPos)
        if (!parsed[0]) {
            return
        }
        let paramTys = parsed[1]
        let paramNames = ParseFunctionParamNames(signature, fPos)
        let astName = if (name == "<init>") { "init" } else { name }
        let retTy = if (astName == "init") {
            if (let Some(parentForRet) <- outer) {
                parentForRet.GetTy() ?? parsed[2]
            } else {
                parsed[2]
            }
        } else {
            parsed[2]
        }
        let params = ArrayList<FuncParam>()
        var idx: Int64 = 0
        while (idx < paramTys.size) {
            let paramName = if (idx < paramNames.size && !paramNames[idx].isEmpty()) {
                paramNames[idx]
            } else {
                "p${idx}"
            }
            let param = CreateFuncParam(paramName, Some(TypeNodeForTy(paramTys[idx])), None, Some(paramTys[idx]))
            if (idx < paramNames.size && !paramNames[idx].isEmpty()) {
                param.isNamedParam = true
            }
            param.fullPackageName = packageName
            param.moduleName = RootPackageName(packageName)
            MarkImportedDecl(param)
            params.add(param)
            idx++
        }
        let paramList = CreateFuncParamList(params, None)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(paramList)
        let funcTy = FuncTy(paramTys.toArray(), retTy)
        let body = CreateFuncBody(paramLists, Some(TypeNodeForTy(retTy)), None, Some(funcTy))
        let funcDecl = CreateFuncDecl(astName, Some(body), Some(funcTy))
        body.funcDecl = Some(funcDecl)
        funcDecl.toBeCompiled = false
        funcDecl.fullPackageName = packageName
        funcDecl.moduleName = RootPackageName(packageName)
        funcDecl.rawMangleName = mangle
        funcDecl.mangledName = mangle
        MarkImportedDecl(funcDecl)
        if (ShouldMarkImportedFunctionAbstract(astName, mangle, outer)) {
            funcDecl.EnableAttr(Attribute.ABSTRACT)
        }
        if (let Some(parent) <- outer) {
            funcDecl.outerDecl = Some(parent)
            if (AddEnumConstructorIfNeeded(parent, name, funcDecl)) {
                return
            }
            if (name == "<init>" || name == "init") {
                funcDecl.EnableAttr(Attribute.CONSTRUCTOR)
            } else if (IsFieldOperator(name)) {
                funcDecl.EnableAttr(Attribute.OPERATOR)
                funcDecl.op = OperatorTokenKind(name)
            }
            AddMember(parent, funcDecl)
        } else {
            funcDecl.EnableAttr(Attribute.GLOBAL)
            file.decls.add(funcDecl)
        }
    }

    private func ShouldMarkImportedFunctionAbstract(astName: String, mangle: String, outer: Option<Decl>): Bool {
        if (mangle.isEmpty() || exportedSymbols.isEmpty() || exportedSymbols.contains(mangle) || astName == "init") {
            return false
        }
        if (let Some(parent) <- outer) {
            return parent.astKind == ASTKind.CLASS_DECL || parent.astKind == ASTKind.INTERFACE_DECL
        }
        return false
    }

    private func ParseFunctionType(signature: String, fPos: Int64): (Bool, ArrayList<Ty>, Ty) {
        let params = ArrayList<Ty>()
        var pos = fPos + 1
        while (pos < signature.size) {
            if (pos + 1 < signature.size && signature[pos] == b'$' && signature[pos + 1] == b'$') {
                pos += 2
                let ret = if (pos >= signature.size) {
                    ParsedType(true, PrimitiveTy(TypeKind.TYPE_UNIT), pos)
                } else {
                    ParseType(signature, pos)
                }
                return (ret.ok, params, ret.ty)
            }
            let parsed = ParseType(signature, pos)
            if (!parsed.ok) {
                return (false, params, InvalidTy())
            }
            params.add(parsed.ty)
            pos = SkipParameterName(signature, parsed.next)
        }
        return (false, params, InvalidTy())
    }

    private func ParseFunctionParamNames(signature: String, fPos: Int64): ArrayList<String> {
        let names = ArrayList<String>()
        var pos = fPos + 1
        while (pos < signature.size) {
            if (pos + 1 < signature.size && signature[pos] == b'$' && signature[pos + 1] == b'$') {
                return names
            }
            let parsed = ParseType(signature, pos)
            if (!parsed.ok) {
                return names
            }
            let parsedName = ParseParameterName(signature, parsed.next)
            if (!parsedName.ok) {
                return names
            }
            names.add(parsedName.text)
            pos = parsedName.next
        }
        return names
    }

    private func ParseVariableType(signature: String, vPos: Int64): ParsedType {
        if (vPos >= signature.size || signature[vPos] != b'V') {
            return ParsedType(false, InvalidTy(), vPos)
        }
        var pos = vPos + 1
        if (pos + 1 >= signature.size || signature[pos] != b'$' || signature[pos + 1] != b'$') {
            return ParsedType(false, InvalidTy(), vPos)
        }
        pos += 2
        return ParseType(signature, pos)
    }

    private func ParseType(signature: String, start: Int64): ParsedType {
        if (start >= signature.size) {
            return ParsedType(false, InvalidTy(), start)
        }
        if (start + 1 < signature.size && signature[start] == b'D' && signature[start + 1] == b'h') {
            return ParsedType(true, PrimitiveTy(TypeKind.TYPE_FLOAT16), start + 2)
        }
        let marker = signature[start]
        if (marker >= b'0' && marker <= b'9') {
            let parsedName = ParseLengthText(signature, start)
            if (!parsedName.ok) {
                return ParsedType(false, InvalidTy(), start)
            }
            var pos = parsedName.next
            let typeArgs = ArrayList<Ty>()
            if (pos < signature.size && signature[pos] == b'<') {
                let parsedArgs = ParseTypeArguments(signature, pos)
                if (!parsedArgs[0]) {
                    return ParsedType(false, InvalidTy(), start)
                }
                for (arg in parsedArgs[1]) {
                    typeArgs.add(arg)
                }
                pos = parsedArgs[2]
            }
            return ParsedType(true, TyForNamedType(parsedName.text, typeArgs), pos)
        }
        if (marker == b'u') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_UNIT), start + 1) }
        if (marker == b'a') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_INT8), start + 1) }
        if (marker == b's') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_INT16), start + 1) }
        if (marker == b'i') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_INT32), start + 1) }
        if (marker == b'l') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_INT64), start + 1) }
        if (marker == b'q') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_INT_NATIVE), start + 1) }
        if (marker == b'h') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_UINT8), start + 1) }
        if (marker == b't') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_UINT16), start + 1) }
        if (marker == b'j') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_UINT32), start + 1) }
        if (marker == b'm') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_UINT64), start + 1) }
        if (marker == b'r') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_UINT_NATIVE), start + 1) }
        if (marker == b'b') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_BOOLEAN), start + 1) }
        if (marker == b'c') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_RUNE), start + 1) }
        if (marker == b'f') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_FLOAT32), start + 1) }
        if (marker == b'd') { return ParsedType(true, PrimitiveTy(TypeKind.TYPE_FLOAT64), start + 1) }
        if (marker == b'F') {
            let parsedFunc = ParseFunctionType(signature, start)
            return ParsedType(parsedFunc[0], FuncTy(parsedFunc[1].toArray(), parsedFunc[2]), signature.size)
        }
        return ParsedType(false, InvalidTy(), start)
    }

    private func ParseTypeArguments(signature: String, start: Int64): (Bool, ArrayList<Ty>, Int64) {
        let args = ArrayList<Ty>()
        var pos = start + 1
        while (pos < signature.size && signature[pos] != b'>') {
            let parsed = ParseType(signature, pos)
            if (!parsed.ok) {
                return (false, args, start)
            }
            args.add(parsed.ty)
            pos = parsed.next
        }
        if (pos >= signature.size || signature[pos] != b'>') {
            return (false, args, start)
        }
        return (true, args, pos + 1)
    }

    private func TyForNamedType(name: String, typeArgs: ArrayList<Ty>): Ty {
        if (name == "Byte") {
            return PrimitiveTy(TypeKind.TYPE_UINT8)
        }
        if (name == "RawArray") {
            let elemTy = if (typeArgs.isEmpty()) { AnyTy() } else { typeArgs[0] }
            return ArrayTy(elemTy, 1u64)
        }
        if (name == "CPointer") {
            let elemTy2 = if (typeArgs.isEmpty()) { AnyTy() } else { typeArgs[0] }
            return PointerTy(elemTy2)
        }
        if (name.size == 1 && name[0] >= b'A' && name[0] <= b'Z') {
            if (let Some(genericTy) <- LookupActiveGenericTy(name)) {
                return genericTy
            }
            return AnyTy()
        }
        if (!inferredNominalKinds.contains(name)) {
            if (let Some(importedNominal) <- FindImportedNominal(name, typeArgs.size)) {
                return TyForNominalDecl(importedNominal, name, typeArgs)
            }
        }
        let nominalKind = inferredNominalKinds.get(name) ?? NominalKindForName(name)
        let nominal = EnsureNominal(name, nominalKind, typeArgs.size)
        return TyForNominalDecl(nominal, name, typeArgs)
    }

    private func TyForNominalDecl(nominal: Decl, name: String, typeArgs: ArrayList<Ty>): Ty {
        if (let Some(structDecl) <- (nominal as StructDecl)) {
            return StructTy(name, structDecl, typeArgs.toArray())
        }
        if (let Some(classDecl) <- (nominal as ClassDecl)) {
            return ClassTy(name, classDecl, typeArgs.toArray())
        }
        if (let Some(enumDecl) <- (nominal as EnumDecl)) {
            return EnumTy(name, enumDecl, typeArgs.toArray())
        }
        if (let Some(interfaceDecl) <- (nominal as InterfaceDecl)) {
            return InterfaceTy(name, interfaceDecl, typeArgs.toArray())
        }
        return InvalidTy()
    }

    private func FindImportedNominal(name: String, genericArity: Int64): Option<Decl> {
        for (importedPackage in importedPackages) {
            if (importedPackage.fullPackageName == packageName) {
                continue
            }
            for (importedFile in importedPackage.files) {
                for (decl in importedFile.decls) {
                    if (decl.identifier.Val() == name && decl.IsNominalDecl() &&
                        ImportedGenericArityMatches(decl, genericArity)) {
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

    private func LookupActiveGenericTy(name: String): Option<Ty> {
        var idx = activeGenericParams.size - 1
        while (idx >= 0) {
            let param = activeGenericParams[idx]
            if (param.identifier.Val() == name) {
                return Some(param.GetTy() ?? GenericsTy(name, param))
            }
            idx--
        }
        return None
    }

    private func PushGenericParams(decl: Decl): Int64 {
        let mark = activeGenericParams.size
        if (let Some(generic) <- decl.generic) {
            for (param in generic.typeParameters) {
                activeGenericParams.add(param)
            }
        }
        return mark
    }

    private func RestoreGenericParams(mark: Int64): Unit {
        while (activeGenericParams.size > mark) {
            activeGenericParams.remove(at: activeGenericParams.size - 1)
        }
    }

    private func EnsureNominal(name: String, kind: UInt8, genericArity: Int64): Decl {
        if (let Some(existing) <- nominalDecls.get(name)) {
            if (NominalKindOfDecl(existing) == kind) {
                EnsureGenericShape(existing, genericArity)
                return existing
            }
            RemoveTopLevelDecl(existing)
        }
        let decl = CreateNominalDecl(kind)
        decl.identifier = SrcIdentifier(name)
        decl.fullPackageName = packageName
        decl.moduleName = RootPackageName(packageName)
        decl.toBeCompiled = false
        MarkImportedDecl(decl)
        if (genericArity > 0) {
            AttachGeneric(decl, genericArity)
        }
        SetNominalTy(decl, name)
        nominalDecls[name] = decl
        file.decls.add(decl)
        return decl
    }

    private func MaterializeSerializedInheritedTypes(data: Array<UInt8>): Unit {
        flat = Some(CjoFlatBuffer(data))
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
        flatDecls.clear()
        flatTypeCache.clear()
        flatGenericParamDecls.clear()
        let declCount = reader.VectorLength(flatAllDecls)
        var idx: Int64 = 0
        while (idx < declCount) {
            let declTable = reader.VectorOffsetElement(flatAllDecls, idx)
            if (declTable >= 0) {
                let record = CreateFlatDeclRecord(reader, declTable, UInt32(idx + 1))
                flatDecls[record.index] = record
            }
            idx++
        }
        idx = 0
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
            reader.StringField(declTable, 18),
            reader.StringField(declTable, 8),
            reader.StringField(declTable, 30),
            reader.StringField(declTable, 28),
            reader.StringField(declTable, 32),
            genericArity
        )
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

    private func FlatNominalKind(kind: UInt16): UInt8 {
        if (kind == 1u16) { return b'C' }
        if (kind == 2u16) { return b'I' }
        if (kind == 8u16) { return b'S' }
        if (kind == 9u16) { return b'U' }
        return b'S'
    }

    private func EnsureFlatDecl(record: CjoFlatDecl): Option<Decl> {
        if (let Some(existing) <- record.decl) {
            return Some(existing)
        }
        if (record.kind == 12u16) {
            if (let Some(param) <- flatGenericParamDecls.get(record.index)) {
                record.decl = Some(param)
                return Some(param)
            }
            let paramDecl = GenericParamDecl()
            paramDecl.identifier = SrcIdentifier(record.identifier)
            paramDecl.fullPackageName = if (record.fullPackageName.isEmpty()) { packageName } else { record.fullPackageName }
            paramDecl.moduleName = RootPackageName(paramDecl.fullPackageName)
            paramDecl.toBeCompiled = false
            paramDecl.exportId = record.exportId
            MarkImportedDecl(paramDecl)
            paramDecl.SetTy(GenericsTy(record.identifier, paramDecl))
            flatGenericParamDecls[record.index] = paramDecl
            record.decl = Some(paramDecl)
            return Some(paramDecl)
        }
        if (record.kind == 1u16 || record.kind == 2u16 || record.kind == 8u16 || record.kind == 9u16) {
            let decl = EnsureNominal(record.identifier, FlatNominalKind(record.kind), record.genericArity)
            if (!record.exportId.isEmpty()) {
                decl.exportId = record.exportId
            }
            if (decl.rawMangleName.isEmpty() && !record.mangledName.isEmpty()) {
                SetImportedMangle(decl, record.mangledName)
            }
            record.decl = Some(decl)
            return Some(decl)
        }
        return None
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
                return Some(paramDecl.GetTy() ?? GenericsTy(paramDecl.identifier.Val(), paramDecl))
            }
        }
        return Some(InvalidTy())
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

    private func SetImportedMangle(decl: Decl, mangle: String): Unit {
        if (mangle.isEmpty()) {
            return
        }
        decl.rawMangleName = mangle
        decl.mangledName = mangle
    }

    private func EnsureGenericShape(decl: Decl, genericArity: Int64): Unit {
        if (genericArity <= 0) {
            return
        }
        if (let Some(generic) <- decl.generic) {
            if (generic.typeParameters.size == genericArity) {
                return
            }
        }
        AttachGeneric(decl, genericArity)
        SetNominalTy(decl, decl.identifier.Val())
    }

    private func CreateNominalDecl(kind: UInt8): Decl {
        if (kind == b'C') {
            let classDecl = ClassDecl()
            classDecl.body = Some(ClassBody())
            return classDecl
        }
        if (kind == b'U') {
            return EnumDecl()
        }
        if (kind == b'I') {
            let interfaceDecl = InterfaceDecl()
            interfaceDecl.body = Some(InterfaceBody())
            return interfaceDecl
        }
        let structDecl = StructDecl()
        structDecl.body = Some(StructBody())
        return structDecl
    }

    private func NominalKindOfDecl(decl: Decl): UInt8 {
        if (let Some(_) <- (decl as ClassDecl)) { return b'C' }
        if (let Some(_) <- (decl as EnumDecl)) { return b'U' }
        if (let Some(_) <- (decl as InterfaceDecl)) { return b'I' }
        return b'S'
    }

    private func RemoveTopLevelDecl(decl: Decl): Unit {
        var idx: Int64 = 0
        while (idx < file.decls.size) {
            if (SameDecl(file.decls[idx], decl)) {
                file.decls.remove(at: idx)
                return
            }
            idx++
        }
    }

    private func AttachGeneric(decl: Decl, genericArity: Int64): Unit {
        let names = ArrayList<String>()
        if (let Some(inferred) <- inferredGenericNames.get(decl.identifier.Val())) {
            if (inferred.size == genericArity) {
                for (name in inferred) {
                    names.add(name)
                }
            }
        }
        if (names.isEmpty()) {
            var idx: Int64 = 0
            while (idx < genericArity) {
                names.add(if (idx == 0) { "T" } else { "T${idx}" })
                idx++
            }
        }
        AttachGenericNames(decl, names)
    }

    private func AttachGenericNames(decl: Decl, names: ArrayList<String>): Unit {
        if (names.isEmpty()) {
            return
        }
        let generic = Generic()
        decl.generic = None
        decl.EnableAttr(Attribute.GENERIC)
        for (idx in 0..names.size) {
            let param = GenericParamDecl()
            param.identifier = SrcIdentifier(names[idx])
            param.fullPackageName = packageName
            param.moduleName = RootPackageName(packageName)
            param.outerDecl = Some(decl)
            MarkImportedDecl(param)
            param.SetTy(GenericsTy(param.identifier.Val(), param))
            generic.typeParameters.add(param)
        }
        decl.generic = Some(generic)
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

    private func MarkImportedDecl(decl: Decl): Unit {
        decl.curFile = Some(file)
        decl.EnableAttr(Attribute.PUBLIC)
        decl.EnableAttr(Attribute.IMPORTED)
        decl.EnableAttr(Attribute.SRC_IMPORTED)
        if (packageName == "std.core") {
            decl.EnableAttr(Attribute.IN_CORE)
        } else if (packageName == "std.ast") {
            decl.EnableAttr(Attribute.IN_MACRO)
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

    private func SkipParameterName(signature: String, start: Int64): Int64 {
        let parsedName = ParseParameterName(signature, start)
        return if (parsedName.ok) { parsedName.next } else { start }
    }

    private func ParseParameterName(signature: String, start: Int64): ParsedText {
        if (start >= signature.size || signature[start] != b'!') {
            return ParsedText(true, "", start)
        }
        let parsedName = ParseLengthText(signature, start + 1)
        if (!parsedName.ok) {
            return ParsedText(false, "", start)
        }
        var pos = parsedName.next
        if (pos < signature.size && signature[pos] == b'=') {
            pos++
        }
        return ParsedText(true, parsedName.text, pos)
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

    private func CollectGenericNames(signature: String, start: Int64, end: Int64): ArrayList<String> {
        let names = ArrayList<String>()
        var pos = start
        while (pos < end) {
            let parsed = ParseLengthText(signature, pos)
            if (parsed.ok) {
                if (parsed.text.size == 1 && parsed.text[0] >= b'A' && parsed.text[0] <= b'Z') {
                    var seen = false
                    for (name in names) {
                        if (name == parsed.text) {
                            seen = true
                            break
                        }
                    }
                    if (!seen) {
                        names.add(parsed.text)
                    }
                }
                pos = parsed.next
            } else {
                pos++
            }
        }
        return names
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

    private func FindFollowingMangle(strings: ArrayList<String>, index: Int64): String {
        var idx = index + 1
        let limit = if (index + 8 < strings.size) { index + 8 } else { strings.size }
        while (idx < limit) {
            if (strings[idx].startsWith("_CN")) {
                return strings[idx]
            }
            idx++
        }
        idx = index + 1
        while (idx < limit) {
            if (strings[idx].startsWith("_C")) {
                return strings[idx]
            }
            idx++
        }
        return ""
    }

    private func IsNominalKind(kind: UInt8): Bool {
        return kind == b'C' || kind == b'S' || kind == b'U' || kind == b'I' || kind == b'T'
    }

    private func NominalKindForName(name: String): UInt8 {
        if (name == "Option" || name == "Ordering" || name.endsWith("State")) {
            return b'U'
        }
        if (name == "Collection" || name == "Iterable" || name == "Iterator" ||
            name == "Equatable" || name == "Comparable" || name == "Hashable" ||
            name == "Countable" || name == "ToString") {
            return b'I'
        }
        if (name == "Object") {
            return b'C'
        }
        return b'S'
    }

    private func IsFieldOperator(field: String): Bool {
        return field == "+" || field == "-" || field == "*" || field == "/" || field == "%" ||
            field == "==" || field == "!=" || field == "<" || field == "<=" || field == ">" ||
            field == ">=" || field == "[]" || field == "()" || field == "**"
    }

    private func OperatorTokenKind(field: String): TokenKind {
        if (field == "+") { return TokenKind.ADD }
        if (field == "-") { return TokenKind.SUB }
        if (field == "*") { return TokenKind.MUL }
        if (field == "/") { return TokenKind.DIV }
        if (field == "%") { return TokenKind.MOD }
        if (field == "==") { return TokenKind.EQUAL }
        if (field == "!=") { return TokenKind.NOTEQ }
        if (field == "<") { return TokenKind.LT }
        if (field == "<=") { return TokenKind.LE }
        if (field == ">") { return TokenKind.GT }
        if (field == ">=") { return TokenKind.GE }
        if (field == "**") { return TokenKind.EXP }
        return TokenKind.ILLEGAL
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
        let materializer = CjoSignatureMaterializer(fullPackageName, pkg, file, importedPackages,
            LoadExportedSymbolsForCjo(fullPackageName, cjoPath))
        materializer.Materialize(ExtractPrintableStrings(data), data)
        AddImportedPackageIfMissing(pkg)
        return true
    }

    private func LoadExportedSymbolsForCjo(fullPackageName: String, cjoPath: String): HashSet<String> {
        let out = HashSet<String>()
        let archivePath = StaticArchivePathForCjo(fullPackageName, cjoPath)
        if (archivePath.isEmpty()) {
            return out
        }
        let (ok, data, _) = FileUtil.ReadBinaryFileToBuffer(archivePath)
        if (!ok) {
            return out
        }
        var builder = StringBuilder()
        for (byte in data) {
            if (byte >= 0x20u8 && byte <= 0x7eu8) {
                builder.append(String.fromUtf8([byte]))
            } else {
                AddExportedSymbolString(out, builder.toString())
                builder = StringBuilder()
            }
        }
        AddExportedSymbolString(out, builder.toString())
        return out
    }

    private func AddExportedSymbolString(out: HashSet<String>, value: String): Unit {
        if (value.startsWith("_C")) {
            out.add(value)
        }
    }

    private func StaticArchivePathForCjo(fullPackageName: String, cjoPath: String): String {
        let modulesMarker = "/modules/"
        let markerPos = cjoPath.indexOf(modulesMarker) ?? return ""
        let targetStart = markerPos + modulesMarker.size
        let targetEnd = cjoPath.indexOf("/", targetStart) ?? return ""
        let home = cjoPath[0..markerPos]
        let targetName = cjoPath[targetStart..targetEnd]
        let libName = "libcangjie-" + ArchivePackageName(fullPackageName) + ".a"
        return FileUtil.JoinPath(FileUtil.JoinPath(FileUtil.JoinPath(home, "lib"), targetName), libName)
    }

    private func ArchivePackageName(fullPackageName: String): String {
        let parts = fullPackageName.split(".")
        if (parts.isEmpty()) {
            return fullPackageName
        }
        let builder = StringBuilder()
        builder.append(parts[0])
        if (parts.size > 1) {
            builder.append("-")
            var idx: Int64 = 1
            while (idx < parts.size) {
                if (idx > 1) {
                    builder.append(".")
                }
                builder.append(parts[idx])
                idx++
            }
        }
        return builder.toString()
    }

    private func ExtractPrintableStrings(data: Array<UInt8>): ArrayList<String> {
        let out = ArrayList<String>()
        var builder = StringBuilder()
        for (byte in data) {
            if (byte >= 0x20u8 && byte <= 0x7eu8) {
                builder.append(String.fromUtf8([byte]))
            } else {
                if (builder.toString().size >= 4) {
                    out.add(builder.toString())
                }
                builder = StringBuilder()
            }
        }
        if (builder.toString().size >= 4) {
            out.add(builder.toString())
        }
        return out
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
