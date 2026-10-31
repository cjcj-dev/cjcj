package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::sema.MemberMap
import cjcj::sema.NativeFFI.{IsSynthetic, IsJavaRefGetter}

// canonical 65ae772 TypeCheck/InheritanceChecker.cpp: consume the map in Check().
public func GenerateJavaForeignAbstractStub(memberMap: HashMap<InheritableDecl, MemberMap>): Unit {
    for ((decl, members) in memberMap) {
        if (let Some(wrapper) <- (decl as ClassDecl)) {
            if (!IsSynthetic(wrapper)) { continue }
            for (entry in members.entries) {
                let member = entry.signature.decl.getOrThrow()
                if (!member.TestAttr(Attribute.ABSTRACT) || IsJavaRefGetter(member)) { continue }
                if (let Some(fd) <- (member as FuncDecl)) {
                    let stub = (ASTCloner.Clone(fd) as FuncDecl).getOrThrow()
                    stub.DisableAttr(Attribute.DEFAULT)
                    var i: Int64 = 0
                    while (i < stub.annotations.size) {
                        if (stub.annotations[i].kind == AstAnnotationKind.FOREIGN_NAME) {
                            stub.annotations.remove(at: i)
                            break
                        }
                        i++
                    }
                    stub.outerDecl = Some(wrapper)
                    Walker(stub, visitPre: { node: Node =>
                        node.curFile = wrapper.curFile
                        if (let Some(clonedDecl) <- (node as Decl)) {
                            clonedDecl.fullPackageName = wrapper.fullPackageName
                            clonedDecl.moduleName = wrapper.moduleName
                        }
                        VisitAction.WALK_CHILDREN
                    }).Walk()
                    wrapper.body.getOrThrow().decls.add(stub)
                }
            }
        }
    }
}
