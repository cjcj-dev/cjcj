package cangjie_compiler::option

public enum Kind {
    | UNKNOWN | FLAG | FLAG_WITH_ARG | SEPARATED | CONTINOUS
}

public enum Backend {
    | UNKNOWN | ALL | CJNATIVE
}

public enum Group {
    | UNKNOWN | GLOBAL | DRIVER | FRONTEND | STABLE | VISIBLE
}

public enum Occurrence {
    | UNKNOWN | SINGLE_OCCURRENCE | MULTIPLE_OCCURRENCE
}

public enum ID {
    | DUMP_TOKENS | DUMP_SYMBOLS | TYPE_CHECK | COMPILE_CJD | DIAG_FORMAT | BACKEND_MODE
    | DUMP_DEPENDENT_PACKAGE | NO_SUB_PACKAGE | CONDITIONAL_COMPILATION_CONFIG
    | COMPILE_DEBUG_MACRO | PARALLEL_MACRO_EXPANSION | COMPILE_DEBUG | TRIMPATH | STRIP_ALL
    | NO_STACKTRACE_INFO | COMPILE_TEST | COMPILE_TESTS_ONLY | EXPORT_FOR_TESTS | MOCK
    | OUTPUT_FILE | OUTPUT_DIR | OUTPUT_JAVA_GEN_DIR | OUTPUT_OBJC_GEN_DIR | NO_PRELUDE
    | STATIC | STATIC_STD | DY_STD | STATIC_LIBS | DY_LIBS | LTO | COMPILE_AS_EXE
    | LTO_KEEP_PKG_VISIBILITY | PROFILE_COMPILE_TIME | PROFILE_COMPILE_MEMORY | ENABLE_EFFECTS
    | DUMP_AST | DUMP_CHIR | DUMP_IR | DUMP_ALL | DUMP_TO_SCREEN | DUMP_ANNOTATIONS_DEBUG
    | DESERIALIZE_CHIR_AND_DUMP | EMIT_CHIR | CHIR_WFC | ENABLE_CHIR_REDUNDANT_GETORTHROW_ELIMINATION
    | DISABLE_CHIR_USELESS_IMPORT_ELIMINATION | CHIR_EA | CONST_PROPAGATION | NO_CONST_PROPAGATION
    | FUNC_INLINING | NO_FUNC_INLINING | DEVIRTUALIZATION | NO_DEVIRTUALIZATION
    | REDUANDANT_RETURN_REMOVAL | NO_REDUANDANT_RETURN_REMOVAL | REDUNDANT_FUTURE_REMOVAL
    | NO_REDUNDANT_FUTURE_REMOVAL | REDUANDANT_ASSIGN_REMOVAL | NO_REDUANDANT_ASSIGN_REMOVAL
    | LOOP_INVARIANT_CODE_MOTION | NO_LOOP_INVARIANT_CODE_MOTION | SROA_OPT | NO_SROA_OPT
    | SWITCH_OPT | LETC_FOLDING | REF_FOLDING | ARRAY_LAMBDA_OPT | SANCOV_INLINE_8BIT
    | SANCOV_INLINE_BOOL_FLAG | SANCOV_TRACE_PC_GUARD | SANCOV_PC_TABLE | SANCOV_STACK_DEPTH
    | SANCOV_TRACE_COMPARES | SANCOV_TRACE_MEM_COMPARES | SANCOV_LEVEL_0 | SANCOV_LEVEL_1
    | SANCOV_LEVEL_2 | SANCOV_LEVEL_CUSTOM | DISABLE_SEMA_VIC | DISABLE_CHIR_OPT
    | DISABLE_BACKEND_OPT | CHIR_OPT_DEBUG | RENDER_CHIR | INT_OVERFLOW_MODE | FAST_MATH_MODE
    | OPT_OPTIONS | LLC_OPTIONS | LINK_OPTION | LINK_OPTIONS | LIBRARY_PATH | LIBRARY
    | USE_RUNTIME_RPATH | TOOLCHAIN | TARGET | TARGET_CPU | SYSROOT | OUTPUT_TYPE | COMPILE_TARGET
    | OPTIMIZATION_0 | OPTIMIZATION_1 | OPTIMIZATION_2 | OPTIMIZATION_3 | OPTIMIZATION_S
    | OPTIMIZATION_Z | OPTIMIZATION_CUSTOM | OPT_PASS_OPTIONS | MODULE_NAME | PACKAGE_COMPILE
    | IMPORT_PATH | PLUGIN_PATH | COMMON_PART_CJO | COMMON_PART_CHIR | INCRE_COMPILE | INCRE_DEBUG
    | SAVE_TEMPS | WARN_OFF | WARN_ON | ERROR_COUNT_LIMIT | VERBOSE | VERSION | HELP
    | COMPILE_MACRO | ENABLE_COVERAGE | EXPERIMENTAL | DEBUG_CODEGEN | JOBS
    | AGGRESSIVE_PARALLEL_COMPILE | SANITIZE | SANITIZE_SET_RPATH | STACK_TRACE_FORMAT
    | FUNC_SECTIONS | NO_FUNC_SECTIONS | DATA_SECTIONS | NO_DATA_SECTIONS | GC_SECTIONS
    | NO_GC_SECTIONS | PGO_INSTR_GEN | PGO_INSTR_USE | DISCARD_EH_FRAME
}

public enum ArgInstanceType { | Input | Option }
public enum ArgType { | FullyParsed | PartiallyParsed }
public enum PathType { | FILE | DIRECTORY }
public enum WarnGroup {
    | UNUSED | UNUSED_MAIN | DRIVER_ARG | DEPRECATED | UNSUPPORT_COMPILE_SOURCE | PACKAGE_IMPORT
    | PARSER | SEMANTICS | INTERPRETER | APILEVEL_CHECK | UNGROUPED | NONE
}
public enum DiagFormat { | JSON | NO_COLOR | DEFAULT }
public enum MockMode { | ON | OFF | RUNTIME_ERROR | DEFAULT }
public enum BackendType { | CJNATIVE | UNKNOWN }
public enum ArchType { | X86_64 | AARCH64 | ARM64 | ARM32 | UNKNOWN }
public enum OSType { | WINDOWS | LINUX | DARWIN | IOS | UNKNOWN }
public enum Vendor { | PC | APPLE | UNKNOWN }
public enum EnvironmentType { | OHOS | GNU | ANDROID | SIMULATOR | NOT_AVAILABLE }
public enum InteropLanguage { | NA | Java | ObjC }
public enum OptimizationLevel { | O0 | O1 | O2 | O3 | Os | Oz }
public enum OutputMode { | EXECUTABLE | STATIC_LIB | SHARED_LIB | CHIR | OBJ }
public enum CompileTarget { | EXECUTABLE | STATIC_LIB | SHARED_LIB | DEFAULT }
public enum LTOMode { | FULL_LTO | THIN_LTO | NO_LTO }
public enum SanitizerCoverageType { | SCK_UNKNOW | SCK_NONE | SCK_FUNCTION | SCK_BB }
public enum StackTraceFormat { | DEFAULT | SIMPLE | ALL }
public enum OptimizationFlag {
    | SWITCH_OPT | CONST_PROPAGATION | LETC_FOLDING | REF_FOLDING | REF_TO_LETC
    | REDUNDANT_RETURNS | REDUNDANT_FUTURE | FUNC_INLINING | DEVIRTUALIZATION
    | REMOVE_REDUNDANT_ASG | ARRAY_LAMBDA_OPT | SROA_OPT | LOOP_INVARIANT_CODE_MOTION
    | VALUE_RANGE_ANALYSIS | REDUNDANT_LOAD
}
public enum PrintBCHIROption { | DESERIALIED | LINKED | CHIR2BCHIR | CE_CHIR2BCHIR | INTERPRETER | CE_LINKED | ALL }
public enum CHIRMode { | NA | STANDARD | WITH_ID | ALL }
public enum SanitizerType { | NONE | ADDRESS | THREAD | HWADDRESS }
public enum CandidateEmitCHIRPhase { | NA | RAW | OPT }
public enum OverflowStrategy { | NA | CHECKED | WRAPPING | THROWING | SATURATING }

public func KindIndex(value: Kind): Int64 {
    return match (value) {
        case Kind.UNKNOWN => 0
        case Kind.FLAG => 1
        case Kind.FLAG_WITH_ARG => 2
        case Kind.SEPARATED => 3
        case Kind.CONTINOUS => 4
    }
}
extend Kind <: Equatable<Kind> {
    public operator func ==(right: Kind): Bool { return KindIndex(this) == KindIndex(right) }
    public operator func !=(right: Kind): Bool { return !(this == right) }
}

public func BackendIndex(value: Backend): Int64 {
    return match (value) {
        case Backend.UNKNOWN => 0
        case Backend.ALL => 1
        case Backend.CJNATIVE => 2
    }
}
extend Backend <: Equatable<Backend> {
    public operator func ==(right: Backend): Bool { return BackendIndex(this) == BackendIndex(right) }
    public operator func !=(right: Backend): Bool { return !(this == right) }
}

public func GroupIndex(value: Group): Int64 {
    return match (value) {
        case Group.UNKNOWN => 0
        case Group.GLOBAL => 1
        case Group.DRIVER => 2
        case Group.FRONTEND => 3
        case Group.STABLE => 4
        case Group.VISIBLE => 5
    }
}
extend Group <: Equatable<Group> {
    public operator func ==(right: Group): Bool { return GroupIndex(this) == GroupIndex(right) }
    public operator func !=(right: Group): Bool { return !(this == right) }
}

public func OccurrenceIndex(value: Occurrence): Int64 {
    return match (value) {
        case Occurrence.UNKNOWN => 0
        case Occurrence.SINGLE_OCCURRENCE => 1
        case Occurrence.MULTIPLE_OCCURRENCE => 2
    }
}
extend Occurrence <: Equatable<Occurrence> {
    public operator func ==(right: Occurrence): Bool { return OccurrenceIndex(this) == OccurrenceIndex(right) }
    public operator func !=(right: Occurrence): Bool { return !(this == right) }
}

public func ArgInstanceTypeIndex(value: ArgInstanceType): Int64 {
    return match (value) {
        case ArgInstanceType.Input => 0
        case ArgInstanceType.Option => 1
    }
}
extend ArgInstanceType <: Equatable<ArgInstanceType> {
    public operator func ==(right: ArgInstanceType): Bool { return ArgInstanceTypeIndex(this) == ArgInstanceTypeIndex(right) }
    public operator func !=(right: ArgInstanceType): Bool { return !(this == right) }
}

public func ArgTypeIndex(value: ArgType): Int64 {
    return match (value) {
        case ArgType.FullyParsed => 0
        case ArgType.PartiallyParsed => 1
    }
}
extend ArgType <: Equatable<ArgType> {
    public operator func ==(right: ArgType): Bool { return ArgTypeIndex(this) == ArgTypeIndex(right) }
    public operator func !=(right: ArgType): Bool { return !(this == right) }
}

public func IDIndex(value: ID): Int64 {
    return match (value) {
        case ID.OUTPUT_FILE => 1
        case ID.OUTPUT_DIR => 2
        case ID.IMPORT_PATH => 3
        case ID.PACKAGE_COMPILE => 4
        case ID.MODULE_NAME => 5
        case ID.TARGET => 6
        case ID.OUTPUT_TYPE => 7
        case ID.COMPILE_TARGET => 8
        case ID.OPTIMIZATION_0 => 9
        case ID.OPTIMIZATION_1 => 10
        case ID.OPTIMIZATION_2 => 11
        case ID.OPTIMIZATION_3 => 12
        case ID.OPTIMIZATION_S => 13
        case ID.OPTIMIZATION_Z => 14
        case ID.OPTIMIZATION_CUSTOM => 15
        case ID.WARN_OFF => 16
        case ID.WARN_ON => 17
        case ID.ERROR_COUNT_LIMIT => 18
        case ID.VERBOSE => 19
        case ID.VERSION => 20
        case ID.HELP => 21
        case ID.EXPERIMENTAL => 22
        case ID.BACKEND_MODE => 23
        case ID.CONDITIONAL_COMPILATION_CONFIG => 24
        case ID.COMPILE_DEBUG => 25
        case ID.NO_PRELUDE => 26
        case ID.STATIC_STD => 27
        case ID.DY_STD => 28
        case ID.LTO => 29
        case ID.COMPILE_AS_EXE => 30
        case ID.LTO_KEEP_PKG_VISIBILITY => 31
        case ID.DUMP_AST => 32
        case ID.DUMP_CHIR => 33
        case ID.DUMP_IR => 34
        case ID.DUMP_ALL => 35
        case ID.DUMP_TO_SCREEN => 36
        case ID.CHIR_EA => 37
        case ID.CHIR_WFC => 38
        case ID.DISABLE_CHIR_OPT => 39
        case ID.DISABLE_BACKEND_OPT => 40
        case ID.SANITIZE => 41
        case ID.JOBS => 42
        case ID.AGGRESSIVE_PARALLEL_COMPILE => 43
        case _ => -1
    }
}
extend ID <: Equatable<ID> {
    public operator func ==(right: ID): Bool { return IDIndex(this) == IDIndex(right) }
    public operator func !=(right: ID): Bool { return !(this == right) }
}

public func WarnGroupIndex(value: WarnGroup): Int64 {
    return match (value) {
        case WarnGroup.UNUSED => 0
        case WarnGroup.UNUSED_MAIN => 1
        case WarnGroup.DRIVER_ARG => 2
        case WarnGroup.DEPRECATED => 3
        case WarnGroup.UNSUPPORT_COMPILE_SOURCE => 4
        case WarnGroup.PACKAGE_IMPORT => 5
        case WarnGroup.PARSER => 6
        case WarnGroup.SEMANTICS => 7
        case WarnGroup.INTERPRETER => 8
        case WarnGroup.APILEVEL_CHECK => 9
        case WarnGroup.UNGROUPED => 10
        case WarnGroup.NONE => 11
    }
}
extend WarnGroup <: Equatable<WarnGroup> {
    public operator func ==(right: WarnGroup): Bool { return WarnGroupIndex(this) == WarnGroupIndex(right) }
    public operator func !=(right: WarnGroup): Bool { return !(this == right) }
}

public func enumIndex(value: OptimizationLevel): Int64 {
    return match (value) {
        case OptimizationLevel.O0 => 0
        case OptimizationLevel.O1 => 1
        case OptimizationLevel.O2 => 2
        case OptimizationLevel.O3 => 3
        case OptimizationLevel.Os => 4
        case OptimizationLevel.Oz => 5
    }
}

extend OptimizationLevel <: Equatable<OptimizationLevel> {
    public operator func ==(right: OptimizationLevel): Bool { return enumIndex(this) == enumIndex(right) }
    public operator func !=(right: OptimizationLevel): Bool { return !(this == right) }
}

public func BackendTypeIndex(value: BackendType): Int64 {
    return match (value) {
        case BackendType.CJNATIVE => 0
        case BackendType.UNKNOWN => 1
    }
}
extend BackendType <: Equatable<BackendType> {
    public operator func ==(right: BackendType): Bool { return BackendTypeIndex(this) == BackendTypeIndex(right) }
    public operator func !=(right: BackendType): Bool { return !(this == right) }
}

public func ArchTypeIndex(value: ArchType): Int64 {
    return match (value) {
        case ArchType.X86_64 => 0
        case ArchType.AARCH64 => 1
        case ArchType.ARM64 => 2
        case ArchType.ARM32 => 3
        case ArchType.UNKNOWN => 4
    }
}
extend ArchType <: Equatable<ArchType> {
    public operator func ==(right: ArchType): Bool { return ArchTypeIndex(this) == ArchTypeIndex(right) }
    public operator func !=(right: ArchType): Bool { return !(this == right) }
}

public func OSTypeIndex(value: OSType): Int64 {
    return match (value) {
        case OSType.WINDOWS => 0
        case OSType.LINUX => 1
        case OSType.DARWIN => 2
        case OSType.IOS => 3
        case OSType.UNKNOWN => 4
    }
}
extend OSType <: Equatable<OSType> {
    public operator func ==(right: OSType): Bool { return OSTypeIndex(this) == OSTypeIndex(right) }
    public operator func !=(right: OSType): Bool { return !(this == right) }
}

public func VendorIndex(value: Vendor): Int64 {
    return match (value) {
        case Vendor.PC => 0
        case Vendor.APPLE => 1
        case Vendor.UNKNOWN => 2
    }
}
extend Vendor <: Equatable<Vendor> {
    public operator func ==(right: Vendor): Bool { return VendorIndex(this) == VendorIndex(right) }
    public operator func !=(right: Vendor): Bool { return !(this == right) }
}

public func EnvironmentTypeIndex(value: EnvironmentType): Int64 {
    return match (value) {
        case EnvironmentType.OHOS => 0
        case EnvironmentType.GNU => 1
        case EnvironmentType.ANDROID => 2
        case EnvironmentType.SIMULATOR => 3
        case EnvironmentType.NOT_AVAILABLE => 4
    }
}
extend EnvironmentType <: Equatable<EnvironmentType> {
    public operator func ==(right: EnvironmentType): Bool {
        return EnvironmentTypeIndex(this) == EnvironmentTypeIndex(right)
    }
    public operator func !=(right: EnvironmentType): Bool { return !(this == right) }
}

public func OutputModeIndex(value: OutputMode): Int64 {
    return match (value) {
        case OutputMode.EXECUTABLE => 0
        case OutputMode.STATIC_LIB => 1
        case OutputMode.SHARED_LIB => 2
        case OutputMode.CHIR => 3
        case OutputMode.OBJ => 4
    }
}
extend OutputMode <: Equatable<OutputMode> {
    public operator func ==(right: OutputMode): Bool { return OutputModeIndex(this) == OutputModeIndex(right) }
    public operator func !=(right: OutputMode): Bool { return !(this == right) }
}

public func CompileTargetIndex(value: CompileTarget): Int64 {
    return match (value) {
        case CompileTarget.EXECUTABLE => 0
        case CompileTarget.STATIC_LIB => 1
        case CompileTarget.SHARED_LIB => 2
        case CompileTarget.DEFAULT => 3
    }
}
extend CompileTarget <: Equatable<CompileTarget> {
    public operator func ==(right: CompileTarget): Bool { return CompileTargetIndex(this) == CompileTargetIndex(right) }
    public operator func !=(right: CompileTarget): Bool { return !(this == right) }
}

public func LTOModeIndex(value: LTOMode): Int64 {
    return match (value) {
        case LTOMode.FULL_LTO => 0
        case LTOMode.THIN_LTO => 1
        case LTOMode.NO_LTO => 2
    }
}
extend LTOMode <: Equatable<LTOMode> {
    public operator func ==(right: LTOMode): Bool { return LTOModeIndex(this) == LTOModeIndex(right) }
    public operator func !=(right: LTOMode): Bool { return !(this == right) }
}

public func SanitizerTypeIndex(value: SanitizerType): Int64 {
    return match (value) {
        case SanitizerType.NONE => 0
        case SanitizerType.ADDRESS => 1
        case SanitizerType.THREAD => 2
        case SanitizerType.HWADDRESS => 3
    }
}
extend SanitizerType <: Equatable<SanitizerType> {
    public operator func ==(right: SanitizerType): Bool { return SanitizerTypeIndex(this) == SanitizerTypeIndex(right) }
    public operator func !=(right: SanitizerType): Bool { return !(this == right) }
}
