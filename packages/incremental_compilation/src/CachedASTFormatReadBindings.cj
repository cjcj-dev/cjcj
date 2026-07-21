package cjcj::incremental_compilation

import cjcj::flatbuffers.{FlatBufferString, Offset, Table, Vector, VerifierTemplate}

// CachedASTFormat_generated.h:57-1433. Field methods retain the generated C++
// accessor names. The C++ namespace is flattened only into each table name.

public class CachedASTFormat_DeclDep <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func decl(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func dependency(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyVector(GetPointer(6u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(6u16)) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_EffectMap <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func srcDecl(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func effectedDecls(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyVector(GetPointer(6u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(6u16)) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_VirtualDep <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func raw(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func wrapper(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(FlatBufferString(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyString(GetPointer(6u16)) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_Usage <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func definition(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func apiUsage(): Option<CachedASTFormat_UseInfo> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(CachedASTFormat_UseInfo(data, p)) } else { None }
    }
    public func bodyUsage(): Option<CachedASTFormat_UseInfo> {
        return if (let Some(p) <- GetPointer(8u16)) { Some(CachedASTFormat_UseInfo(data, p)) } else { None }
    }
    public func boxedTypes(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(10u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyTable(GetPointer(6u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_UseInfo(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 8u16) &&
            verifier.VerifyTable(GetPointer(8u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_UseInfo(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 10u16) &&
            verifier.VerifyVector(GetPointer(10u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(10u16)) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_UseInfo <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func usedDecls(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func usedNames(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyVector(GetPointer(4u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(4u16)) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyVector(GetPointer(6u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(6u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_NameInfo(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_NameInfo <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func name(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func conditions(): Option<Vector<Bool>> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(Vector<Bool>(data, p)) } else { None }
    }
    public func parentDecls(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(8u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func qualifiers(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(10u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyVector(GetPointer(6u16), 1) &&
            VerifyOffset(verifier, 8u16) &&
            verifier.VerifyVector(GetPointer(8u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(8u16)) &&
            VerifyOffset(verifier, 10u16) &&
            verifier.VerifyVector(GetPointer(10u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(10u16)) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_Relation <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func definition(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func inherited(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func extends(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(8u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func extendInterfaces(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(10u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyVector(GetPointer(6u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(6u16)) &&
            VerifyOffset(verifier, 8u16) &&
            verifier.VerifyVector(GetPointer(8u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(8u16)) &&
            VerifyOffset(verifier, 10u16) &&
            verifier.VerifyVector(GetPointer(10u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(10u16)) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_CompilerAddedUsage <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func definition(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func related(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyVector(GetPointer(6u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(6u16)) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_SemanticInfo <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func usages(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func relations(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func builtInTypeRelations(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(8u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func compilerAddedUsages(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(10u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyVector(GetPointer(4u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(4u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_Usage(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyVector(GetPointer(6u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(6u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_Relation(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 8u16) &&
            verifier.VerifyVector(GetPointer(8u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(8u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_Relation(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 10u16) &&
            verifier.VerifyVector(GetPointer(10u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(10u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_CompilerAddedUsage(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_GlobalVarIndex <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func file(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func id(): Int32 { return GetField(6u16, 0i32) }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyField<Int32>(verifier, 6u16, 4) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_MemberDecl <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func mangle(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func sig(): UInt64 { return GetField(6u16, 0u64) }
    public func srcUse(): UInt64 { return GetField(8u16, 0u64) }
    public func body(): UInt64 { return GetField(10u16, 0u64) }
    public func `type`(): UInt8 { return GetField(12u16, 0u8) }
    public func isGV(): Bool { return GetField(14u16, false) }
    public func gvid(): Option<CachedASTFormat_GlobalVarIndex> {
        return if (let Some(p) <- GetPointer(16u16)) { Some(CachedASTFormat_GlobalVarIndex(data, p)) } else { None }
    }
    public func members(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(18u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func cgMangle(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(20u16)) { Some(FlatBufferString(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyField<UInt64>(verifier, 6u16, 8) &&
            VerifyField<UInt64>(verifier, 8u16, 8) &&
            VerifyField<UInt64>(verifier, 10u16, 8) &&
            VerifyField<UInt8>(verifier, 12u16, 1) &&
            VerifyField<Bool>(verifier, 14u16, 1) &&
            VerifyOffset(verifier, 16u16) &&
            verifier.VerifyTable(GetPointer(16u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_GlobalVarIndex(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 18u16) &&
            verifier.VerifyVector(GetPointer(18u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(18u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_MemberDecl(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 20u16) &&
            verifier.VerifyString(GetPointer(20u16)) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_TopDecl <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func mangle(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func sig(): UInt64 { return GetField(6u16, 0u64) }
    public func srcUse(): UInt64 { return GetField(8u16, 0u64) }
    public func body(): UInt64 { return GetField(10u16, 0u64) }
    public func `type`(): UInt8 { return GetField(12u16, 0u8) }
    public func isGV(): Bool { return GetField(14u16, false) }
    public func instVar(): UInt64 { return GetField(16u16, 0u64) }
    public func virt(): UInt64 { return GetField(18u16, 0u64) }
    public func gvid(): Option<CachedASTFormat_GlobalVarIndex> {
        return if (let Some(p) <- GetPointer(20u16)) { Some(CachedASTFormat_GlobalVarIndex(data, p)) } else { None }
    }
    public func members(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(22u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func extends(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(24u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func cgMangle(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(26u16)) { Some(FlatBufferString(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyField<UInt64>(verifier, 6u16, 8) &&
            VerifyField<UInt64>(verifier, 8u16, 8) &&
            VerifyField<UInt64>(verifier, 10u16, 8) &&
            VerifyField<UInt8>(verifier, 12u16, 1) &&
            VerifyField<Bool>(verifier, 14u16, 1) &&
            VerifyField<UInt64>(verifier, 16u16, 8) &&
            VerifyField<UInt64>(verifier, 18u16, 8) &&
            VerifyOffset(verifier, 20u16) &&
            verifier.VerifyTable(GetPointer(20u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_GlobalVarIndex(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 22u16) &&
            verifier.VerifyVector(GetPointer(22u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(22u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_MemberDecl(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 24u16) &&
            verifier.VerifyVector(GetPointer(24u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(24u16)) &&
            VerifyOffset(verifier, 26u16) &&
            verifier.VerifyString(GetPointer(26u16)) &&
            verifier.EndTable()
    }
}

public class CachedASTFormat_HashedPackage <: Table {
    public init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    public func version(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(4u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func packageName(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(6u16)) { Some(FlatBufferString(data, p)) } else { None }
    }
    public func specs(): UInt64 { return GetField(8u16, 0u64) }
    public func compileOptionArgs(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(10u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func topDecls(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(12u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func importedDecls(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(14u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func varAndFunc(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(16u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func chirOptInfo(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(18u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func virtualDep(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(20u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func varInitDep(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(22u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func ccOutFuncs(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(24u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    public func lambdaCounter(): UInt64 { return GetField(26u16, 0u64) }
    public func envClassCounter(): UInt64 { return GetField(28u16, 0u64) }
    public func strLitCounter(): UInt64 { return GetField(30u16, 0u64) }
    public func semanticInfo(): Option<CachedASTFormat_SemanticInfo> {
        return if (let Some(p) <- GetPointer(32u16)) { Some(CachedASTFormat_SemanticInfo(data, p)) } else { None }
    }
    public func bitcodeFilesName(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(34u16)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    public func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, 4u16) &&
            verifier.VerifyString(GetPointer(4u16)) &&
            VerifyOffset(verifier, 6u16) &&
            verifier.VerifyString(GetPointer(6u16)) &&
            VerifyField<UInt64>(verifier, 8u16, 8) &&
            VerifyOffset(verifier, 10u16) &&
            verifier.VerifyVector(GetPointer(10u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(10u16)) &&
            VerifyOffset(verifier, 12u16) &&
            verifier.VerifyVector(GetPointer(12u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(12u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_TopDecl(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 14u16) &&
            verifier.VerifyVector(GetPointer(14u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(14u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_TopDecl(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 16u16) &&
            verifier.VerifyVector(GetPointer(16u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(16u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_DeclDep(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 18u16) &&
            verifier.VerifyVector(GetPointer(18u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(18u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_EffectMap(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 20u16) &&
            verifier.VerifyVector(GetPointer(20u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(20u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_VirtualDep(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 22u16) &&
            verifier.VerifyVector(GetPointer(22u16), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(22u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_VirtualDep(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 24u16) &&
            verifier.VerifyVector(GetPointer(24u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(24u16)) &&
            VerifyField<UInt64>(verifier, 26u16, 8) &&
            VerifyField<UInt64>(verifier, 28u16, 8) &&
            VerifyField<UInt64>(verifier, 30u16, 8) &&
            VerifyOffset(verifier, 32u16) &&
            verifier.VerifyTable(GetPointer(32u16),
                {p: Int64, v: VerifierTemplate => CachedASTFormat_SemanticInfo(data, p).Verify(v)}) &&
            VerifyOffset(verifier, 34u16) &&
            verifier.VerifyVector(GetPointer(34u16), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(34u16)) &&
            verifier.EndTable()
    }
}

public func VerifyHashedPackageBuffer(data: Array<UInt8>, verifier: VerifierTemplate): Bool {
    return HashedPackageBufferHasIdentifier(data) &&
        verifier.VerifyBuffer({p: Int64, v: VerifierTemplate => CachedASTFormat_HashedPackage(data, p).Verify(v)})
}
