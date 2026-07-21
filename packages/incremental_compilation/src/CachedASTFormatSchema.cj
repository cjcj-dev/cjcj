package cjcj::incremental_compilation

import cjcj::flatbuffers.ReadScalar

// CachedASTFormat.fbs:10-124 and CachedASTFormat_generated.h:1436-1472.
// C++ namespace CachedASTFormat is flattened into the CachedASTFormat_ table
// prefix because this package already contains cache-domain classes named
// GlobalVarIndex, UseInfo, and SemanticInfo.

public func GetHashedPackage(data: Array<UInt8>): CachedASTFormat_HashedPackage {
    return CachedASTFormat_HashedPackage(data, Int64(ReadScalar(data, 0, 0u32)))
}

public func HashedPackageIdentifier(): String {
    return "CAST"
}

public func HashedPackageBufferHasIdentifier(data: Array<UInt8>): Bool {
    return data.size >= 8 && data[4] == 0x43u8 && data[5] == 0x41u8 && data[6] == 0x53u8 && data[7] == 0x54u8
}
