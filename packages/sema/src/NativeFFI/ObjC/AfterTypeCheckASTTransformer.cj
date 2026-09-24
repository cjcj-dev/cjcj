package cjcj::sema.NativeFFI.ObjC

import std.collection.ArrayList
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine
import cjcj::modules.SemaImportManager
import cjcj::sema.{TypeManager, GenerateTypeMapping}
import cjcj::sema.NativeFFI.{CreateCall, CreateSuperCall, CreateThisCall, CreateThisRef, WithinFile, WrapReturningLambdaExpr}
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
    // Upstream a51ced71, AfterTypeCheckASTTransformer.cpp:178-352.
    private func AppendNativeObjCIdMarkerIfNeeded(call: CallExpr, curFile: Option<File>): Unit {
        if (!HasNativeObjCIdMarkerParam(call.resolvedFunction.getOrThrow())) { return }
        call.args.add(CreateFuncArg(WithinFile<RefExpr>(
            CreateRefExpr(objCLib.GetNativeObjCIdMarkerInstance().getOrThrow()), curFile)))
    }

    public func TransformToObjCImplBaseCtorDecl(ctor: FuncDecl, impl: ClassDecl): Unit {
        let params = ctor.funcBody.getOrThrow().paramLists[0].params
        params.clear()
        params.add(CreateFuncParam("$obj", None, None, objCLib.GetNativeObjCIdTy()))
        params.add(CreateFuncParam("$registryId", None, None, objCLib.GetRegistryIdTy()))
        params.add(CreateFuncParam("$mrk", None, None, objCLib.GetNativeObjCIdMarkerTy()))
        let ctorTy = FuncTyOf(typeManager, params, impl.GetTy().getOrThrow())
        ctor.identifier = SrcIdentifier("init")
        ctor.SetTy(ctorTy)
        ctor.EnableAttr(Attribute.PUBLIC)
        ctor.EnableAttr(Attribute.CONSTRUCTOR)
        ctor.funcBody.getOrThrow().SetTy(ctorTy)
        ctor.funcBody.getOrThrow().parentClassLike = Some(impl)
        ctor.funcBody.getOrThrow().body.getOrThrow().SetTy(impl.GetTy().getOrThrow())
    }

    public func TransformToObjCImplBaseCtorBody(ctorBody: FuncBody, impl: ClassDecl, regComp: ClassDecl): Unit {
        let params = ctorBody.paramLists[0].params
        CJC_ASSERT_WITH_MSG(params.size > 1, "expected at least 2 params")
        let curFile = impl.curFile
        let handleRef = CreateRefExpr(params[0])
        let regIdRef = CreateRefExpr(params[1])
        let superClass = impl.GetSuperClassDecl().getOrThrow()
        ctorBody.body.getOrThrow().body.clear()
        if (IsObjCImpl(superClass)) {
            let superCtor = GetObjCImplBaseCtor(superClass).getOrThrow()
            let call = CreateSuperCall(superClass, superCtor, superCtor.GetTy().getOrThrow())
            call.args.add(CreateFuncArg(handleRef))
            call.args.add(CreateFuncArg((ASTCloner.Clone(regIdRef) as Expr).getOrThrow()))
            call.curFile = curFile
            AppendNativeObjCIdMarkerIfNeeded(call, curFile)
            ctorBody.body.getOrThrow().body.add(call)
        } else {
            CJC_ASSERT_WITH_MSG(IsObjCMirror(superClass), "expected super class to be @ObjCMirror")
            let superCtor = GetObjCMirrorBaseCtor(superClass).getOrThrow()
            let call = CreateSuperCall(superClass, superCtor, superCtor.GetTy().getOrThrow())
            call.args.add(CreateFuncArg(handleRef))
            call.curFile = curFile
            AppendNativeObjCIdMarkerIfNeeded(call, curFile)
            ctorBody.body.getOrThrow().body.add(call)
        }
        let decl = objCLib.GetGetFromRegistryByIdDecl().getOrThrow()
        let ref = CreateRefExpr(decl)
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(regIdRef))
        ref.instTys.add(regComp.GetTy().getOrThrow())
        ref.SetTy(typeManager.GetInstantiatedTy(decl.GetTy().getOrThrow(), GenerateTypeMapping(decl, ref.instTys)))
        ref.typeArguments.add(CreateRefType(regComp))
        let call = CreateCallExpr(ref, args, Some(decl), regComp.GetTy(), CallKind.CALL_DECLARED_FUNCTION)
        let field = GetObjCImplRegCompanionField(impl).getOrThrow()
        let lhs = CreateMemberAccess(CreateThisRef(impl, impl.GetTy().getOrThrow(), impl.curFile.getOrThrow()), field)
        ctorBody.body.getOrThrow().body.add(CreateAssignExpr(lhs, call, TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
    }

    public func TransformToObjCImplRegCompBaseCtorBody(ctorBody: FuncBody, regComp: ClassDecl): Unit {
        let curFile = regComp.curFile.getOrThrow()
        let params = ctorBody.paramLists[0].params
        CJC_ASSERT_WITH_MSG(!params.isEmpty(), "expected at least 1 param")
        let handleRef = CreateRefExpr(params[0])
        if (let Some(superClass) <- GetObjCImplRegistryCompanionSuperClass(regComp)) {
            let superCtor = GetObjCImplRegCompanionBaseCtor(superClass).getOrThrow()
            let call = CreateSuperCall(superClass, superCtor, superCtor.GetTy().getOrThrow())
            call.args.add(CreateFuncArg(handleRef))
            call.curFile = Some(curFile)
            ctorBody.body.getOrThrow().body.add(call)
            return
        }
        let put = CreateCall(objCLib.GetPutToRegistryDecl().getOrThrow(), curFile,
            CreateThisRef(regComp, regComp.GetTy().getOrThrow(), curFile))
        let set = CreateCall(objCLib.GetSetRegistryIdDecl().getOrThrow(), curFile, handleRef, put)
        ctorBody.body.getOrThrow().body.add(set)
    }

    public func TransformToObjCImplRegDataCtorDecl(ctor: FuncDecl, impl: ClassDecl, regComp: ClassDecl): Unit {
        let tupleTy = typeManager.GetTupleTy([objCLib.GetNativeObjCIdTy().getOrThrow(), regComp.GetTy().getOrThrow()])
        let param = CreateFuncParam("$regData", None, None, Some(tupleTy))
        let params = ctor.funcBody.getOrThrow().paramLists[0].params
        params.add(param, at: 0)
        let ctorTy = FuncTyOf(typeManager, params, impl.GetTy().getOrThrow())
        ctor.identifier = SrcIdentifier("init")
        ctor.SetTy(ctorTy)
        ctor.funcBody.getOrThrow().SetTy(ctorTy)
    }

    public func TransformToObjCImplUserCtorBody(ctorBody: FuncBody, regDataCtor: FuncDecl,
        impl: ClassDecl, regComp: ClassDecl, objCClassRef: Expr): Unit {
        let curFile = ctorBody.curFile.getOrThrow()
        let handleParam = CreateFuncParam("$obj", None, None, objCLib.GetNativeObjCIdTy())
        let handleRef = CreateRefExpr(handleParam)
        let regCtor = GetObjCImplRegCompanionBaseCtor(regComp).getOrThrow()
        let regCall = CreateCall(regCtor, curFile, (ASTCloner.Clone(handleRef) as Expr).getOrThrow())
        let tupleTy = typeManager.GetTupleTy([objCLib.GetNativeObjCIdTy().getOrThrow(), regComp.GetTy().getOrThrow()])
        let elements = ArrayList<Expr>(); elements.add(handleRef); elements.add(regCall)
        let nodes = ArrayList<Node>(); nodes.add(CreateTupleLit(elements, tupleTy))
        let lambdaParams = ArrayList<FuncParam>(); lambdaParams.add(handleParam)
        let lambda = WithinFile<LambdaExpr>(WrapReturningLambdaExpr(typeManager, nodes, lambdaParams: lambdaParams), Some(curFile))
        let allocCall = CreateCall(objCLib.GetAllocDecl().getOrThrow(), curFile, objCClassRef)
        let lambdaArgs = ArrayList<FuncArg>(); lambdaArgs.add(CreateFuncArg(allocCall))
        let lambdaCall = CreateCallExpr(lambda, lambdaArgs, None, Some(tupleTy), CallKind.CALL_INVALID)
        let args = ArrayList<FuncArg>(); args.add(CreateFuncArg(lambdaCall))
        for (param in ctorBody.paramLists[0].params) {
            args.add(CreateFuncArg(WithinFile<RefExpr>(CreateRefExpr(param), Some(curFile))))
        }
        let call = CreateThisCall(impl, regDataCtor, regDataCtor.GetTy().getOrThrow(), curFile, args)
        ctorBody.body.getOrThrow().body.clear()
        ctorBody.body.getOrThrow().body.add(call)
    }
}
