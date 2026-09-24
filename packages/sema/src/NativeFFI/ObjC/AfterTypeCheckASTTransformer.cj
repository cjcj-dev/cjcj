package cjcj::sema.NativeFFI.ObjC

import std.collection.ArrayList
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::utils.CJC_ASSERT_WITH_MSG

// Upstream a51ced71, AfterTypeCheck/Utils/AfterTypeCheckASTTransformer.cpp:29-37.
private func FuncTyOf(typeManager: TypeManager, params: ArrayList<FuncParam>, retTy: Ty): Ty {
    let paramTys = ArrayList<Ty>()
    for (param in params) {
        paramTys.add(param.GetTy().getOrThrow())
    }
    return typeManager.GetFunctionTy(paramTys.toArray(), retTy)
}

public class AfterTypeCheckASTTransformer {
    private let typeManager: TypeManager
    private let astInserter: ASTInserter
    private let objCLib: InteropLibBridge

    public init(importManager: SemaImportManager, typeManager: TypeManager,
        diag: DiagnosticEngine, astInserter: ASTInserter) {
        this.typeManager = typeManager
        this.astInserter = astInserter
        objCLib = InteropLibBridge(importManager, diag)
    }

    // Upstream a51ced71, AfterTypeCheck/Utils/AfterTypeCheckASTTransformer.cpp:52-57.
    public func TransformToObjCImplRegCompanionField(vd: VarDecl, regComp: ClassDecl): Unit {
        vd.identifier = SrcIdentifier("$reg")
        vd.SetTy(regComp.GetTy().getOrThrow())
        vd.EnableAttr(Attribute.PRIVATE)
        vd.EnableAttr(Attribute.INITIALIZED)
        vd.EnableAttr(Attribute.NO_REFLECT_INFO)
    }

    // Upstream a51ced71, AfterTypeCheck/Utils/AfterTypeCheckASTTransformer.cpp:59-82.
    public func TransformToObjCImplStaticProxyFunc(proxy: FuncDecl, origin: FuncDecl,
        regCompanion: ClassDecl): Unit {
        CJC_ASSERT_WITH_MSG(origin.TestAttr(Attribute.STATIC), "expected static function to be proxied")
        CJC_ASSERT_WITH_MSG(!origin.funcBody.getOrThrow().paramLists.isEmpty(), "expected at least one param list")
        proxy.EnableAttr(Attribute.OBJ_C_IMPL_MOVED_MEMBER_PROXY)
        let params = proxy.funcBody.getOrThrow().paramLists[0].params
        let args = ArrayList<FuncArg>()
        for (param in params) {
            args.add(CreateFuncArg(CreateRefExpr(param)))
        }
        let memberAccess = CreateMemberAccess(CreateRefExpr(regCompanion), origin)
        let call = CreateCallExpr(memberAccess, args, Some(origin),
            Some((origin.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy), CallKind.CALL_DECLARED_FUNCTION)
        let nodes = ArrayList<Node>()
        nodes.add(call)
        let body = proxy.funcBody.getOrThrow().body.getOrThrow().body
        body.clear()
        for (node in nodes) { body.add(node) }
    }

    // Upstream a51ced71, AfterTypeCheck/Utils/AfterTypeCheckASTTransformer.cpp:84-128.
    public func TransformToObjCImplProxyProp(pd: PropDecl, vd: VarDecl, receiver: Decl): Unit {
        pd.identifier = vd.identifier
        pd.SetTy(vd.GetTy().getOrThrow())
        pd.CloneAttrs(vd)
        pd.EnableAttr(Attribute.COMPILER_ADD)
        pd.EnableAttr(Attribute.OBJ_C_IMPL_MOVED_MEMBER_PROXY)
        pd.isVar = vd.isVar
        for (modifier in vd.modifiers) {
            pd.modifiers.add(modifier)
        }
        for (anno in vd.annotations) {
            pd.annotations.add((ASTCloner.Clone(anno) as Annotation).getOrThrow())
        }
        if (pd.getters.isEmpty()) {
            let paramLists = ArrayList<FuncParamList>()
            paramLists.add(CreateFuncParamList(ArrayList<FuncParam>()))
            let getter = CreateFuncDecl("", CreateFuncBody(paramLists, None,
                CreateBlock(ArrayList<Node>(), None), None), None)
            TransformToProxyPropGetter(getter, vd, receiver, pd)
            astInserter.InsertGetterInto(pd, getter)
        } else {
            TransformToProxyPropGetter(pd.getters[0], vd, receiver, pd)
        }
        if (vd.isVar) {
            pd.EnableAttr(Attribute.MUT)
            let mutModifier = Modifier(TokenKind.MUT, vd.begin)
            mutModifier.curFile = vd.curFile
            pd.modifiers.add(mutModifier)
            if (pd.setters.isEmpty()) {
                let paramLists = ArrayList<FuncParamList>()
                paramLists.add(CreateFuncParamList(ArrayList<FuncParam>()))
                let setter = CreateFuncDecl("", CreateFuncBody(paramLists, None,
                    CreateBlock(ArrayList<Node>(), None), None), None)
                TransformToProxyPropSetter(setter, vd, receiver, pd)
                astInserter.InsertSetterInto(pd, setter)
            } else {
                TransformToProxyPropSetter(pd.setters[0], vd, receiver, pd)
            }
        }
    }

    // Upstream a51ced71, AfterTypeCheck/Utils/AfterTypeCheckASTTransformer.cpp:130-146.
    public func TransformToProxyPropGetter(getter: FuncDecl, origin: VarDecl, receiver: Decl, pd: PropDecl): Unit {
        let body = getter.funcBody.getOrThrow().body.getOrThrow()
        body.body.clear()
        body.body.add(CreateMemberAccess(CreateRefExpr(receiver), origin))
        body.SetTy(origin.GetTy().getOrThrow())
        getter.identifier = SrcIdentifier("$" + pd.identifier.Val() + "get")
        let getterTy = typeManager.GetFunctionTy([], pd.GetTy().getOrThrow())
        getter.SetTy(getterTy)
        getter.funcBody.getOrThrow().SetTy(getterTy)
        getter.CloneAttrs(pd)
        getter.DisableAttr(Attribute.MUT)
        getter.EnableAttr(Attribute.COMPILER_ADD)
    }

    // Upstream a51ced71, AfterTypeCheck/Utils/AfterTypeCheckASTTransformer.cpp:148-176.
    public func TransformToProxyPropSetter(setter: FuncDecl, origin: VarDecl, receiver: Decl, pd: PropDecl): Unit {
        let param = CreateFuncParam("value", None, None, origin.GetTy())
        let paramRef = CreateRefExpr(param)
        CJC_ASSERT_WITH_MSG(!setter.funcBody.getOrThrow().paramLists.isEmpty(), "expected at least one param list")
        let params = setter.funcBody.getOrThrow().paramLists[0].params
        params.clear()
        params.add(param)
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let setterTy = FuncTyOf(typeManager, params, unitTy)
        let assignment = CreateAssignExpr(CreateMemberAccess(CreateRefExpr(receiver), origin), paramRef, Some(unitTy))
        let body = setter.funcBody.getOrThrow().body.getOrThrow()
        body.body.clear()
        body.body.add(assignment)
        body.SetTy(unitTy)
        setter.identifier = SrcIdentifier("$" + pd.identifier.Val() + "set")
        setter.SetTy(setterTy)
        setter.funcBody.getOrThrow().SetTy(setterTy)
        setter.CloneAttrs(pd)
        setter.DisableAttr(Attribute.MUT)
        setter.EnableAttr(Attribute.COMPILER_ADD)
    }
}
