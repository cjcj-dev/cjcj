package cjcj::frontend

public import cjcj::basic.{
    BEGIN_POSITION, CANGJIE_VERSION, DEFAULT_POSITION, INVALID_POSITION, DiagCategory, DiagColor, DiagKindRefactor,
    DiagHelp, DiagSeverity, DiagnosticBuilder, IntegratedString, MakeRange, Position, PositionStatus, Range, Source,
    SourceManager
}
public import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.StringConvertor
import cjcj::flatbuffers.{FlatBufferString, Vector}
import cjcj::basic.Diagnostic as BasicDiagnostic
import cjcj::basic.DiagFormat as BasicDiagFormat
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.FaithfulUnorderedMap
import cjcj::basic.Range as BasicRange
import cjcj::chir.CHIRContext as RealCHIRContext
import cjcj::chir.Function as RealCHIRFunction
import cjcj::chir.Package as RealCHIRPackage
import cjcj::modules.SemaCjoManager
import cjcj::modules.SemaImportManager
import cjcj::modules.MacroHostImportManager
import cjcj::modules.{GetPackage, PackageFormat_AliasInfo, PackageFormat_Anno, PackageFormat_ArrayInfo,
    PackageFormat_ArrayTyInfo, PackageFormat_ClassInfo, PackageFormat_CompositeTyInfo, PackageFormat_Constraint,
    PackageFormat_Decl, PackageFormat_EnumInfo, PackageFormat_Expr, PackageFormat_ExtendInfo,
    PackageFormat_ForInInfo, PackageFormat_FullId, PackageFormat_FuncBody, PackageFormat_FuncInfo,
    PackageFormat_FuncParamList,
    PackageFormat_FuncTyInfo, PackageFormat_Generic, PackageFormat_GenericTyInfo, PackageFormat_InterfaceInfo,
    PackageFormat_LetPatternDestructorInfo, PackageFormat_MatchCaseInfo, PackageFormat_Package,
    PackageFormat_Pattern, PackageFormat_Position, PackageFormat_ReferenceInfo, PackageFormat_SemaTy,
    PackageFormat_StructInfo, PackageFormat_TryInfo, PackageFormat_VarWithPatternInfo,
    MF_DECL_KIND_CLASS_DECL, MF_DECL_KIND_ENUM_DECL, MF_DECL_KIND_EXTEND_DECL, MF_DECL_KIND_FUNC_DECL,
    MF_DECL_KIND_FUNC_PARAM, MF_DECL_KIND_INTERFACE_DECL, MF_DECL_KIND_PROP_DECL, MF_DECL_KIND_STRUCT_DECL,
    MF_DECL_KIND_TYPE_ALIAS_DECL, MF_DECL_KIND_VAR_DECL, MF_DECL_KIND_VAR_WITH_PATTERN_DECL,
    MF_EXPR_KIND_ARRAY_EXPR, MF_EXPR_KIND_ARRAY_LIT, MF_EXPR_KIND_CALL_EXPR, MF_EXPR_KIND_FOR_IN_EXPR,
    MF_EXPR_KIND_JUMP_EXPR, MF_EXPR_KIND_LAMBDA_EXPR, MF_EXPR_KIND_LET_PATTERN_DESTRUCTOR,
    MF_EXPR_KIND_LIT_CONST_EXPR, MF_EXPR_KIND_MATCH_EXPR, MF_EXPR_KIND_MEMBER_ACCESS, MF_EXPR_KIND_REF_EXPR,
    MF_EXPR_KIND_TRY_EXPR, MF_PATTERN_KIND_COMMAND_TYPE_PATTERN, MF_PATTERN_KIND_ENUM_PATTERN,
    MF_PATTERN_KIND_EXCEPT_TYPE_PATTERN, MF_PATTERN_KIND_TUPLE_PATTERN, MF_PATTERN_KIND_TYPE_PATTERN,
    MF_TYPE_KIND_ARRAY, MF_TYPE_KIND_BOOL, MF_TYPE_KIND_CLASS, MF_TYPE_KIND_C_POINTER, MF_TYPE_KIND_C_STRING,
    MF_TYPE_KIND_ENUM, MF_TYPE_KIND_FLOAT16, MF_TYPE_KIND_FLOAT32, MF_TYPE_KIND_FLOAT64, MF_TYPE_KIND_FUNC,
    MF_TYPE_KIND_GENERIC, MF_TYPE_KIND_INT16, MF_TYPE_KIND_INT32, MF_TYPE_KIND_INT64, MF_TYPE_KIND_INT8,
    MF_TYPE_KIND_INTERFACE, MF_TYPE_KIND_INT_NATIVE, MF_TYPE_KIND_NOTHING, MF_TYPE_KIND_RUNE,
    MF_TYPE_KIND_STRUCT, MF_TYPE_KIND_TUPLE, MF_TYPE_KIND_TYPE, MF_TYPE_KIND_UINT16, MF_TYPE_KIND_UINT32,
    MF_TYPE_KIND_UINT64, MF_TYPE_KIND_UINT8, MF_TYPE_KIND_UINT_NATIVE, MF_TYPE_KIND_UNIT, MF_TYPE_KIND_V_ARRAY}
import cjcj::option.OptimizationLevel
import cjcj::option.enumIndex
public import cjcj::mangle.BaseMangler
import cjcj::sema.TypeManager as FaithfulSemaTypeManager
import cjcj::sema.Test.TestManager as RealTestManager
import cjcj::utils.{AST_PACKAGE_NAME, CORE_PACKAGE_NAME, DynamicCast, EraseIf, JoinStrings, MAIN_INVOKE,
    SERIALIZED_FILE_EXTENSION, SYNC_PACKAGE_NAME, CJC_ASSERT, IncrementalCompilationLogger}
import cjcj::utils.FileUtil
import cjcj::utils.ProfileRecorder
import cjcj::utils.STANDARD_LIBS
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

private func IsAllFuncDecl(results: ArrayList<Decl>): Bool {
    for (decl in results) {
        if (decl.astKind != ASTKind.FUNC_DECL && decl.astKind != ASTKind.MACRO_DECL) {
            return false
        }
    }
    return true
}

private func WarnUselessImport(diag: DiagnosticEngine, importRange: BasicRange, decl: Decl): Unit {
    let name = decl.identifier.Val()
    let builder = diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
        DiagKindRefactor.package_shadowed_import, importRange, arguments: [name])
    builder.AddNote(MakeRange(decl.identifier.Begin(), name), "'" + name + "' is declared here")
    builder.Emit()
}

private func WarnConflictImport(diag: DiagnosticEngine, name: String, current: BasicRange, previous: BasicRange): Unit {
    let builder = diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
        DiagKindRefactor.package_conflict_import, current, arguments: [name])
    builder.AddNote(previous, "The previous was imported here")
    builder.Emit()
}

private func IsSamePosition(pos1: Position, pos2: Position): Bool {
    return pos1 == pos2 && pos1.fileID == pos2.fileID
}

private func DiagForDifferentPackageNames(
    diag: DiagnosticEngine,
    packageNamePosMap: ArrayList<(String, String, Position, Bool)>
): Unit {
    var diagPosition = Position()
    var diagPackageName = ""
    for (item in packageNamePosMap) {
        if (item[3]) {
            diagPosition = item[2]
            diagPackageName = item[0]
            break
        }
    }
    let builder = diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
        DiagKindRefactor.package_multiple_package_declarations, MakeRange(diagPosition, diagPackageName))
    var counter: UInt8 = 0u8
    for (item in packageNamePosMap) {
        if (counter >= 2u8) {
            break
        }
        if (IsSamePosition(diagPosition, item[2])) {
            continue
        }
        if (item[3]) {
            builder.AddNote(MakeRange(item[2], item[0]),
                "another different package declaration '" + item[1] + " package " + item[0] + "'")
        } else {
            builder.AddNote(MakeRange(item[2], ""),
                "another different package declaration 'public package " + DEFAULT_PACKAGE_NAME + "'")
        }
        counter++
    }
    builder.Emit()
}

private func DiagRootPackageModifier(diag: DiagnosticEngine, packageSpec: PackageSpec): Unit {
    let packageRange = MakeRange(packageSpec.packageName.Begin(), packageSpec.packageName.Val())
    let builder = DiagnoseRefactor(diag.AsBasicDiagnosticEngine(),
        DiagKindRefactor.package_root_package_should_be_public, packageSpec, packageRange)
    let packageMsg = "package " + packageSpec.packageName.Val()
    builder.AddNote("default modifier of 'package' is 'public', you can use '" + packageMsg + "' instead")
    builder.Emit()
}

private func IsRootPackage(packageSpec: PackageSpec): Bool {
    if (packageSpec.hasDoubleColon && packageSpec.prefixPaths.size == 1) {
        return true
    }
    return packageSpec.prefixPaths.isEmpty()
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
    private let realImplicitFuncsPerPkg: HashMap<String, HashMap<String, RealCHIRFunction>> =
        HashMap<String, HashMap<String, RealCHIRFunction>>()
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

    public func SetImplicitFuncs(pkg: RealCHIRPackage, funcs: HashMap<String, RealCHIRFunction>): Unit {
        let copy = HashMap<String, RealCHIRFunction>()
        for ((key, value) in funcs) {
            copy.add(key, value)
        }
        realImplicitFuncsPerPkg[pkg.GetName()] = copy
    }

    public func GetImplicitFuncs(pkg: RealCHIRPackage): HashMap<String, RealCHIRFunction> {
        return realImplicitFuncsPerPkg.get(pkg.GetName()) ?? HashMap<String, RealCHIRFunction>()
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

// ReferenceLoader.cpp:25-35 SetFuncParentReference.
private func SetFuncParentReference(funcDecl: FuncDecl, parentDecl: Decl): Unit {
    let body = funcDecl.funcBody.getOrThrow()
    if (parentDecl.IsClassLikeDecl()) {
        body.parentClassLike = Some((parentDecl as ClassLikeDecl).getOrThrow())
    } else if (let Some(structDecl) <- (parentDecl as StructDecl)) {
        body.parentStruct = Some(structDecl)
    } else if (let Some(enumDecl) <- (parentDecl as EnumDecl)) {
        body.parentEnum = Some(enumDecl)
    }
}

// ReferenceLoader.cpp:37-63 SetMemberDeclReference.
private func SetMemberDeclReference(member: Decl, parentDecl: Decl): Unit {
    var parentTypeDecl = parentDecl
    if (let Some(extendDecl) <- (parentDecl as ExtendDecl)) {
        if (let Some(extendedDecl) <- Ty.GetDeclPtrOfTy(extendDecl.GetTy())) {
            parentTypeDecl = extendedDecl
        }
    }
    if (let Some(propDecl) <- (member as PropDecl)) {
        for (getter in propDecl.getters) { SetFuncParentReference(getter, parentTypeDecl) }
        for (setter in propDecl.setters) { SetFuncParentReference(setter, parentTypeDecl) }
    } else if (let Some(funcDecl) <- (member as FuncDecl)) {
        SetFuncParentReference(funcDecl, parentTypeDecl)
        let body = funcDecl.funcBody.getOrThrow()
        if (body.paramLists.isEmpty()) { return }
        for (param in body.paramLists[0].params) {
            if (let Some(desugarDecl) <- param.desugarDecl) {
                SetFuncParentReference(desugarDecl, parentTypeDecl)
            }
        }
    }
}

// ReferenceLoader.cpp:66-109 Wrap2RefType.
private func Wrap2RefType(ty: Ty): Option<RefType> {
    let kind = ty.kind
    if (!(kind == TypeKind.TYPE_ENUM || kind == TypeKind.TYPE_STRUCT || kind == TypeKind.TYPE_ARRAY ||
        kind == TypeKind.TYPE_VARRAY || kind == TypeKind.TYPE_POINTER || kind == TypeKind.TYPE_CSTRING ||
        kind == TypeKind.TYPE_CLASS || kind == TypeKind.TYPE_INTERFACE || kind == TypeKind.TYPE ||
        kind == TypeKind.TYPE_GENERICS || kind == TypeKind.TYPE_NOTHING || kind == TypeKind.TYPE_INVALID)) {
        return None
    }
    var hasTypeAlias = kind == TypeKind.TYPE
    let refType = RefType()
    for (typeArg in ty.typeArgs) {
        let wrapped = WrapType(Some(typeArg)).getOrThrow()
        refType.typeArguments.add(wrapped)
        hasTypeAlias = hasTypeAlias || !Ty.IsInitialTy(wrapped.aliasTy)
    }
    refType.SetTy(ty)
    refType.ref.identifier = SrcIdentifier(ty.name)
    if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
        refType.ref.target = Some(decl)
        refType.ref.identifier = if ((ty as ClassThisTy).isSome()) { SrcIdentifier("This") } else { decl.identifier }
    }
    if (hasTypeAlias) { refType.aliasTy = Some(ty) }
    refType.EnableAttr(Attribute.IMPORTED)
    refType.EnableAttr(Attribute.COMPILER_ADD)
    refType.EnableAttr(Attribute.IS_CHECK_VISITED)
    return Some(refType)
}

// ReferenceLoader.cpp:111-153 WrapType.
private func WrapType(tyOpt: Option<Ty>): Option<Type> {
    let ty = tyOpt ?? return None
    var hasTypeAlias = false
    if (TypeKindIndex(ty.kind) <= TypeKindIndex(TypeKind.TYPE_BOOLEAN) && ty.kind != TypeKind.TYPE_NOTHING) {
        let primitive = PrimitiveType()
        primitive.str = ty.String()
        primitive.SetTy(ty)
        primitive.EnableAttr(Attribute.IMPORTED)
        primitive.EnableAttr(Attribute.COMPILER_ADD)
        primitive.EnableAttr(Attribute.IS_CHECK_VISITED)
        return Some(primitive)
    } else if (let Some(funcTy) <- (ty as FuncTy)) {
        let funcType = FuncType()
        for (paramTy in funcTy.paramTys) {
            let paramType = WrapType(Some(paramTy)).getOrThrow()
            funcType.paramTypes.add(paramType)
            hasTypeAlias = hasTypeAlias || !Ty.IsInitialTy(paramType.aliasTy)
        }
        funcType.SetTy(ty)
        let retType = WrapType(Some(funcTy.retTy)).getOrThrow()
        funcType.retType = Some(retType)
        hasTypeAlias = hasTypeAlias || !Ty.IsInitialTy(retType.aliasTy)
        funcType.EnableAttr(Attribute.IMPORTED)
        funcType.EnableAttr(Attribute.COMPILER_ADD)
        funcType.EnableAttr(Attribute.IS_CHECK_VISITED)
        if (hasTypeAlias) { funcType.aliasTy = Some(ty) }
        return Some(funcType)
    } else if (let Some(tupleTy) <- (ty as TupleTy)) {
        let tupleType = TupleType()
        for (typeArg in tupleTy.typeArgs) {
            let fieldType = WrapType(Some(typeArg)).getOrThrow()
            tupleType.fieldTypes.add(fieldType)
            hasTypeAlias = hasTypeAlias || !Ty.IsInitialTy(fieldType.aliasTy)
        }
        tupleType.SetTy(ty)
        tupleType.EnableAttr(Attribute.IMPORTED)
        tupleType.EnableAttr(Attribute.COMPILER_ADD)
        tupleType.EnableAttr(Attribute.IS_CHECK_VISITED)
        if (hasTypeAlias) { tupleType.aliasTy = Some(ty) }
        return Some(tupleType)
    }
    let refType = Wrap2RefType(ty) ?? return None
    return refType
}

// ReferenceLoader.cpp:155-170 UpdateType.
private func UpdateType(astType: Option<Type>, loadedType: Type): Type {
    let existing = astType ?? return loadedType
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

// ReferenceLoader.cpp:172-201 PostLoadReference.
private func PostLoadReference(expr: Expr): Unit {
    if (let Some(callExpr) <- (expr as CallExpr)) {
        callExpr.resolvedFunction = if (let Some(target) <- callExpr.baseFunc.getOrThrow().GetTarget()) {
            target as FuncDecl
        } else { None }
    } else if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
        for (arg in arrayExpr.args) { arg.SetTy(arg.expr.getOrThrow().GetTy().getOrThrow()) }
    } else if (let Some(pointerExpr) <- (expr as PointerExpr)) {
        if (let Some(arg) <- pointerExpr.arg) { arg.SetTy(arg.expr.getOrThrow().GetTy().getOrThrow()) }
    }
}

// ASTSerializeUtils.h:43-45 package-index sentinels.
private const INVALID_PACKAGE_INDEX: Int32 = -1
private const CURRENT_PKG_INDEX: Int32 = -2
private const PKG_REFERENCE_INDEX: Int32 = -3

// IncrementalLoader.cpp:29-34 IsChangedDeclMayOmitType.
private func IsChangedDeclMayOmitType(decl: Decl): Bool {
    return decl.toBeCompiled && !decl.TestAttr(Attribute.CONSTRUCTOR) &&
        (decl.astKind == ASTKind.FUNC_DECL || decl.astKind == ASTKind.VAR_DECL ||
        decl.TestAttr(Attribute.GENERIC))
}

// IncrementalLoader.cpp:36-39 DoNotLoadCache.
private func DoNotLoadCache(decl: Decl): Bool {
    return decl.astKind == ASTKind.PRIMARY_CTOR_DECL || decl.astKind == ASTKind.TYPE_ALIAS_DECL ||
        decl.astKind == ASTKind.FUNC_PARAM
}

// IncrementalLoader.cpp:139-145 CollectRemovedDecl.
private func CollectRemovedDecl(mangledName: String, needRemoved: HashSet<String>): Unit {
    needRemoved.add(mangledName)
    if (IncrementalCompilationLogger.GetInstance().IsEnable()) {
        IncrementalCompilationLogger.GetInstance().LogLn(
            "[CollectRemovedDecl] removed mangled: " + mangledName)
    }
}

private class CjoSignatureMaterializer {
    private let packageName: String
    private var pkg: Package
    private var filesByIndex: HashMap<UInt32, File>
    private var allFileIds: Array<UInt64> = Array<UInt64>()
    private var idToFileMap: HashMap<UInt64, File>
    private let importedPackages: ArrayList<Package>
    private let importedFullPackageNames: ArrayList<String> = ArrayList<String>()
    private let packageDecls: HashMap<String, PackageDecl>
    private let exportIdDeclMaps: HashMap<String, HashMap<String, Decl>>
    private let diag: DiagnosticEngine
    private var flat: Option<CjoFlatBuffer> = None
    private var flatAllDecls: Int64 = -1
    private var flatAllTypes: Int64 = -1
    private var flatAllExprs: Int64 = -1
    private var flatImports: Int64 = -1
    private var data: Option<Array<UInt8>> = None
    private var packageTable: Option<PackageFormat_Package> = None
    private var allTypes: Array<Option<Ty>> = Array<Option<Ty>>()
    private let typeManager: FaithfulSemaTypeManager
    private let tyLoaderMap: HashMap<UInt16, (UInt32, PackageFormat_SemaTy) -> Unit> =
        HashMap<UInt16, (UInt32, PackageFormat_SemaTy) -> Unit>()
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
    private var isLoadCache: Bool
    private var isChirNow: Bool = false

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
        InitializeTypeLoader()
    }

    public func Materialize(data: Array<UInt8>): Unit {
        let _ = LoadPackageDependencies(data)
        LoadPackageDecls()
        LoadRefs()
    }

    public func LoadPackageDependencies(newData: Array<UInt8>): Bool {
        data = Some(newData)
        packageTable = Some(GetPackage(newData))
        let allTypeTables = packageTable.getOrThrow().GetAllTypes().getOrThrow()
        allTypes = Array<Option<Ty>>(Int64(allTypeTables.size()), repeat: None)
        importedFullPackageNames.clear()
        let importTables = packageTable.getOrThrow().GetImports().getOrThrow()
        var importIndex: UInt32 = 0u32
        while (importIndex < importTables.size()) {
            importedFullPackageNames.add(
                FlatBufferString(newData, (importTables.Get(importIndex) as Int64).getOrThrow()).str())
            importIndex++
        }
        PreLoadImportedPackageNode(newData)
        return flatAllTypes >= 0 && flatAllDecls >= 0
    }

    public func LoadPackageDecls(): Unit {
        LoadSerializedDeclRecords()
        MaterializeSerializedDecls()
    }

    public func LoadRefs(): Unit {
        let _ = packageTable.getOrThrow()
        for ((index, decl) in allLoadedDecls) {
            let declObj = GetFormatDeclByIndex(index)
            LoadDeclRefs(declObj, decl)
            LoadDeclDependencies(declObj, decl)
        }
        for ((index, expr) in allLoadedExprs) {
            LoadExprRefs(GetFormatExprByIndex(index), expr)
        }
        for (dummy in allDummyExprs) {
            let dummyExpr = (dummy as Expr).getOrThrow()
            dummyExpr.SetTy(dummyExpr.desugarExpr.getOrThrow().GetTy().getOrThrow())
        }
        for ((_, expr) in allLoadedExprs) { PostLoadReference(expr) }
    }

    // ASTLoader.cpp:207-220 VerifyForData.
    private func VerifyForData(id: String): Bool {
        let rawData = data ?? Array<UInt8>()
        if (!CjoFlatBuffer(rawData).VerifyPackageBuffer()) {
            diag.DiagnoseRefactor(DiagKindRefactor.module_loaded_ast_failed, DEFAULT_POSITION,
                arguments: [id, packageName, CANGJIE_VERSION])
            return false
        }
        return true
    }

    // ASTLoaderImpl.h:173-180 GetAttributes.
    private func GetAttributes(decl: PackageFormat_Decl): AttributePack {
        let attrs = AttributePack()
        let rawAttrs = decl.GetAttributes().getOrThrow()
        var wordIndex: UInt32 = 0u32
        while (wordIndex < rawAttrs.size()) {
            let word = (rawAttrs.Get(wordIndex) as UInt64).getOrThrow()
            var bit: Int64 = 0
            while (bit < 64) {
                if ((word & (1u64 << UInt64(bit))) != 0u64) {
                    if (let Some(attr) <- FlatAttributeByIndex(Int64(wordIndex) * 64 + bit)) {
                        attrs.SetAttr(attr, true)
                    }
                }
                bit++
            }
            wordIndex++
        }
        return attrs
    }

    // ASTLoaderImpl.h:228 LoadDecl.
    private func LoadDecl(declIndex: UInt32): Option<Decl> {
        if (let Some(loaded) <- allLoadedDecls.get(declIndex)) {
            return Some(loaded)
        }
        if (let Some(record) <- flatDecls.get(declIndex)) {
            return EnsureFlatDecl(record)
        }
        return None
    }

    // IncrementalLoader.cpp:49-98 LoadCachedTypeForDecl.
    private func LoadCachedTypeForDecl(decl: PackageFormat_Decl, astDecl: Decl): Unit {
        astDecl.exportId = decl.GetExportId().getOrThrow().str()
        astDecl.mangledName = decl.GetMangledName().getOrThrow().str()
        AddDeclToImportedPackage(astDecl)
        if (let Some(funcDecl) <- (astDecl as FuncDecl)) {
            if (let Some(funcBody) <- funcDecl.funcBody) {
                if (!funcBody.paramLists.isEmpty()) {
                    let info = decl.GetInfoAsFuncInfo().getOrThrow()
                    let rawParamLists = info.GetFuncBody().getOrThrow().GetParamLists().getOrThrow()
                    let paramList = PackageFormat_FuncParamList(data.getOrThrow(),
                        (rawParamLists.Get(0u32) as Int64).getOrThrow())
                    let params = paramList.GetParams().getOrThrow()
                    let length = params.size()
                    CJC_ASSERT(UInt32(funcBody.paramLists[0].params.size) == length)
                    var offset: UInt32 = 0u32
                    while (offset < length) {
                        let index = (params.Get(offset) as UInt32).getOrThrow()
                        if (!allLoadedDecls.contains(index)) {
                            allLoadedDecls.add(index, funcBody.paramLists[0].params[Int64(offset)])
                        }
                        offset++
                    }
                }
            }
        }
        if (!astDecl.toBeCompiled && GetAttributes(decl).TestAttr(Attribute.IS_ANNOTATION)) {
            astDecl.EnableAttr(Attribute.IS_ANNOTATION)
            var found: Option<Annotation> = None
            for (annotation in astDecl.annotations) {
                if (annotation.kind == AstAnnotationKind.ANNOTATION) {
                    found = Some(annotation)
                    break
                }
            }
            CJC_ASSERT(found.isSome())
            let info = decl.GetInfoAsClassInfo().getOrThrow()
            let annotation = found.getOrThrow()
            annotation.target = UInt16(info.GetAnnoTargets())
            annotation.runtimeVisible = info.GetRuntimeVisible()
        }
        if (let Some(generic) <- astDecl.GetGeneric()) {
            if (let Some(genericIndex) <- decl.GetGeneric()) {
                generic.EnableAttr(Attribute.INCRE_COMPILE)
                let typeParameters = genericIndex.GetTypeParameters().getOrThrow()
                let length = typeParameters.size()
                CJC_ASSERT(UInt32(generic.typeParameters.size) == length)
                var index: UInt32 = 0u32
                while (index < length) {
                    let genericParamIndex = (typeParameters.Get(index) as UInt32).getOrThrow()
                    CJC_ASSERT(genericParamIndex != 0u32)
                    let genericParamDecl = generic.typeParameters[Int64(index)]
                    genericParamDecl.exportId =
                        GetFormatDeclByIndex(genericParamIndex).GetExportId().getOrThrow().str()
                    genericParamDecl.outerDecl = Some(astDecl)
                    AddDeclToImportedPackage(genericParamDecl)
                    if (!allLoadedDecls.contains(genericParamIndex)) {
                        allLoadedDecls.add(genericParamIndex, genericParamDecl)
                    }
                    index++
                }
            }
        }
    }

    // IncrementalLoader.cpp:100-114 PrepareForLoadTypeCache.
    private func PrepareForLoadTypeCache(sourcePackage: Package): Unit {
        let cachedPackage = packageTable.getOrThrow()
        let imports = cachedPackage.GetImports().getOrThrow()
        var importIndex: UInt32 = 0u32
        while (importIndex < imports.size()) {
            importedFullPackageNames.add(FlatBufferString(data.getOrThrow(),
                (imports.Get(importIndex) as Int64).getOrThrow()).str())
            importIndex++
        }
        var fileCount = sourcePackage.files.size
        let cachedFileCount = Int64(cachedPackage.GetAllFiles().getOrThrow().size())
        if (cachedFileCount > fileCount) {
            fileCount = cachedFileCount
        }
        allFileIds = Array<UInt64>(fileCount, repeat: 0u64)
        var fileIndex: Int64 = 0
        while (fileIndex < sourcePackage.files.size) {
            allFileIds[fileIndex] = sourcePackage.files[fileIndex].begin.fileID
            fileIndex++
        }
    }

    // IncrementalLoader.cpp:116-136 CollectRemovedDefaultImpl.
    private func CollectRemovedDefaultImpl(astDecl: Decl, decl: PackageFormat_Decl,
        needRemoved: HashSet<String>): Unit {
        let body: Option<Vector<UInt32>> = if (astDecl.astKind == ASTKind.CLASS_DECL) {
            decl.GetInfoAsClassInfo().getOrThrow().GetBody()
        } else if (astDecl.astKind == ASTKind.INTERFACE_DECL) {
            decl.GetInfoAsInterfaceInfo().getOrThrow().GetBody()
        } else if (astDecl.astKind == ASTKind.ENUM_DECL) {
            decl.GetInfoAsEnumInfo().getOrThrow().GetBody()
        } else if (astDecl.astKind == ASTKind.STRUCT_DECL) {
            decl.GetInfoAsStructInfo().getOrThrow().GetBody()
        } else if (astDecl.astKind == ASTKind.EXTEND_DECL) {
            decl.GetInfoAsExtendInfo().getOrThrow().GetBody()
        } else {
            None
        }
        if (!astDecl.toBeCompiled || body.isNone()) {
            return
        }
        let members = body.getOrThrow()
        var offset: UInt32 = 0u32
        while (offset < members.size()) {
            let member = GetFormatDeclByIndex((members.Get(offset) as UInt32).getOrThrow())
            if (member.GetMangledBeforeSema().getOrThrow().str().isEmpty() &&
                GetAttributes(member).TestAttr(Attribute.DEFAULT)) {
                CollectRemovedDecls(member, needRemoved)
            }
            offset++
        }
    }

    // IncrementalLoader.cpp:148-205 CollectRemovedDecls.
    private func CollectRemovedDecls(decl: PackageFormat_Decl, needRemoved: HashSet<String>): Unit {
        if (decl.GetKind() == MF_DECL_KIND_FUNC_DECL) {
            CollectRemovedDecl(decl.GetMangledName().getOrThrow().str(), needRemoved)
            let info = decl.GetInfoAsFuncInfo().getOrThrow()
            let paramLists = info.GetFuncBody().getOrThrow().GetParamLists().getOrThrow()
            var paramListIndex: UInt32 = 0u32
            while (paramListIndex < paramLists.size()) {
                let paramList = PackageFormat_FuncParamList(data.getOrThrow(),
                    (paramLists.Get(paramListIndex) as Int64).getOrThrow())
                let desugars = paramList.GetDesugars().getOrThrow()
                var desugarOffset: UInt32 = 0u32
                while (desugarOffset < desugars.size()) {
                    let desugarIndex = (desugars.Get(desugarOffset) as UInt32).getOrThrow()
                    if (desugarIndex != 0u32) {
                        let member = GetFormatDeclByIndex(desugarIndex)
                        CollectRemovedDecl(member.GetMangledName().getOrThrow().str(), needRemoved)
                    }
                    desugarOffset++
                }
                paramListIndex++
            }
        } else if (decl.GetKind() == MF_DECL_KIND_PROP_DECL) {
            let info = decl.GetInfoAsPropInfo().getOrThrow()
            let setters = info.GetSetters().getOrThrow()
            var setterIndex: UInt32 = 0u32
            while (setterIndex < setters.size()) {
                let setter = GetFormatDeclByIndex((setters.Get(setterIndex) as UInt32).getOrThrow())
                CollectRemovedDecl(setter.GetMangledName().getOrThrow().str(), needRemoved)
                setterIndex++
            }
            let getters = info.GetGetters().getOrThrow()
            var getterIndex: UInt32 = 0u32
            while (getterIndex < getters.size()) {
                let getter = GetFormatDeclByIndex((getters.Get(getterIndex) as UInt32).getOrThrow())
                CollectRemovedDecl(getter.GetMangledName().getOrThrow().str(), needRemoved)
                getterIndex++
            }
        } else if (decl.GetKind() == MF_DECL_KIND_VAR_DECL) {
            let attrs = GetAttributes(decl)
            if (attrs.TestAttr(Attribute.GLOBAL) || attrs.TestAttr(Attribute.STATIC)) {
                CollectRemovedDecl(decl.GetMangledName().getOrThrow().str(), needRemoved)
            }
        } else {
            let body: Option<Vector<UInt32>> = if (decl.GetKind() == MF_DECL_KIND_CLASS_DECL) {
                decl.GetInfoAsClassInfo().getOrThrow().GetBody()
            } else if (decl.GetKind() == MF_DECL_KIND_INTERFACE_DECL) {
                decl.GetInfoAsInterfaceInfo().getOrThrow().GetBody()
            } else if (decl.GetKind() == MF_DECL_KIND_ENUM_DECL) {
                decl.GetInfoAsEnumInfo().getOrThrow().GetBody()
            } else if (decl.GetKind() == MF_DECL_KIND_STRUCT_DECL) {
                decl.GetInfoAsStructInfo().getOrThrow().GetBody()
            } else if (decl.GetKind() == MF_DECL_KIND_EXTEND_DECL) {
                decl.GetInfoAsExtendInfo().getOrThrow().GetBody()
            } else {
                None
            }
            if (body.isNone()) {
                return
            }
            if (decl.GetKind() != MF_DECL_KIND_EXTEND_DECL) {
                CollectRemovedDecl(decl.GetMangledName().getOrThrow().str(), needRemoved)
            }
            let members = body.getOrThrow()
            var memberIndex: UInt32 = 0u32
            while (memberIndex < members.size()) {
                CollectRemovedDecls(
                    GetFormatDeclByIndex((members.Get(memberIndex) as UInt32).getOrThrow()), needRemoved)
                memberIndex++
            }
        }
    }

    // IncrementalLoader.cpp:207-221 ClearInstantiatedCache.
    private func ClearInstantiatedCache(instantiatedDeclIndexes: ArrayList<UInt32>,
        needRemoved: HashSet<String>): Unit {
        for (index in instantiatedDeclIndexes) {
            let declInfo = GetFormatDeclByIndex(index)
            let genericDecl = GetDeclFromIndex(declInfo.GetGenericDecl())
            if (genericDecl.isNone() || genericDecl.getOrThrow().toBeCompiled) {
                CollectRemovedDecls(declInfo, needRemoved)
            }
        }
    }

    // IncrementalLoader.cpp:223-233 LoadDesugarDecl<MainDecl>.
    private func LoadDesugarDecl(decl: MainDecl, index: UInt32): Unit {
        if (decl.toBeCompiled) {
            return
        }
        decl.desugarDecl = LoadDecl(index).getOrThrow() as FuncDecl
        let desugarDecl = decl.desugarDecl.getOrThrow()
        desugarDecl.EnableAttr(Attribute.INCRE_COMPILE)
        desugarDecl.DisableAttr(Attribute.IMPORTED)
    }

    // IncrementalLoader.cpp:223-233 LoadDesugarDecl<MacroDecl>.
    private func LoadDesugarDecl(decl: MacroDecl, index: UInt32): Unit {
        if (decl.toBeCompiled) {
            return
        }
        decl.desugarDecl = LoadDecl(index).getOrThrow() as FuncDecl
        let desugarDecl = decl.desugarDecl.getOrThrow()
        desugarDecl.EnableAttr(Attribute.INCRE_COMPILE)
        desugarDecl.DisableAttr(Attribute.IMPORTED)
    }

    // IncrementalLoader.cpp:235-263 HasInlineDefaultParamFunc.
    private func HasInlineDefaultParamFunc(decl: PackageFormat_Decl): Bool {
        let ret = ArrayList<String>()
        if (decl.GetKind() == MF_DECL_KIND_FUNC_DECL) {
            ret.add(decl.GetMangledName().getOrThrow().str())
            let info = decl.GetInfoAsFuncInfo().getOrThrow()
            let paramLists = info.GetFuncBody().getOrThrow().GetParamLists().getOrThrow()
            var paramListIndex: UInt32 = 0u32
            while (paramListIndex < paramLists.size()) {
                let paramList = PackageFormat_FuncParamList(data.getOrThrow(),
                    (paramLists.Get(paramListIndex) as Int64).getOrThrow())
                let desugars = paramList.GetDesugars().getOrThrow()
                var desugarOffset: UInt32 = 0u32
                while (desugarOffset < desugars.size()) {
                    let desugarIndex = (desugars.Get(desugarOffset) as UInt32).getOrThrow()
                    if (desugarIndex != 0u32) {
                        let desugarDecl = GetFormatDeclByIndex(desugarIndex)
                        let attrs = GetAttributes(desugarDecl)
                        let desugarInfo = desugarDecl.GetInfoAsFuncInfo()
                        if (attrs.TestAttr(Attribute.HAS_INITIAL) &&
                            attrs.TestAttr(Attribute.IMPLICIT_ADD) && desugarInfo.isSome() &&
                            desugarInfo.getOrThrow().GetIsInline() && canInline) {
                            return true
                        }
                    }
                    desugarOffset++
                }
                paramListIndex++
            }
        }
        return false
    }

    // IncrementalLoader.cpp:266-344 LoadCachedTypeForPackage.
    public func LoadCachedTypeForPackage(sourcePackage: Package,
        mangledName2DeclMap: HashMap<String, Decl>): HashSet<String> {
        if (!VerifyForData("cached type")) {
            return HashSet<String>()
        }
        isLoadCache = true
        try {
            let rawData = data.getOrThrow()
            packageTable = Some(GetPackage(rawData))
            flat = Some(CjoFlatBuffer(rawData))
            let reader = flat.getOrThrow()
            let root = reader.RootTable()
            flatAllTypes = reader.VectorField(root, 18)
            flatAllDecls = reader.VectorField(root, 20)
            flatAllExprs = reader.VectorField(root, 22)
            flatImports = reader.VectorField(root, 12)
            LoadSerializedDeclRecords()
            PrepareForLoadTypeCache(sourcePackage)
            let logger = IncrementalCompilationLogger.GetInstance()
            logger.LogLn(
                "[LoadCachedTypeForPackage] begin collect some unfounded for incr compile to remove:")
            let instantiatedDeclIndexes = ArrayList<UInt32>()
            let genericIndexes = ArrayList<UInt32>()
            let unfounded = HashSet<String>()
            let allDecls = packageTable.getOrThrow().GetAllDecls().getOrThrow()
            var index: UInt32 = 0u32
            while (index < allDecls.size()) {
                let realIndex = index + 1u32
                let decl = GetFormatDeclByIndex(realIndex)
                if (GetAttributes(decl).TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                    instantiatedDeclIndexes.add(realIndex)
                    index++
                    continue
                }
                let mangle = decl.GetMangledBeforeSema().getOrThrow().str()
                let found = mangledName2DeclMap.get(mangle)
                if (found.isNone()) {
                    if (!mangle.isEmpty()) {
                        CollectRemovedDecls(decl, unfounded)
                    }
                    index++
                    continue
                }
                let astDecl = found.getOrThrow()
                if (IsChangedDeclMayOmitType(astDecl) || DoNotLoadCache(astDecl)) {
                    if (astDecl.TestAttr(Attribute.GENERIC)) {
                        if (!allLoadedDecls.contains(realIndex)) {
                            allLoadedDecls.add(realIndex, astDecl)
                        }
                        genericIndexes.add(realIndex)
                    }
                    index++
                    continue
                }
                if (let Some(mainDecl) <- (astDecl as MainDecl)) {
                    LoadDesugarDecl(mainDecl, realIndex)
                } else if (let Some(macroDecl) <- (astDecl as MacroDecl)) {
                    LoadDesugarDecl(macroDecl, realIndex)
                } else {
                    LoadCachedTypeForDecl(decl, astDecl)
                    CollectRemovedDefaultImpl(astDecl, decl, unfounded)
                    if (!allLoadedDecls.contains(realIndex)) {
                        allLoadedDecls.add(realIndex, astDecl)
                    }
                    let info = decl.GetInfoAsFuncInfo()
                    let bodyIndex = if (let Some(varInfo) <- decl.GetInfoAsVarInfo()) {
                        varInfo.GetInitializer()
                    } else if (let Some(varWithPatternInfo) <- decl.GetInfoAsVarWithPatternInfo()) {
                        varWithPatternInfo.GetInitializer()
                    } else if (let Some(aliasInfo) <- decl.GetInfoAsAliasInfo()) {
                        aliasInfo.GetAliasedTy()
                    } else if (let Some(paramInfo) <- decl.GetInfoAsParamInfo()) {
                        paramInfo.GetDefaultVal()
                    } else {
                        0u32
                    }
                    if (bodyIndex != 0u32 ||
                        (info.isSome() && info.getOrThrow().GetIsInline() && canInline) ||
                        HasInlineDefaultParamFunc(decl)) {
                        astDecl.toBeCompiled = true
                    }
                }
                index++
            }
            ClearInstantiatedCache(instantiatedDeclIndexes, unfounded)
            for (genericIndex in genericIndexes) {
                allLoadedDecls.remove(genericIndex)
            }
            allTypes = Array<Option<Ty>>(
                Int64(packageTable.getOrThrow().GetAllTypes().getOrThrow().size()), repeat: None)
            LoadRefs()
            return unfounded
        } finally {
            isLoadCache = false
        }
    }

    // ReferenceLoader.cpp:210-214 ASTLoader::SetIsChirNow.
    public func SetIsChirNow(value!: Bool = false): Unit { isChirNow = value }

    // ReferenceLoader.cpp:216-232 InitializeTypeLoader.
    private func InitializeTypeLoader(): Unit {
        tyLoaderMap.clear()
        let setType = {tyIndex: UInt32, typeObj: PackageFormat_SemaTy => SetTypeTy(tyIndex, typeObj)}
        tyLoaderMap[MF_TYPE_KIND_C_POINTER] = setType
        tyLoaderMap[MF_TYPE_KIND_ARRAY] = setType
        tyLoaderMap[MF_TYPE_KIND_V_ARRAY] = setType
        tyLoaderMap[MF_TYPE_KIND_C_STRING] = setType
        tyLoaderMap[MF_TYPE_KIND_STRUCT] = setType
        tyLoaderMap[MF_TYPE_KIND_ENUM] = setType
        tyLoaderMap[MF_TYPE_KIND_INTERFACE] = setType
        tyLoaderMap[MF_TYPE_KIND_CLASS] = setType
        tyLoaderMap[MF_TYPE_KIND_TYPE] = setType
        tyLoaderMap[MF_TYPE_KIND_TUPLE] = setType
        tyLoaderMap[MF_TYPE_KIND_FUNC] = setType
        tyLoaderMap[MF_TYPE_KIND_GENERIC] = {tyIndex: UInt32, typeObj: PackageFormat_SemaTy =>
            SetGenericTy(tyIndex, typeObj)
        }
    }

    // ASTLoaderImpl.h:184-189 GetFormatDeclByIndex.
    private func GetFormatDeclByIndex(declIndex: UInt32): PackageFormat_Decl {
        CJC_ASSERT(declIndex != 0u32)
        let tables = packageTable.getOrThrow().GetAllDecls().getOrThrow()
        return PackageFormat_Decl(data.getOrThrow(), (tables.Get(declIndex - 1u32) as Int64).getOrThrow())
    }

    // ASTLoaderImpl.h:191-196 GetFormatExprByIndex.
    private func GetFormatExprByIndex(exprIndex: UInt32): PackageFormat_Expr {
        CJC_ASSERT(exprIndex != 0u32)
        let tables = packageTable.getOrThrow().GetAllExprs().getOrThrow()
        return PackageFormat_Expr(data.getOrThrow(), (tables.Get(exprIndex - 1u32) as Int64).getOrThrow())
    }

    // ASTLoaderImpl.h:347-351 GetExprByIndex.
    private func GetExprByIndex(index: UInt32): Option<Expr> { return allLoadedExprs.get(index) }

    // ASTLoader.cpp:432-457 LoadPos.
    private func LoadPos(posObj: PackageFormat_Position): Position {
        let fileIndex = posObj.GetFile()
        let pkgIndex = posObj.GetPkgId()
        let line = posObj.GetLine()
        let column = posObj.GetColumn()
        var fileId: UInt64 = 0u64
        if (pkgIndex == 0u32) {
            fileId = if (fileIndex == 0u32) { 0u64 } else { allFileIds[Int64(fileIndex - 1u32)] }
        } else {
            CJC_ASSERT(Int64(pkgIndex - 1u32) < importedFullPackageNames.size)
            let fullPackageName = importedFullPackageNames[Int64(pkgIndex - 1u32)]
            if (let Some(packageDecl) <- packageDecls.get(fullPackageName)) {
                CJC_ASSERT(Int64(fileIndex) < packageDecl.srcPackage.files.size)
                let file = packageDecl.srcPackage.files[Int64(fileIndex)]
                fileId = file.begin.fileID
                idToFileMap[fileId] = file
            }
        }
        return Position(fileId, Int64(line), Int64(column))
    }

    // ASTLoader.cpp:543-578 GetDeclFromIndex.
    private func GetDeclFromIndex(fullId: Option<PackageFormat_FullId>): Option<Decl> {
        let id = fullId ?? return None
        let pkgIndex = id.GetPkgId()
        if (pkgIndex == INVALID_PACKAGE_INDEX) { return None }
        if (pkgIndex == PKG_REFERENCE_INDEX) {
            if (let Some(packageDecl) <- packageDecls.get(id.GetDecl().getOrThrow().str())) {
                return packageDecl
            }
            return None
        } else if (pkgIndex == CURRENT_PKG_INDEX) {
            return allLoadedDecls.get(id.GetIndex())
        }
        let fullPackageName = importedFullPackageNames[Int64(pkgIndex)]
        let exportId = id.GetDecl().getOrThrow().str()
        if (let Some(exportIdDeclMap) <- exportIdDeclMaps.get(fullPackageName)) {
            if (let Some(decl) <- exportIdDeclMap.get(exportId)) { return Some(decl) }
        }
        if (!packageDecls.contains(fullPackageName) && !isLoadCache) {
            diag.DiagnoseRefactor(DiagKindRefactor.package_invalid_cjo_dependency, DEFAULT_POSITION,
                arguments: [packageName, fullPackageName])
        }
        return None
    }

    // ASTLoaderImpl.h:263-267 GetASTTypeKind.
    private func GetASTTypeKind(kind: UInt16): TypeKind {
        if (kind == MF_TYPE_KIND_UNIT) { return TypeKind.TYPE_UNIT }
        if (kind == MF_TYPE_KIND_INT8) { return TypeKind.TYPE_INT8 }
        if (kind == MF_TYPE_KIND_INT16) { return TypeKind.TYPE_INT16 }
        if (kind == MF_TYPE_KIND_INT32) { return TypeKind.TYPE_INT32 }
        if (kind == MF_TYPE_KIND_INT64) { return TypeKind.TYPE_INT64 }
        if (kind == MF_TYPE_KIND_INT_NATIVE) { return TypeKind.TYPE_INT_NATIVE }
        if (kind == MF_TYPE_KIND_UINT8) { return TypeKind.TYPE_UINT8 }
        if (kind == MF_TYPE_KIND_UINT16) { return TypeKind.TYPE_UINT16 }
        if (kind == MF_TYPE_KIND_UINT32) { return TypeKind.TYPE_UINT32 }
        if (kind == MF_TYPE_KIND_UINT64) { return TypeKind.TYPE_UINT64 }
        if (kind == MF_TYPE_KIND_UINT_NATIVE) { return TypeKind.TYPE_UINT_NATIVE }
        if (kind == MF_TYPE_KIND_FLOAT16) { return TypeKind.TYPE_FLOAT16 }
        if (kind == MF_TYPE_KIND_FLOAT32) { return TypeKind.TYPE_FLOAT32 }
        if (kind == MF_TYPE_KIND_FLOAT64) { return TypeKind.TYPE_FLOAT64 }
        if (kind == MF_TYPE_KIND_RUNE) { return TypeKind.TYPE_RUNE }
        if (kind == MF_TYPE_KIND_NOTHING) { return TypeKind.TYPE_NOTHING }
        if (kind == MF_TYPE_KIND_BOOL) { return TypeKind.TYPE_BOOLEAN }
        return TypeKind.TYPE_INVALID
    }

    // ReferenceLoader.cpp:269-291 LoadType.
    public func LoadType(tyIndex: UInt32): Ty {
        if (tyIndex == 0u32) { return FaithfulSemaTypeManager.GetInvalidTy() }
        let index = tyIndex - 1u32
        if (let Some(ty) <- allTypes[Int64(index)]) { return ty }
        let typeTables = packageTable.getOrThrow().GetAllTypes().getOrThrow()
        let typeObj = PackageFormat_SemaTy(data.getOrThrow(), (typeTables.Get(index) as Int64).getOrThrow())
        if (GetPrimitiveTy(index, typeObj)) { return allTypes[Int64(index)].getOrThrow() }
        if (let Some(handler) <- tyLoaderMap.get(typeObj.GetKind())) {
            handler(index, typeObj)
        } else {
            allTypes[Int64(index)] = Some(FaithfulSemaTypeManager.GetInvalidTy())
        }
        return allTypes[Int64(index)].getOrThrow()
    }

    // ReferenceLoader.cpp:293-304 GetPrimitiveTy.
    private func GetPrimitiveTy(tyIndex: UInt32, typeObj: PackageFormat_SemaTy): Bool {
        if (typeObj.GetKind() >= MF_TYPE_KIND_UNIT && typeObj.GetKind() <= MF_TYPE_KIND_BOOL) {
            let astKind = GetASTTypeKind(typeObj.GetKind())
            CJC_ASSERT(astKind != TypeKind.TYPE_INVALID)
            allTypes[Int64(tyIndex)] = Some(FaithfulSemaTypeManager.GetPrimitiveTy(astKind))
            return true
        }
        return false
    }

    // ReferenceLoader.cpp:306-332 SetGenericTy.
    private func SetGenericTy(tyIndex: UInt32, typeObj: PackageFormat_SemaTy): Unit {
        let info = typeObj.GetInfoAsGenericTyInfo().getOrThrow()
        let decl = GetDeclFromIndex(info.GetDeclPtr()) ?? return
        let genericParamDecl = (decl as GenericParamDecl).getOrThrow()
        let genericTy = typeManager.GetGenericsTy(genericParamDecl)
        allTypes[Int64(tyIndex)] = Some(genericTy)
        if (isLoadCache) { return }
        let upperBounds = info.GetUpperBounds().getOrThrow()
        let upperBoundIdentities = HashSet<Ptr<Ty>>()
        for (existing in genericTy.upperBounds) { upperBoundIdentities.add(Ptr<Ty>(existing)) }
        var index: UInt32 = 0u32
        while (index < upperBounds.size()) {
            let upperTy = LoadType((upperBounds.Get(index) as UInt32).getOrThrow())
            let upperKey = Ptr<Ty>(upperTy)
            if (!upperBoundIdentities.contains(upperKey)) {
                upperBoundIdentities.add(upperKey)
                genericTy.upperBounds.add(upperTy)
            }
            index++
        }
        let generic = genericParamDecl.outerDecl.getOrThrow().GetGeneric().getOrThrow()
        let storedBounds = HashSet<Ptr<Ty>>()
        for (upperTy in genericTy.upperBounds) { storedBounds.add(Ptr<Ty>(upperTy)) }
        let genericKey = Ptr<GenericsTy>(genericTy)
        if (!generic.assumptionCollection.contains(genericKey)) {
            generic.assumptionCollection[genericKey] = storedBounds
        }
    }

    // ReferenceLoader.cpp:334-344 LoadTypeArgs.
    private func LoadTypeArgs(typeObj: PackageFormat_SemaTy): Array<Ty> {
        let typeArgs = ArrayList<Ty>()
        let rawArgs = typeObj.GetTypeArgs().getOrThrow()
        var index: UInt32 = 0u32
        while (index < rawArgs.size()) {
            typeArgs.add(LoadType((rawArgs.Get(index) as UInt32).getOrThrow()))
            index++
        }
        return typeArgs.toArray()
    }

    // ReferenceLoader.cpp:346-398 SetTypeTy.
    private func SetTypeTy(tyIndex: UInt32, typeObj: PackageFormat_SemaTy): Unit {
        let kind = typeObj.GetKind()
        var ty: Ty = FaithfulSemaTypeManager.GetInvalidTy()
        if (kind == MF_TYPE_KIND_C_STRING) {
            ty = FaithfulSemaTypeManager.GetCStringTy()
        } else if (kind == MF_TYPE_KIND_C_POINTER) {
            let args = typeObj.GetTypeArgs().getOrThrow()
            CJC_ASSERT(args.size() == 1u32)
            ty = typeManager.GetPointerTy(LoadType((args.Get(0u32) as UInt32).getOrThrow()))
        } else if (kind == MF_TYPE_KIND_ARRAY) {
            let info = typeObj.GetInfoAsArrayTyInfo().getOrThrow()
            let args = typeObj.GetTypeArgs().getOrThrow()
            CJC_ASSERT(args.size() == 1u32)
            ty = typeManager.GetArrayTy(LoadType((args.Get(0u32) as UInt32).getOrThrow()), UInt64(info.GetDimsOrSize()))
        } else if (kind == MF_TYPE_KIND_V_ARRAY) {
            let info = typeObj.GetInfoAsArrayTyInfo().getOrThrow()
            let args = typeObj.GetTypeArgs().getOrThrow()
            CJC_ASSERT(args.size() == 1u32)
            ty = typeManager.GetVArrayTy(LoadType((args.Get(0u32) as UInt32).getOrThrow()), info.GetDimsOrSize())
        } else if (kind == MF_TYPE_KIND_TUPLE) {
            ty = typeManager.GetTupleTy(LoadTypeArgs(typeObj))
        } else if (kind == MF_TYPE_KIND_FUNC) {
            let info = typeObj.GetInfoAsFuncTyInfo().getOrThrow()
            let cfg = FuncTyConfig()
            cfg.isC = info.GetIsC()
            cfg.hasVariableLenArg = info.GetHasVariableLenArg()
            ty = typeManager.GetFunctionTy(LoadTypeArgs(typeObj), LoadType(info.GetRetType()), cfg: cfg)
        } else {
            let info = typeObj.GetInfoAsCompositeTyInfo().getOrThrow()
            let decl = GetDeclFromIndex(info.GetDeclPtr())
            if (let None <- decl) { allTypes[Int64(tyIndex)] = Some(ty); return }
            let typeArgs = LoadTypeArgs(typeObj)
            if (kind == MF_TYPE_KIND_TYPE) {
                ty = typeManager.GetTypeAliasTy((decl.getOrThrow() as TypeAliasDecl).getOrThrow(), typeArgs)
            } else if (kind == MF_TYPE_KIND_CLASS) {
                let classDecl = (decl.getOrThrow() as ClassDecl).getOrThrow()
                ty = if (info.GetIsThisTy()) { typeManager.GetClassThisTy(classDecl, typeArgs) } else {
                    typeManager.GetClassTy(classDecl, typeArgs)
                }
            } else if (kind == MF_TYPE_KIND_INTERFACE) {
                ty = typeManager.GetInterfaceTy((decl.getOrThrow() as InterfaceDecl).getOrThrow(), typeArgs)
            } else if (kind == MF_TYPE_KIND_STRUCT) {
                ty = typeManager.GetStructTy((decl.getOrThrow() as StructDecl).getOrThrow(), typeArgs)
            } else if (kind == MF_TYPE_KIND_ENUM) {
                ty = typeManager.GetEnumTy((decl.getOrThrow() as EnumDecl).getOrThrow(), typeArgs: typeArgs)
            }
        }
        allTypes[Int64(tyIndex)] = Some(ty)
    }

    // ReferenceLoader.cpp:400-430 LoadInheritedTypes.
    private func LoadInheritedTypes(declObj: PackageFormat_Decl, inheritableDecl: InheritableDecl): Unit {
        let inheritedTypes = if (let Some(_) <- (inheritableDecl as ClassDecl)) {
            declObj.GetInfoAsClassInfo().getOrThrow().GetInheritedTypes().getOrThrow()
        } else if (let Some(_) <- (inheritableDecl as InterfaceDecl)) {
            declObj.GetInfoAsInterfaceInfo().getOrThrow().GetInheritedTypes().getOrThrow()
        } else if (let Some(_) <- (inheritableDecl as EnumDecl)) {
            declObj.GetInfoAsEnumInfo().getOrThrow().GetInheritedTypes().getOrThrow()
        } else if (let Some(_) <- (inheritableDecl as StructDecl)) {
            declObj.GetInfoAsStructInfo().getOrThrow().GetInheritedTypes().getOrThrow()
        } else {
            declObj.GetInfoAsExtendInfo().getOrThrow().GetInheritedTypes().getOrThrow()
        }
        let loadedTypes = ArrayList<Type>()
        let directSubtypeIdentities = HashSet<Ptr<Ty>>()
        var index: UInt32 = 0u32
        while (index < inheritedTypes.size()) {
            let serializedIndex = (inheritedTypes.Get(index) as UInt32).getOrThrow()
            if (serializedIndex != 0u32) {
                let loadedType = WrapType(Some(LoadType(serializedIndex))).getOrThrow()
                if (!Ty.IsTyCorrect(loadedType.GetTy()) && isLoadCache) { return }
                if (let Some(classLikeTy) <- (loadedType.GetTy() as ClassLikeTy)) {
                    let subtype = inheritableDecl.GetTy().getOrThrow()
                    directSubtypeIdentities.clear()
                    for (existing in classLikeTy.directSubtypes) {
                        directSubtypeIdentities.add(Ptr<Ty>(existing))
                    }
                    let subtypeKey = Ptr<Ty>(subtype)
                    if (!directSubtypeIdentities.contains(subtypeKey)) { classLikeTy.directSubtypes.add(subtype) }
                }
                loadedTypes.add(loadedType)
            }
            index++
        }
        var loadedIndex: Int64 = 0
        while (loadedIndex < loadedTypes.size) {
            if (loadedIndex < inheritableDecl.inheritedTypes.size) {
                inheritableDecl.inheritedTypes[loadedIndex] =
                    UpdateType(Some(inheritableDecl.inheritedTypes[loadedIndex]), loadedTypes[loadedIndex])
            } else {
                inheritableDecl.inheritedTypes.add(loadedTypes[loadedIndex])
            }
            loadedIndex++
        }
        while (inheritableDecl.inheritedTypes.size > loadedTypes.size) {
            inheritableDecl.inheritedTypes.remove(at: inheritableDecl.inheritedTypes.size - 1)
        }
    }

    // ReferenceLoader.cpp:432-453 LoadGenericConstraintsRef.
    private func LoadGenericConstraintsRef(genericRef: Option<PackageFormat_Generic>, generic: Option<Generic>): Unit {
        let astGeneric = generic ?? return
        let rawGeneric = genericRef ?? return
        if (astGeneric.TestAttr(Attribute.INCRE_COMPILE)) { return }
        let constraints = rawGeneric.GetConstraints().getOrThrow()
        var index: UInt32 = 0u32
        while (index < constraints.size()) {
            let rawConstraint = PackageFormat_Constraint(
                data.getOrThrow(), (constraints.Get(index) as Int64).getOrThrow())
            let constraint = GenericConstraint()
            constraint.begin = LoadPos(rawConstraint.GetBegin().getOrThrow())
            constraint.end = LoadPos(rawConstraint.GetEnd().getOrThrow())
            constraint.refType = Wrap2RefType(LoadType(rawConstraint.GetType()))
            let upperBounds = rawConstraint.GetUppers().getOrThrow()
            var upperIndex: UInt32 = 0u32
            while (upperIndex < upperBounds.size()) {
                constraint.upperBounds.add(WrapType(Some(
                    LoadType((upperBounds.Get(upperIndex) as UInt32).getOrThrow()))).getOrThrow())
                upperIndex++
            }
            constraint.isImplicitlyIntroduced = rawConstraint.GetIsImplicitlyIntroduced()
            astGeneric.genericConstraints.add(constraint)
            index++
        }
    }

    // ReferenceLoader.cpp:455-469 LoadAnnotationBaseExpr.
    private func LoadAnnotationBaseExpr(rawAnno: PackageFormat_Anno, annotation: Annotation): Unit {
        if (annotation.kind != AstAnnotationKind.CUSTOM) { return }
        if (let Some(targetCtr) <- GetDeclFromIndex(rawAnno.GetTarget())) {
            let refExpr = RefExpr()
            refExpr.ref.target = Some(targetCtr)
            refExpr.ref.identifier = targetCtr.identifier
            refExpr.SetTy(targetCtr.GetTy().getOrThrow())
            annotation.baseExpr = Some(refExpr)
        }
    }

    // ReferenceLoader.cpp:471-500 LoadNominalDeclRef.
    private func LoadNominalDeclRef(declObj: PackageFormat_Decl, astDecl: Decl): Unit {
        if (let Some(inheritableDecl) <- (astDecl as InheritableDecl)) {
            for (member in inheritableDecl.GetMemberDeclPtrs()) {
                SetMemberDeclReference(member, inheritableDecl)
            }
            if (!inheritableDecl.toBeCompiled) { LoadInheritedTypes(declObj, inheritableDecl) }
        } else if (let Some(funcDecl) <- (astDecl as FuncDecl)) {
            let funcBody = funcDecl.funcBody.getOrThrow()
            let nonGenericCtor = funcDecl.TestAttr(Attribute.CONSTRUCTOR) && funcBody.body.isNone()
            if (!nonGenericCtor) {
                let loadedType = WrapType(Some(LoadType(declObj.GetInfoAsFuncInfo().getOrThrow()
                    .GetFuncBody().getOrThrow().GetRetType()))).getOrThrow()
                funcBody.retType = Some(UpdateType(funcBody.retType, loadedType))
            }
            funcBody.SetTy(funcDecl.GetTy().getOrThrow())
        }
        if (let Some(extendDecl) <- (astDecl as ExtendDecl)) {
            extendDecl.extendedType = Some(UpdateType(
                extendDecl.extendedType, WrapType(extendDecl.GetTy()).getOrThrow()))
        }
        if (astDecl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            astDecl.genericDecl = GetDeclFromIndex(declObj.GetGenericDecl())
        }
    }

    // ReferenceLoader.cpp:502-507 LoadTypeAliasDeclRef.
    private func LoadTypeAliasDeclRef(declObj: PackageFormat_Decl, typeAliasDecl: TypeAliasDecl): Unit {
        typeAliasDecl.typeNode = WrapType(Some(LoadType(
            declObj.GetInfoAsAliasInfo().getOrThrow().GetAliasedTy())))
    }

    // ReferenceLoader.cpp:509-521 LoadDeclDependencies.
    private func LoadDeclDependencies(declObj: PackageFormat_Decl, astDecl: Decl): Unit {
        if (!deserializingCommon) { return }
        let rawDeps = declObj.GetDependencies() ?? return
        var index: UInt32 = 0u32
        while (index < rawDeps.size()) {
            let fullId = PackageFormat_FullId(data.getOrThrow(), (rawDeps.Get(index) as Int64).getOrThrow())
            astDecl.dependencies.add(GetDeclFromIndex(Some(fullId)))
            index++
        }
    }

    // ReferenceLoader.cpp:524-580 LoadDeclRefs.
    private func LoadDeclRefs(declObj: PackageFormat_Decl, astDecl: Decl): Unit {
        astDecl.SetTy(LoadType(declObj.GetType()))
        if (!Ty.IsTyCorrect(astDecl.GetTy()) && isLoadCache) { return }
        LoadGenericConstraintsRef(declObj.GetGeneric(), astDecl.GetGeneric())
        let rawAnnotations = declObj.GetAnnotations().getOrThrow()
        CJC_ASSERT(Int64(rawAnnotations.size()) == astDecl.annotations.size)
        var annotationIndex: UInt32 = 0u32
        while (annotationIndex < rawAnnotations.size()) {
            LoadAnnotationBaseExpr(PackageFormat_Anno(data.getOrThrow(),
                (rawAnnotations.Get(annotationIndex) as Int64).getOrThrow()), astDecl.annotations[Int64(annotationIndex)])
            annotationIndex++
        }
        let kind = declObj.GetKind()
        if (kind == MF_DECL_KIND_FUNC_DECL || kind == MF_DECL_KIND_STRUCT_DECL ||
            kind == MF_DECL_KIND_ENUM_DECL || kind == MF_DECL_KIND_INTERFACE_DECL ||
            kind == MF_DECL_KIND_CLASS_DECL || kind == MF_DECL_KIND_EXTEND_DECL) {
            LoadNominalDeclRef(declObj, astDecl)
        } else if (kind == MF_DECL_KIND_TYPE_ALIAS_DECL) {
            LoadTypeAliasDeclRef(declObj, (astDecl as TypeAliasDecl).getOrThrow())
        } else if (kind == MF_DECL_KIND_VAR_WITH_PATTERN_DECL) {
            let rawPattern = declObj.GetInfoAsVarWithPatternInfo().getOrThrow().GetIrrefutablePattern().getOrThrow()
            LoadPatternRefs(rawPattern, (astDecl as VarWithPatternDecl).getOrThrow()
                .irrefutablePattern.getOrThrow())
        } else if (kind == MF_DECL_KIND_FUNC_PARAM || kind == MF_DECL_KIND_VAR_DECL ||
            kind == MF_DECL_KIND_PROP_DECL) {
            let varDecl = (astDecl as VarDeclAbstract).getOrThrow()
            let declTy = astDecl.GetTy().getOrThrow()
            if (varDecl.typeNode.isNone() && (declTy.HasAliasTy() || declTy.IsFunc())) {
                varDecl.typeNode = WrapType(Some(declTy))
            }
        }
    }

    // ReferenceLoader.cpp:582-655 LoadExprRefs.
    private func LoadExprRefs(exprObj: PackageFormat_Expr, expr: Expr): Unit {
        expr.SetTy(LoadType(exprObj.GetType()))
        expr.mapExpr = GetExprByIndex(exprObj.GetMapExpr())
        let kind = exprObj.GetKind()
        if (kind == MF_EXPR_KIND_MEMBER_ACCESS) {
            let info = exprObj.GetInfoAsReferenceInfo().getOrThrow()
            let member = (expr as MemberAccess).getOrThrow()
            member.target = GetDeclFromIndex(info.GetTarget())
            let instTys = info.GetInstTys().getOrThrow()
            var index: UInt32 = 0u32
            while (index < instTys.size()) {
                member.instTys.add(LoadType((instTys.Get(index) as UInt32).getOrThrow()))
                index++
            }
            member.matchedParentTy = Some(LoadType(info.GetMatchedParentTy()))
        } else if (kind == MF_EXPR_KIND_REF_EXPR) {
            let info = exprObj.GetInfoAsReferenceInfo().getOrThrow()
            let refExpr = (expr as RefExpr).getOrThrow()
            refExpr.ref.target = GetDeclFromIndex(info.GetTarget())
            let instTys = info.GetInstTys().getOrThrow()
            var index: UInt32 = 0u32
            while (index < instTys.size()) {
                refExpr.instTys.add(LoadType((instTys.Get(index) as UInt32).getOrThrow()))
                index++
            }
            refExpr.matchedParentTy = Some(LoadType(info.GetMatchedParentTy()))
        } else if (kind == MF_EXPR_KIND_ARRAY_LIT) {
            if (expr.TyKind() != TypeKind.TYPE_VARRAY) {
                let arrayLit = (expr as ArrayLit).getOrThrow()
                arrayLit.initFunc = if (let Some(initDecl) <-
                    GetDeclFromIndex(exprObj.GetInfoAsArrayInfo().getOrThrow().GetInitFunc())) {
                    initDecl as FuncDecl
                } else { None }
                CJC_ASSERT(arrayLit.initFunc.isSome())
            }
        } else if (kind == MF_EXPR_KIND_ARRAY_EXPR) {
            if (expr.TyKind() != TypeKind.TYPE_VARRAY) {
                let arrayExpr = (expr as ArrayExpr).getOrThrow()
                arrayExpr.initFunc = if (let Some(initDecl) <-
                    GetDeclFromIndex(exprObj.GetInfoAsArrayInfo().getOrThrow().GetInitFunc())) {
                    initDecl as FuncDecl
                } else { None }
            }
        } else if (kind == MF_EXPR_KIND_LAMBDA_EXPR) {
            (expr as LambdaExpr).getOrThrow().funcBody.getOrThrow().SetTy(expr.GetTy().getOrThrow())
        } else if (kind == MF_EXPR_KIND_LIT_CONST_EXPR) {
            let litConstExpr = (expr as LitConstExpr).getOrThrow()
            if (expr.GetTy().getOrThrow().IsString()) {
                litConstExpr.ref = Wrap2RefType(expr.GetTy().getOrThrow())
            }
            InitializeLitConstValue(litConstExpr)
        } else if (kind == MF_EXPR_KIND_JUMP_EXPR) {
            let jumpExpr = (expr as JumpExpr).getOrThrow()
            jumpExpr.refLoop = jumpExpr.mapExpr
            jumpExpr.mapExpr = None
        }
        LoadSubNodeRefs(exprObj, expr)
    }

    // ReferenceLoader.cpp:661-712 LoadSubNodeRefs.
    private func LoadSubNodeRefs(exprObj: PackageFormat_Expr, expr: Expr): Unit {
        let kind = exprObj.GetKind()
        if (kind == MF_EXPR_KIND_CALL_EXPR) {
            let callExpr = (expr as CallExpr).getOrThrow()
            let operands = exprObj.GetOperands().getOrThrow()
            CJC_ASSERT(operands.size() - 1u32 == UInt32(callExpr.args.size))
            var index: UInt32 = 1u32
            while (index < operands.size()) {
                let exprIndex = (operands.Get(index) as UInt32).getOrThrow()
                CJC_ASSERT(exprIndex != 0u32)
                let arg = callExpr.args[Int64(index - 1u32)]
                arg.SetTy(LoadType(GetFormatExprByIndex(exprIndex).GetType()))
                if (arg.TestAttr(Attribute.HAS_INITIAL)) {
                    arg.expr.getOrThrow().SetTy(arg.GetTy().getOrThrow())
                }
                index++
            }
        } else if (kind == MF_EXPR_KIND_TRY_EXPR) {
            let tryExpr = (expr as TryExpr).getOrThrow()
            let patterns = exprObj.GetInfoAsTryInfo().getOrThrow().GetPatterns().getOrThrow()
            CJC_ASSERT(Int64(patterns.size()) == tryExpr.catchPatterns.size)
            var index: UInt32 = 0u32
            while (index < patterns.size()) {
                LoadPatternRefs(PackageFormat_Pattern(data.getOrThrow(),
                    (patterns.Get(index) as Int64).getOrThrow()), tryExpr.catchPatterns[Int64(index)])
                index++
            }
        } else if (kind == MF_EXPR_KIND_MATCH_EXPR) {
            let matchExpr = (expr as MatchExpr).getOrThrow()
            let operands = exprObj.GetOperands().getOrThrow()
            if (matchExpr.matchMode) {
                CJC_ASSERT(operands.size() - 1u32 == UInt32(matchExpr.matchCases.size))
                var index: UInt32 = 1u32
                while (index < operands.size()) {
                    LoadMatchCaseRef((operands.Get(index) as UInt32).getOrThrow(),
                        matchExpr.matchCases[Int64(index - 1u32)], matchExpr.selector.getOrThrow())
                    index++
                }
            } else {
                var index: UInt32 = 0u32
                while (index < operands.size()) {
                    let matchCaseObj = GetFormatExprByIndex((operands.Get(index) as UInt32).getOrThrow())
                    matchExpr.matchCaseOthers[Int64(index)].SetTy(LoadType(matchCaseObj.GetType()))
                    index++
                }
            }
        } else if (kind == MF_EXPR_KIND_FOR_IN_EXPR) {
            LoadPatternRefs(exprObj.GetInfoAsForInInfo().getOrThrow().GetPattern().getOrThrow(),
                (expr as ForInExpr).getOrThrow().pattern.getOrThrow())
        }
        LoadSubNodeRefs2(exprObj, expr)
    }

    // ReferenceLoader.cpp:714-728 LoadSubNodeRefs2.
    private func LoadSubNodeRefs2(exprObj: PackageFormat_Expr, expr: Expr): Unit {
        if (exprObj.GetKind() != MF_EXPR_KIND_LET_PATTERN_DESTRUCTOR) { return }
        let letPattern = (expr as LetPatternDestructor).getOrThrow()
        let patterns = exprObj.GetInfoAsLetPatternDestructorInfo().getOrThrow().GetPatterns().getOrThrow()
        var index: UInt32 = 0u32
        while (index < patterns.size()) {
            LoadPatternRefs(PackageFormat_Pattern(data.getOrThrow(),
                (patterns.Get(index) as Int64).getOrThrow()), letPattern.patterns[Int64(index)])
            index++
        }
        let operands = exprObj.GetOperands().getOrThrow()
        letPattern.initializer.getOrThrow().SetTy(LoadType(GetFormatExprByIndex(
            (operands.Get(0u32) as UInt32).getOrThrow()).GetType()))
    }

    // ReferenceLoader.cpp:730-743 LoadMatchCaseRef.
    private func LoadMatchCaseRef(index: UInt32, matchCase: MatchCase, selector: Expr): Unit {
        let matchCaseObj = GetFormatExprByIndex(index)
        matchCase.SetTy(LoadType(matchCaseObj.GetType()))
        let patterns = matchCaseObj.GetInfoAsMatchCaseInfo().getOrThrow().GetPatterns().getOrThrow()
        CJC_ASSERT(Int64(patterns.size()) == matchCase.patterns.size)
        var patternIndex: UInt32 = 0u32
        while (patternIndex < patterns.size()) {
            let pattern = matchCase.patterns[Int64(patternIndex)]
            LoadPatternRefs(PackageFormat_Pattern(data.getOrThrow(),
                (patterns.Get(patternIndex) as Int64).getOrThrow()), pattern)
            pattern.ctxExpr = Some(selector)
            patternIndex++
        }
    }

    // ReferenceLoader.cpp:745-785 LoadPatternRefs.
    private func LoadPatternRefs(patternObj: PackageFormat_Pattern, pattern: Pattern): Unit {
        let types = patternObj.GetTypes().getOrThrow()
        CJC_ASSERT(types.size() >= 1u32)
        pattern.SetTy(LoadType((types.Get(0u32) as UInt32).getOrThrow()))
        let kind = patternObj.GetKind()
        if (kind == MF_PATTERN_KIND_TUPLE_PATTERN) {
            let subPatterns = patternObj.GetPatterns().getOrThrow()
            let tuplePattern = (pattern as TuplePattern).getOrThrow()
            var index: UInt32 = 0u32
            while (index < subPatterns.size()) {
                LoadPatternRefs(PackageFormat_Pattern(data.getOrThrow(),
                    (subPatterns.Get(index) as Int64).getOrThrow()), tuplePattern.patterns[Int64(index)])
                index++
            }
        } else if (kind == MF_PATTERN_KIND_TYPE_PATTERN) {
            let subPatterns = patternObj.GetPatterns().getOrThrow()
            let typePattern = (pattern as TypePattern).getOrThrow()
            LoadPatternRefs(PackageFormat_Pattern(data.getOrThrow(),
                (subPatterns.Get(0u32) as Int64).getOrThrow()), typePattern.pattern.getOrThrow())
            typePattern.typeNode = WrapType(pattern.GetTy())
        } else if (kind == MF_PATTERN_KIND_ENUM_PATTERN) {
            let subPatterns = patternObj.GetPatterns().getOrThrow()
            let enumPattern = (pattern as EnumPattern).getOrThrow()
            var index: UInt32 = 0u32
            while (index < subPatterns.size()) {
                LoadPatternRefs(PackageFormat_Pattern(data.getOrThrow(),
                    (subPatterns.Get(index) as Int64).getOrThrow()), enumPattern.patterns[Int64(index)])
                index++
            }
        } else if (kind == MF_PATTERN_KIND_EXCEPT_TYPE_PATTERN) {
            let subPatterns = patternObj.GetPatterns().getOrThrow()
            let exceptPattern = (pattern as ExceptTypePattern).getOrThrow()
            LoadPatternRefs(PackageFormat_Pattern(data.getOrThrow(),
                (subPatterns.Get(0u32) as Int64).getOrThrow()), exceptPattern.pattern.getOrThrow())
            exceptPattern.types.clear()
            var index: UInt32 = 1u32
            while (index < types.size()) {
                exceptPattern.types.add(WrapType(Some(LoadType(
                    (types.Get(index) as UInt32).getOrThrow()))).getOrThrow())
                index++
            }
        } else if (kind == MF_PATTERN_KIND_COMMAND_TYPE_PATTERN) {
            let subPatterns = patternObj.GetPatterns().getOrThrow()
            let commandPattern = (pattern as CommandTypePattern).getOrThrow()
            LoadPatternRefs(PackageFormat_Pattern(data.getOrThrow(),
                (subPatterns.Get(0u32) as Int64).getOrThrow()), commandPattern.pattern.getOrThrow())
            commandPattern.types.clear()
            var index: UInt32 = 1u32
            while (index < types.size()) {
                commandPattern.types.add(WrapType(Some(LoadType(
                    (types.Get(index) as UInt32).getOrThrow()))).getOrThrow())
                index++
            }
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
        packageTable = Some(GetPackage(rawData))
        let allTypeTables = packageTable.getOrThrow().GetAllTypes().getOrThrow()
        allTypes = Array<Option<Ty>>(Int64(allTypeTables.size()), repeat: None)
        importedFullPackageNames.clear()
        let importTables = packageTable.getOrThrow().GetImports().getOrThrow()
        var importIndex: UInt32 = 0u32
        while (importIndex < importTables.size()) {
            importedFullPackageNames.add(
                FlatBufferString(rawData, (importTables.Get(importIndex) as Int64).getOrThrow()).str())
            importIndex++
        }
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
        allFileIds = Array<UInt64>()
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
        let fileSize = reader.VectorLength(filesVec)
        allFileIds = Array<UInt64>(fileSize, repeat: 0u64)
        var idx: Int64 = 0
        while (idx < fileSize) {
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
        let allFileInfo = reader.VectorField(root, 32)
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
        allFileIds[fileIndex] = fileID
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
        let optionsTable = reader.OffsetField(root, 36)
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
        allFileIds = Array<UInt64>()
        let reader = flat.getOrThrow()
        let root = reader.RootTable()
        if (root < 0) {
            return
        }
        pkg.fullPackageName = reader.StringField(root, 8)
        pkg.EnableAttr(Attribute.IMPORTED)
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
        let filesVec = reader.VectorField(root, 14)
        let fileSize = reader.VectorLength(filesVec)
        allFileIds = Array<UInt64>(fileSize, repeat: 0u64)
        var fileIdx: Int64 = 0
        while (fileIdx < fileSize) {
            allFileIds[fileIdx] = FileByFlatIndex(UInt32(fileIdx + 1)).begin.fileID
            fileIdx++
        }
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
        if (let Some(callExpr) <- (expr as CallExpr)) {
            callExpr.resolvedFunction = if (let Some(target) <- callExpr.baseFunc.getOrThrow().GetTarget()) {
                target as FuncDecl
            } else { None }
        } else if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
            for (arg in arrayExpr.args) { arg.SetTy(arg.expr.getOrThrow().GetTy().getOrThrow()) }
        } else if (let Some(pointerExpr) <- (expr as PointerExpr)) {
            if (let Some(arg) <- pointerExpr.arg) { arg.SetTy(arg.expr.getOrThrow().GetTy().getOrThrow()) }
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
        for ((_, expr) in allLoadedExprs) { PostLoadFlatReference(expr) }
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
        if (!decl.TestAttr(Attribute.FROM_COMMON_PART) || !deserializingCommon) {
            decl.EnableAttr(Attribute.IMPORTED)
        }
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
            if (fileIndex == 0u32) { 0u64 } else { allFileIds[Int64(fileIndex) - 1] }
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
                AddDeclToImportedPackage(gpd)
            }
            return Some(gpd)
        }
        if (ShouldAddFlatDeclToImportedPackage(record.kind)) {
            AddDeclToImportedPackage(decl)
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
            LoadInheritableDeclAdvancedInfo(reader, record, inheritable)
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
            AddDeclToImportedPackage(varDecl)
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
            CreateAndLoadBasicInfo(reader, exprTable, ce)
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
        CreateAndLoadBasicInfo(reader, exprTable, invalidExpr)
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
        CreateAndLoadBasicInfo(reader, exprTable, le)
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
        CreateAndLoadBasicInfo(reader, exprTable, we)
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
        CreateAndLoadBasicInfo(reader, exprTable, pte)
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
        CreateAndLoadBasicInfo(reader, exprTable, je)
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
        CreateAndLoadBasicInfo(reader, exprTable, ide)
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
        CreateAndLoadBasicInfo(reader, exprTable, tce)
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
        CreateAndLoadBasicInfo(reader, exprTable, te)
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
        CreateAndLoadBasicInfo(reader, exprTable, pe)
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
        CreateAndLoadBasicInfo(reader, exprTable, re)
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
        CreateAndLoadBasicInfo(reader, exprTable, se)
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
        CreateAndLoadBasicInfo(reader, exprTable, ae)
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
        CreateAndLoadBasicInfo(reader, exprTable, pe)
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
        CreateAndLoadBasicInfo(reader, exprTable, te)
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
        CreateAndLoadBasicInfo(reader, exprTable, ie)
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
        CreateAndLoadBasicInfo(reader, exprTable, we)
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
        CreateAndLoadBasicInfo(reader, exprTable, dwe)
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
        CreateAndLoadBasicInfo(reader, exprTable, me)
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
        CreateAndLoadBasicInfo(reader, exprTable, lpd)
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
        CreateAndLoadBasicInfo(reader, exprTable, fie)
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
        CreateAndLoadBasicInfo(reader, exprTable, ue)
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
        CreateAndLoadBasicInfo(reader, exprTable, be)
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
        CreateAndLoadBasicInfo(reader, exprTable, se)
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
        CreateAndLoadBasicInfo(reader, exprTable, ae)
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
        CreateAndLoadBasicInfo(reader, exprTable, al)
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
        CreateAndLoadBasicInfo(reader, exprTable, tl)
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
        CreateAndLoadBasicInfo(reader, exprTable, ma)
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
        CreateAndLoadBasicInfo(reader, exprTable, re)
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

    private func CreateAndLoadBasicInfo(reader: CjoFlatBuffer, exprTable: Int64, expr: Expr): Unit {
        LoadFlatNodeBasicInfo(reader, exprTable, expr)
        expr.overflowStrategy = FlatOverflowStrategy(reader.U8Field(exprTable, 16, 0u8))
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
        CreateAndLoadBasicInfo(reader, exprTable, lce)
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
        pattern.matchBeforeRuntime = reader.U8Field(patternTable, 20, 0u8) != 0u8
        pattern.needRuntimeTypeCheck = reader.U8Field(patternTable, 22, 0u8) != 0u8
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

    // C++: Modules/ASTSerialization/ASTLoader.cpp:867-879.
    private func LoadAnnoTargets(reader: CjoFlatBuffer, infoTable: Int64, annotation: Annotation): Unit {
        let anno1 = reader.U8Field(infoTable, 12, 0u8)
        if (anno1 == 0xffu8) {
            annotation.target = 0xffffu16
            return
        }
        let anno2 = reader.U8Field(infoTable, 16, 0u8)
        annotation.target = (UInt16(anno2) << 7) | UInt16(anno1)
    }

    // C++: Modules/ASTSerialization/ASTLoader.cpp:881-910.
    private func LoadInheritableDeclAdvancedInfo(reader: CjoFlatBuffer, record: CjoFlatDecl,
        parent: InheritableDecl): Unit {
        let infoTable = reader.OffsetField(record.table, 38)
        CJC_ASSERT(infoTable >= 0)
        if (parent.TestAttr(Attribute.IS_ANNOTATION)) {
            let anno1 = reader.U8Field(infoTable, 12, 0u8)
            let anno2 = reader.U8Field(infoTable, 16, 0u8)
            if (anno1 != 0u8 || anno2 != 0u8) {
                let annotation = Annotation()
                annotation.kind = AstAnnotationKind.ANNOTATION
                LoadAnnoTargets(reader, infoTable, annotation)
                annotation.runtimeVisible = reader.U8Field(infoTable, 14, 0u8) != 0u8
                parent.annotations.add(annotation)
            }
        }
        let body = reader.VectorField(infoTable, 6)
        CJC_ASSERT(body >= 0)
        var idx: Int64 = 0
        let count = reader.VectorLength(body)
        while (idx < count) {
            let memberIndex = reader.VectorU32(body, idx)
            let memberRecord = flatDecls.get(memberIndex).getOrThrow()
            let member = EnsureFlatDecl(memberRecord).getOrThrow()
            AddFlatMember(parent, member)
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

    private func AddDeclToImportedPackage(decl: Decl): Unit {
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
        reportError = reportError && !isChirNow
        if (decl.TestAttr(Attribute.FROM_COMMON_PART)) {
            reportError = false
            if (DeclaredInDifferentFiles(decl, existingDecl)) {
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

    private func DeclaredInDifferentFiles(left: Decl, right: Decl): Bool {
        if (let Some(leftFile) <- left.curFile) {
            if (let Some(rightFile) <- right.curFile) {
                return leftFile != rightFile
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
    public let declMap: TreeMap<String, ArrayList<Decl>> = TreeMap<String, ArrayList<Decl>>()
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

public class ImportManager <: SemaImportManager & SemaCjoManager & MacroHostImportManager {
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
    private let packageMembers: HashMap<String, TreeMap<String, ArrayList<Decl>>> =
        HashMap<String, TreeMap<String, ArrayList<Decl>>>()
    private let packageMembersVisited: HashSet<String> = HashSet<String>()
    private let importedPackageNameMap: HashMap<Node, (String, Bool)> =
        HashMap<Node, (String, Bool)>()
    private let visitedPkgs: HashSet<String> = HashSet<String>()
    private let typeAliasCache: HashMap<Int64, Ty> = HashMap<Int64, Ty>()
    private let commonPartLoaders: ArrayList<CjoSignatureMaterializer> = ArrayList<CjoSignatureMaterializer>()
    private let importedDeclsMap: TreeMap<String, ArrayList<Decl>> = TreeMap<String, ArrayList<Decl>>()
    private let fileImportedDeclsMap: HashMap<UInt64, TreeMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, TreeMap<String, ArrayList<Decl>>>()
    private let fileUsedMacroDeclsMap: HashMap<UInt64, TreeMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, TreeMap<String, ArrayList<Decl>>>()
    // Macro packages directly imported by a source package (keyed by full package name to dedupe).
    // Populated per source package during import resolution (UpdateMacroPackageUsage); exposed via
    // GetImportedPkgsForMacro for the macro-expansion pipeline.
    private let directMacroDeps: HashMap<String, Package> = HashMap<String, Package>()
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
        for (path in globalOptions.importPaths) {
            searchPath.add(path)
        }
        searchPath.add(".")
        for (path in globalOptions.environment.cangjiePaths) {
            searchPath.add(path)
        }
        searchPath.add(cangjieModules)
    }

    public func GetSearchPath(): ArrayList<String> {
        return searchPath
    }

    public func GeneratePkgDepInfo(pkgs: ArrayList<Package>): ArrayList<String> {
        let out = ArrayList<String>()
        for (pkg in pkgs) {
            out.add(GeneratePkgDepInfo(pkg, exportCJO: false))
        }
        return out
    }

    // Faithful port of C++ ImportManager::GeneratePkgDepInfo (src/Modules/ImportManager.cpp:691-747):
    // emit the full package dependency descriptor JSON (package / isMacro / accessLevel / structured
    // dependencies with import positions / transitive std-dependencies / feature set / product flag),
    // as consumed by --scan-dependency. exportCJO=true (the .cjo-write default) records import file
    // names rather than absolute paths and derives std-dependencies from the package's collected
    // dependent std packages.
    func GeneratePkgDepInfo(pkg: Package, exportCJO!: Bool = true): String {
        let dependencies = HashMap<String, FrontendDepInfoItem>()
        let features = HashSet<String>()
        var isProduct = true
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsImportMulti() || importSpec.TestAttr(Attribute.IMPLICIT_ADD)) {
                    continue
                }
                let names = importSpec.content.GetPossiblePackageNames()
                if (names.isEmpty()) {
                    continue
                }
                let longName = FileUtil.ToPackageName(names[0])
                let shortName = FileUtil.ToPackageName(names[names.size - 1])
                if (!dependencies.contains(longName)) {
                    dependencies[longName] = CreateDepInfoItem(longName, shortName)
                }
                if (let Some(item) <- dependencies.get(longName)) {
                    item.imports.add(importSpec)
                }
            }
            if (let Some(featureDirective) <- file.feature) {
                if (let Some(set) <- featureDirective.featuresSet) {
                    for (featureId in set.content) {
                        features.add(featureId.ToString())
                    }
                }
                for (anno in featureDirective.annotations) {
                    if (anno.kind == AstAnnotationKind.NON_PRODUCT) {
                        isProduct = false
                    }
                }
            }
        }
        return "{\"package\":\"" + EscapeJson(pkg.fullPackageName) + "\"," +
            "\"isMacro\":" + DepInfoBool(pkg.isMacroPackage) + "," +
            "\"accessLevel\":\"" + DepInfoAccessLevel(pkg.accessible) + "\"," +
            "\"dependencies\":" + DependenciesToJson(dependencies, exportCJO) + "," +
            "\"std-dependencies\":" + StdDependenciesToJson(dependencies, pkg, exportCJO) + "," +
            "\"features\":" + FeatureSetToJson(features) + "," +
            "\"product\":" + DepInfoBool(isProduct) + "}"
    }

    private func CreateDepInfoItem(longName: String, shortName: String): FrontendDepInfoItem {
        let item = FrontendDepInfoItem()
        if (STANDARD_LIBS.contains(longName)) {
            item.packageName = longName
            item.isStd = true
        } else if (STANDARD_LIBS.contains(shortName)) {
            item.packageName = shortName
            item.isStd = true
        } else {
            item.packageName = shortName
            if (longName != shortName) {
                item.orPackage = longName
            }
            item.isStd = false
        }
        return item
    }

    private func DependenciesToJson(dependencies: HashMap<String, FrontendDepInfoItem>, exportCJO: Bool): String {
        let keys = ArrayList<String>()
        for (key in dependencies.keys()) {
            keys.add(key)
        }
        sort(keys)
        let items = ArrayList<String>()
        for (name in keys) {
            if (let Some(item) <- dependencies.get(name)) {
                items.add(DependencyItemToJson(item, exportCJO))
            }
        }
        return "[" + JoinStrings(items, ",") + "]"
    }

    private func DependencyItemToJson(item: FrontendDepInfoItem, exportCJO: Bool): String {
        SortImportSpecsByPosition(item.imports)
        var value = "{\"package\":\"" + EscapeJson(item.packageName) + "\","
        if (!item.orPackage.isEmpty()) {
            value += "\"orPackage\":\"" + EscapeJson(item.orPackage) + "\","
        }
        value += "\"isStd\":" + DepInfoBool(item.isStd) + ","
        value += "\"imports\":" + ImportSpecsToJson(item.imports, exportCJO) + "}"
        return value
    }

    private func ImportSpecsToJson(imports: ArrayList<ImportSpec>, exportCJO: Bool): String {
        let items = ArrayList<String>()
        for (importSpec in imports) {
            items.add(ImportSpecToJson(importSpec, exportCJO))
        }
        return "[" + JoinStrings(items, ",") + "]"
    }

    private func ImportSpecToJson(importSpec: ImportSpec, exportCJO: Bool): String {
        var fileName = ""
        if (let Some(curFileValue) <- importSpec.curFile) {
            fileName = if (exportCJO) { curFileValue.fileName } else { curFileValue.filePath }
        }
        return "{\"file\":\"" + EscapeJson(fileName) + "\"," +
            "\"begin\":" + DepInfoPosition(importSpec.begin) + "," +
            "\"end\":" + DepInfoPosition(importSpec.end) + "}"
    }

    private func DepInfoPosition(pos: Position): String {
        return "{\"line\":" + pos.line.toString() + ",\"column\":" + pos.column.toString() + "}"
    }

    private func StdDependenciesToJson(
        dependencies: HashMap<String, FrontendDepInfoItem>,
        pkg: Package,
        exportCJO: Bool
    ): String {
        let stdDependencies = HashMap<String, HashSet<String>>()
        stdDependencies[CORE_PACKAGE_NAME] = HashSet<String>()
        if (exportCJO) {
            for (stdName in pkg.GetAllDependentStdPkgs()) {
                CollectStdDependency(stdDependencies, stdName)
            }
        } else {
            for (depName in dependencies.keys()) {
                if (let Some(item) <- dependencies.get(depName)) {
                    if (item.isStd) {
                        CollectStdDependency(stdDependencies, item.packageName)
                    }
                }
            }
        }
        let keys = ArrayList<String>()
        for (key in stdDependencies.keys()) {
            keys.add(key)
        }
        sort(keys)
        let items = ArrayList<String>()
        for (stdName in keys) {
            let imports = if (let Some(importSet) <- stdDependencies.get(stdName)) {
                FeatureSetToJson(importSet)
            } else {
                "[]"
            }
            items.add("{\"" + EscapeJson(stdName) + "\":" + imports + "}")
        }
        return "[" + JoinStrings(items, ",") + "]"
    }

    private func CollectStdDependency(stdDependencies: HashMap<String, HashSet<String>>, stdPkg: String): Unit {
        if (stdDependencies.contains(stdPkg)) {
            return
        }
        let importInfo = HashSet<String>()
        stdDependencies[stdPkg] = importInfo
        var pkgOpt = GetPackage(stdPkg)
        if (let None <- pkgOpt) {
            let cjoPath = FileUtil.FindSerializationFile(stdPkg, ".cjo", searchPath.toArray())
            if (cjoPath.isEmpty()) {
                diag.DiagnoseRefactor(DiagKindRefactor.package_search_error, DEFAULT_POSITION, arguments: [stdPkg])
                return
            }
            if (!LoadImportedPackageFromCjo(stdPkg, cjoPath)) {
                return
            }
            pkgOpt = GetPackage(stdPkg)
        }
        if (let Some(stdPkgInfo) <- pkgOpt) {
            for (file in stdPkgInfo.files) {
                for (importSpec in file.imports) {
                    importInfo.add(importSpec.content.GetImportedPackageNameWithIsDecl())
                }
            }
        }
        let importNames = ArrayList<String>()
        for (importName in importInfo) {
            importNames.add(importName)
        }
        for (importName in importNames) {
            CollectStdDependency(stdDependencies, importName)
        }
    }

    private func FeatureSetToJson(features: HashSet<String>): String {
        let ordered = ArrayList<String>()
        for (feature in features) {
            ordered.add(feature)
        }
        sort(ordered)
        let items = ArrayList<String>()
        for (feature in ordered) {
            items.add("\"" + EscapeJson(feature) + "\"")
        }
        return "[" + JoinStrings(items, ",") + "]"
    }

    private func SortImportSpecsByPosition(imports: ArrayList<ImportSpec>): Unit {
        sort(imports, by: { left: ImportSpec, right: ImportSpec =>
            if (left.begin < right.begin) {
                Ordering.LT
            } else if (right.begin < left.begin) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
    }

    private func DepInfoBool(value: Bool): String {
        return if (value) { "true" } else { "false" }
    }

    private func DepInfoAccessLevel(level: AccessLevel): String {
        return match (level) {
            case AccessLevel.PUBLIC => "public"
            case AccessLevel.PROTECTED => "protected"
            case _ => "internal"
        }
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
        directMacroDeps.clear()
        for (pkg in pkgs) {
            if (pkg.fullPackageName.isEmpty()) {
                diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "empty package name")
                return false
            }
            CheckPackageSpecsIdentical(pkg)
            AddImplicitImports(pkg, opts)
            sourcePackagesForMembers.add(pkg)
            AddSourcePackage(pkg)
        }
        ResolveImportedPackages(pkgs)
        for (pkg in pkgs) {
            dependencyGraph.getOrThrow().AddDependenciesForPackage(pkg)
        }
        for (pkg in pkgs) {
            RebuildPackageMembers(pkg.fullPackageName)
        }
        for (pkg in pkgs) {
            AddImportedDeclsForSourcePackage(pkg)
        }
        // Record each source package's directly-imported macro packages after the dependency graph is
        // built. Faithful to C++ ImportManager::ResolveImports -> UpdateMacroPackageUsage
        // (src/Modules/ImportManager.cpp:594-597,538-546): only direct (not transitive) imports count.
        for (pkg in pkgs) {
            UpdateMacroPackageUsage(pkg)
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

    private func CheckPackageSpecsIdentical(pkg: Package): Unit {
        let packageNamePosMap = ArrayList<(String, String, Position, Bool)>()
        for (file in pkg.files) {
            if (file.packageSpec.isNone() || file.begin == file.end) {
                var exists = false
                for (item in packageNamePosMap) {
                    if (item[0] == DEFAULT_PACKAGE_NAME && item[1] == "public") {
                        exists = true
                        break
                    }
                }
                if (!exists) {
                    packageNamePosMap.add((DEFAULT_PACKAGE_NAME, "public", file.begin, false))
                }
            } else if (let Some(packageSpec) <- file.packageSpec) {
                if (IsRootPackage(packageSpec) && !packageSpec.TestAttr(Attribute.PUBLIC)) {
                    DiagRootPackageModifier(diag, packageSpec)
                }
                let fullPackageName = packageSpec.GetPackageName()
                let accessLevel = GetAccessLevelStr(packageSpec)
                var exists = false
                for (item in packageNamePosMap) {
                    if (item[0] == fullPackageName && item[1] == accessLevel) {
                        exists = true
                        break
                    }
                }
                if (!exists) {
                    let position = if (packageSpec.prefixPaths.isEmpty()) {
                        packageSpec.packageName.Begin()
                    } else {
                        packageSpec.prefixPoses[0]
                    }
                    packageNamePosMap.add((fullPackageName, accessLevel, position, true))
                }
            }
        }
        sort(packageNamePosMap, by: { left: (String, String, Position, Bool),
            right: (String, String, Position, Bool) =>
            if (left[0] < right[0]) {
                Ordering.LT
            } else if (left[0] > right[0]) {
                Ordering.GT
            } else if (left[1] < right[1]) {
                Ordering.LT
            } else if (left[1] > right[1]) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        if (packageNamePosMap.size > 1) {
            DiagForDifferentPackageNames(diag, packageNamePosMap)
        }
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

    public func GetCjoManager(): SemaCjoManager {
        return this
    }

    public func GetAllImportedPackages(includeMacroPkg: Bool): ArrayList<PackageDecl> {
        return GetAllPackageDecls(includeMacroPkg: includeMacroPkg)
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

    // Faithful port of C++ ImportManager::UpdateMacroPackageUsage (src/Modules/ImportManager.cpp:538-546):
    // record the macro packages that pkg imports directly (GetCurImportedPackages returns direct
    // dependencies only), skipping compiler/tool-injected packages. Transitively-imported macro
    // packages are intentionally excluded.
    private func UpdateMacroPackageUsage(pkg: Package): Unit {
        for (importedPkg in GetCurImportedPackages(pkg.fullPackageName)) {
            if (!importedPkg.TestAttr(Attribute.TOOL_ADD) && importedPkg.isMacroPackage) {
                directMacroDeps[importedPkg.fullPackageName] = importedPkg
            }
        }
    }

    // Faithful port of C++ ImportManager::GetImportedPkgsForMacro (include/cangjie/Modules/ImportManager.h:246-249):
    // the set of macro packages directly imported by the compiled source packages.
    public func GetImportedPkgsForMacro(): ArrayList<Package> {
        let out = ArrayList<Package>()
        for (name in directMacroDeps.keys()) {
            if (let Some(pkg) <- directMacroDeps.get(name)) {
                out.add(pkg)
            }
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

    public func GetAllImportedDecls(file: File): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        for (group in GetImportedDecls(file)) {
            for (decl in group.decls) {
                AddDeclIfMissing(out, decl)
            }
        }
        return out
    }

    public func AddUsedMacroDecls(file: File, decl: Decl): Unit {
        if (!fileUsedMacroDeclsMap.contains(file.indexOfPackage)) {
            fileUsedMacroDeclsMap[file.indexOfPackage] = TreeMap<String, ArrayList<Decl>>()
        }
        if (let Some(usedDeclMap) <- fileUsedMacroDeclsMap.get(file.indexOfPackage)) {
            PutImportedDecl(usedDeclMap, decl.fullPackageName, decl)
        }
    }

    public func GetImportedStdMacroPackages(): ArrayList<String> {
        let stdMacroPackages = ["std.unittest.testmacro", "std.unittest.mock.mockmacro", "std.deriving"]
        let out = ArrayList<String>()
        for (packageName in stdMacroPackages) {
            if (GetPackageDecl(packageName).isSome()) {
                out.add(packageName)
            }
        }
        return out
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

    public func GetSyncDecl(name: String): Option<Decl> {
        return GetImportedDecl<Decl>(SYNC_PACKAGE_NAME, name)
    }

    public func GetImportedDecl<T>(packageName: String, name: String): Option<T> where T <: Decl {
        let decls = GetPackageMembersByName(packageName, name)
        if (decls.isEmpty()) {
            if (let Some(decl) <- GetImplicitPackageMembersByName(packageName, name)) {
                return DynamicCast<T>(decl)
            }
            return None
        }
        return DynamicCast<T>(decls[0])
    }

    public func GetCoreDecl<T>(name: String): Option<T> where T <: Decl {
        return GetImportedDecl<T>(CORE_PACKAGE_NAME, name)
    }

    public func GetAstDecl<T>(name: String): Option<T> where T <: Decl {
        return GetImportedDecl<T>(AST_PACKAGE_NAME, name)
    }

    public func GetImportedPackageDecl(node: Node, packageName: String): (Option<PackageDecl>, Bool) {
        if (let Some(file) <- node.curFile) {
            let decls = GetImportedDeclsByName(file, packageName)
            var ret: Option<PackageDecl> = None
            for (decl in decls) {
                if (let Some(packageDecl) <- (decl as PackageDecl)) {
                    if (let None <- ret) {
                        ret = Some(packageDecl)
                    } else {
                        return (ret, true)
                    }
                }
            }
            return (ret, false)
        }
        return (None, false)
    }

    private func CollectDeclsFromImportToMap(srcFullPackageName: String, importSpec: ImportSpec,
        targetMap: TreeMap<String, ArrayList<Decl>>): Unit {
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
            if (let Some(info) <- GetPackageInfo(targetPackageName)) {
                for (name in info.declMap.keys()) {
                    let decls = info.declMap.get(name) ?? continue
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

    public func GetPackageMembersByName(pkg: Package, name: String): ArrayList<Decl> {
        return GetPackageMembersByName(pkg.fullPackageName, name)
    }

    public func GetImportedDeclsByName(file: File, name: String): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        if (let Some(decls) <- importedDeclsMap.get(name)) {
            for (decl in decls) {
                AddDeclIfMissing(out, decl)
            }
        }
        if (let Some(fileMap) <- fileImportedDeclsMap.get(file.fileHash)) {
            if (let Some(decls2) <- fileMap.get(name)) {
                for (decl2 in decls2) {
                    AddDeclIfMissing(out, decl2)
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
        declMap: TreeMap<String, ArrayList<Decl>>
    ): Unit {
        if (let None <- GetPackageInfo(importedPackage)) {
            return
        }
        let importLevel = GetAccessLevel(importSpec)
        if (importSpec.IsImportAll()) {
            if (let Some(info) <- GetPackageInfo(importedPackage)) {
                for (name in info.declMap.keys()) {
                    let decls = info.declMap.get(name) ?? continue
                    if (!declMap.contains(name)) {
                        declMap.add(name, ArrayList<Decl>())
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
            declMap.add(targetName, ArrayList<Decl>())
        }
        if (let Some(targetMap) <- declMap.get(targetName)) {
            AddImportedDeclToMap(decls, targetMap, importLevel)
        }
    }

    private func AddDeclToMap(decl: Decl, declMap: TreeMap<String, ArrayList<Decl>>): Unit {
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

    private func GetFileImportedDeclMap(fileHash: UInt64): TreeMap<String, ArrayList<Decl>> {
        if (!fileImportedDeclsMap.contains(fileHash)) {
            fileImportedDeclsMap[fileHash] = TreeMap<String, ArrayList<Decl>>()
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

    private func PutImportedDecl(map: TreeMap<String, ArrayList<Decl>>, name: String, decl: Decl): Unit {
        if (!map.contains(name)) {
            map.add(name, ArrayList<Decl>())
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
        var idx: Int64 = 0
        while (idx < values.size) {
            if (CompNodeByPos(decl, values[idx])) {
                values.add(decl, at: idx)
                return
            }
            idx++
        }
        values.add(decl)
    }

    private func CompNodeByPos(left: Decl, right: Decl): Bool {
        return left.begin.fileID < right.begin.fileID ||
            (left.begin.fileID == right.begin.fileID && left.begin < right.begin) ||
            (left.begin.fileID == right.begin.fileID && left.begin == right.begin && left.objectId < right.objectId)
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
            CheckRedefinition(pkg)
        }
    }

    private func CheckRedefinition(pkg: Package): Unit {
        let pkgImportNamePos = HashMap<String, BasicRange>()
        let fileImportNamePos = HashMap<File, HashMap<String, BasicRange>>()
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsImportMulti() || importSpec.IsImportAll()) {
                    continue
                }
                let im = importSpec.content
                let name = if (importSpec.IsImportSingle()) { im.identifier.Val() } else { im.aliasName.Val() }
                let decls = GetImportedDeclsByName(file, name)
                if (decls.isEmpty()) {
                    continue
                }
                let range = if (importSpec.IsImportSingle()) {
                    MakeRange(im.identifier.Begin(), im.identifier.Val())
                } else {
                    MakeRange(im.aliasName.Begin(), im.aliasName.Val())
                }
                let posMap = if (importSpec.IsReExport()) {
                    pkgImportNamePos
                } else {
                    if (!fileImportNamePos.contains(file)) {
                        fileImportNamePos[file] = HashMap<String, BasicRange>()
                    }
                    fileImportNamePos.get(file).getOrThrow()
                }
                var success = !posMap.contains(name)
                var previous = posMap.get(name)
                if (success) {
                    posMap[name] = range
                }
                if (importSpec.IsReExport() && success) {
                    if (!fileImportNamePos.contains(file)) {
                        fileImportNamePos[file] = HashMap<String, BasicRange>()
                    }
                    let filePosMap = fileImportNamePos.get(file).getOrThrow()
                    success = !filePosMap.contains(name)
                    previous = filePosMap.get(name)
                    if (success) {
                        filePosMap[name] = range
                    }
                }
                let sourceDecls = ArrayList<Decl>()
                for (decl in GetPackageMembersByName(pkg.fullPackageName, name)) {
                    if (let Some(declFile) <- decl.curFile) {
                        if (let Some(declPackage) <- declFile.curPackage) {
                            if (declPackage == pkg) {
                                sourceDecls.add(decl)
                            }
                        }
                    }
                }
                if (!IsAllFuncDecl(sourceDecls)) {
                    WarnUselessImport(diag, range, sourceDecls[0])
                } else if (!success) {
                    WarnConflictImport(diag, name, range, previous.getOrThrow())
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
            packageMembers[fullPackageName] = TreeMap<String, ArrayList<Decl>>()
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
        targetMembers: TreeMap<String, ArrayList<Decl>>
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
        targetMembers: TreeMap<String, ArrayList<Decl>>,
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

    private func ReadCjo(fullPackageName: String, cjoPath: String, printErr!: Bool = true,
        sourcePackage!: Option<Package> = None): Option<CjoSignatureMaterializer> {
        let (ok, data, reason) = FileUtil.ReadBinaryFileToBuffer(cjoPath)
        if (!ok && printErr) {
            diag.DiagnoseRefactor(DiagKindRefactor.module_read_file_to_buffer_failed, DEFAULT_POSITION,
                arguments: [cjoPath, reason])
            return None
        }
        let pkg = sourcePackage ?? CreatePackage(fullPackageName)
        let filesByIndex = HashMap<UInt32, File>()
        let idToFileMap = HashMap<UInt64, File>()
        if (sourcePackage.isSome()) {
            var fileIndex: Int64 = 0
            while (fileIndex < pkg.files.size) {
                let file = pkg.files[fileIndex]
                filesByIndex.add(UInt32(fileIndex + 1), file)
                idToFileMap.add(file.begin.fileID, file)
                fileIndex++
            }
        }
        let materializer = CjoSignatureMaterializer(fullPackageName, pkg, filesByIndex, idToFileMap, importedPackages,
            packageDecls, exportIdDeclMaps, diag, typeManager, importSrcCode: importSrcCode,
            deserializingCommon: sourcePackage.isNone(), canInline: canInlineImportedSource, data: Some(data))
        return Some(materializer)
    }

    // CjoManager.cpp:487-500 CjoManager::LoadCachedPackage.
    public func LoadCachedPackage(pkg: Package, cjoPath: String,
        mangledName2DeclMap: HashMap<String, Decl>): HashSet<String> {
        let loader = ReadCjo(pkg.fullPackageName, cjoPath, printErr: false, sourcePackage: Some(pkg))
        if (loader.isNone()) {
            return HashSet<String>()
        }
        let result = loader.getOrThrow().LoadCachedTypeForPackage(pkg, mangledName2DeclMap)
        for (file in pkg.files) {
            ReplaceTypeAliasInNode(file)
        }
        return result
    }

    // ImportManager.cpp:365-370 ImportManager::LoadCachedTypeForPackage.
    public func LoadCachedTypeForPackage(pkg: Package,
        mangledName2DeclMap: HashMap<String, Decl>): HashSet<String> {
        let cachedCjo = globalOptions.GenerateCachedPathName(
            pkg.fullPackageName, SERIALIZED_FILE_EXTENSION)
        return LoadCachedPackage(pkg, cachedCjo, mangledName2DeclMap)
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

    private func AddImplicitImports(pkg: Package, opts: GlobalOptions): Unit {
        for (file in pkg.files) {
            if (opts.implicitPrelude) {
                AddImplicitImportAll(file, "std.core")
            }
            if (opts.enableCompileTest) {
                AddImplicitImportAll(file, "std.unittest")
                AddImplicitImportAll(file, "std.unittest.testmacro")
            }
            if (opts.compileTestsOnly && IsTestPackage(pkg.fullPackageName)) {
                AddImplicitImportAll(file, GetMainPartPkgNameForTestPkg(pkg.fullPackageName))
            }
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

    private func AddNoteForExtendExportDiag(builder: Option<DiagnosticBuilder>, note: String): Unit {
        if (let Some(b) <- builder) {
            b.AddNote(note)
        }
    }

    private func AddNoteForExtendExportDiag(builder: Option<DiagnosticBuilder>, range: BasicRange, note: String): Unit {
        if (let Some(b) <- builder) {
            b.AddNote(range, "to use the following extension, import '" + note + "'")
        }
    }

    private func GetExtendTypeAliasRealTarget(decl: Decl): Decl {
        if (let Some(tad) <- (decl as TypeAliasDecl)) {
            if (let Some(typeNode) <- tad.typeNode) {
                if (!tad.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                    if (let Some(realTarget) <- typeNode.GetTarget()) {
                        return GetExtendTypeAliasRealTarget(realTarget)
                    }
                }
            }
        }
        return decl
    }

    public func IsTypeAccessible(file: File, typeNode: Type): Bool {
        // NOTE: For compatibility reason, extension declaration's visibility does not depend on alias declarations.
        if (let Some(target) <- typeNode.GetTarget()) {
            let decl = GetExtendTypeAliasRealTarget(target)
            return typeManager.IsDeclAccessible(file, decl)
        }
        // Builtin type and primitive type is always accessible.
        return true
    }

    public func IsExtendAllUpperBoundsImported(ed: ExtendDecl, file: File, builder: Option<DiagnosticBuilder>): Bool {
        if (let None <- ed.generic) {
            return true
        }
        let upperboundsNotImported = TreeSet<String>()
        var areAllUpperBoundsImported = true
        for (gc in ed.generic.getOrThrow().genericConstraints) {
            for (ub in gc.upperBounds) {
                if (!IsTypeAccessible(file, ub)) {
                    areAllUpperBoundsImported = false
                    upperboundsNotImported.add(ub.GetTy().getOrThrow().String())
                    break
                }
            }
        }
        for (up in upperboundsNotImported) {
            AddNoteForExtendExportDiag(builder, MakeRange(ed.begin, ed.end), up)
        }
        return areAllUpperBoundsImported
    }

    public func IsExtendAccessible(file: File, ed: ExtendDecl, builder: Option<DiagnosticBuilder>): Bool {
        if (let None <- file.curPackage) {
            return true
        }
        let filePackage = file.curPackage.getOrThrow()
        if (ed.fullPackageName == filePackage.fullPackageName) {
            return true
        }
        let curPkgName = filePackage.fullPackageName

        if (globalOptions.compileTestsOnly && ed.TestAttr(Attribute.FOR_TEST) && IsTestPackage(curPkgName) &&
            GetMainPartPkgNameForTestPkg(curPkgName) == ed.fullPackageName) {
            return true
        }
        let areAllUpperBoundsImported = IsExtendAllUpperBoundsImported(ed, file, builder)
        var hasAnyInterfacesImported = false
        var isExtendedTypeAccessible = false
        let extendedDecl = Ty.GetInheritableDeclPtrOfTy(ed.GetTy())
        let isInSamePkg = if (let Some(realExtendedDecl) <- extendedDecl) {
            ed.fullPackageName == realExtendedDecl.fullPackageName
        } else {
            ed.fullPackageName == "std.core"
        }
        if (!isInSamePkg) {
            for (inhert in ed.inheritedTypes) {
                if (IsTypeAccessible(file, inhert)) {
                    hasAnyInterfacesImported = true
                }
            }
            isExtendedTypeAccessible = IsTypeAccessible(file, ed.extendedType.getOrThrow())
        } else {
            hasAnyInterfacesImported = true
            if (let Some(realExtendedDecl) <- extendedDecl) {
                let relation = GetFrontendPackageRelation(filePackage.fullPackageName, realExtendedDecl.fullPackageName)
                isExtendedTypeAccessible = IsFrontendVisible(realExtendedDecl, relation)
            } else {
                isExtendedTypeAccessible = true
            }
        }
        if (!hasAnyInterfacesImported) {
            if (let Some(b) <- builder) {
                b.AddNote(MakeRange(ed.begin, ed.end),
                    "to use the following extension, you must import at least one of its inherited interfaces")
            }
        }
        // For direct extension, all upperbound (if any) need to be imported.
        // For interface extension, all upperbound (if any) and at lest one interface need to be imported.
        if (!isExtendedTypeAccessible) {
            AddNoteForExtendExportDiag(builder, MakeRange(ed.begin, ed.end),
                ed.extendedType.getOrThrow().GetTy().getOrThrow().String())
        }
        let isExtendImported = areAllUpperBoundsImported && hasAnyInterfacesImported && isExtendedTypeAccessible
        return ed.IsExportedDecl() && isExtendImported
    }

    private func FindImplmentInterface(file: File, member: Decl, it: Type): Option<Type> {
        let _ = file
        let targetDecl = Ty.GetInheritableDeclPtrOfTy(it.GetTy())
        if (let None <- targetDecl) {
            return None
        }
        let target = targetDecl.getOrThrow()
        for (superType in target.inheritedTypes) {
            if (let Some(implInterface) <- FindImplmentInterface(file, member, superType)) {
                return Some(implInterface)
            }
        }
        for (m in target.GetMemberDecls()) {
            if (typeManager.PairIsOverrideOrImpl(member, m)) {
                return Some(it)
            }
        }
        return None
    }

    public func IsExtendMemberImported(extendDecl: ExtendDecl, file: File, member: Decl,
        builder: Option<DiagnosticBuilder>): Bool {
        if (extendDecl.inheritedTypes.isEmpty()) {
            return true
        }
        let extendedDecl = Ty.GetInheritableDeclPtrOfTy(extendDecl.GetTy())
        let isInSamePkg = if (let Some(realExtendedDecl) <- extendedDecl) {
            extendDecl.fullPackageName == realExtendedDecl.fullPackageName
        } else {
            extendDecl.fullPackageName == "std.core"
        }
        if (isInSamePkg) {
            if (!IsTypeAccessible(file, extendDecl.extendedType.getOrThrow())) {
                AddNoteForExtendExportDiag(builder, MakeRange(extendDecl.begin, extendDecl.end),
                    extendDecl.GetTy().getOrThrow().String())
                return false
            }
            return true
        }
        // Check whether the interface to which the member belongs is imported.
        for (superType in extendDecl.inheritedTypes) {
            if (let Some(implInterface) <- FindImplmentInterface(file, member, superType)) {
                if (!IsTypeAccessible(file, implInterface)) {
                    AddNoteForExtendExportDiag(builder, MakeRange(extendDecl.begin, extendDecl.end),
                        implInterface.GetTy().getOrThrow().String())
                    return false
                }
                return true
            }
        }
        return false
    }

    public func IsExtendMemberAccessible(file: File, member: Decl, baseTy: Ty,
        builder: Option<DiagnosticBuilder>): Bool {
        let extendOpt = typeManager.GetExtendDeclByMember(member, baseTy)
        if ((let None <- extendOpt) || (let None <- file.curPackage)) {
            return true
        }
        let extendDecl = extendOpt.getOrThrow()
        let curPkgName = file.curPackage.getOrThrow().fullPackageName
        if (globalOptions.compileTestsOnly && !member.TestAttr(Attribute.PRIVATE) &&
            extendDecl.TestAttr(Attribute.FOR_TEST) && IsTestPackage(curPkgName) &&
            GetMainPartPkgNameForTestPkg(curPkgName) == member.fullPackageName) {
            return true
        }
        // Access to extended members must meet the following four requirements:
        // 1. extension is exported.
        // 2. extension is imported. `IsExtendAccessible` checks 1 and 2.
        // 3. extension member is exported. `IsExportedDecl` checks 3.
        // 4. extension member is imported.
        if (extendDecl.fullPackageName == curPkgName) {
            return true
        }
        if (!IsExtendAccessible(file, extendDecl, builder)) {
            return false
        }
        if (!member.IsExportedDecl()) {
            AddNoteForExtendExportDiag(builder,
                "cannot access this member because it is not declared in any interface implemented by the extension")
            return false
        }

        return IsExtendMemberImported(extendDecl, file, member, builder)
    }

    private func IsTestPackage(pkgName: String): Bool {
        return pkgName.size >= 5 && pkgName[pkgName.size - 5..pkgName.size] == "$test"
    }

    private func GetMainPartPkgNameForTestPkg(testPkgName: String): String {
        return testPkgName[0..testPkgName.size - 5]
    }
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
    private let impl: RealTestManager

    public init(importManager: SemaImportManager, typeManager: FaithfulSemaTypeManager,
        diag: BasicDiagnosticEngine, compilationOptions: GlobalOptions) {
        impl = RealTestManager(importManager, typeManager, diag, compilationOptions)
    }

    public func MarkDeclsForTestIfNeeded(pkgs: ArrayList<Package>): Unit {
        impl.MarkDeclsForTestIfNeeded(pkgs)
    }

    public func PrepareToMock(pkgs: ArrayList<Package>): Unit {
        for (pkg in pkgs) {
            impl.PrepareToMock(pkg)
        }
    }

    // The GenericInstantiation mock hooks need the sema TestManager directly (the
    // sema.GenericInstantiation package cannot see this frontend wrapper).
    public func GetImpl(): RealTestManager {
        return impl
    }
}

public func EscapeJson(text: String): String {
    return text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")
}

// One entry of the "dependencies" array in the package dependency descriptor (see
// GeneratePkgDepInfo). Mirrors C++ DependencyInfoItem (src/Modules/ImportManager.cpp:85-90).
private class FrontendDepInfoItem {
    public var packageName: String = ""
    public var orPackage: String = ""
    public var isStd: Bool = false
    public let imports: ArrayList<ImportSpec> = ArrayList<ImportSpec>()

    public init() {}
}

public let DIR_SEPARATOR: String = "/"
