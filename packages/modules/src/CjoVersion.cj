package cjcj::modules

// cangjie_compiler@12883f2b include/cangjie/Modules/CjoVersion.h:151-155.
public const CJO_MAJOR_VERSION: UInt8 = 0u8
public const CJO_MINOR_VERSION: UInt8 = 1u8
public const CJO_PATCH_VERSION: UInt8 = 0u8

public enum CjoVersionCompat {
    | COMPATIBLE
    | MAJOR_MISMATCH
    | MINOR_TOO_NEW
}

// ASTLoader.cpp:57-66: major must match; only older/equal minor is accepted.
// Patch deliberately does not participate in the compatibility decision.
public func CheckCjoVersionCompat(cjoMajor: UInt8, cjoMinor: UInt8): CjoVersionCompat {
    if (cjoMajor != CJO_MAJOR_VERSION) {
        return CjoVersionCompat.MAJOR_MISMATCH
    }
    if (cjoMinor > CJO_MINOR_VERSION) {
        return CjoVersionCompat.MINOR_TOO_NEW
    }
    return CjoVersionCompat.COMPATIBLE
}
