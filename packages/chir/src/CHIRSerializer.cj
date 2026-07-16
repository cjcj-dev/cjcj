package cjcj::chir

public class CHIRSerializer {
    public static func Serialize(pkg: Package, filename: String, phase: ToCHIRPhase): Unit {
        let serializer = CHIRSerializerImpl(pkg)
        serializer.Initialize()
        serializer.Dispatch()
        serializer.Save(filename, phase)
    }

    public static func Serialize(pkg: Package): Array<UInt8> {
        let serializer = CHIRSerializerImpl(pkg)
        serializer.Initialize()
        serializer.Dispatch()
        return serializer.ConvertToMemoryData()
    }
}
