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

// ASTSerialization.h:96-100. Patch is exposed, but never orders versions.
public struct CjoVersionTriplet {
    public var major: UInt8 = 0u8
    public var minor: UInt8 = 0u8
    public var patch: UInt8 = 0u8
    public init() {}
}

public enum CjoVersionOrder <: Equatable<CjoVersionOrder> {
    | OLDER | EQUAL | NEWER | DIFFERENT_MAJOR
    public operator func ==(other: CjoVersionOrder): Bool {
        match (this, other) {
            case (OLDER, OLDER) | (EQUAL, EQUAL) | (NEWER, NEWER) |
                 (DIFFERENT_MAJOR, DIFFERENT_MAJOR) => true
            case _ => false
        }
    }
    public operator func !=(other: CjoVersionOrder): Bool { !(this == other) }
}

// ASTLoader.cpp:76-115, same major/minor ordering and predicate decomposition.
public func CompareCjoVersion(lhsMajor: UInt8, lhsMinor: UInt8,
    rhsMajor: UInt8, rhsMinor: UInt8): CjoVersionOrder {
    if (lhsMajor != rhsMajor) { return CjoVersionOrder.DIFFERENT_MAJOR }
    if (lhsMinor < rhsMinor) { return CjoVersionOrder.OLDER }
    if (lhsMinor > rhsMinor) { return CjoVersionOrder.NEWER }
    return CjoVersionOrder.EQUAL
}

public func VersionAtLeast(cjoMajor: UInt8, cjoMinor: UInt8,
    requiredMajor: UInt8, requiredMinor: UInt8): Bool {
    let order = CompareCjoVersion(cjoMajor, cjoMinor, requiredMajor, requiredMinor)
    return order == CjoVersionOrder.EQUAL || order == CjoVersionOrder.NEWER
}

public func VersionAtMost(cjoMajor: UInt8, cjoMinor: UInt8,
    requiredMajor: UInt8, requiredMinor: UInt8): Bool {
    let order = CompareCjoVersion(cjoMajor, cjoMinor, requiredMajor, requiredMinor)
    return order == CjoVersionOrder.EQUAL || order == CjoVersionOrder.OLDER
}

public func VersionExactly(cjoMajor: UInt8, cjoMinor: UInt8,
    requiredMajor: UInt8, requiredMinor: UInt8): Bool {
    return CompareCjoVersion(cjoMajor, cjoMinor, requiredMajor, requiredMinor) == CjoVersionOrder.EQUAL
}
