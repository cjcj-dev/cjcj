package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::sema.NativeFFI.{InteropLibBridge, WithinFile}
import cjcj::utils.{CJC_ASSERT, JAVA_REF_FIELD_NAME}

public class GenerateJavaReferenceFieldInJObject {
    private let ilib: InteropLibBridge

    public init(ilib: InteropLibBridge) {
        this.ilib = ilib
    }

    private func CreateJavaReferenceField(jobject: ClassDecl): VarDecl {
        let javaEntityDecl = ilib.GetJavaEntityDecl().getOrThrow()
        let javaref = CreateVarDecl(JAVA_REF_FIELD_NAME, None, Some(CreateRefType(javaEntityDecl)))
        javaref.SetTy(javaEntityDecl.GetTy().getOrThrow())
        javaref.EnableAttr(Attribute.INITIALIZATION_CHECKED)
        javaref.EnableAttr(Attribute.INITIALIZED)
        javaref.curFile = jobject.curFile
        let mod = Modifier(TokenKind.PUBLIC, javaref.begin)
        mod.curFile = jobject.curFile
        javaref.modifiers.add(mod)
        javaref.isVar = false
        return javaref
    }

    private func InsertJavaReferenceField(jobject: ClassDecl): VarDecl {
        CJC_ASSERT(IsJObject(jobject))
        let field = WithinFile(CreateJavaReferenceField(jobject), jobject.curFile)
        field.outerDecl = Some(jobject)
        field.fullPackageName = jobject.fullPackageName
        field.moduleName = jobject.moduleName
        if (let Some(body) <- jobject.body) {
            field.begin = body.begin
            field.end = body.begin
        }
        field.EnableAttr(Attribute.IN_CLASSLIKE)
        field.EnableAttr(Attribute.PUBLIC)
        jobject.GetMemberDecls().add(field)
        return field
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (mirror in ctx.GetJavaMirrors()) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (IsJObject(mirror)) {
                if (let Some(jobject) <- (mirror as ClassDecl)) {
                    InsertJavaReferenceField(jobject)
                }
            }
        }
    }
}
