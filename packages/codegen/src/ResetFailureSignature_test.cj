package cjcj::codegen

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::chir.*
import cjcj::ast.InterfaceDecl as AstInterfaceDecl
import cjcj::ast.InterfaceTy as AstInterfaceTy
import cjcj::ast.FuncTy as AstFuncTy
import cjcj::ast.PrimitiveTy as AstPrimitiveTy
import cjcj::ast.TypeKind as AstTypeKind
import cjcj::ast.Ty as AstTy
import cjcj::ast.SrcIdentifier

@Test
public class ResetFailureSignatureTest {
    @TestCase
    public func TranslatedAnyParameterKeepsExactlyOneManagedReference(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let translator = CHIRType(builder, CHIRTypeCache())
        let decl = AstInterfaceDecl()
        decl.identifier = SrcIdentifier("Any")
        let definition = builder.CreateClassDef("std.core", "Any", "Any", isClass: false)
        translator.SetGlobalNominalCache(decl, definition)
        let astAny = AstInterfaceTy("Any", decl, Array<AstTy>())
        let astFunc = AstFuncTy(Array<AstTy>(1, repeat: astAny), AstPrimitiveTy(AstTypeKind.TYPE_INT32))
        let translated = (translator.TranslateType(astFunc) as FuncType).getOrThrow()
        let parameter = translated.GetParamType(0)
        let reference = (parameter as RefType).getOrThrow()
        @Assert(reference.GetBaseType().IsAny())
        @Assert(IRBuilder2.IsResetFailureValueType(parameter))
        @Assert(!IRBuilder2.IsResetFailureValueType(reference.GetBaseType()))
        @Assert(!IRBuilder2.IsResetFailureValueType(context.GetRefTy(parameter)))
    }

    @TestCase
    public func UnrelatedClassAndScalarAreNotTheManagedAnyParameter(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let impostor = builder.CreateClassDef("fixture", "Any", "Any", isClass: false)
        let other = context.GetRefTy(context.GetClassTy(impostor, ArrayList<Type>()))
        @Assert(!IRBuilder2.IsResetFailureValueType(other))
        @Assert(!IRBuilder2.IsResetFailureValueType(context.GetInt32Ty()))
    }
}
