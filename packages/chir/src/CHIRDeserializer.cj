package cangjie_compiler::chir

public class CHIRDeserializer {
    public init() {}

    public func DeserializePackage(text: String, builder: CHIRBuilder): Package {
        return CHIRDeserializerImpl(builder).DeserializePackage(text)
    }
}
