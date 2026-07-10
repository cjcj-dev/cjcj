package cjcj::chir

public class CHIRSerializer {
    public static func Serialize(pkg: Package, filename: String, phase: ToCHIRPhase): Unit {
        let serializer = CHIRSerializerImpl(pkg)
        serializer.Initialize()
        serializer.Dispatch()
        serializer.Save(filename, phase)
    }
}
