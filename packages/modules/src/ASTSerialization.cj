package cjcj::modules

import cjcj::flatbuffers.{VerifierOptions, VerifierTemplate}
import cjcj::basic.{CANGJIE_VERSION, DEFAULT_POSITION, DiagKindRefactor, DiagnosticEngine}

// Binary header reader. Full package materialization belongs to the frontend loader.
public class ASTLoader {
    private let data: Array<UInt8>
    private let requestedPackageName: String
    private let diag: DiagnosticEngine
    private var packageTable: Option<PackageFormat_Package> = None
    private var cjoPath: String = ""

    public init(data: Array<UInt8>, fullPackageName: String, diag: DiagnosticEngine) {
        this.data = data
        requestedPackageName = fullPackageName
        this.diag = diag
    }

    public func LoadPackageDepInfo(): String {
        if (!VerifyForData("ast")) {
            return ""
        }
        packageTable = Some(GetPackage(data))
        if (!CheckCjoVersion()) {
            return ""
        }
        return packageTable.getOrThrow().GetPkgDepInfo().getOrThrow().str()
    }

    public func GetCjoVersion(): CjoVersionTriplet {
        let (version, _) = ReadCjoVersion()
        return version
    }

    public func HasCjoVersion(): Bool {
        let (_, hasVersion) = ReadCjoVersion()
        return hasVersion
    }

    public func IsCjoVersionAtLeast(requiredMajor: UInt8, requiredMinor: UInt8): Bool {
        let (version, hasVersion) = ReadCjoVersion()
        if (!hasVersion) { return false }
        return VersionAtLeast(version.major, version.minor, requiredMajor, requiredMinor)
    }

    public func IsCjoVersionAtMost(requiredMajor: UInt8, requiredMinor: UInt8): Bool {
        let (version, hasVersion) = ReadCjoVersion()
        if (!hasVersion) { return false }
        return VersionAtMost(version.major, version.minor, requiredMajor, requiredMinor)
    }

    public func IsCjoVersionExactly(requiredMajor: UInt8, requiredMinor: UInt8): Bool {
        let (version, hasVersion) = ReadCjoVersion()
        if (!hasVersion) { return false }
        return VersionExactly(version.major, version.minor, requiredMajor, requiredMinor)
    }

    private func ReadCjoVersion(): (CjoVersionTriplet, Bool) {
        var result = CjoVersionTriplet()
        if (packageTable.isNone()) { return (result, false) }
        let cjoVer = packageTable.getOrThrow().GetCjoVersion()
        if (cjoVer.isNone()) { return (result, false) }
        let version = cjoVer.getOrThrow()
        result.major = version.GetMajorNum()
        result.minor = version.GetMinorNum()
        result.patch = version.GetPatchNum()
        return (result, true)
    }

    public func SetCjoPath(path: String): Unit {
        cjoPath = path
    }

    // ASTLoader.cpp:352-390, called after verification and package assignment.
    private func CheckCjoVersion(diagnose!: Bool = true): Bool {
        let cjoVer = packageTable.getOrThrow().GetCjoVersion()
        if (cjoVer.isNone()) {
            if (diagnose) { DiagnoseVersionMismatch() }
            return false
        }
        let ver = cjoVer.getOrThrow()
        let compat = CheckCjoVersionCompat(ver.GetMajorNum(), ver.GetMinorNum())
        if (let CjoVersionCompat.COMPATIBLE <- compat) {
            return true
        }
        if (diagnose) { DiagnoseVersionMismatch() }
        return false
    }

    private func DiagnoseVersionMismatch(): Unit {
        let table = packageTable.getOrThrow()
        let producerVer = if (let Some(ver) <- table.GetVersion()) { ver.str() } else { "unknown" }
        let fullPackageName = if (let Some(name) <- table.GetFullPkgName()) {
            name.str()
        } else { "unknown package name" }
        diag.DiagnoseRefactor(DiagKindRefactor.module_version_not_identical, DEFAULT_POSITION,
            arguments: [cjoPath, fullPackageName, producerVer, CANGJIE_VERSION]).Emit()
    }

    private func VerifyForData(id: String): Bool {
        var options = VerifierOptions()
        options.maxDepth = UInt32(FB_MAX_DEPTH)
        options.maxTables = UInt32(FB_MAX_TABLES)
        let verifier = VerifierTemplate(data, opts: options)
        if (!VerifyPackageBuffer(data, verifier)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.module_loaded_ast_failed,
                DEFAULT_POSITION,
                arguments: [id, requestedPackageName, CANGJIE_VERSION]
            ).Emit()
            return false
        }
        return true
    }

}
