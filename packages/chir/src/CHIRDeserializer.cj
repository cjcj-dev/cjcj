package cjcj::chir

import cjcj::basic.CANGJIE_VERSION
import cjcj::utils.FileUtil
import std.core.Box as CoreBox

public class CHIRDeserializer {
    private init() {}

    public static func Deserialize(fileName: String, chirBuilder: CHIRBuilder, phase: CoreBox<ToCHIRPhase>,
        compilePlatform!: Bool = false): Bool {
        if (FileUtil.IsDir(fileName)) {
            eprintln(fileName + " is a directory.")
            return false
        }
        if (!FileUtil.FileExist(fileName)) {
            eprintln(fileName + " not exist.")
            return false
        }
        let deserializer = CHIRDeserializerImpl(chirBuilder, compilePlatform: compilePlatform)
        let (readOk, serializationInfo, failedReason) = FileUtil.ReadBinaryFileToBuffer(fileName)
        if (!readOk) {
            eprintln(failedReason + ".")
            return false
        }
        var options = VerifierOptions()
        options.maxDepth = UInt32.Max
        options.maxTables = UInt32.Max
        let verifier = VerifierTemplate(serializationInfo, opts: options)
        if (!verifier.VerifyBuffer({position: Int64, active: VerifierTemplate =>
            PackageFormat_CHIRPackage(serializationInfo, position).Verify(active)})) {
            eprintln("validation of '" + fileName + "' failed, please confirm it was created by compiler whose version is '" +
                CANGJIE_VERSION + "'.")
            return false
        }
        let chirPackage = GetCHIRPackage(serializationInfo)
        deserializer.Run(chirPackage)
        phase.value = ToCHIRPhaseFromUInt8(chirPackage.GetPhase())
        return true
    }
}
