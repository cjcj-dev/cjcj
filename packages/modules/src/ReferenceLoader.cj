package cangjie_compiler::modules

import std.collection.*

public class ReferenceLoader {
    private let decls: HashMap<String, Decl> = HashMap<String, Decl>()

    public init() {}

    public init(pkg: Package) {
        RegisterPackage(pkg)
    }

    public func RegisterPackage(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                RegisterDecl(decl)
            }
        }
    }

    public func RegisterDecl(decl: Decl): Unit {
        let mangleKey = GetDeclMangleKey(decl)
        if (!mangleKey.isEmpty()) {
            decls[mangleKey] = decl
        }
        if (!decl.fullPackageName.isEmpty() && !decl.identifier.isEmpty()) {
            decls[decl.fullPackageName + "." + decl.identifier] = decl
        }
        if (!decl.identifier.isEmpty()) {
            decls[decl.identifier] = decl
        }
    }

    public func LoadReference(reference: String): String {
        if (let Some(decl) <- ResolveReference(reference)) {
            return decl.ToString()
        }
        return reference
    }

    public func ResolveReference(reference: String): Option<Decl> {
        return decls.get(reference)
    }
}
