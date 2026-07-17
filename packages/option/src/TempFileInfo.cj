package cjcj::option

public enum TempFileKind {
    | O_CJO
    | O_CJO_FLAG
    | O_FULL_BCHIR
    | O_BCHIR
    | T_BC
    | O_BC
    | O_EXE
    | O_DYLIB
    | O_STATICLIB
    | O_MACRO
    | O_CHIR
    | T_OPT_BC
    | O_OPT_BC
    | T_ASM
    | O_OBJ
    | T_OBJ
    | T_EXE_MAC
    | T_DYLIB_MAC
}

public func TempFileKindSuffix(kind: TempFileKind, options: GlobalOptions): String {
    return match (kind) {
        case TempFileKind.O_CJO => ".cjo"
        case TempFileKind.O_CJO_FLAG => ".cjo.flag"
        case TempFileKind.O_FULL_BCHIR => ".full.bchir"
        case TempFileKind.O_BCHIR => ".bchir"
        case TempFileKind.T_BC => ".bc"
        case TempFileKind.O_BC => ".bc"
        case TempFileKind.O_EXE => if (options.target.os == OSType.WINDOWS) { ".exe" } else { "" }
        case TempFileKind.O_DYLIB => DylibSuffix(options.target.os)
        case TempFileKind.O_STATICLIB => ".a"
        case TempFileKind.O_MACRO => DylibSuffix(options.target.os)
        case TempFileKind.O_CHIR => ".chir"
        case TempFileKind.T_OPT_BC => ".opt.bc"
        case TempFileKind.O_OPT_BC => ".bc"
        case TempFileKind.T_ASM => ".s"
        case TempFileKind.O_OBJ => ObjSuffix(options.target.os)
        case TempFileKind.T_OBJ => ".o"
        case TempFileKind.T_EXE_MAC => "_temp"
        case TempFileKind.T_DYLIB_MAC => "_temp.dylib"
    }
}

public func DylibSuffix(os: OSType): String {
    return match (os) {
        case OSType.WINDOWS => ".dll"
        case OSType.DARWIN => ".dylib"
        case OSType.IOS => ".dylib"
        case OSType.LINUX => ".so"
        case OSType.UNKNOWN => ".so"
    }
}

public func ObjSuffix(os: OSType): String {
    return if (os == OSType.WINDOWS) { ".obj" } else { ".o" }
}
