package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::sema.MemberMap

// Upstream a51ced71, NativeFFI/Utils.cpp:479-491.
private func RebindClonedStubToSynthetic(stub: Decl, synthetic: ClassDecl): Unit {
    stub.outerDecl = Some(synthetic)
    let walker = Walker(stub, visitPre: {node: Node =>
        node.curFile = synthetic.curFile
        if (let Some(decl) <- (node as Decl)) {
            decl.fullPackageName = synthetic.fullPackageName
            decl.moduleName = synthetic.moduleName
        }
        return VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

// Upstream a51ced71, AfterTypeCheck/Interop/GenerateInMirrorInterfaceHandleWrappers.cpp:36-47.
private func GenerateHandleWrapperClassStub(handleWrapper: ClassDecl, member: Decl): Unit {
    let stub = (ASTCloner.Clone(member) as Decl).getOrThrow()
    var i: Int64 = 0
    while (i < stub.annotations.size) {
        if (stub.annotations[i].kind == AstAnnotationKind.FOREIGN_NAME) {
            stub.annotations.remove(at: i)
        } else {
            i++
        }
    }
    RebindClonedStubToSynthetic(stub, handleWrapper)
    handleWrapper.body.getOrThrow().decls.add(stub)
}

// Upstream a51ced71, AfterTypeCheck/Interop/GenerateInMirrorInterfaceHandleWrappers.cpp:49-70.
public func GenerateMirrorInterfaceHandleWrapperAbstractMemberImplStubs(
    handleWrapper: ClassDecl, members: MemberMap): Unit {
    for (entry in members.entries) {
        let decl = entry.signature.decl.getOrThrow()
        if (!decl.TestAttr(Attribute.ABSTRACT)) {
            continue
        }
        match (decl.astKind) {
            case ASTKind.FUNC_DECL | ASTKind.PROP_DECL => GenerateHandleWrapperClassStub(handleWrapper, decl)
            case _ => continue
        }
    }
}
