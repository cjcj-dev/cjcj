package cangjie_compiler::chir

public class CHIRSerializer {
    public init() {}

    public func SerializePackage(pkg: Package): String {
        return pkg.ToString()
    }
}

public class CHIRDeserializer {
    public init() {}

    public func DeserializePackage(text: String, builder: CHIRBuilder): Package {
        // TODO(selfhost:CHIR): port binary CHIR package format and AST/module metadata; textual fallback preserves buildability only.
        let name = if (text.startsWith("package ")) { text[8..].split("\n")[0] } else { "<deserialized>" }
        return builder.CreatePackage(name)
    }
}
