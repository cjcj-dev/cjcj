package cjcj::chir

import cjcj::utils.ProfileRecorder
import cjcj::flatbuffers.DetachedBuffer

public class CHIRSerializer {
    public static func Serialize(pkg: Package, filename: String, phase: ToCHIRPhase): Unit {
        // CHIR/Serializer/CHIRSerializer.cpp:53.
        try (recorder = ProfileRecorder("CHIR", "serialization: " + PhaseToString(phase))) {
            let serializer = CHIRSerializerImpl(pkg)
            try {
                serializer.Initialize()
                serializer.Dispatch()
                serializer.Save(filename, phase)
            } finally {
                serializer.Close()
            }
        }
    }

    public static func Serialize(pkg: Package): DetachedBuffer {
        let serializer = CHIRSerializerImpl(pkg)
        try {
            serializer.Initialize()
            serializer.Dispatch()
            return serializer.ConvertToMemoryData()
        } finally {
            serializer.Close()
        }
    }
}
