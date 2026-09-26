package cjcj::chir

import cjcj::utils.ProfileRecorder

public class CHIRSerializer {
    public static func Serialize(pkg: Package, filename: String, phase: ToCHIRPhase): Unit {
        // CHIR/Serializer/CHIRSerializer.cpp:53.
        try (recorder = ProfileRecorder("CHIR", "serialization: " + PhaseToString(phase))) {
            let serializer = CHIRSerializerImpl(pkg)
            serializer.Initialize()
            serializer.Dispatch()
            serializer.Save(filename, phase)
        }
    }

    public static func Serialize(pkg: Package): Array<UInt8> {
        let serializer = CHIRSerializerImpl(pkg)
        serializer.Initialize()
        serializer.Dispatch()
        return serializer.ConvertToMemoryData()
    }
}
