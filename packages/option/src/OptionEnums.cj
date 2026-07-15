package cjcj::option

public import cjcj::utils.{OverflowStrategy, OverflowStrategyIndex}

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
    | DUMP_TOKENS | DUMP_SYMBOLS | TYPE_CHECK | COMPILE_CJD
    | DIAG_FORMAT | BACKEND_MODE | DUMP_DEPENDENT_PACKAGE | NO_SUB_PACKAGE
    | CONDITIONAL_COMPILATION_CONFIG | COMPILE_DEBUG_MACRO | PARALLEL_MACRO_EXPANSION | COMPILE_DEBUG
    | TRIMPATH | STRIP_ALL | NO_STACKTRACE_INFO | COMPILE_TEST
    | COMPILE_TESTS_ONLY | EXPORT_FOR_TESTS | MOCK | OUTPUT_FILE
    | OUTPUT_DIR | OUTPUT_JAVA_GEN_DIR | OUTPUT_OBJC_GEN_DIR | NO_PRELUDE
    | STATIC | STATIC_STD | DY_STD | STATIC_LIBS
    | DY_LIBS | LTO | LTO_STATICLIB_FORMAT | COMPILE_AS_EXE | LTO_KEEP_PKG_VISIBILITY
    | PROFILE_COMPILE_TIME | PROFILE_COMPILE_MEMORY | ENABLE_EFFECTS | DUMP_AST
    | DUMP_CHIR | DUMP_IR | DUMP_ALL | DUMP_TO_SCREEN
    | DUMP_ANNOTATIONS_DEBUG | DESERIALIZE_CHIR_AND_DUMP | EMIT_CHIR | CHIR_WFC
    | ENABLE_CHIR_REDUNDANT_GETORTHROW_ELIMINATION | DISABLE_CHIR_USELESS_IMPORT_ELIMINATION | CHIR_EA | CONST_PROPAGATION
    | NO_CONST_PROPAGATION | FUNC_INLINING | NO_FUNC_INLINING | DEVIRTUALIZATION
    | NO_DEVIRTUALIZATION | REDUANDANT_RETURN_REMOVAL | NO_REDUANDANT_RETURN_REMOVAL | REDUNDANT_FUTURE_REMOVAL
    | NO_REDUNDANT_FUTURE_REMOVAL | REDUANDANT_ASSIGN_REMOVAL | NO_REDUANDANT_ASSIGN_REMOVAL | LOOP_INVARIANT_CODE_MOTION
    | NO_LOOP_INVARIANT_CODE_MOTION | SROA_OPT | NO_SROA_OPT | SWITCH_OPT
    | LETC_FOLDING | REF_FOLDING | ARRAY_LAMBDA_OPT | SANCOV_INLINE_8BIT
    | SANCOV_INLINE_BOOL_FLAG | SANCOV_TRACE_PC_GUARD | SANCOV_PC_TABLE | SANCOV_STACK_DEPTH
    | SANCOV_TRACE_COMPARES | SANCOV_TRACE_MEM_COMPARES | SANCOV_LEVEL_0 | SANCOV_LEVEL_1
    | SANCOV_LEVEL_2 | SANCOV_LEVEL_CUSTOM | DISABLE_SEMA_VIC | DISABLE_CHIR_OPT
    | DISABLE_BACKEND_OPT | CHIR_OPT_DEBUG | RENDER_CHIR | INT_OVERFLOW_MODE
    | FAST_MATH_MODE | OPT_OPTIONS | LLC_OPTIONS | LINK_OPTION
    | LINK_OPTIONS | LIBRARY_PATH | LIBRARY | USE_RUNTIME_RPATH
    | TOOLCHAIN | TARGET | TARGET_CPU | SYSROOT
    | OUTPUT_TYPE | COMPILE_TARGET | OPTIMIZATION_0 | OPTIMIZATION_1
    | OPTIMIZATION_2 | OPTIMIZATION_3 | OPTIMIZATION_S | OPTIMIZATION_Z
    | OPTIMIZATION_CUSTOM | OPT_PASS_OPTIONS | MODULE_NAME | PACKAGE_COMPILE
    | IMPORT_PATH | PLUGIN_PATH | COMMON_PART_CJO | COMMON_PART_CHIR
    | INCRE_COMPILE | INCRE_DEBUG | SAVE_TEMPS | WARN_OFF
    | WARN_ON | ERROR_COUNT_LIMIT | VERBOSE | VERSION
    | HELP | COMPILE_MACRO | ENABLE_COVERAGE | EXPERIMENTAL
    | DEBUG_CODEGEN | JOBS | AGGRESSIVE_PARALLEL_COMPILE | SANITIZE
    | SANITIZE_SET_RPATH | OBF_STRING | NO_OBF_STRING | OBF_CONST
    | NO_OBF_CONST | OBF_LAYOUT | NO_OBF_LAYOUT | OBF_CF_FLATTEN
    | NO_OBF_CF_FLATTEN | OBF_CF_BOGUS | NO_OBF_CF_BOGUS | OBF_ALL
    | OBF_EXPORT_SYMS | NO_OBF_EXPORT_SYMS | OBF_SYM_INPUT_MAPPING | OBF_SYM_OUTPUT_MAPPING
    | OBF_MAP_FILE | OBF_SYM_PREFIX | OBF_SOURCE_PATH | NO_OBF_SOURCE_PATH
    | OBF_LINE_NUMBER | NO_OBF_LINE_NUMBER | OBF_CONFIG | OBF_LEVEL
    | OBF_SEED | INTERP_CONST_EVAL_DEBUG | PRINT_BCHIR | DISABLE_CODEGEN
    | DISABLE_REFLECTION | STACK_TRACE_FORMAT | FUNC_SECTIONS | NO_FUNC_SECTIONS
    | DATA_SECTIONS | NO_DATA_SECTIONS | GC_SECTIONS | NO_GC_SECTIONS
    | PGO_INSTR_GEN | PGO_INSTR_USE | DISCARD_EH_FRAME
}


public enum ArgInstanceType { | Input | Option }
public enum ArgType { | FullyParsed | PartiallyParsed }
public enum PathType { | FILE | DIRECTORY }
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
        case ID.DUMP_TOKENS => 0
        case ID.DUMP_SYMBOLS => 1
        case ID.TYPE_CHECK => 2
        case ID.COMPILE_CJD => 3
        case ID.DIAG_FORMAT => 4
        case ID.BACKEND_MODE => 5
        case ID.DUMP_DEPENDENT_PACKAGE => 6
        case ID.NO_SUB_PACKAGE => 7
        case ID.CONDITIONAL_COMPILATION_CONFIG => 8
        case ID.COMPILE_DEBUG_MACRO => 9
        case ID.PARALLEL_MACRO_EXPANSION => 10
        case ID.COMPILE_DEBUG => 11
        case ID.TRIMPATH => 12
        case ID.STRIP_ALL => 13
        case ID.NO_STACKTRACE_INFO => 14
        case ID.COMPILE_TEST => 15
        case ID.COMPILE_TESTS_ONLY => 16
        case ID.EXPORT_FOR_TESTS => 17
        case ID.MOCK => 18
        case ID.OUTPUT_FILE => 19
        case ID.OUTPUT_DIR => 20
        case ID.OUTPUT_JAVA_GEN_DIR => 21
        case ID.OUTPUT_OBJC_GEN_DIR => 22
        case ID.NO_PRELUDE => 23
        case ID.STATIC => 24
        case ID.STATIC_STD => 25
        case ID.DY_STD => 26
        case ID.STATIC_LIBS => 27
        case ID.DY_LIBS => 28
        case ID.LTO => 29
        case ID.COMPILE_AS_EXE => 30
        case ID.LTO_KEEP_PKG_VISIBILITY => 31
        case ID.PROFILE_COMPILE_TIME => 32
        case ID.PROFILE_COMPILE_MEMORY => 33
        case ID.ENABLE_EFFECTS => 34
        case ID.DUMP_AST => 35
        case ID.DUMP_CHIR => 36
        case ID.DUMP_IR => 37
        case ID.DUMP_ALL => 38
        case ID.DUMP_TO_SCREEN => 39
        case ID.DUMP_ANNOTATIONS_DEBUG => 40
        case ID.DESERIALIZE_CHIR_AND_DUMP => 41
        case ID.EMIT_CHIR => 42
        case ID.CHIR_WFC => 43
        case ID.ENABLE_CHIR_REDUNDANT_GETORTHROW_ELIMINATION => 44
        case ID.DISABLE_CHIR_USELESS_IMPORT_ELIMINATION => 45
        case ID.CHIR_EA => 46
        case ID.CONST_PROPAGATION => 47
        case ID.NO_CONST_PROPAGATION => 48
        case ID.FUNC_INLINING => 49
        case ID.NO_FUNC_INLINING => 50
        case ID.DEVIRTUALIZATION => 51
        case ID.NO_DEVIRTUALIZATION => 52
        case ID.REDUANDANT_RETURN_REMOVAL => 53
        case ID.NO_REDUANDANT_RETURN_REMOVAL => 54
        case ID.REDUNDANT_FUTURE_REMOVAL => 55
        case ID.NO_REDUNDANT_FUTURE_REMOVAL => 56
        case ID.REDUANDANT_ASSIGN_REMOVAL => 57
        case ID.NO_REDUANDANT_ASSIGN_REMOVAL => 58
        case ID.LOOP_INVARIANT_CODE_MOTION => 59
        case ID.NO_LOOP_INVARIANT_CODE_MOTION => 60
        case ID.SROA_OPT => 61
        case ID.NO_SROA_OPT => 62
        case ID.SWITCH_OPT => 63
        case ID.LETC_FOLDING => 64
        case ID.REF_FOLDING => 65
        case ID.ARRAY_LAMBDA_OPT => 66
        case ID.SANCOV_INLINE_8BIT => 67
        case ID.SANCOV_INLINE_BOOL_FLAG => 68
        case ID.SANCOV_TRACE_PC_GUARD => 69
        case ID.SANCOV_PC_TABLE => 70
        case ID.SANCOV_STACK_DEPTH => 71
        case ID.SANCOV_TRACE_COMPARES => 72
        case ID.SANCOV_TRACE_MEM_COMPARES => 73
        case ID.SANCOV_LEVEL_0 => 74
        case ID.SANCOV_LEVEL_1 => 75
        case ID.SANCOV_LEVEL_2 => 76
        case ID.SANCOV_LEVEL_CUSTOM => 77
        case ID.DISABLE_SEMA_VIC => 78
        case ID.DISABLE_CHIR_OPT => 79
        case ID.DISABLE_BACKEND_OPT => 80
        case ID.CHIR_OPT_DEBUG => 81
        case ID.RENDER_CHIR => 82
        case ID.INT_OVERFLOW_MODE => 83
        case ID.FAST_MATH_MODE => 84
        case ID.OPT_OPTIONS => 85
        case ID.LLC_OPTIONS => 86
        case ID.LINK_OPTION => 87
        case ID.LINK_OPTIONS => 88
        case ID.LIBRARY_PATH => 89
        case ID.LIBRARY => 90
        case ID.USE_RUNTIME_RPATH => 91
        case ID.TOOLCHAIN => 92
        case ID.TARGET => 93
        case ID.TARGET_CPU => 94
        case ID.SYSROOT => 95
        case ID.OUTPUT_TYPE => 96
        case ID.COMPILE_TARGET => 97
        case ID.OPTIMIZATION_0 => 98
        case ID.OPTIMIZATION_1 => 99
        case ID.OPTIMIZATION_2 => 100
        case ID.OPTIMIZATION_3 => 101
        case ID.OPTIMIZATION_S => 102
        case ID.OPTIMIZATION_Z => 103
        case ID.OPTIMIZATION_CUSTOM => 104
        case ID.OPT_PASS_OPTIONS => 105
        case ID.MODULE_NAME => 106
        case ID.PACKAGE_COMPILE => 107
        case ID.IMPORT_PATH => 108
        case ID.PLUGIN_PATH => 109
        case ID.COMMON_PART_CJO => 110
        case ID.COMMON_PART_CHIR => 111
        case ID.INCRE_COMPILE => 112
        case ID.INCRE_DEBUG => 113
        case ID.SAVE_TEMPS => 114
        case ID.WARN_OFF => 115
        case ID.WARN_ON => 116
        case ID.ERROR_COUNT_LIMIT => 117
        case ID.VERBOSE => 118
        case ID.VERSION => 119
        case ID.HELP => 120
        case ID.COMPILE_MACRO => 121
        case ID.ENABLE_COVERAGE => 122
        case ID.EXPERIMENTAL => 123
        case ID.DEBUG_CODEGEN => 124
        case ID.JOBS => 125
        case ID.AGGRESSIVE_PARALLEL_COMPILE => 126
        case ID.SANITIZE => 127
        case ID.SANITIZE_SET_RPATH => 128
        case ID.OBF_STRING => 129
        case ID.NO_OBF_STRING => 130
        case ID.OBF_CONST => 131
        case ID.NO_OBF_CONST => 132
        case ID.OBF_LAYOUT => 133
        case ID.NO_OBF_LAYOUT => 134
        case ID.OBF_CF_FLATTEN => 135
        case ID.NO_OBF_CF_FLATTEN => 136
        case ID.OBF_CF_BOGUS => 137
        case ID.NO_OBF_CF_BOGUS => 138
        case ID.OBF_ALL => 139
        case ID.OBF_EXPORT_SYMS => 140
        case ID.NO_OBF_EXPORT_SYMS => 141
        case ID.OBF_SYM_INPUT_MAPPING => 142
        case ID.OBF_SYM_OUTPUT_MAPPING => 143
        case ID.OBF_MAP_FILE => 144
        case ID.OBF_SYM_PREFIX => 145
        case ID.OBF_SOURCE_PATH => 146
        case ID.NO_OBF_SOURCE_PATH => 147
        case ID.OBF_LINE_NUMBER => 148
        case ID.NO_OBF_LINE_NUMBER => 149
        case ID.OBF_CONFIG => 150
        case ID.OBF_LEVEL => 151
        case ID.OBF_SEED => 152
        case ID.INTERP_CONST_EVAL_DEBUG => 153
        case ID.PRINT_BCHIR => 154
        case ID.DISABLE_CODEGEN => 155
        case ID.DISABLE_REFLECTION => 156
        case ID.STACK_TRACE_FORMAT => 157
        case ID.FUNC_SECTIONS => 158
        case ID.NO_FUNC_SECTIONS => 159
        case ID.DATA_SECTIONS => 160
        case ID.NO_DATA_SECTIONS => 161
        case ID.GC_SECTIONS => 162
        case ID.NO_GC_SECTIONS => 163
        case ID.PGO_INSTR_GEN => 164
        case ID.PGO_INSTR_USE => 165
        case ID.DISCARD_EH_FRAME => 166
        case ID.LTO_STATICLIB_FORMAT => 167
    }
}

extend ID <: Equatable<ID> {
    public operator func ==(right: ID): Bool { return IDIndex(this) == IDIndex(right) }
    public operator func !=(right: ID): Bool { return !(this == right) }
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

public func DiagFormatIndex(value: DiagFormat): Int64 {
    return match (value) {
        case DiagFormat.JSON => 0
        case DiagFormat.NO_COLOR => 1
        case DiagFormat.DEFAULT => 2
    }
}
extend DiagFormat <: Equatable<DiagFormat> {
    public operator func ==(right: DiagFormat): Bool { return DiagFormatIndex(this) == DiagFormatIndex(right) }
    public operator func !=(right: DiagFormat): Bool { return !(this == right) }
}

public func MockModeIndex(value: MockMode): Int64 {
    return match (value) {
        case MockMode.ON => 0
        case MockMode.OFF => 1
        case MockMode.RUNTIME_ERROR => 2
        case MockMode.DEFAULT => 3
    }
}
extend MockMode <: Equatable<MockMode> {
    public operator func ==(right: MockMode): Bool { return MockModeIndex(this) == MockModeIndex(right) }
    public operator func !=(right: MockMode): Bool { return !(this == right) }
}

public func SanitizerCoverageTypeIndex(value: SanitizerCoverageType): Int64 {
    return match (value) {
        case SanitizerCoverageType.SCK_UNKNOW => -1
        case SanitizerCoverageType.SCK_NONE => 0
        case SanitizerCoverageType.SCK_FUNCTION => 1
        case SanitizerCoverageType.SCK_BB => 2
    }
}
extend SanitizerCoverageType <: Equatable<SanitizerCoverageType> {
    public operator func ==(right: SanitizerCoverageType): Bool {
        return SanitizerCoverageTypeIndex(this) == SanitizerCoverageTypeIndex(right)
    }
    public operator func !=(right: SanitizerCoverageType): Bool { return !(this == right) }
}

public func StackTraceFormatIndex(value: StackTraceFormat): Int64 {
    return match (value) {
        case StackTraceFormat.DEFAULT => 0
        case StackTraceFormat.SIMPLE => 1
        case StackTraceFormat.ALL => 2
    }
}
extend StackTraceFormat <: Equatable<StackTraceFormat> {
    public operator func ==(right: StackTraceFormat): Bool {
        return StackTraceFormatIndex(this) == StackTraceFormatIndex(right)
    }
    public operator func !=(right: StackTraceFormat): Bool { return !(this == right) }
}

public func OptimizationFlagIndex(value: OptimizationFlag): Int64 {
    return match (value) {
        case OptimizationFlag.SWITCH_OPT => 0
        case OptimizationFlag.CONST_PROPAGATION => 1
        case OptimizationFlag.LETC_FOLDING => 2
        case OptimizationFlag.REF_FOLDING => 3
        case OptimizationFlag.REF_TO_LETC => 4
        case OptimizationFlag.REDUNDANT_RETURNS => 5
        case OptimizationFlag.REDUNDANT_FUTURE => 6
        case OptimizationFlag.FUNC_INLINING => 7
        case OptimizationFlag.DEVIRTUALIZATION => 8
        case OptimizationFlag.REMOVE_REDUNDANT_ASG => 9
        case OptimizationFlag.ARRAY_LAMBDA_OPT => 10
        case OptimizationFlag.SROA_OPT => 11
        case OptimizationFlag.LOOP_INVARIANT_CODE_MOTION => 12
        case OptimizationFlag.VALUE_RANGE_ANALYSIS => 13
        case OptimizationFlag.REDUNDANT_LOAD => 14
    }
}
extend OptimizationFlag <: Equatable<OptimizationFlag> {
    public operator func ==(right: OptimizationFlag): Bool {
        return OptimizationFlagIndex(this) == OptimizationFlagIndex(right)
    }
    public operator func !=(right: OptimizationFlag): Bool { return !(this == right) }
}

public func PrintBCHIROptionIndex(value: PrintBCHIROption): Int64 {
    return match (value) {
        case PrintBCHIROption.DESERIALIED => 0
        case PrintBCHIROption.LINKED => 1
        case PrintBCHIROption.CHIR2BCHIR => 2
        case PrintBCHIROption.CE_CHIR2BCHIR => 3
        case PrintBCHIROption.INTERPRETER => 4
        case PrintBCHIROption.CE_LINKED => 5
        case PrintBCHIROption.ALL => 6
    }
}
extend PrintBCHIROption <: Equatable<PrintBCHIROption> {
    public operator func ==(right: PrintBCHIROption): Bool {
        return PrintBCHIROptionIndex(this) == PrintBCHIROptionIndex(right)
    }
    public operator func !=(right: PrintBCHIROption): Bool { return !(this == right) }
}

public func CHIRModeIndex(value: CHIRMode): Int64 {
    return match (value) {
        case CHIRMode.NA => 0
        case CHIRMode.STANDARD => 1
        case CHIRMode.WITH_ID => 2
        case CHIRMode.ALL => 3
    }
}
extend CHIRMode <: Equatable<CHIRMode> {
    public operator func ==(right: CHIRMode): Bool { return CHIRModeIndex(this) == CHIRModeIndex(right) }
    public operator func !=(right: CHIRMode): Bool { return !(this == right) }
}

public func CandidateEmitCHIRPhaseIndex(value: CandidateEmitCHIRPhase): Int64 {
    return match (value) {
        case CandidateEmitCHIRPhase.NA => 0
        case CandidateEmitCHIRPhase.RAW => 1
        case CandidateEmitCHIRPhase.OPT => 2
    }
}
extend CandidateEmitCHIRPhase <: Equatable<CandidateEmitCHIRPhase> {
    public operator func ==(right: CandidateEmitCHIRPhase): Bool {
        return CandidateEmitCHIRPhaseIndex(this) == CandidateEmitCHIRPhaseIndex(right)
    }
    public operator func !=(right: CandidateEmitCHIRPhase): Bool { return !(this == right) }
}
