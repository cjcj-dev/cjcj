package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public class Collector {
    public let decls: ArrayList<Decl> = ArrayList<Decl>()

    public init() {}

    public func Collect(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                collectDecl(decl)
            }
        }
    }

    private func collectDecl(decl: Decl): Unit {
        decls.add(decl)
        for (member in decl.GetMemberDecls()) {
            collectDecl(member)
        }
    }
}
